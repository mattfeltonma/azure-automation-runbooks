## Create resource group
##
resource "azurerm_resource_group" "rg" {
  name     = "${local.resource_group_prefix}${local.purpose}${local.location_code}"
  location = var.location
  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create user-assigned managed identity
##
resource "azurerm_user_assigned_identity" "umi" {
  name                = "${local.umi_prefix}${local.purpose}${local.location_code}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Pause for 30 seconds to allow the identity to be created
##
resource "time_sleep" "sleep_identity" {
  depends_on = [
    azurerm_user_assigned_identity.umi
]
  create_duration = "30s"
}

## Create role assignments for user-assigned managed identity at the management group
##
resource "azurerm_role_assignment" "vm_contributor" {
  depends_on = [ 
    time_sleep.sleep_identity 
 ]

  scope                = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}"
  description         = "Allow the user-assigned managed identity used by the Azure Automation account to manage virtual machines"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.umi.principal_id
}

resource "azurerm_role_assignment" "network_contributor" {
  depends_on = [ 
    time_sleep.sleep_identity 
  ]

  scope                = "/providers/Microsoft.Management/managementGroups/${var.management_group_name}"
  description         = "Allow the user-assigned managed identity used by the Azure Automation account to manage Azure Firewall and Azure Application Gateway"
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.umi.principal_id
}

## Pause for 60 seconds to allow the identity to be created
##
resource "time_sleep" "sleep_rbac" {
  depends_on = [
    azurerm_user_assigned_identity.umi
]
  create_duration = "60s"
}

## Create Azure Automation account
##
resource "azurerm_automation_account" "auto_account" {
  depends_on = [ 
    time_sleep.sleep_rbac
]
  name                = "${local.automation_account_prefix}${local.purpose}${local.location_code}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name            = "Basic"
  public_network_access_enabled = true
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.umi.id
    ]
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      tags["created_date"],
      tags["created_by"]
    ]
  }
}

## Create variables for the Azure Automation account
##
resource "azurerm_automation_variable_int" "boot_cycle_days" {
  name                = "boot_cycle_days"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  value               = var.vm_max_deallocated_days
  encrypted = true

}

resource "azurerm_automation_variable_string" "umi_client_id" {
  name                = "umi_client_id"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  value               = azurerm_user_assigned_identity.umi.client_id
  encrypted = true
}

## Create a schedule for the Azure Automation account
##
resource "azurerm_automation_schedule" "boot_vm_cycle_on" {
  name                = "boot_vm_cycle_on"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  description         = "This is the schedule used for CycleVmOn runbook"
  start_time          = local.job_start_time_vm_cycle_on
  frequency           = "Day"
  interval            = 1
  timezone            = var.time_zone_iana_id
}

resource "azurerm_automation_schedule" "boot_vm_cycle_off" {
  name                = "boot_vm_cycle_off"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  description         = "This is the schedule used for CycleVmOff runbook"
  start_time          = local.job_start_time_vm_cycle_off
  frequency           = "Day"
  interval            = 1
  timezone            = var.time_zone_iana_id
}

resource "azurerm_automation_schedule" "boot_azfw_cycle_on" {
  name                = "boot_azfw_cycle_on"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  description         = "This is the schedule used for CycleAzureFirewallOn runbook"
  start_time          = local.job_start_time_azfw_cycle_on
  frequency           = "Day"
  interval            = 1
  timezone            = var.time_zone_iana_id
}

resource "azurerm_automation_schedule" "boot_azfw_cycle_off" {
  name                = "boot_azfw_cycle_off"
  automation_account_name = azurerm_automation_account.auto_account.name
  resource_group_name = azurerm_resource_group.rg.name
  description         = "This is the schedule used for CycleAzureFirewallOff runbook"
  start_time          = local.job_start_time_azfw_cycle_off
  frequency           = "Day"
  interval            = 1
  timezone            = var.time_zone_iana_id
}

## Create runbooks for the Azure Automation account
##
data "local_file" "cycle_vm_on" {
  filename = "../runbooks/CycleVmsOn.ps1"
}

resource "azurerm_automation_runbook" "cycle_vm_on" {
  name                = "CycleVmsOn"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name

  automation_account_name = azurerm_automation_account.auto_account.name
  runbook_type        = "PowerShell72"
  log_verbose         = false
  log_progress        = true
  description         = "This runbook cycles on virtual machines with the tag of cycle set to true if the machine has been off for ${var.vm_max_deallocated_days} days"
  tags = local.tags

  content = data.local_file.cycle_vm_on.content
  job_schedule {
    schedule_name = azurerm_automation_schedule.boot_vm_cycle_on.name
  } 
}

data "local_file" "cycle_vm_off" {
  filename = "../runbooks/CycleVmsOff.ps1"
}

resource "azurerm_automation_runbook" "cycle_vm_off" {
  name                = "CycleVmsOff"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name

  automation_account_name = azurerm_automation_account.auto_account.name
  runbook_type        = "PowerShell72"
  log_verbose         = false
  log_progress        = true
  description         = "This runbook cycles off virtual machines with the tag of cycle set to true if the machine has been on for more than 24 hours"
  tags = local.tags

  content = data.local_file.cycle_vm_off.content
  job_schedule {
    schedule_name = azurerm_automation_schedule.boot_vm_cycle_off.name
  } 
}

data "local_file" "cycle_firewall_off" {
  filename = "../runbooks/CycleAzureFirewallOff.ps1"
}

resource "azurerm_automation_runbook" "cycle_firewall_off" {
  name                = "CycleAzureFirewallOff"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name

  automation_account_name = azurerm_automation_account.auto_account.name
  runbook_type        = "PowerShell72"
  log_verbose         = false
  log_progress        = true
  description         = "This runbook deallocates Azure Firewall instances with the tag of cycle set to true at a user specified time"
  tags = local.tags

  content = data.local_file.cycle_vm_off.content
  job_schedule {
    schedule_name = azurerm_automation_schedule.boot_azfw_cycle_off.name
  } 
}

data "local_file" "cycle_firewall_on" {
  filename = "../runbooks/CycleAzureFirewallOn.ps1"
}

resource "azurerm_automation_runbook" "cycle_firewall_on" {
  name                = "CycleAzureFirewallOn"
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name

  automation_account_name = azurerm_automation_account.auto_account.name
  runbook_type        = "PowerShell72"
  log_verbose         = false
  log_progress        = true
  description         = "This runbook allocates Azure Firewall instances with the tag of cycle set to true at a user specified time"
  tags = local.tags

  content = data.local_file.cycle_vm_off.content
  job_schedule {
    schedule_name = azurerm_automation_schedule.boot_azfw_cycle_on.name
  } 
}