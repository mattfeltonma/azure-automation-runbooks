## Configure key variables
##
$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$count = 0

## Function to parse resource ids
##
function Parse-AzureResourceId {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId
    )

    ## Create a hash table to store the pieces of an Azure Resource ID
    ##
    $components = @{
        SubscriptionId = $null
        ResourceGroup  = $null
        ResourceName   = $null
    }

    ## Extract each piece of the Azure Resource ID
    ##
    $components.SubscriptionId = if ($ResourceId -match "/subscriptions/([^/]+)")  {$matches[1]}
    $components.ResourceGroup  = if ($ResourceId -match "/resourceGroups/([^/]+)") {$matches[1]}
    $components.ResourceName   = $ResourceId.Split("/")[-1]

    ## Return the hash table containing the components of the Azure Resource ID
    ##
    return $components
}

## Get the necessary variables from the Automation Account variables
##
try {
    Write-Output "Retrieving the necessary variables from the Automation Account..."
    $umi_client_id = Get-AutomationVariable -Name umi_client_id
}
catch {
    Write-Error -Message "Unable to retrieve Automation Account variables: $($PSItem.ToString())"
}

## Set the Azure context using the user-assigned managed identity
##
try {
    Write-Output "Creating an identity context using the user-assigned managed identity..."
    $context = (Connect-AzAccount -Identity -AccountId $umi_client_id).context
    $null = Set-AzContext -SubscriptionName $context.Subscription -DefaultProfile $context
}
catch {
    Write-Error -Message "Unable setup context for user-assigned managed identity: $($PSItem.ToString())"
}

## Get a list of subscriptions
##
try {
    Write-Output "Getting a list of subscriptions in the Entra ID tenant..."
    $subscriptions = Get-AzSubscription | Select-Object -ExpandProperty Name
}
catch {
    Write-Error -Message "Unable to list subscriptions: $($PSItem.ToString())"
}

