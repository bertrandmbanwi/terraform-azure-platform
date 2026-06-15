#!/usr/bin/env bash
#
# bootstrap.sh - One-time setup for Terraform state backend and GitHub OIDC.
# Creates: resource group, storage account + container for remote state,
# an Entra ID app registration with federated credentials for GitHub Actions,
# and scoped role assignments (Contributor plus a constrained RBAC admin for
# Key Vault). No client secrets are created or stored.
# Safe to rerun: all steps are idempotent and reuse existing resources.
#
# Usage: ./bootstrap.sh <subscription_id> <github_org/repo> [location]
# Example: ./bootstrap.sh 00000000-0000-0000-0000-000000000000 myorg/myrepo centralus

set -euo pipefail

usage() {
  echo "Usage: $0 <subscription_id> <github_org/repo> [location]"
  exit 1
}

[[ $# -lt 2 ]] && usage

SUBSCRIPTION_ID="$1"
GITHUB_REPO="$2"
LOCATION="${3:-centralus}"
RG_NAME="rg-tfstate"
CONTAINER_NAME="tfstate"
APP_NAME="github-oidc-terraform-platform"
# Providers needed by this script and the later stacks (network, AKS, monitoring).
PROJECT_PROVIDERS=(Microsoft.Storage Microsoft.Network Microsoft.Compute Microsoft.ContainerService Microsoft.OperationalInsights Microsoft.ManagedIdentity Microsoft.KeyVault)

# --- Pre-flight checks -------------------------------------------------------

command -v az >/dev/null 2>&1 || { echo "ERROR: Azure CLI not found." >&2; exit 1; }

[[ "${SUBSCRIPTION_ID}" =~ ^[0-9a-fA-F-]{36}$ ]] \
  || { echo "ERROR: '${SUBSCRIPTION_ID}' does not look like a subscription GUID." >&2; exit 1; }

[[ "${GITHUB_REPO}" =~ ^[^/]+/[^/]+$ ]] \
  || { echo "ERROR: '${GITHUB_REPO}' must be in org/repo format." >&2; exit 1; }

az account show >/dev/null 2>&1 \
  || { echo "ERROR: Not logged in. Run: az login --tenant <tenant_id>" >&2; exit 1; }

az account set --subscription "${SUBSCRIPTION_ID}"

ACTIVE_SUB="$(az account show --query id --output tsv)"
[[ "${ACTIVE_SUB}" == "${SUBSCRIPTION_ID}" ]] \
  || { echo "ERROR: Active subscription is ${ACTIVE_SUB}, expected ${SUBSCRIPTION_ID}." >&2; exit 1; }

# --- Resource provider registration ------------------------------------------
# Fresh subscriptions have most providers unregistered. Unregistered providers
# fail with misleading errors (e.g. SubscriptionNotFound from storage).

echo "==> Checking resource provider registrations"
for ns in "${PROJECT_PROVIDERS[@]}"; do
  state="$(az provider show --namespace "${ns}" --query registrationState --output tsv 2>/dev/null || echo "Unknown")"
  if [[ "${state}" != "Registered" ]]; then
    echo "    Registering ${ns} (was: ${state})"
    az provider register --namespace "${ns}" --output none
  fi
done

# Block only on Microsoft.Storage since this script needs it now.
# The rest finish in the background before the later stacks run.
echo "==> Waiting for Microsoft.Storage registration to complete"
az provider register --namespace Microsoft.Storage --wait --output none

# --- State backend ------------------------------------------------------------

az group create --name "${RG_NAME}" --location "${LOCATION}" --output none

# Reuse an existing state storage account if one exists in the RG; otherwise
# create one with a random suffix (names must be globally unique).
SA_NAME="$(az storage account list --resource-group "${RG_NAME}" --query "[0].name" --output tsv)"
if [[ -z "${SA_NAME}" ]]; then
  SA_NAME="sttfstate$(openssl rand -hex 4)"
  echo "==> Creating state storage account: ${RG_NAME}/${SA_NAME}/${CONTAINER_NAME}"
  az storage account create \
    --name "${SA_NAME}" \
    --resource-group "${RG_NAME}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
else
  echo "==> Reusing existing state storage account: ${SA_NAME}"
fi

az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${SA_NAME}" \
  --auth-mode login \
  --output none

# --- Entra app registration + GitHub OIDC federation --------------------------

APP_ID="$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" --output tsv)"
if [[ -z "${APP_ID}" ]]; then
  echo "==> Creating Entra app registration: ${APP_NAME}"
  APP_ID="$(az ad app create --display-name "${APP_NAME}" --query appId --output tsv)"
else
  echo "==> Reusing existing app registration: ${APP_NAME} (${APP_ID})"
fi

az ad sp show --id "${APP_ID}" >/dev/null 2>&1 || az ad sp create --id "${APP_ID}" --output none

# Federated credentials: trust GitHub Actions tokens from main and from PRs.
existing_creds="$(az ad app federated-credential list --id "${APP_ID}" --query "[].name" --output tsv)"

if ! grep -q "^github-main$" <<< "${existing_creds}"; then
  echo "==> Adding federated credential: github-main"
  az ad app federated-credential create --id "${APP_ID}" --parameters "{
    \"name\": \"github-main\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none
fi

if ! grep -q "^github-pr$" <<< "${existing_creds}"; then
  echo "==> Adding federated credential: github-pr"
  az ad app federated-credential create --id "${APP_ID}" --parameters "{
    \"name\": \"github-pr\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_REPO}:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none
fi

# --- Role assignments ----------------------------------------------------------
# Retry: a freshly created service principal can take up to a minute to
# replicate, and role assignment fails with PrincipalNotFound until then.

echo "==> Assigning Contributor at subscription scope (tighten later per stack)"
if [[ -z "$(az role assignment list --assignee "${APP_ID}" --role Contributor --scope "/subscriptions/${SUBSCRIPTION_ID}" --query "[0].id" --output tsv)" ]]; then
  for attempt in 1 2 3 4 5; do
    if az role assignment create \
      --assignee "${APP_ID}" \
      --role "Contributor" \
      --scope "/subscriptions/${SUBSCRIPTION_ID}" \
      --output none 2>/dev/null; then
      break
    fi
    [[ "${attempt}" -eq 5 ]] && { echo "ERROR: Role assignment failed after 5 attempts." >&2; exit 1; }
    echo "    Principal not replicated yet, retrying in 15s (attempt ${attempt}/5)"
    sleep 15
  done
fi

# Scoped RBAC admin so stack 03 can create the two Key Vault role assignments it
# needs, and nothing else. The ABAC condition restricts the assignable role
# definitions to Key Vault Secrets Officer and Key Vault Secrets User only.
# Verify the GUIDs with:
#   az role definition list --name "Key Vault Secrets User" --query "[].name" -o tsv

RBAC_ADMIN_CONDITION="$(cat <<'CONDITION'
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
CONDITION
)"

