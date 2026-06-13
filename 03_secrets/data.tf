data "azurerm_client_config" "current" {}

# Same backend coordinates as your foundation remote state, different keys.
data "terraform_remote_state" "cluster" {
  backend = "azurerm"
  config = {
    resource_group_name  = "REPLACE_WITH_TFSTATE_RG"
    storage_account_name = "REPLACE_WITH_TFSTATE_SA"
    container_name       = "REPLACE_WITH_TFSTATE_CONTAINER"
    key                  = "02_cluster.tfstate"
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "azurerm"
  config = {
    resource_group_name  = "REPLACE_WITH_TFSTATE_RG"
    storage_account_name = "REPLACE_WITH_TFSTATE_SA"
    container_name       = "REPLACE_WITH_TFSTATE_CONTAINER"
    key                  = "00_bootstrap.tfstate" # match your actual 00 state key
  }
}
