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
    $boot_cycle_days = Get-AutomationVariable -Name boot_cycle_days
}
catch {
    Write-Error -Message "Unable to retrieve Automation Account variables: $($PSItem.ToString())"
}

## Create an identity context using the user-assigned managed identity
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

## Setup a foreach loop which will iterate through each subscription
## and reboot machines with the tag "cycle" set to true
##
Write-Output "Identifing subscriptions with machines that need to be cycled on..."
foreach ($subscription in $subscriptions) {
    try {
        Write-Output "Processing $subscription subscription..."
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
                Write-Output "$($vm.Name) is configured for cycling"
            }
        }

    }
    catch {
        Write-Error -Message "Unable to get a list of machines to be cycled: $($PSItem.ToString())"
    }

    ## Iterate through the virtual machine list and boot machines that haven't been booted in the period specified
    ##
    try {
        Write-Output "Iterating through virtual machines configured for cycling and booting machines that have not been running for $($boot_cycle_days) days..."
        
        ## Get the current date and time in the specified time zone
        ##
        $local_time_zone = [System.TimeZoneInfo]::Local
        $target_time_zone = [System.TimeZoneInfo]::FindSystemTimeZoneById($time_zone)
        $current_time_unconverted = Get-Date
        $converted_time = [System.TimeZoneInfo]::ConvertTime($current_time_unconverted, $local_time_zone, $target_time_zone)  

        foreach ($vm in $cycle_vms) {
            [Hashtable]$vmtag = (Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name).Tags
            if ($vmtag.ContainsKey("lastBooted")) {
                if ((Get-Date($vmtag['lastBooted'])).AddDays($boot_cycle_days) -lt $converted_time) {
                    Write-Output "$($vm.Name) has not been booted in the last $($boot_cycle_days) days"
                    $tag = @{"lastBooted" = "$converted_time" }
                    try {
                        $null = Update-AzTag -Tag $tag -Operation Merge -ResourceId $vm.id
                        if ($vm.PowerState -ne "VM Running") {
                            $null = Start-AzVm $vm.Name -ResourceGroupName $vm.ResourceGroupName
                            $count++
                        }
                        else {
                            Write-Output "$($vm.Name) is not yet tagged with lastRebooted"
                            $tag = @{"lastBooted" = "$converted_time" }
                            try {
                                $null = Update-AzTag -Tag $tag -Operation Merge -ResourceId $vm.id
                                if ($vm.PowerState -ne "VM Running") {
                                    $null = Start-AzVm $vm.Name -ResourceGroupName $vm.ResourceGroupName
                                    $count++
                                }
                            }
                            catch {
                                Write-Error -Message "Unable to tag or boot $($vm.Name): $($PSItem.ToString())"
                            }
                        }
                    }
                    catch {
                        Write-Error -Message "Unable to tag or boot $($vm.Name): $($PSItem.ToString())"
                    }
                }
            }
        
            ## If the tag doesn't exist, add it and boot the virtual machine if it isn't booted
            else {
                Write-Output "$($vm.Name) is not yet tagged with lastRebooted"
                $tag = @{"lastBooted" = "$converted_time $time_zone" }
                try {
                    $null = Update-AzTag -Tag $tag -Operation Merge -ResourceId $vm.id
                    if ($vm.PowerState -ne "VM Running") {
                        $null = Start-AzVm $vm.Name -ResourceGroupName $vm.ResourceGroupName
                        $count++
                    }
                }
                catch {
                    Write-Error -Message "Unable to tag or boot $($vm.Name): $($PSItem.ToString())"
                }
            }
        }
    }
    catch {
        Write-Error -Message "Unable to tag and boot machines $($PSItem.ToString())"
    }
}
Write-Output "$($count) virtual machines were successfully started"