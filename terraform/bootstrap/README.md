# terraform/bootstrap

Optional, **off by default**. This demo's Terraform roots (`azure/`, `aws/`,
`gcp/`, `environments/demo/`) all use local state (`terraform.tfstate` on
disk, gitignored) - there is no requirement to run anything in this folder
to complete the demo.

This folder exists only so that, if you later want to move to shared/remote
Terraform state (recommended for anything beyond a personal demo - local
state can't be safely shared between people or CI runners), the storage
resources for all three clouds are already written, reviewed, and ready to
apply on demand - you don't have to design them from scratch under time
pressure.

## Why three separate sub-roots, not one

`azure/`, `aws/`, `gcp/` are three **independent** Terraform roots (like the
top-level `terraform/azure`, `terraform/aws`, `terraform/gcp`), each
declaring only its own cloud's provider. This is deliberate, not
duplication: Terraform initializes every `provider` block a root declares as
soon as you run `plan`/`apply`, even for resources with `count = 0`. A
single combined bootstrap root declaring all three providers would force you
to have valid Azure **and** AWS **and** GCP credentials just to bootstrap
one cloud's state storage - exactly the kind of unwanted cross-cloud
coupling this whole repo is designed to avoid elsewhere. Keeping them
separate means you can bootstrap (or skip) each cloud entirely
independently, same as the top-level cloud roots.

## Why local state is the default here

- This is a single-operator demo repo, not a team-shared production
  environment. Local state avoids needing to stand up and pay for (however
  cheaply) cloud storage before you've even created the demo itself.
- Each of the 3 cloud roots is already independently destroyable
  (`scripts/99-destroy-all.ps1`); remote state adds real value once multiple
  people or CI pipelines need to collaborate on the *same* state, which is
  not this repo's scenario.

## How to switch a root to remote state

1. Decide which cloud(s) need it. For each one, `cd
   terraform/bootstrap/<cloud>` and create a gitignored
   `terraform.tfvars` there with `create_state_backend = true`.
2. Set `state_storage_suffix` to something unique to your account (storage
   account / S3 bucket / GCS bucket names must be globally unique across
   every customer of that cloud - your subscription/account/project ID's
   first several characters work well).
3. `terraform init && terraform apply` in that sub-folder only. This
   creates just that cloud's storage resource - it does not touch the
   top-level `terraform/azure`, `terraform/aws`, or `terraform/gcp` roots.
4. Copy the `state_backend_config` output into that cloud's top-level root
   (`terraform/<cloud>/versions.tf`), then run `terraform init
   -migrate-state` in that root to move its existing local state into the
   new backend.

Each cloud's backend resource is genuinely minimal (a storage
account/bucket, versioning, encryption/public-access-block where
applicable) - no you don't need a DynamoDB lock table for the AWS backend if
you're on Terraform >= 1.10 (`use_lockfile = true` in the S3 backend block
handles native, lock-table-free state locking).

## Cost

Applying any of the three sub-roots with the default `create_state_backend
= false` creates **zero** resources. Enabling it creates one small storage
account/bucket for that cloud only - billed at each provider's ordinary
object-storage rates for a single small state file.
