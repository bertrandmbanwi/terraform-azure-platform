variable "project" {
  description = "Project name used in resource naming and tags."
  type        = string
  default     = "platform"
}

variable "env" {
  description = "Environment name (dev, staging, prod). Drives naming and tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources in this stack."
  type        = string
  default     = "centralus"
}

variable "address_space" {
  description = "CIDR blocks for the platform virtual network."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}
