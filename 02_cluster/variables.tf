variable "project" {
  description = "Project name used in resource naming and tags."
  type        = string
  default     = "platform"
}

variable "env" {
  description = "Environment name (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region; must match 01_foundation."
  type        = string
  default     = "centralus"
}

variable "node_count" {
  description = "AKS default pool node count."
  type        = number
  default     = 1
}

variable "vm_size" {
  description = "AKS node VM size."
  type        = string
  default     = "Standard_B2s"
}
