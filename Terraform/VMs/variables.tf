/*variable "subscription_id" {
  type = string
  default = "<SPNSubscriptionID>"
}

variable "client_id" {
  type = string
  default = "<SPNClientID>"
}

variable "tenant_id" {
  type = string
  default = "<SPNTenantID>"
}

variable "client_secret" {
    type = string
    default = "<SPNClientSecret>"
}

variable "environment" {
    type = string
    default = "public"
}*/

variable "prefix" {
  type = string
  default = "bluekc"
}

variable "resource_group_name" {
  type = string
  default = "Blue-KC-RG"
}

variable "vnet_name" {
  type = string
  default = "vnet"
}

variable "subnet_name" {
  type = string
  default = "vmsubnet"
}

variable "resource_group_location" {
  type = string
  default = "East US"
}

variable "vm_username" {
  type = string
  default = "bluekcadmin"
}

variable "keyvault_id" {
  type = string
  default = "/subscriptions/8688fca6-f9ff-4c38-b2cb-b31972c4a1ad/resourceGroups/Blue-KC-RG/providers/Microsoft.KeyVault/vaults/mullis-bluekc-kv"
}

variable "asetlist" {
  type = list
  default = ["aset1","aset2","aset3","aset4","aset5"]
}

variable "Tags" {
  default = {
    "Environment"   = "Ahead - Azure Lab - Internal"
    "Exception"     = "No"
    "Owner"         = "Shaun Mullis"
    "StopResources" = "Yes"
  }
}

variable "vmdetails" {
  default = [
    {
      name = "vm1"
      asetIndexNum = 0
      size = "Standard_F2"
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    },
    {
      name = "vm2-360"
      asetIndexNum = 2
      size = "Standard_F2"
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    },
    {
      name = "sqlvm1"
      asetIndexNum = 1
      size = "Standard_DS4_v2"
      publisher = "MicrosoftSQLServer"
      offer     = "sql2019-ws2019"
      sku       = "sqldev"
      version   = "latest"
    },
    {
      name = "vm3-fxi"
      asetIndexNum = 3
      size = "Standard_F2"
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    },
    {
      name = "vm4-ui"
      asetIndexNum = 4
      size = "Standard_F2"
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2019-Datacenter"
      version   = "latest"
    }
  ]
}