echo "==> Assigning scoped Role Based Access Control Administrator (Key Vault roles only)"
if [[ -z "$(az role assignment list --assignee "${APP_ID}" --role "Role Based Access Control Administrator" --scope "/subscriptions/${SUBSCRIPTION_ID}" --query "[0].id" --output tsv)" ]]; then
  for attempt in 1 2 3 4 5; do
    if az role assignment create \
      --assignee "${APP_ID}" \
      --role "Role Based Access Control Administrator" \
      --scope "/subscriptions/${SUBSCRIPTION_ID}" \
      --condition "${RBAC_ADMIN_CONDITION}" \
      --condition-version "2.0" \
      --description "CI may assign only Key Vault Secrets Officer/User (stack 03)" \
      --output none 2>/dev/null; then
      break
    fi
    [[ "${attempt}" -eq 5 ]] && { echo "ERROR: RBAC admin role assignment failed after 5 attempts." >&2; exit 1; }
    echo "    Principal not replicated yet, retrying in 15s (attempt ${attempt}/5)"
    sleep 15
  done
fi

# --- Summary -------------------------------------------------------------------

TENANT_ID="$(az account show --query tenantId --output tsv)"

cat <<EOF

Bootstrap complete. Add these as GitHub Actions variables (not secrets, none are sensitive):
  AZURE_CLIENT_ID:       ${APP_ID}
  AZURE_TENANT_ID:       ${TENANT_ID}
  AZURE_SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}

Backend config for each stack:
  resource_group_name  = "${RG_NAME}"
  storage_account_name = "${SA_NAME}"
  container_name       = "${CONTAINER_NAME}"
  key                  = "<stack_name>.tfstate"
EOF