## Identify subscriptions with Azure Firewall instances and re-allocate the instances
## Use the information in the resource tags to re-add the necessary vhub (for VWAN) and public IPs (for VNet)
##
Write-Output "Identity subscriptions with Azure Firewall instances that are configured for cycling..."
foreach ($subscription in $subscriptions) {
    try {
        Write-Output "Processing $subscription subscription..."
        $null = Set-AzContext -Subscription $subscription

        ## Get a list of Azure Firewall instances that need to be cycled
        ##
        Write-Output  "Identifying Azure Firewall Instances configured for cycling in subscription $($subscription)..."
        $fws = Get-AzFirewall | Select-Object -Property *
        [array]$cycle_fws = @()
        foreach ($fw in $fws) {
            [Hashtable]$fwtag = $fw.Tag
                if ($fwtag.ContainsKey("cycle") -and $fwtag["cycle"] -eq "true") {
                $cycle_fws += $fw
            }
        }
    }
    catch {
        Write-Error -Message "Unable to get a list of Azure Firewall instances to be cycled: $($PSItem.ToString())"
    }

    ## Iterate through the Azure Firewall instances list and allocate Azure Firewall instances that are deallocated
    ##
    try {
        Write-Output "Iterating through Azure Firewall instances configured for cycling and allocating..."
        foreach ($fw in $cycle_fws) {
            ## Check to see if the Azure Firewall instance is deployed to a VWAN Hub
            ##
            if ($fw.Sku.Name -eq "AZFW_Hub") {

                ## Check to see if an IP configuration doesn't exist. If it doesn't, this means the Azure Firewall is an unallocated state
                ##
                if (!$fw.IPConfigurations) {
                    Write-Output "Allocating Azure Firewall instance $($fw.Name)..."

                    ## Check to see if the the vwan_hub_id tag exists. If it does, use the hub id when re-allocating the firewall
                    ##
                    if  ($fwtag.ContainsKey("vwan_hub_id")) {

                        ## Get the virtual WAN hub object
                        ##
                        $vwan_hub_pieces = Parse-AzureResourceId -ResourceId $fwtag["vwan_hub_id"]
                        $vwan_hub_object = Get-AzVirtualHub -ResourceGroupName $vwan_hub_pieces.ResourceGroup -Name $vwan_hub_pieces.ResourceName

                        ## Allocate the Azure Firewall instance
                        ##
                        $current_fw = Get-AzFirewall -ResourceGroupName $fw.ResourceGroupName -Name $fw.Name
                        $current_fw.Allocate($vwan_hub_object)
                        $null = Set-AzFirewall -AzureFirewall $current_fw
                        $count++
                    }
                    else {
                        Write-Error -Message "Unable to allocate Azure Firewall instance $($fw.Name) due to missing tags"
                        Exit
                    }
                }
            }
            ## Check to see if the Azure Firewall instance is deployed to a virtual network
            ##
            if ($fw.Sku.Name -eq "AZFW_VNet") {

                ## Check to see if an IP configuration doesn't exist. If it doesn't, this means the Azure Firewall is an unallocated state
                ##
                if (!$fw.IpConfigurations) {
                    Write-Output "Allocating Azure Firewall instance $($fw.Name)..."
                    $public_ips = @()

                    ## Iterate through each tag to find the tags containing public IPs and the virtual network ID.
                    ##
                    foreach ($key in $fwtag.Keys) {
                        Write-Output "Processing tag $($key)..."
                        if ($key -like "public_ip*") {
                            Write-Output "Found a key that matches public_ip..."
                            $public_ips += $fwtag[$key]
                        }
                        if ($key -like "vnet_id") {
                            Write-Output "Found a key that matches vnet_id..."
                            $vnet_id = $fwtag[$key]
                        }
                        if ($key -like "mgmt_public_ip_id") {
                            Write-Output "Found a key that matches mgmt_public_ip_id..."
                            $mgmt_ip = $fwtag[$key]
                        }
                    }

                    ## If both the virtual network id and public IPs are found, allocate the Azure Firewall instance
                    ##
                    if ($vnet_id -and $public_ips) {
                        $current_fw = Get-AzFirewall -ResourceGroupName $fw.ResourceGroupName -Name $fw.Name
                        $public_ips_objects = @()
                        ## Get the virtual network object
                        ##
                        $vnet_id_pieces = Parse-AzureResourceId -ResourceId $vnet_id
                        Write-Output "The virtual network resource group is $($vnet_id_pieces.ResourceGroup) and the virtual network name is $($vnet_id_pieces.ResourceName)"
                        $vnet_object = Get-AzVirtualNetwork -ResourceGroupName $vnet_id_pieces.ResourceGroup -Name $vnet_id_pieces.ResourceName

                        ## Get the public IP address objects
                        ##
                        foreach ($ip in $public_ips) {
                            $ip_object_pieces = Parse-AzureResourceId -ResourceId $ip
                            Write-Output "The public IP resource group is $($ip_object_pieces.ResourceGroup) and the public IP name is $($ip_object_pieces.ResourceName)"
                            $ip_object = Get-AzPublicIpAddress -ResourceGroupName $ip_object_pieces.ResourceGroup -Name $ip_object_pieces.ResourceName
                            $public_ips_objects += $ip_object
                        }
                        
                        ## Get the management public IP address object
                        ##
                        if (!$mgmt_ip) {
                            ## Allocate the Azure Firewall instance
                            ##
                            Write-Output "Allocating Azure Firewall instance $($fw.Name)..."
                            $current_fw.Allocate($vnet_object,$public_ips_objects)
                            $null = Set-AzFirewall -AzureFirewall $current_fw
                            $count++
                        }
                        else {
                            $mgmt_ip_object_pieces = Parse-AzureResourceId -ResourceId $mgmt_ip
                            Write-Output "The management public IP resource group is $($mgmt_ip_object_pieces.ResourceGroup) and the management public IP name is $($mgmt_ip_object_pieces.ResourceName)"
                            $mgmt_ip_object = Get-AzPublicIpAddress -ResourceGroupName $mgmt_ip_object_pieces.ResourceGroup -Name $mgmt_ip_object_pieces.ResourceName
                            
                            ## Allocate the Azure Firewall instance
                            ##
                            Write-Output "Allocating Azure Firewall instance $($fw.Name)..."
                            $current_fw.Allocate($vnet_object,$public_ips_objects, $mgmt_ip_object)
                            $null = Set-AzFirewall -AzureFirewall $current_fw
                            $count++
                        }
                    }
                    else {
                        Write-Error -Message "Unable to allocate Azure Firewall instance $($fw.Name) due to missing tags"
                        Exit
                    }
                }
            }
        }
    }
    catch {
        Write-Error -Message "Unable to allocate firewalls $($PSItem.ToString())"
    }
}
Write-Output "$($count) Azure Firewall instances were successfully allocated"
