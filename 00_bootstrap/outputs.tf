output "eso_identity_client_id" {
  description = "Client ID of the ESO identity. Paste into the gitops ServiceAccount annotation."
  value       = azurerm_user_assigned_identity.eso.client_id
}

output "eso_identity_principal_id" {
  description = "Principal (object) ID of the ESO identity, for the Key Vault role assignment in 03."
  value       = azurerm_user_assigned_identity.eso.principal_id
}

output "eso_identity_id" {
  description = "Resource ID of the ESO identity, parent for the federated credential in 03."
  value       = azurerm_user_assigned_identity.eso.id
}

output "eso_identity_resource_group_name" {
  description = "Resource group of the ESO identity."
  value       = azurerm_resource_group.identity.name
}
