locals {
  name = "${var.project}-${var.env}"

  common_tags = {
    project    = var.project
    env        = var.env
    managed_by = "terraform"
    stack      = "02_cluster"
    ephemeral  = "true"
  }
}

# Reads 01_foundation's outputs from its state file. Only valid while
# foundation exists, which the lifecycle workflow guarantees by ordering.
data "terraform_remote_state" "foundation" {
  backend = "azurerm"

  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateae74a3bf"
    container_name       = "tfstate"
    key                  = "01_foundation.tfstate"
  }
}

module "aks" {
  # v0.2.0
  source = "git::https://github.com/bertrandmbanwi/terraform-azure-modules.git//aks?ref=d7a21b285fe13174e5bd93d394a4abe20b7ce905"

  name                = local.name
  location            = var.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name
  subnet_id           = data.terraform_remote_state.foundation.outputs.subnet_ids["aks"]
  node_count          = var.node_count
  vm_size             = var.vm_size
  tags                = local.common_tags
}
