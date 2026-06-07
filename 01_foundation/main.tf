locals {
  name = "${var.project}-${var.env}"

  common_tags = {
    project    = var.project
    env        = var.env
    managed_by = "terraform"
    stack      = "01_foundation"
    ephemeral  = "true"
  }

  subnets = {
    # /22 because Azure CNI assigns an IP per pod; a /24 exhausts fast.
    aks = {
      address_prefixes = [cidrsubnet(var.address_space[0], 6, 0)]
    }
    # Service endpoints subnet for storage/key vault access from the vnet.
    endpoints = {
      address_prefixes  = [cidrsubnet(var.address_space[0], 8, 16)]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
  }
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.common_tags
}

module "network" {
  # v0.1.0; pinned to the commit SHA rather than the tag because tags are
  # mutable and SHA pinning is the supply chain control (CKV_TF_1).
  source = "git::https://github.com/bertrandmbanwi/terraform-azure-modules.git//network?ref=74754c10dd879ca2e4b5790c80903b4f240f19e9"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = var.address_space
  subnets             = local.subnets
  tags                = local.common_tags
}
