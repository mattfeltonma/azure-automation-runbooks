## Configure key variables
##
$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
$count = 0

## Get the necessary variables from the Automation Account variables
##
try {
    Write-Output "Retrieving the necessary variables from the Automation Account..."
    $umi_client_id = Get-AutomationVariable -Name umi_client_id
}
catch {
    Write-Error -Message "Unable to retrieve Automation Account variables: $($PSItem.ToString())"
}

## Get client id for user-assigned managed identity and set the identity context
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

## Identify subscriptions with Azure Firewall instances and deallocate instances that are running
## Add necessary tags so instances can be spun back up
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

    ## Iterate through the Azure Firewall instances list and deallocate the Azure Firewall instances are running
    ##
    try {
        Write-Output "Iterating through Azure Firewall instances configured for cycling and deallocating..."
        foreach ($fw in $cycle_fws) {

            ## Process if the Azure Firewall is deployed to a VWAN Hub
            ##
            if ($fw.Sku.Name -eq "AZFW_Hub") {
                $tag = @{"vwan_hub_id" = $fw.VirtualHub.Id }
                $null = Update-AzTag $tag -Operation Merge -ResourceId $fw.Id
                while ($current_fw.ProvisioningState -ne "Succeeded") {
                    Write-Output "Waitings for Azure Firewall $($fw.Name) to be in a succeeded state before deallocating. Checking again in 30 seconds.."
                    Start-Sleep -Seconds 30
                    $current_fw = Get-AzFirewall -ResourceGroupName $fw.ResourceGroupName -Name $fw.Name
                }
                Write-Output "Deallocating Azure Firewall instance $($fw.Name)..."
                $current_fw.Deallocate()
                $null = Set-AzFirewall -AzureFirewall $current_fw
                $count++
            }

            ## Process if the Azure Firewall is deployed to a virtual network
            ##
            if ($fw.Sku.Name -eq "AZFW_VNet") {
                $ip_config_count = 1
                $new_tags = @{}
                foreach ($config in $fw.IpConfigurations) {

                    ## If this is the first ipConfiguration it will have a subnet property
                    ##
                    if ($config.Subnet) {
                        if ($config.Subnet.Id -match "(.*?/virtualNetworks/[^/]+)") {
                            Write-Output "Found subnet $($config.Subnet.Id) for Azure Firewall $($fw.Name) and adding as a tag"
                            $new_tags.Add("vnet_id", $matches[1])
                        }
                    }

                    ## All other ipConfigurations will have a publicIPAddress property
                    ##
                    if ($config.PublicIPAddress) {
                        Write-Output "Found public IP $($config.PublicIPAddress.Id) for Azure Firewall $($fw.Name) and adding as a tag"
                        $new_tags.Add("public_ip_id$($ip_config_count)", $config.PublicIPAddress.Id)
                    }
                    $ip_config_count++
                }

                ## Get the public IP address for the management IP configuration if one exists
                ##                
                if ($fw.ManagementIpConfiguration -ne $null) {
                    $mgmt_ip = $fw.ManagementIpConfiguration.PublicIpAddress.Id
                    Write-Output "Found management IP $($mgmt_ip) for Azure Firewall $($fw.Name) and adding as a tag"
                    $new_tags.Add("mgmt_public_ip_id", $mgmt_ip)
                }

                try {
                    $null = Update-AzTag -Tag $new_tags -Operation Merge -ResourceId $fw.Id
                }
                catch {
                    Write-Error -Message "Unable to add tags for management public IP: $($PSItem.ToString())"
                }

                ## Deallocate the Azure Firewall instance
                ##
                $current_fw = Get-AzFirewall -ResourceGroupName $fw.ResourceGroupName -Name $fw.Name
                while ($current_fw.ProvisioningState -ne "Succeeded") {
                    Write-Output "Waitings for Azure Firewall $($fw.Name) to be in a succeeded state before deallocating. Checking again in 30 seconds.."
                    Start-Sleep -Seconds 30
                    $current_fw = Get-AzFirewall -ResourceGroupName $fw.ResourceGroupName -Name $fw.Name
                }
                Write-Output "Deallocating Azure Firewall instance $($fw.Name)..."
                $current_fw.Deallocate()
                $null = Set-AzFirewall -AzureFirewall $current_fw
                $count++
            }
        }
    }
    catch {
        Write-Error -Message "Unable to deallocate firewalls $($PSItem.ToString())"
    }
}
Write-Output "$($count) Azure Firewall instances were successfully deallocated"
