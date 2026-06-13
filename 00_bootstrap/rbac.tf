data "azurerm_subscription" "current" {}

# Allows the CI service principal to assign ONLY the two Key Vault data-plane
# roles that stack 03 needs, scoped by an ABAC condition. It cannot hand out any
# other role, so this is a tightly bounded escalation of the CI identity.
resource "azurerm_role_assignment" "ci_kv_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  # Match this to the actual service principal resource name in your 00 stack.
  # If you only have the application, add a data "azuread_service_principal"
  # keyed on its client_id and reference that instead.
  principal_id   = azuread_service_principal.github_oidc.object_id
  principal_type = "ServicePrincipal"

  condition_version = "2.0"
  # GUIDs: Key Vault Secrets Officer (b86a8fe4-...), Key Vault Secrets User (4633458b-...).
  # Verify with: az role definition list --name "Key Vault Secrets User" --query "[].name" -o tsv
  condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b86a8fe4-44ce-4948-aee5-eccb2c155cd6, 4633458b-17de-408a-b874-0445c86b69e6}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {b86a8fe4-44ce-4948-aee5-eccb2c155cd6, 4633458b-17de-408a-b874-0445c86b69e6}
     )
    )
  EOT
}
