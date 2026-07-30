# Demo Runsheet

A step-by-step execution guide, with expected timing and output, for
running this demo live end-to-end. Every script lives in `scripts/` and can
be run directly (`pwsh scripts\NN-name.ps1`) or via the matching `make`
target.

## Before you start

- [ ] All required CLIs installed and on `PATH` — see the prerequisites table in the [README](../README.md#prerequisites), or just run `make check-tools`.
- [ ] `.env` created and filled in (see next section).
- [ ] For any AWS/GCP cloud you enabled: interactive login already completed (`aws sso login`, `gcloud auth login` + `application-default login`) — see [AUTHENTICATION-AND-PERMISSIONS.md](AUTHENTICATION-AND-PERMISSIONS.md) for the exact commands and required IAM roles.
- [ ] You're comfortable with the approximate cost in the README before running `apply`.

## Configure your `.env`

Everything in this repo is driven by a single `.env` file at the repo root.
It is gitignored and never committed.

```powershell
Copy-Item .env.example .env
```

Then edit it. `.env.example` documents every field; these are the ones that
actually matter for a first run:

| Field | Required? | What to set it to |
|---|---|---|
| `ENABLE_AZURE` / `ENABLE_AWS` / `ENABLE_GCP` | Yes | `true` for each cloud you want to run. **Azure must be `true`** — it hosts the Fleet Manager hub that the other clouds join. Start with Azure-only if you're only set up on one cloud. |
| `OWNER` | Yes | Your email or team alias. Applied as a tag/label on every resource in every cloud so you can find and bill them later. |
| `NAME_PREFIX` | No | 2-10 lowercase alphanumeric chars, default `flarc`. **Change this** if you share a subscription/account with others, so your resource names don't collide with theirs. |
| `GCP_PROJECT_ID` | Only if `ENABLE_GCP=true` | Your GCP **project ID** (not the project name or number). |
| `AWS_PROFILE` | Only if `ENABLE_AWS=true` | The named AWS CLI profile to use, e.g. the one you created with `aws configure sso --profile <name>`. |
| `AZURE_EXPECTED_SUBSCRIPTION_ID` | No, but recommended | Your Azure subscription ID. When set, scripts hard-fail if your active `az` session points somewhere else — cheap insurance against deploying into the wrong subscription. Leave blank to just use whatever `az account show` returns. |
| `AWS_EXPECTED_ACCOUNT_ID` | No, but recommended | Same idea for AWS: your 12-digit account ID. |
| `EXPIRATION_DATE` | No | `YYYY-MM-DD` teardown reminder, applied as a tag. Metadata only — nothing auto-deletes. |
| `*_REGION_OVERRIDE` | No | Leave blank to let `02-select-regions.ps1` discover a working region per cloud. Set only if you have a data-residency or proximity requirement. |

Everything else in `.env.example` has a working default. No passwords, keys,
or secrets belong in this file — see
[AUTHENTICATION-AND-PERMISSIONS.md](AUTHENTICATION-AND-PERMISSIONS.md) for
why, and what to use instead.

### Names and regions in this document

Resource names below use this repo's **default** `.env` values
(`NAME_PREFIX=flarc`, `ENVIRONMENT=demo`). Every cloud resource is named
`<NAME_PREFIX>-<ENVIRONMENT>-<suffix>`, so with the defaults you get
`flarc-demo-rg`, `flarc-demo-aks`, `flarc-demo-eks`, `flarc-demo-gke`,
`flarc-demo-fleet`, and `flarc-demo-nodes`. **If you changed `NAME_PREFIX`
or `ENVIRONMENT`, substitute accordingly** — or run `terraform output` in
the relevant `terraform/<cloud>/` directory to see the real names.

Fleet **member** names (`aks-demo`, `eks-demo`, `gke-demo`) and the
`online-boutique` namespace are fixed and do not vary with `NAME_PREFIX`.

Regions shown (`us-east-1`, `us-central1-a`, `eastus2`) are examples from
one run. Yours are whatever `scripts/02-select-regions.ps1` discovered —
check `artifacts/region-selection.json` before copy-pasting any command.

## Step-by-step

| # | Script | What it does | Typical duration | Billable? |
|---|---|---|---|---|
| 00 | `00-check-tools.ps1` | Verifies all required CLIs/extensions are installed with a minimum version | ~10s | No |
| 00b | `00-bootstrap-auth.ps1` | Checks per-cloud auth status; prints (and can launch) the correct interactive login command for anything missing | Interactive — as long as login takes | No |
| 01 | `01-test-cloud-access.ps1` | Read-only calls per enabled cloud (`az account show`, `aws sts get-caller-identity`, `gcloud projects describe`) to confirm auth actually works | ~5-15s | No |
| 02 | `02-select-regions.ps1` | Dynamically discovers/verifies a region per cloud (falls back to a documented default with reasoning if a cloud is unauthenticated); writes `artifacts/region-selection.json` | ~10-30s | No |
| 03 | `03-init-plan.ps1` | `terraform init` + `validate` + `plan` for every enabled cloud root | ~30-90s per cloud | No |
| 04 | `04-apply.ps1` | `terraform apply` for every enabled cloud root — **creates real, billable infrastructure**. Requires typed confirmation (`Confirm-BillableAction`) unless `-AutoApprove` is passed | **~8-15 min** (AKS/EKS/GKE cluster creation dominates) | **Yes** |
| 05 | `05-connect-arc.ps1` | Runs `az connectedk8s connect` for the enabled non-Azure clouds (EKS, GKE), projecting them into Azure as `connectedClusters` | ~2-4 min per cluster | No (Arc onboarding itself is free) |
| 06 | `06-join-fleet.ps1` | `az fleet member create` for all enabled clouds, applying the `cloud`/`provider`/`demo`/`location`/`environment` labels atomically at join time | ~1-2 min per cluster | No |
| 07 | `07-deploy-workload.ps1` | Applies `kubernetes/base/` (namespace + all 11 Online Boutique services + Redis) as a kustomization to the **hub**, then applies the 3 `ResourceOverride` objects and the `ClusterResourcePlacement`; Fleet propagates the namespace to every labeled member | ~1-3 min to appear on members after CRP applies | No |
| 08 | `08-validate-demo.ps1` | Runs `kubernetes/validation/smoke-test-job.yaml` against each member and polls the `frontend-external` Service until an external IP/hostname is assigned; prints all three live URLs | ~2-5 min (waiting for cloud LB provisioning) | No |
| 99 | `99-destroy-all.ps1` | Full reverse-order teardown: hub workload → Fleet members → Arc disconnect → `terraform destroy` (gcp → aws → azure). Requires typed `"destroy"` confirmation unless `-AutoApprove` | ~10-15 min | No (removes billing) |

Total time for a full, uninterrupted 00→08 run across all three clouds:
**roughly 25-40 minutes**, dominated by cloud control-plane provisioning
(EKS and GKE cluster creation are typically the slowest single steps).

### One manual step between 06 and 07: Fleet hub RBAC

`scripts/07-deploy-workload.ps1` talks to the Fleet hub's **Kubernetes API**,
which Azure subscription-level roles do not grant — even `Owner`. If you
haven't already assigned yourself `Azure Kubernetes Fleet Manager RBAC
Cluster Admin` **at the Fleet resource scope**, step 07 fails with
`Forbidden`.

```powershell
$fleetId = az fleet show -g flarc-demo-rg -n flarc-demo-fleet --query id -o tsv
az role assignment create `
  --role "Azure Kubernetes Fleet Manager RBAC Cluster Admin" `
  --assignee "$(az ad signed-in-user show --query id -o tsv)" `
  --scope $fleetId
```

Wait a minute or two for RBAC propagation, then continue. This assignment
lives on the Fleet resource, so it is **destroyed along with the Fleet** by
`99-destroy-all.ps1` and must be recreated after every fresh `apply`.

## Live demo talk track

1. **Show the repo structure**, not just the running result — the point of this demo is *how little cloud-specific code exists*. `kubernetes/base/` has zero cloud references; `kubernetes/overrides/` has exactly three small files that do.
2. **Show the Fleet hub**: `kubectl --context <hub> get clusterresourceplacement crp-online-boutique -o wide` — point out `PLACEMENT_STATUS` reaching `Successful` for all 3 members.
3. **Show the three live storefronts side by side** (URLs printed by step 08) — same product catalog, same version, running on three different clouds from one deploy.
4. **Show a cloud-specific difference that came from an override, not the app**: `kubectl --context <aks> get svc frontend-external -o jsonpath='{.metadata.annotations}'` vs the same on EKS/GKE — different LB annotations, same Service spec otherwise. Optionally show the `PLATFORM` badge rendering differently in each frontend if the UI theme supports it.
5. **Show `az fleet member list -g <rg> --fleet-name <fleet>`** — three members, three clouds, one label schema.
6. **(Optional) Live-edit an override**: change `frontend-env-platform-override`'s value for one cloud, `kubectl apply` it directly against the hub, and show it reconcile on that member within seconds — without touching `kubernetes/base/` at all.
7. **Close with cost/teardown**: note that this is real billable infrastructure in three clouds, then (if the demo is truly ending) run `make destroy` on screen to show teardown is a first-class, one-command operation — not an afterthought.

## Pausing and resuming clusters without deleting them

For a demo environment that needs to sit idle for a while (overnight at a
multi-day conference, over a weekend, between rehearsal and the live
session), you don't need `make destroy` plus a fresh `apply` — every
cluster's **compute** can be paused and resumed independently of
Terraform state. The three clouds behave differently here, because only
AKS can fully deallocate its control plane:

| Cloud | Control plane can stop too? | What stops billing | Native operation |
|---|---|---|---|
| **Azure (AKS)** | Yes | `az aks stop` — nodes **and** control plane | Cluster-level stop/start |
| **AWS (EKS)** | No — the control plane fee bills regardless | Scale the managed node group to 0 | Node group scaling only |
| **GCP (GKE)** | Mostly — zonal cluster management fee is often waived (one free zonal cluster per billing account) | Scale the node pool to 0 | Node pool scaling only |

**Two things specific to this repo before you start:**

1. **Never pause the Fleet hub cluster.** It's a separate, always-on
   cluster (see `docs/ARCHITECTURE.md`) that hosts the
   `ClusterResourcePlacement` and reconciles every member — stopping it
   takes down Fleet management for all three clouds at once. Only pause
   the three **member** clusters: `aks-demo`, `eks-demo`, `gke-demo`.
2. **Pausing `eks-demo`/`gke-demo` makes Arc report them "Offline" — that's
   expected, not broken.** The Arc agent runs as pods on that cluster's
   own nodes, so scaling those nodes to 0 takes the agent down with them.
   `az connectedk8s show --name eks-demo --resource-group flarc-demo-rg
   --query connectivityStatus -o tsv` will report `Offline`, and that
   member's `ClusterResourcePlacement` status on the hub goes stale until
   nodes come back — both self-heal within a few minutes with no need to
   re-run `05-connect-arc.ps1` / `06-join-fleet.ps1`.

The restart sizing used throughout below is **minimum 1, desired 2,
maximum 3** nodes — matching this repo's own Azure/AWS Terraform defaults
(`aks_min_count`/`aks_max_count`, `node_min_size`/`node_max_size`). GCP's
Terraform default is currently 2/4 (`terraform/gcp/variables.tf`); the
commands below apply 1/3 for a manual pause/resume regardless — update
that file too if you want Terraform's own baseline to match going forward.

### Amazon EKS (AWS Console)

Amazon EKS lets you **pause** the managed node group to stop compute
charges, but the cluster control plane must stay active and continues to
bill — see the table above.

**Step 1 — Stop compute nodes (scale to 0)**

1. Log in to the **AWS Management Console**.
2. Search for and select **Elastic Kubernetes Service**.
3. Click your cluster — **`flarc-demo-eks`**.
4. Select the **Compute** tab.
5. Under **Node groups**, select **`flarc-demo-nodes`** and click **Edit**.
6. Set the **Minimum size**, **Maximum size**, and **Desired size** to **0**.
7. Click **Save changes**.

**Step 2 — Restart compute nodes**

1. Navigate back to the cluster's **Compute** tab.
2. Select **`flarc-demo-nodes`** and click **Edit**.
3. Set **Minimum** = **1**, **Desired** = **2**, **Maximum** = **3**.
4. Click **Save changes** to trigger provisioning of new nodes.

**CLI automation:**

```
# Stop - scale the managed node group to 0
aws eks update-nodegroup-config \
  --cluster-name flarc-demo-eks \
  --nodegroup-name flarc-demo-nodes \
  --scaling-config minSize=0,maxSize=0,desiredSize=0 \
  --region us-east-1

# Check progress
aws eks describe-nodegroup \
  --cluster-name flarc-demo-eks \
  --nodegroup-name flarc-demo-nodes \
  --region us-east-1 \
  --query 'nodegroup.{status:status,scaling:scalingConfig}'

# Restart - minimum 1, desired 2, maximum 3
aws eks update-nodegroup-config \
  --cluster-name flarc-demo-eks \
  --nodegroup-name flarc-demo-nodes \
  --scaling-config minSize=1,maxSize=3,desiredSize=2 \
  --region us-east-1
```

`us-east-1` matches `artifacts/region-selection.json` — confirm yours before running.

> **Caution:** this scaling-config update does **not** respect
> `PodDisruptionBudget`s — EKS terminates nodes immediately through the
> underlying Auto Scaling Group regardless of target size, so pods are
> evicted abruptly rather than gracefully drained (see "Handling
> persistent storage volumes" below for why this matters).

### Google GKE (GCP Console)

Google Cloud lets you scale worker nodes to zero to save on compute
costs; for the zonal Standard cluster this demo creates, the control
plane management fee is often waived under the one-free-zonal-cluster
allowance (see the table above).

**Step 1 — Stop compute nodes (scale to 0)**

1. Log in to the **Google Cloud Console**.
2. Navigate to **Kubernetes Engine** > **Clusters**.
3. Click on the name of your cluster — **`flarc-demo-gke`**.
4. Select the **Nodes** tab at the top.
5. Under the **Node Pools** section, click **`flarc-demo-nodes`**.
6. Click the **Edit** button at the top of the page.
7. Uncheck **Enable autoscaling** (this repo enables it by default, min 2/max 4).
8. Change the **Number of nodes** to **0**.
9. Click **Save**.

**Step 2 — Restart compute nodes**

1. Navigate back to the node pool's **Edit** page.
2. Change the **Number of nodes** back to **2** (desired).
3. Re-enable **Autoscaling** with **Minimum** = **1**, **Maximum** = **3**.
4. Click **Save** to scale the infrastructure back up.

**CLI automation:**

```
# Stop - disable autoscaling first (min-count 2 would fight a manual resize to 0), then scale to 0
gcloud container clusters update flarc-demo-gke \
  --node-pool flarc-demo-nodes \
  --no-enable-autoscaling \
  --zone us-central1-a \
  --project <GCP_PROJECT_ID>

gcloud container clusters resize flarc-demo-gke \
  --node-pool flarc-demo-nodes \
  --num-nodes 0 \
  --zone us-central1-a \
  --project <GCP_PROJECT_ID> \
  --quiet

# Restart - minimum 1, desired 2, maximum 3
gcloud container clusters resize flarc-demo-gke \
  --node-pool flarc-demo-nodes \
  --num-nodes 2 \
  --zone us-central1-a \
  --project <GCP_PROJECT_ID> \
  --quiet

gcloud container clusters update flarc-demo-gke \
  --node-pool flarc-demo-nodes \
  --enable-autoscaling \
  --min-nodes 1 \
  --max-nodes 3 \
  --zone us-central1-a \
  --project <GCP_PROJECT_ID>
```

`us-central1-a` matches `artifacts/region-selection.json`; `<GCP_PROJECT_ID>` is your `.env`'s `GCP_PROJECT_ID` — confirm both before running.

GKE gracefully drains nodes it removes — `PodDisruptionBudget`s and
`terminationGracePeriodSeconds` are respected for up to an hour, unlike EKS above.

### Azure AKS (Portal or CLI)

AKS is the one cloud here that can pause the **control plane as well as
the nodes**, halting compute charges entirely while stopped — not just
reducing the node count. Prefer this over node-pool scaling whenever you
want the deepest pause.

**Option A — Stop/start the whole cluster (recommended)**

*Portal:*
1. Sign in to the **Azure portal**.
2. Search for and open **Kubernetes services**.
3. Select **`flarc-demo-aks`**.
4. On the **Overview** page, click **Stop** in the top toolbar and confirm.
5. To resume, open the same cluster and click **Start**.

*CLI:*
```
# Stop - deallocates both agent nodes and the control plane
az aks stop --name flarc-demo-aks --resource-group flarc-demo-rg

# Start - restores previous control plane state and node count
az aks start --name flarc-demo-aks --resource-group flarc-demo-rg

# Confirm
az aks show --name flarc-demo-aks --resource-group flarc-demo-rg --query powerState.code -o tsv

# API server IP can change across a stop/start - refresh kubeconfig cheaply
az aks get-credentials --name flarc-demo-aks --resource-group flarc-demo-rg --overwrite-existing
```

> **Caution:** Microsoft recommends waiting **15-30 minutes after a stop**
> before starting again — the stop needs time to fully complete, and
> restarting mid-shutdown can disrupt it. `az aks start` always restores
> the **same node count the cluster had before it was stopped**, so to
> land on min 1/desired 2/max 3 exactly, apply Option B's scaling either
> right before you stop or right after you start.

**Option B — Just scale the node pool (parity with the EKS/GKE pattern)**

This repo's AKS cluster has a single `system` node pool, and AKS never
lets a `System` pool scale to 0 (at least one node must stay up to run
system pods) — so this option bottoms out at 1 node, not a full pause.
Use Option A for that.

*Portal:* **Kubernetes services** > **`flarc-demo-aks`** > **Node pools**
> **system** > **Scale** > set node count.

*CLI:*
```
# Enable/update the autoscaler bounds: minimum 1, maximum 3
# (use --enable-cluster-autoscaler instead if it isn't already on for this pool)
az aks nodepool update \
  --resource-group flarc-demo-rg \
  --cluster-name flarc-demo-aks \
  --name system \
  --update-cluster-autoscaler \
  --min-count 1 \
  --max-count 3

# Set the desired count
az aks nodepool scale \
  --resource-group flarc-demo-rg \
  --cluster-name flarc-demo-aks \
  --name system \
  --node-count 2
```

`flarc-demo-rg`/`flarc-demo-aks` match this repo's default `NAME_PREFIX`/`ENVIRONMENT` naming — run `terraform output` in `terraform/azure/` to confirm yours if you've customized `.env`.

### Handling persistent storage volumes while nodes are scaled down

**This demo has nothing to worry about today** — no
`PersistentVolumeClaim`/`StorageClass` is defined anywhere in
`kubernetes/base/`; Redis runs as a plain in-cluster cache with no backing
volume (an explicit non-goal — see `docs/OPERATIONS.md`). Scaling any of
the three clusters to 0 and back is fully stateless right now.

If you extend this demo with a real stateful component later (a
database, a Redis with AOF/RDB persistence, etc.), the rules that apply
across all three clouds are:

- **Scaling nodes to 0 never deletes PVCs, PVs, or the underlying cloud
  disk** (EBS volume / Persistent Disk / Azure Disk) — only compute (VMs)
  is torn down. Data is preserved, and the disk keeps accruing its own
  (much smaller) storage cost the entire time nodes are stopped.
- **Cloud block storage is zone-bound.** A `ReadWriteOnce` PVC backed by
  EBS/PD/Azure Disk can only attach to a node in the **same zone** the
  volume was created in. If the replacement node comes up in a different
  zone after scale-up, the pod gets stuck `Pending`/`ContainerCreating`
  with a `FailedAttachVolume`/`FailedMount` event instead of just
  rescheduling cleanly.
- **Default StorageClasses on AKS/EKS/GKE already use
  `volumeBindingMode: WaitForFirstConsumer`**, which defers volume
  creation until a pod is actually scheduled — this is what lets the
  volume follow the pod's zone instead of the other way around. Don't
  override this to `Immediate` for anything you intend to scale to 0.
- **For `StatefulSet`s**, avoid spreading single-replica stateful
  workloads across zones — it only increases the odds the next node lands
  in the "wrong" zone on restart. If cross-zone resilience genuinely
  matters, use zone-redundant storage instead of zonal disks: Azure Disk
  **ZRS** SKUs or GCP **regional Persistent Disks** both replicate
  synchronously across zones so a scale-up in any zone can still attach.
  AWS EBS has no direct equivalent — the standard workaround is
  application-level replication (e.g. a database's own replica set)
  rather than a storage-layer one.
- **Graceful draining differs by cloud — matters most for stateful
  pods.** GKE's node-pool scale-down and AKS's `az aks stop` both cordon
  and drain nodes first, respecting `PodDisruptionBudget`s (AKS's stop
  additionally deletes any **standalone** pod not owned by a
  Deployment/StatefulSet/DaemonSet/Job — never a concern for this demo's
  all-Deployment workload). **EKS is the outlier**: updating a managed
  node group's scaling config terminates nodes immediately via the
  underlying Auto Scaling Group, ignoring PodDisruptionBudgets regardless
  of target size — plan for an abrupt shutdown, not a graceful one, on
  that cloud specifically.

After resuming any cloud, re-run `scripts/08-validate-demo.ps1` — cloud
LoadBalancers can come back with new external IPs, and AKS specifically
can also change its API server IP across a stop/start cycle.

## If something goes wrong mid-demo

See `docs/TROUBLESHOOTING.md` first. The most common live-demo hiccups are
cloud LoadBalancer provisioning taking longer than expected (step 08 polls
with a generous timeout for exactly this reason) and Arc connect requiring
the target cluster's kubeconfig context to already be current (`05-connect-arc.ps1`
sets it explicitly per cloud rather than assuming `kubectl config
current-context`).
