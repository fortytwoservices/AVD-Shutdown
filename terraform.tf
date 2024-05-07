variable "mailsender" {
  default     = "AVDNotifications@fortytwo.io"
  description = "The email address used for sending emails"
}

variable "TenantId" {
  default     = "labs.fortytwo.io"
  description = "The tenant ID used for the Service Principal"
}

variable "ClientId" {
  default     = ""
  description = "The client ID used for the Service Principal"
}

variable "ClientSecret" {
  default     = ""
  description = "The client secret used for the Service Principal"
}

variable "subscriptionid" {
  default     = "ba345d34-f8c3-47ae-bc1c-b45b3e27da21"
  description = "The subscription ID's (comma seperated list) where we look for the AVD Resources"
}

variable "useManagedIdentity" {
  default     = "true"
  description = "Use the Managed Identity for the function app"
}


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

  app_settings = {
    "mailsender"         = "${var.mailsender}"
    "TenantId"           = "${var.TenantId}"
    "ClientId"           = "${var.ClientId}"
    "ClientSecret"       = "${var.ClientSecret}"
    "subscriptionid"     = "${trimspace(var.subscriptionid)}"
    "useManagedIdentity" = "${var.useManagedIdentity}"
  }

}

resource "azurerm_app_service_source_control" "deployment" {
  app_id   = azurerm_linux_web_app.functionapp.id
  repo_url = "https://github.com/fortytwoservices/AVD-ShutdownWebhook"
  branch   = "main"
}

data "azurerm_subscription" "subscription" {
}

resource "azurerm_role_assignment" "functionapp" {
  for_each             = toset(split(",", var.subscriptionid))
  scope                = data.azurerm_subscription.subscription.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.functionapp.principal_id
}