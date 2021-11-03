#############################################################################
# RESOURCES
#############################################################################

locals{
  env_name = (terraform.workspace == "stage") ? "stage" : "prod"
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${local.env_name}_${var.resource_group_name}"
  location = var.location
}

module "vnet-main" {
  source              = "Azure/vnet/azurerm"
  version             = "~> 2.0"
  resource_group_name = azurerm_resource_group.resource_group.name
  vnet_name           = "${local.env_name}_${var.resource_group_name}"
  address_space       = [var.vnet_cidr_range]
  subnet_prefixes     = var.subnet_prefixes
  subnet_names        = var.subnet_names
  nsg_ids             = {}


  depends_on = [azurerm_resource_group.resource_group]
}

resource "azurerm_network_interface" "vnet_main" {
  #count = var.numOfvms 
  count = var.env == "prod" ? 2 : 1
  name                = "${local.env_name}_${var.prefix}-nic${count.index}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = element(module.vnet-main.vnet_subnets,0)
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_machine" "vm" {
  #count = var.numOfvms 
  count = var.env == "prod" ? 2 : 1
  name                  = "${local.env_name}_${var.prefix}-vm${count.index}"
  location              = azurerm_resource_group.resource_group.location
  resource_group_name   = azurerm_resource_group.resource_group.name
  network_interface_ids = [azurerm_network_interface.vnet_main[count.index].id]
  vm_size               = "Standard_DS1_v2"
  availability_set_id   = azurerm_availability_set.avail_set.id

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${local.env_name}_${var.prefix}-disk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
 
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/chen/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
  }
}
os_profile {
   computer_name = "computer"
   admin_username = "chen"
 }
}

# output "principal_id" {
#   value = azurerm_virtual_machine.vm[0].id
# }
# output "system_assigned_identity_principal_ids" {
#   value       = "${azurerm_virtual_machine.vm[0].identity.principal_id}"
#   depends_on  = [azurerm_virtual_machine.vm]
# }

resource "azurerm_availability_set" "avail_set" {
  name                = "${local.env_name}_aset"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_public_ip" "chen_pub_ip" {
  name                = "${local.env_name}_PublicIPForLB"
  location            = "East US"
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "chen_lb" {
  name                = "${local.env_name}_LoadBalancer"
  location            = "East US"
  resource_group_name = azurerm_resource_group.resource_group.name

  frontend_ip_configuration {
    name                 = "${local.env_name}_PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.chen_pub_ip.id
  }
}

resource "azurerm_lb_probe" "probe" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.chen_lb.id
  name                = "${local.env_name}_probe"
  port                = 8080
  protocol            = "TCP"
}

resource "azurerm_lb_rule" "lb_rule" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.chen_lb.id
  name                           = "${local.env_name}_LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 8080
  frontend_ip_configuration_name = "${local.env_name}_PublicIPAddress"
  probe_id                       = azurerm_lb_probe.probe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.chen_BackEnd.id]
}

resource "azurerm_lb_backend_address_pool" "chen_BackEnd" {
  # resource_group_name = azurerm_resource_group.vnet_main.name
  loadbalancer_id     = azurerm_lb.chen_lb.id
  name                = "${local.env_name}_backendpool"
}

resource "azurerm_network_interface_backend_address_pool_association" "association" {
  count = var.env == "prod" ? 2 : 1
  network_interface_id    = azurerm_network_interface.vnet_main[count.index].id
  ip_configuration_name = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.chen_BackEnd.id
}

data "azurerm_virtual_network" "chen_bastion" {
  name                = "bastion1"
  resource_group_name = "bastion1"
}

output "virtual_network_id" {
  value = data.azurerm_virtual_network.chen_bastion.id
}

resource "azurerm_virtual_network_peering" "peering" {
  name                         = "${local.env_name}_peering"
  resource_group_name          = azurerm_resource_group.resource_group.name
  virtual_network_name         = module.vnet-main.vnet_name
  remote_virtual_network_id    = data.azurerm_virtual_network.chen_bastion.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true

  # `allow_gateway_transit` must be set to false for vnet Global Peering
  allow_gateway_transit = false
}

resource "azurerm_virtual_network_peering" "peering2" {
  name                         = "${local.env_name}_peering2"
  resource_group_name          = data.azurerm_virtual_network.chen_bastion.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.chen_bastion.name
  remote_virtual_network_id    = module.vnet-main.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true

  # `allow_gateway_transit` must be set to false for vnet Global Peering
  allow_gateway_transit = false
}


data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "chen-keyvault" {
  name                = "chen-keyvault"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = "chen-azuretask-rg"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
}

resource "azurerm_key_vault_access_policy" "access" {
  key_vault_id = azurerm_key_vault.chen-keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = "08d0cb9f-26ef-48e1-b1d4-668ce7469220"

  key_permissions = [
    "Get",
  ]

  secret_permissions = [
    "Get",
  ]
}

# resource "azurerm_key_vault_access_policy" "accesspo" {
#   key_vault_id = azurerm_key_vault.example.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = data.azurerm_client_config.current.object_id

#   key_permissions = [
#     "Get",
#   ]

#   secret_permissions = [
#     "Get",
#   ]
# }