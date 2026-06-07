output "resource_group_name" {
  description = "Platform resource group, consumed by 02_cluster."
  value       = azurerm_resource_group.platform.name
}

output "vnet_id" {
  description = "Virtual network resource ID."
  value       = module.network.vnet_id
}

output "subnet_ids" {
  description = "Map of subnet key to subnet ID; 02_cluster reads the aks entry."
  value       = module.network.subnet_ids
}
