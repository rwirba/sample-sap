variable "aks_name" {
  type        = string
  description = "Name of the AKS cluster"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "node_count" {
  type        = number
  default     = 2
}

variable "node_vm_size" {
  type        = string
  default     = "Standard_DS2_v2"
}

variable "acr_id" {
  type        = string
  description = "ID of the ACR to assign AcrPull role"
}

# variable "acr_id" {
#   description = "The full resource ID of the ACR"
# }