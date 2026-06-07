# terraform-azure-platform

[![apply-verify-destroy](https://github.com/bertrandmbanwi/terraform-azure-platform/actions/workflows/apply-verify-destroy.yml/badge.svg)](https://github.com/bertrandmbanwi/terraform-azure-platform/actions/workflows/apply-verify-destroy.yml)

Ephemeral Azure platform, including a real AKS cluster, provisioned entirely
through CI with zero stored cloud credentials. Every run builds the full
platform, independently verifies it against ARM and the Kubernetes API,
archives evidence, and destroys everything in reverse order. The only
persistent resources are a state storage account and the audit trail.

## Why ephemeral

Most portfolio Terraform proves it compiled once. This repo proves, on every
run, that the complete lifecycle works: provision, validate out of band at
the kubelet level, tear down. A weekly scheduled run re-proves it without
human involvement.

The economics are the point: Infracost estimates this platform at roughly
$55/month if left running. A full lifecycle run consumes about nine minutes
of one D2s_v3 node, around one and a half cents. The gap between the
steady-state estimate and the actual spend is the value of the pattern,
quantified on every pull request.

## Architecture

Two repositories:

- [terraform-azure-modules](https://github.com/bertrandmbanwi/terraform-azure-modules):
  versioned module library (network, aks), consumed via git source with
  commit-SHA pinning
- this repo: numbered stacks applied in order, each with isolated state

Stacks:

| Stack | Purpose | State key |
|---|---|---|
| 00_bootstrap | One-time: state backend, GitHub OIDC federation, resource providers | none (script) |
| 01_foundation | Resource group, vnet, subnets, NSGs | 01_foundation.tfstate |
| 02_cluster | AKS: workload identity, OIDC issuer, Azure CNI, network policy | 02_cluster.tfstate |

02_cluster reads 01_foundation's outputs via remote state, which only
resolve while foundation exists. That is why cluster PRs get a
validate-only gate (fmt, validate, checkov) rather than a plan, and why the
lifecycle workflow is an ordered orchestration: 01 up, 02 up, verify, then
02 down before 01 down. Tearing down a vnet under a live cluster is the
failure the reverse ordering exists to prevent.

Authentication: GitHub Actions OIDC federated to an Entra app registration.
No client secrets exist anywhere. PR runs authenticate via a `pull_request`
subject claim, main-branch runs via `refs/heads/main`. The bootstrap script
creates both federated credentials.

## Pipelines

- **plan.yml** (PRs): three parallel jobs. Full plan for 01_foundation
  (fmt, init with readonly lockfile, validate, plan, checkov); validate-only
  for 02_cluster (remote-state reason above); Infracost diff across both
  stacks, posted as a living PR comment.
- **apply-verify-destroy.yml** (manual + weekly): ordered apply of both
  stacks, then a separately authenticated session verifies against ARM
  (provisioning state) and against Kubernetes itself
  (`kubectl wait --for=condition=Ready`), evidence uploaded as an artifact,
  then destroys run unconditionally via `if: always()` in reverse order.
- **janitor.yml** (every 6 hours): deletes any resource group tagged
  `ephemeral=true`. It shares the lifecycle's concurrency group, so it can
  only run while no lifecycle is active, which means anything tagged
  ephemeral that it finds is orphaned by definition. No TTL math required.

## Design decisions

- **SHA-pinned module sources.** Tags are mutable; commit hashes are not
  (CKV_TF_1). Version bumps update the hash, with the human-readable
  version kept in a comment.
- **One concurrency group, never cancel-in-progress.** Everything touching
  this platform's state serializes through `tf-platform`. Cancelling
  Terraform mid-run orphans the state blob lease, so runs queue instead of
  killing each other.
- **Out-of-band verification.** Terraform reporting success, ARM reporting
  Succeeded, and a kubelet reporting Ready are three different claims. The
  verify step checks the strongest one available.
- **Destroy runs even on failure.** Evidence capture and both destroy steps
  use `if: always()`. A failed verify still leaves a clean subscription and
  a downloadable crime scene.
- **terraform_wrapper disabled in the lifecycle workflow.** The
  setup-terraform wrapper contaminates `terraform output -raw`, which the
  verify step consumes in shell.
- **Lock files committed with multi-platform hashes** (darwin_arm64 +
  linux_amd64), enforced with `init -lockfile=readonly` so drift fails
  loudly instead of self-mutating.
- **No kube_config output.** Outputs land in state and in evidence
  artifacts; credentials are retrieved at verify time via
  `az aks get-credentials` instead.
- **Service CIDR pinned outside the vnet range** (172.16.0.0/16 vs
  10.10.0.0/16) so cluster services can never collide with vnet addressing.
- **The module library does not create resource groups** and ships NSGs
  with no custom rules: Azure defaults already deny inbound internet, and a
  library guessing at workload rules would be wrong in one direction or
  the other.

## Troubleshooting log (real failures from building this)

- **`SubscriptionNotFound` on storage account creation while the
  subscription provably exists.** Cause: the Microsoft.Storage resource
  provider is unregistered on fresh subscriptions; the storage
  name-availability precheck returns this misleading error. Resource groups
  still create fine because Microsoft.Resources is pre-registered. Fix:
  `az provider register`, now a guard in bootstrap.sh. Isolated with
  `bash -x` after `--output none` had been hiding which command actually
  failed.
- **AKS create failed 400: "VM size Standard_B2s is not allowed in your
  subscription in location centralus."** Free trial subscriptions carry a
  restricted per-region VM catalog; the original x64 B-series is excluded
  here. Fix: pick from the allowed list in the error (Standard_D2s_v3),
  after confirming with `az vm list-skus --location <region> --size <sku>`
  that the restrictions field is empty. Bonus: this failure validated the
  lifecycle's failure path end to end. Evidence still uploaded, both
  destroys still ran via `if: always()`, zero orphaned resources, zero cost.
- **Node OS disk silently defaulted to 128GB Premium (P10, ~20 USD/month),
  more than half the node's own cost.** Surfaced by the Infracost PR
  comment, not by any error. Fixed in module v0.2.1 with a 32GB default,
  cutting the cluster estimate ~27%. Cost review in PRs exists for exactly
  this class of invisible default.
- **AADSTS5000225 on login.** A second, dormant tenant on the same account
  had been blocked by Microsoft's inactivity lifecycle policy and poisoned
  the CLI's multi-tenant discovery. Fix: always `az login --tenant <id>`.
- **Plan job hung minutes at "Acquiring state lock."** Stale blob lease
  from an interrupted run. Fix: break the lease, then prevent recurrence
  with the shared concurrency group.
- **GitHub rejected pushes at the 100MB limit.** `.terraform/` provider
  binaries (218MB) committed before a `.gitignore` existed. Required
  history rewrite; the binary stays in history even after deletion
  otherwise.
- **CI silently mutated the committed lock file** because it was generated
  on macOS only. Fix: `terraform providers lock` for both platforms plus
  readonly enforcement.

## Running this yourself

1. `00_bootstrap/bootstrap.sh <subscription_id> <org/repo> [location]`
   (idempotent; prints the three values to add as GitHub Actions variables,
   plus the state storage account name)
2. Update the backend storage account name in each stack's versions.tf
3. Add an `INFRACOST_API_KEY` repo secret (free tier) for the cost job
4. Open a PR touching a stack: plan, validation, checkov, and cost diff run
   automatically
5. Merge, then dispatch apply-verify-destroy from the Actions tab and watch
   a Kubernetes cluster build itself, prove itself, and remove itself in
   about twelve minutes
