# Cost Saving Azure Automation Runbooks 

## Updates
* 12/3/2024 - Breakfix; addressed missing time_zone variable
* 12/1/2024 - Initial release

## Overview
The Terraform code in this repository can be used to deploy a collection of Azure Automation Runbooks that can be used to saved costs in an Azure environment used for experimentation. The PowerShell code included in these runbooks de-allocate and allocate Azure Firewalls instances and Azure Virtual Machines based on a configured tag.

## Infrastructure
The Terraform code in this repository deploys a number of resources including:

* Resource Group to store the resources created by this deployment
* Azure Automation Account and supporting child resources including variables, schedules, and runbooks
* User-assigned Managed Identity assigned to the Azure Automation Account
* Azure RBAC Role Assignments for Virtual Machine Contributor and Virtual Network Contributor created at the management group specified by the user.

![infra deployed by solution](/assets/infra.svg)
*Infra deployed by solution*



## Azure Automation
The components within the Azure Automation Account deployed within this solution are described below.

### Variables
This solution deploys three encrypted variables.
* **boot_cycle_days** - This is maximum number of days a virtual machine should be shutdown for. After this number of days, the virtual machine is powered up for 24 hours.
* **umi_client_id** - This is the client id of the user-assigned managed identity associated with the Azure Automation Account

### Schedules
This solution deploys a schedule for each runbook.
* **boot_azfw_cycle_off** - This is the schedule used by the CycleAzureFirewallOff runbook. It is run daily at a time specified by the user and will deallocated the appropriately tagged Azure Firewall instances.
* **boot_azfw_cycle_on** This is the schedule used by the CycleAzureFirewallOn runbook. It is run daily at a time specified by the user and will reallocate the appropriately tagged Azure Firewall instances.
* **boot_vm_cycle_off** This is the schedule used by the CycleVmsOn runbook. It is run daily 30 minutes after the boot_vm_cycle_on schedule is run. Appropriately tagged VMs that have been running for 24 hours will be deallocated at this time.
* **boot_vm_cycle_on** This is the schedule used by the CycleVmsOn runbook. It is run daily at midnight. Appropriately tagged VMs that have not been running for the user specified number of days will be reallocated.

### Azure Virtual Machine Runbooks
While Azure Virtual Machines can be [automatically shutdown](https://learn.microsoft.com/en-us/azure/virtual-machines/auto-shutdown-vm?tabs=portal) and [cycled using](https://learn.microsoft.com/en-us/azure/azure-functions/start-stop-vms/overview) using native features, sometimes more complex requirements must be satisifed such as ensuring only certain machines machines boot every few days to receive updates. The two runbooks named CycleVmsOn and CycleVmsOff include PowerShell code which is used to cycle appropriately tagged virtual machines both off and on based on a specific schedule provided by the user.

Both runbooks search for virtual machines tagged with cycle set to true across all subscriptions the managed identity of the Azure Automation Account have access to. 

#### CycleVmsOn
With the CycleVmsOn runbook, each cycle-enabled virtual machine is checked for a tag named lastBooted. If this tag does not exist this tag is set to the current date and time. When the machine is stopped and does not have this tag, it is started and the tag is set to the current date and time. When the tag does exist, and the machine is deallocated, the runbook will check to lastBooted tag to see if it has been a certain number of days (specifed by the user in the max_deallocated_days variable) since the machine was last running. If it has, the machine is started. This ensures machines are powered on every few days to update their status and perform updates.

#### CycleVmsOff
With the CycleVmsOff runbook, each cycle-enabled running virtual machine is checked for a tag named lastBooted. If the tag exists, the machine is running, and the date in the tag is 1 day older than the current date, the virtual machine is powered off and the tag is updated to the current date. This ensures machines that have been running for more than 24 hours are powered down to save on costs.

### Azure Firewall Runbooks
Azure Firewall [supports deallocation](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq#how-can-i-stop-and-start-azure-firewall) to save on costs when it is not actively being used. The two runbooks named CycleAzureFirewallOff and CycleAzureFirewallOn are used to deallocate and allocate Azure Firewall instances that are tagged with the tag cycle and value of true. The start and stop time can be specified by the user using the time_azfw_cycle_on and time_azfw_cycle_off Terraform variables. 

## Pre-requisites
You must be Owner, User Access Administrator, or have appropriate permissions to create Azure RBAC Role Assignments at the Management Group you specify when deploying the solution.

## Deployment
1. Create a terraform.tfvars file that includes the variables below. A sample variables file named terraform.tfvars-example has been provided for you.

    * **location** - The location to deploy the resources.
    * **management_group_name** - The management group the Azure RBAC Role Assignments will be created at. T    he subscriptiosn you want to manage should be under this management group.
    * **time_zone_iana_id** - The [Windows time zone designation](https://learn.microsoft.com/en-us/rest/api/maps/timezone/get-timezone-enum-windows?view=rest-maps-2024-04-01&tabs=HTTP#examples) you want used for the schedules. This is set to America/New_York by default.
    * **vm_deallocated_day** - The maximum number of days a virtual machine should be deallocated for. This is used in the logic of the CycleVmsOn runbook to reallocate machines that have been deallocated for this length of time.
    * **time_azfw_cycle_off** - The time (in UTC) you would like the Azure Firewalls deallocated. By default this is 12AM EST.
    * **time_azfw_cycle_on** - The time (in UTC) you would like the Azure Firewalls reallocated. By default this is 7AM EST.
    * **time_vm_cycle** - The time (in UTC) you would like the CycleVmsOn runbook to run. The CycleVmsOff will run 30 minutes after this time. This is set to 12AM EST by default.
    * **tag** - Any tags you would like added to the resources

2. Tag the Azure Virtual Machines and Azure Firewall instances you would like to be controlled by the runbooks with a tag of cycle set to true.
