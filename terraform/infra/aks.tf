module "aks" {
  source              = "../modules/aks"
  aks_name            = var.aks_name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  acr_id              = module.acr.acr_login_server
}