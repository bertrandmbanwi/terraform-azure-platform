provider "azurerm" {
  features {
    key_vault {
      # Purge the vault on destroy so the stable name is free to recreate next run,
      # and recover rather than fail if a prior purge ever did not complete.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  use_oidc = true
}
