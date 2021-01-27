variable "subscription_id" {
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
}

variable "prefix" {
  type = string
  default = "<PrefixForResourceNames>"
}

variable "resource_group_name" {
  type = string
  default = "<RGName>"
}

variable "resource_group_location" {
  type = string
  default = "East US"
}

variable "adminGroup" {
  type = string
  default = "<AADAdminGroupObjectID>"
}