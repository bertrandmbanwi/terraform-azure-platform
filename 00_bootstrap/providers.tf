# 00_bootstrap/providers.tf  (new file, or add to your existing versions.tf)
provider "azurerm" {
  features {}

  # 00 runs locally with your az login, so CLI auth is used by default.
  # azurerm 4.x requires subscription_id to be set explicitly.
  subscription_id = "635e43cc-4ab9-4134-9b6c-f982c56991b9"
}
