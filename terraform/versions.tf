## Configure the providers
##
terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.13.1"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.6.0"
    }
  }
  required_version = ">= 1.8.3"
}