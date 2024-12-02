## Get the current subscription id
##
data "azurerm_subscription" "current" {}

## Get the identity config that is used to deploy the resources
##
data "azurerm_client_config" "identity_config" { }