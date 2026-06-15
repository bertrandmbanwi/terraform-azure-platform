locals {
  rg_name     = data.terraform_remote_state.cluster.outputs.resource_group_name
  oidc_issuer = data.terraform_remote_state.cluster.outputs.oidc_issuer_url

  eso_identity_id           = data.terraform_remote_state.bootstrap.outputs.eso_identity_id
  eso_identity_principal_id = data.terraform_remote_state.bootstrap.outputs.eso_identity_principal_id
  eso_identity_rg           = data.terraform_remote_state.bootstrap.outputs.eso_identity_resource_group_name

  tags = {
    env        = "dev"
    project    = "platform"
    stack      = "03_secrets"
    managed_by = "terraform"
    ephemeral  = "true"
  }
}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = local.rg_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # If your pinned provider rejects this, fall back to: enable_rbac_authorization = true
  rbac_authorization_enabled = true

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # First cut: public access. The CI runner seeds the secret from outside the
  # vnet and the nodes read over public egress. Locking to the endpoints subnet
  # or a private endpoint is a later hardening step.
  public_network_access_enabled = true

  tags = local.tags
}

# Deployer needs data-plane write to seed the demo secret.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# ESO identity needs data-plane read only.
resource "azurerm_role_assignment" "eso_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.eso_identity_principal_id
  principal_type       = "ServicePrincipal"
}

# Key Vault data-plane RBAC is eventually consistent; wait before writing.
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.deployer_secrets_officer]
  create_duration = "90s"
}

resource "azurerm_key_vault_secret" "demo" {
  name         = var.demo_secret_name
  value        = var.demo_secret_value
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [time_sleep.wait_for_rbac]
}

# Bind the persistent ESO identity to THIS run's cluster issuer and the ESO SA.
# Recreated every run because the issuer changes with each cluster.
resource "azurerm_federated_identity_credential" "eso" {
  name                = "eso-${var.sa_namespace}-${var.sa_name}"
  resource_group_name = local.eso_identity_rg
  parent_id           = local.eso_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.oidc_issuer
  subject             = "system:serviceaccount:${var.sa_namespace}:${var.sa_name}"
}
