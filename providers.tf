#############################################################################
#TERRAFORM CONFIG
#############################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "chen_tf_task"
    storage_account_name = "chenmstorage"  
    container_name       = "chenmcontainer"
    key                  = "terraform.tfstate"
  }

}

#############################################################################
# PROVIDERS
#############################################################################

provider "azurerm" {
  features {}
}