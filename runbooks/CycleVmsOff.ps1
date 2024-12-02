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
    $time_zone = Get-AutomationVariable -Name time_zone
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

Write-Information -Message "Identity subscriptions with machines that need to be cycled off..."
foreach ($subscription in $subscriptions) {
    try {
        Write-Information -Message "Processing $subscription subscription..."
        $null = Set-AzContext -Subscription $subscription

        ## Get a list of VMs that need to be cycled
        ##
        Write-Output  "Identifying subscriptions with machines that are configured for cycling for subscription $($subscription)..."
        $vms = Get-AzVM -status
        [array]$cycle_vms = @()
        foreach ($vm in $vms) {
            [Hashtable]$vmtag = (Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name  $vm.Name).Tags
            if ($vmtag.ContainsKey("cycle") -and $vmtag["cycle"] -eq "true") {
                $cycle_vms += $vm
            }
        }

    }
    catch {
        Write-Error -Message "Unable to get a list of machines to be cycled: $($PSItem.ToString())"
    }

    ## Iterate through the virtual machine list and deallocate the machines that have been running for 24 hours
    ##
    try {
        Write-Output "Iterating through virtual machines configured for cycling and deallocating machines that have run for greater than 24 hours..."
        $local_time_zone = [System.TimeZoneInfo]::Local
        $target_time_zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($time_zone)
        $current_time_unconverted = Get-Date
        $converted_time = [System.TimeZoneInfo]::ConvertTime($current_time_unconverted, $local_time_zone, $target_time_zone)  

        foreach ($vm in $cycle_vms) {
            [Hashtable]$vmtag = (Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name).Tags
            if ($vmtag.ContainsKey("lastBooted")) {
                if ((Get-Date($vmtag['lastBooted'])).AddDays(1) -lt $converted_time -and ($vm.PowerState -eq "VM Running")) {
                    Write-Output "$($vm.Name) has been running for 24 hours and will be deallocated"
                    try {
                        $tag = @{"lastBooted" = "$converted_time" }
                        $null = Update-AzTag -Tag $tag -Operation Merge -ResourceId $vm.id
                        $null = Stop-AzVm $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force
                        $count++
                    }
                    catch {
                        Write-Error -Message "Unable to deallocate $($vm.Name): $($PSItem.ToString())"
                    }
                }
            }
        }
    }
    catch {
        Write-Error -Message "Unable to deallocate machines $($PSItem.ToString())"
    }
}
Write-Output "$($count) virtual machines were successfully deallocated"