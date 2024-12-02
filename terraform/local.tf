locals {
  ## Naming conventions
  ##
  automation_account_prefix = "autoac"
  resource_group_prefix     = "rg"
  umi_prefix                = "umi"

  ## Region abbreviations
  ##
  region_abbreviations = {
    "australiacentral"   = "acl",
    "australiacentral2"  = "acl2",
    "australiaeast"      = "ae",
    "australiasoutheast" = "ase",
    "brazilsouth"        = "brs",
    "brazilsoutheast"    = "bse",
    "canadacentral"      = "cnc",
    "canadaeast"         = "cne",
    "centralindia"       = "ci",
    "centralus"          = "cus",
    "centraluseuap"      = "ccy",
    "eastasia"           = "ea",
    "eastus"             = "eus",
    "eastus2"            = "eus2",
    "eastus2euap"        = "ecy",
    "francecentral"      = "frc",
    "francesouth"        = "frs",
    "germanynorth"       = "gn",
    "germanywestcentral" = "gwc",
    "israelcentral"      = "ilc",
    "italynorth"         = "itn",
    "japaneast"          = "jpe",
    "japanwest"          = "jpw",
    "jioindiacentral"    = "jic",
    "jioindiawest"       = "jiw",
    "koreacentral"       = "krc",
    "koreasouth"         = "krs",
    "mexicocentral"      = "mxc",
    "newzealandnorth"    = "nzn",
    "northcentralus"     = "ncus",
    "northeurope"        = "ne",
    "norwayeast"         = "nwe",
    "norwaywest"         = "nww",
    "polandcentral"      = "plc",
    "qatarcentral"       = "qac",
    "southafricanorth"   = "san",
    "southafricawest"    = "saw",
    "southcentralus"     = "scus",
    "southeastasia"      = "sea",
    "southindia"         = "si",
    "spaincentral"       = "spac"
    "swedencentral"      = "swc",
    "switzerlandnorth"   = "swn",
    "switzerlandwest"    = "sww",
    "uaecentral"         = "uaec",
    "uaenorth"           = "uaen",
    "uksouth"            = "uks",
    "ukwest"             = "ukw",
    "westcentralus"      = "wcus",
    "westeurope"         = "we",
    "westindia"          = "wi",
    "westus"             = "wus",
    "westus2"            = "wus2",
    "westus3"            = "wus3"
  }
  location_code = lookup(local.region_abbreviations, var.location, var.location)

  ## Deployment specific
  ##
  purpose = "autocycle"

  ## Create the necessary timestamps
  ##
    current_time = timestamp()
    ## Add 24 hours to the current time
    ##
    next_day = timeadd(local.current_time, "24h")
    ## Extract the date from the next_day timestamp
    ##
    next_day_date = substr(local.next_day, 0, 10)
    ## Configure start times of each job offset by the user specified offset
    ##
    job_start_time_vm_cycle_on = "${local.next_day_date}T${var.time_vm_cycle }Z"
    job_start_time_vm_cycle_off  = timeadd(local.job_start_time_vm_cycle_on, "30m")
    job_start_time_azfw_cycle_on = "${local.next_day_date}T${var.time_azfw_cycle_on}Z"
    job_start_time_azfw_cycle_off  = "${local.next_day_date}T${var.time_azfw_cycle_off}Z"

  ## Add required tags and merge them with the provided tags
  ##
  required_tags = {
    created_date = timestamp()
    created_by   = data.azurerm_client_config.identity_config.object_id
  }

  tags = merge(
    var.tags,
    local.required_tags
  )
}
