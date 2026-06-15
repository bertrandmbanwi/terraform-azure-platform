terraform {
  required_version = "~> 1.15.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.75"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Copy the exact backend block from 01_foundation/02_cluster, changing only the key.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateae74a3bf"
    container_name       = "tfstate"
    key                  = "03_secrets.tfstate"
  }
}
