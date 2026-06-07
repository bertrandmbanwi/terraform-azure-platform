output "cluster_name" {
  description = "AKS cluster name, consumed by the verify step."
  value       = module.aks.cluster_name
}

output "resource_group_name" {
  description = "Resource group containing the cluster."
  value       = data.terraform_remote_state.foundation.outputs.resource_group_name
}

output "oidc_issuer_url" {
  description = "Workload identity issuer, for later projects."
  value       = module.aks.oidc_issuer_url
}
