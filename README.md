# terraform-azure-platform

[![apply-verify-destroy](https://github.com/bertrandmbanwi/terraform-azure-platform/actions/workflows/apply-verify-destroy.yml/badge.svg)](https://github.com/bertrandmbanwi/terraform-azure-platform/actions/workflows/apply-verify-destroy.yml)

Ephemeral Azure platform provisioned entirely through CI with zero stored cloud
credentials. Every piece of infrastructure in this repo is created, independently
verified against ARM, evidence-captured, and destroyed in a single pipeline run.
The only persistent resources are a state storage account and the audit trail.

## Why ephemeral

Most portfolio Terraform proves it compiled once. This repo proves, on every
run, that the full lifecycle works: provision, validate out of band, tear down.
The weekly scheduled run re-proves it without human involvement. Cost of the
entire platform at rest: cents per month for state storage.

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
| 02_cluster | AKS (in progress) | 02_cluster.tfstate |

Authentication: GitHub Actions OIDC federated to an Entra app registration.
No client secrets exist. PR runs authenticate via a `pull_request` subject
claim, main-branch runs via `refs/heads/main`. The bootstrap script creates
both federated credentials.

## Pipelines

- **plan.yml** (PRs): fmt, init with readonly lockfile, validate, plan,
  checkov scan, Infracost diff commented on the PR
- **apply-verify-destroy.yml** (manual + weekly): apply, then a separately
  authenticated session interrogates ARM to confirm the resources exist
  (provisioning state, vnet presence, subnet count), evidence uploaded as an
  artifact, destroy runs unconditionally via `if: always()`
- **janitor.yml** (every 6 hours): deletes any resource group tagged
  `ephemeral=true`; the safety net for a failed destroy

## Design decisions

- **SHA-pinned module sources.** Tags are mutable; commit hashes are not
  (CKV_TF_1). Version bumps update the hash, with the human-readable version
  kept in a comment.
- **Shared concurrency group, never cancel-in-progress.** Everything touching
  one state file serializes through one group. Cancelling Terraform mid-run
  orphans the state blob lease, so runs queue instead of killing each other.
  The janitor joins the same group, which is what makes it safe: anything
  tagged ephemeral that exists while the janitor holds the group is orphaned
  by definition. No timestamps needed.
- **Out-of-band verification.** Terraform reporting success and the resources
  existing are different claims. The verify step authenticates separately and
  asks ARM directly.
- **terraform_wrapper disabled in the lifecycle workflow.** The setup-terraform
  wrapper contaminates `terraform output -raw`, which the verify step consumes.
- **Lock file committed with multi-platform hashes** (darwin_arm64 + linux_amd64),
  enforced with `init -lockfile=readonly` so drift fails loudly.
- **Module library does not create resource groups** and ships NSGs with no
  custom rules: Azure defaults already deny inbound internet, and a library
  guessing at workload rules would be wrong in one direction or the other.

## Troubleshooting log (real failures from building this)

- **`SubscriptionNotFound` on storage account creation while the subscription
  provably exists.** Cause: the Microsoft.Storage resource provider is
  unregistered on fresh subscriptions; the storage name-availability precheck
  returns this misleading error. Resource groups still create fine because
  Microsoft.Resources is pre-registered. Fix: `az provider register`, now a
  guard in bootstrap.sh. Isolated with `bash -x` after `--output none` had
  been hiding which command actually failed.
- **AADSTS5000225 on login.** A second, dormant tenant on the same account had
  been blocked by Microsoft's inactivity lifecycle policy and poisoned the
  CLI's multi-tenant discovery. Fix: always `az login --tenant <id>`.
- **Plan job hung minutes at "Acquiring state lock."** Stale blob lease from
  an interrupted run. Fix: break the lease, then prevent recurrence with the
  shared concurrency group.
- **GitHub rejected pushes at the 100MB limit.** `.terraform/` provider
  binaries (218MB) committed before a `.gitignore` existed. Required history
  rewrite; the binary stays in history even after deletion otherwise.
- **CI silently mutated the committed lock file** because it was generated on
  macOS only. Fix: `terraform providers lock` for both platforms plus
  readonly enforcement.

## Running this yourself

1. `00_bootstrap/bootstrap.sh <subscription_id> <org/repo> [location]`
   (idempotent; prints the three values to add as GitHub Actions variables)
2. Update the backend storage account name in each stack's versions.tf
3. Open a PR touching a stack: plan + checkov + cost diff run automatically
4. Merge, then dispatch apply-verify-destroy from the Actions tab
