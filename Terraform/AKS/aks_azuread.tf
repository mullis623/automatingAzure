terraform {
  required_providers {
    azurerm = {
      version = "~>2.39.0"
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

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_virtual_network" "aksvnet" {
  name                = "${var.prefix}-network"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "akssubnet" {
  name                 = "${var.prefix}-akssubnet"
  virtual_network_name = azurerm_virtual_network.aksvnet.name
  resource_group_name  = azurerm_resource_group.rg.name
  address_prefixes     = ["10.1.0.0/22"]
}

resource "azurerm_kubernetes_cluster" "akscluster" {
  name                = "${var.prefix}-akscluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
    type                = "VirtualMachineScaleSets"

    vnet_subnet_id = azurerm_subnet.akssubnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
      azure_active_directory {
          admin_group_object_ids = [var.adminGroup]
          managed = true
    }
    enabled = true
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    network_policy     = "calico"
  }

  tags = {
    Environment = "Development"
  }
}
