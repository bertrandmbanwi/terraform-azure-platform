# Persistent resource group for platform-level managed identities. Survives
# cluster rebuilds so the ESO identity's client ID stays stable.
resource "azurerm_resource_group" "identity" {
  name     = "rg-platform-identity"
  location = var.location
  tags = {
    project    = "platform"
    managed_by = "terraform"
    persistent = "true"
  }
}

# Identity used by External Secrets Operator to read Key Vault. Created once and
# reused every run, so its client ID can be hardcoded in the gitops ServiceAccount.
resource "azurerm_user_assigned_identity" "eso" {
  name                = "id-eso-platform"
  resource_group_name = azurerm_resource_group.identity.name
  location            = azurerm_resource_group.identity.location
  tags = {
    project    = "platform"
    managed_by = "terraform"
    persistent = "true"
  }
}
