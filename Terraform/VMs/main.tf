terraform {
  required_providers {
    azurerm = {
      version = "=2.5.0"
    }
  }
}

provider "azurerm" {

    subscription_id = var.subscription_id
    client_id     = var.client_id
    client_secret = var.client_secret
    tenant_id     = var.tenant_id
    environment   = var.environment

    features {}
}

data "azurerm_key_vault_secret" "vmAdminPasswordSecret" {
    name = "vmadminpassword"
    key_vault_id = var.keyvault_id
}

data "azurerm_subnet" "subnet" {
    name                 = "${var.prefix}-subnet"
    virtual_network_name = "${var.prefix}-network"
    resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-${var.resource_group_name}"
  location = var.resource_group_location
}

resource "azurerm_availability_set" "asets" {
  count               = length(var.asetlist)
  name                = "${var.prefix}-${var.asetlist[count.index]}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_interface" "appnics" {
  count               = length(var.vmdetails)
  name                = "${var.prefix}-vmnic.${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vmloop" {
  count               = length(var.vmdetails)
  name                = "${var.prefix}-${var.vmdetails[count.index].name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vmdetails[count.index].size
  admin_username      = var.vm_username
  admin_password      = data.azurerm_key_vault_secret.vmAdminPasswordSecret.value
  availability_set_id = azurerm_availability_set.asets["${var.vmdetails[count.index].asetNum}"].id
  network_interface_ids = [
    azurerm_network_interface.appnics[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}