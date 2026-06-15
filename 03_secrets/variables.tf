variable "location" {
  description = "Azure region for the Key Vault. Match the rest of the platform."
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique Key Vault name (3-24 chars, starts with a letter)."
  type        = string
  default     = "kv-bm-platform-dev"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Name must be 3-24 chars, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "demo_secret_name" {
  description = "Demo secret name in Key Vault, pulled by ESO."
  type        = string
  default     = "demo-secret"
}

variable "demo_secret_value" {
  description = "Throwaway demo value to prove the sync path. Real secrets would never be seeded through Terraform state."
  type        = string
  default     = "hello-from-key-vault"
}

variable "sa_namespace" {
  description = "Namespace of the ESO ServiceAccount that authenticates to Key Vault."
  type        = string
  default     = "secret-demo"
}

variable "sa_name" {
  description = "ServiceAccount name federated to the ESO identity."
  type        = string
  default     = "kv-reader"
}
