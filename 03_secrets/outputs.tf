output "key_vault_name" {
  description = "Name of the demo Key Vault."
  value       = azurerm_key_vault.this.name
}

output "key_vault_uri" {
  description = "Vault URI; must match the vaultUrl in the gitops SecretStore."
  value       = azurerm_key_vault.this.vault_uri
}

output "demo_secret_name" {
  description = "Demo secret name; matches remoteRef.key in the ExternalSecret."
  value       = azurerm_key_vault_secret.demo.name
}
