#############################################################################
# VARIABLES
#############################################################################

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "vnet_cidr_range" {
  type    = string
  default = "100.0.0.0/16"
}

variable "subnet_prefixes" {
  type    = list(string)
  default = ["100.0.0.0/24", "100.0.1.0/24"]
}

variable "subnet_names" {
  type    = list(string)
  default = ["subnet1", "subnet2"]
}

variable "prefix" {
  type = string 
  default = "chen_tf"
}

variable "env"{
  type = string
}

# variable "env_name"{
#     type = string
#     default = "dev"
# }

# resource "azurerm_key_vault" "chen-keyvault" {
#   # (resource arguments)
# }