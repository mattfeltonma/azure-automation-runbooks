variable "management_group_name" {
  description = "The name of the management group where the role assignment will be created"
  type        = string
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
}

variable "tags" {
  description = "The tags to add to resources"
  type        = map(string)
}

variable "time_zone_iana_id" {
    description = "The IANA time zone to use when recording the time in the lastBoot tag. See this article for details: https://learn.microsoft.com/en-us/rest/api/maps/timezone/get-timezone-enum-windows?view=rest-maps-2024-04-01&tabs=HTTP#response"
    type        = string
    default = "America/New_York"
}

variable "time_azfw_cycle_off" {
    description = "The time to run the CycleAzureFirewallOff runbook which deallocates the Azure Firewall instances. This should be in the format HH:MM:SS and should be offset from UTC time. For example, 11PM Eastern Standard Time would be 04:00:00"
    type        = string
    default = "04:00:00"
}

variable "time_azfw_cycle_on" {
    description = "The time to run the CycleAzureFirewallOn runbook which reallocates the Azure Firewall instances. This should be in the format HH:MM:SS and should be offset from UTC time. For example, 7AM Eastern Standard Time would be 12:00:00"
    type        = string
    default = "12:00:00"
}

variable "time_vm_cycle" {
    description = "The time to run the CycleVmOn runbook. The CycleVmOff runbook will run 30 minutes later. This should be in the format HH:MM:SS and should be offset from UTC time. For example, midnight Eastern Standard Time would be 05:00:00"
    type        = string
    default = "05:00:00"
}

variable "vm_max_deallocated_days" {
  description = "The maximum amount of days a VM should be deallocated"
  type        = number
}