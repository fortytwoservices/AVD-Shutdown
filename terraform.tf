# Create a resource group and functionApp with powershell 7.2 runtime
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-AVDfunctionApp"
  location = "norwayeast"
}

resource "random_string" "functionapp" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_service_plan" "serviceplan" {
  name                = "sp-AVDfunctionApp-${random_string.functionapp.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Y1"
  os_type             = "Linux"
}

resource "azurerm_user_assigned_identity" "functionapp" {
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  name                = "mi-AVDfunctionApp-${random_string.functionapp.result}"
}

resource "azurerm_storage_account" "functionapp" {
  name                            = "stavdfapp${random_string.functionapp.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_linux_function_app" "functionapp" {
  name                       = "AVDfunctionApp-${random_string.functionapp.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.serviceplan.id
  storage_account_name       = azurerm_storage_account.functionapp.name
  storage_account_access_key = azurerm_storage_account.functionapp.primary_access_key

  site_config {
    application_stack {
      powershell_core_version = 7.2
    }
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.functionapp.id
    ]
  }
}
