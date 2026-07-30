# Operations

Day-2 guidance for living with this demo beyond the initial deploy.
Everything here assumes you've completed the runsheet in
`docs/DEMO-RUNSHEET.md` at least once.

## Idempotent re-runs

Every script in `scripts/00-99` is designed to be safely re-run:

- `00-check-tools.ps1` / `01-test-cloud-access.ps1` are pure reads.
- `02-select-regions.ps1` overwrites `artifacts/region-selection.json` fresh each time (re-run after completing AWS/GCP login to upgrade their entries from "fallback" to "dynamically verified").
- `03-init-plan.ps1` / `04-apply.ps1` are ordinary `terraform init`/`plan`/`apply` — Terraform's own idempotency applies; re-running with no config changes plans/applies zero changes.
- `05-connect-arc.ps1` / `06-join-fleet.ps1` check for an existing `connectedClusters` / Fleet member resource before creating one, so re-running after a partial failure (e.g., you only got AWS authenticated after the first pass) only acts on what's missing.
- `07-deploy-workload.ps1` uses `kubectl apply`, so re-running after an image tag bump or override edit reconciles in place.
- `99-destroy-all.ps1` skips any cloud/resource that's already gone rather than erroring.

This means the normal operational pattern is: **fix the one thing that was
blocked, then just re-run the same numbered script** — never edit state by
hand.

## Scaling

- **AKS/EKS node count**: edit `node_count` (AKS) or `node_desired_size` (EKS) in the respective `terraform.tfvars`, then re-run `03-init-plan.ps1` + `04-apply.ps1` for that cloud only (`ENABLE_AWS=false`/`ENABLE_GCP=false` in `.env` to scope it).
- **GKE node pool**: already autoscales 2-4 nodes per zone by default (`gke_node_pool_min_count`/`max_count` in `terraform/gcp/variables.tf`) — no action needed for normal load; raise the max for a larger demo audience.
- **Online Boutique pod replicas**: each Deployment in `kubernetes/base/` ships with upstream's default `replicas: 1`. For a louder demo, add a `ResourceOverride` (or a plain kustomize patch in `kubernetes/base/` if you want it on all three clouds identically) rather than editing the Deployment YAML in place, to keep the override-based customization story consistent.

## Updating the application version

Online Boutique is pinned to `v0.10.6` throughout `kubernetes/base/*.yaml`
(exact image tags, not `:latest`) for reproducibility. To move to a newer
upstream release:

1. Check the [upstream release notes](https://github.com/GoogleCloudPlatform/microservices-demo/releases) for breaking changes.
2. Update the image tag in each affected `kubernetes/base/*.yaml` file (search for the old tag to find every reference).
3. Re-run `07-deploy-workload.ps1` — Fleet propagates the change to all three members from the one edit.
4. Re-run `08-validate-demo.ps1` to confirm the smoke test still passes on all three.

## Cost monitoring

- Azure: `az consumption usage list` or the Cost Management blade, scoped to the resource group in `.env`'s `AZURE_RESOURCE_GROUP`.
- AWS: Cost Explorer, filtered by the tags Terraform applies (`Project=fleet-arc-demo`) — see `terraform/aws/main.tf`'s default tags block.
- GCP: Billing reports, filtered by label (`project=fleet-arc-demo` applied to created resources where the resource type supports labels).
- All three roots tag/label their resources consistently specifically so a cost query can isolate "everything this demo created" from other activity in a shared subscription/account/project.

## Extending to a 4th cloud (or a different Kubernetes distribution)

The pattern generalizes cleanly:

1. Add `terraform/<cloud>/` following the same shape as the existing three roots (own provider block, own `variables.tf`/`outputs.tf`, no cross-root dependency).
2. Add the cloud to `terraform/environments/demo/` as one more gated `terraform_remote_state` data source (`count = fileexists(...) ? 1 : 0` pattern — see `docs/ARCHITECTURE.md`).
3. Add one more `ENABLE_<CLOUD>` flag to `.env.example` and thread it through `scripts/lib/common.ps1`'s `Get-EnabledClouds`.
4. Onboard the new cluster to Fleet the same way EKS/GKE are: Arc-connect (if not natively Azure) then `az fleet member create --member-labels cloud=<new>,provider=<new>,demo=fleet-arc-online-boutique,location=<region>,environment=demo`.
5. Add one more `clusterSelector` block (not a new file) to each existing `ResourceOverride` if the new cloud needs its own annotation/env value — the override files are intentionally structured as "one file per concern, one rule per cloud" to make this a small diff, not a new file.

No change to `kubernetes/base/` or the `ClusterResourcePlacement` itself is
needed — the CRP already selects on the generic `demo=fleet-arc-online-boutique`
label, which the new member gets automatically at join time.

## Explicit non-goals

This demo does not implement, and has no roadmap to implement:

- Backup/disaster recovery for any component (nothing here holds state that survives a member being deleted — Redis is a fresh in-cluster cache, not a data store of record).
- Blue/green or canary rollout automation for application updates.
- Network policy / service mesh / mTLS between services.
- Autoscaling of the Fleet hub itself (it runs a fixed single node — hub load in this demo is trivially small: 1 CRP + 3 overrides + 3 members).
- Multi-tenancy — this is a single-team demo environment model throughout (one `.env`, one set of enabled clouds, one Fleet).

## Tearing down

`make destroy` / `pwsh scripts\99-destroy-all.ps1` removes resources in
strict reverse-dependency order (hub workload → Fleet members → Arc
disconnect → `terraform destroy` gcp → aws → azure) so that, for example,
Terraform never tries to destroy an EKS cluster that Fleet/Arc still has a
live reference to. It requires typed `"destroy"` confirmation unless you
pass `-AutoApprove`, and — like every other script — only touches clouds
enabled in `.env`.
