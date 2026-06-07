# subscription_id is intentionally not set here. azurerm v4 requires it
# explicitly, and we supply it via the ARM_SUBSCRIPTION_ID environment
# variable in CI and locally, keeping the config portable across
# subscriptions without code changes.
provider "azurerm" {
  features {}
}
