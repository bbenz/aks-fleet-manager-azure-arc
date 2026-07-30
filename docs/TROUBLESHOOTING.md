# Troubleshooting

Every issue below was hit for real while building and running this
repository — none are hypothetical. They're split into two groups:

- **[Running the demo](#running-the-demo)** — things you may hit yourself.
- **[Why the code looks like this](#why-the-code-looks-like-this)** — defects
  already fixed in this repo, documented so you don't reintroduce them if
  you fork or extend it.

---

## Running the demo

### Execution policy: "running scripts is disabled on this system" {#execution-policy}

**Symptom:** Running any `scripts/*.ps1` under stock Windows PowerShell 5.1
fails immediately with something like:
```
File ...\scripts\00-check-tools.ps1 cannot be loaded because running scripts
is disabled on this system.
```
This is especially likely to surface indirectly — e.g. calling `gcloud`
bare from PowerShell resolves to `gcloud.ps1` (not `.cmd`) on Windows, so
even a script that never directly touches `Set-ExecutionPolicy` can trip
this the moment it shells out to `gcloud`.

**Why:** Windows PowerShell 5.1's default execution policy is `Restricted`
in many environments. PowerShell 7 (`pwsh`) ships a more permissive default
(`RemoteSigned`) and is unaffected. Check yours with
`Get-ExecutionPolicy -List` — every scope showing `Undefined` resolves to
`Restricted`.

**Fixes (pick one):**
1. **Use PowerShell 7** (`pwsh`) instead of `powershell` to run these scripts — this repo targets `#Requires -Version 5.1` for compatibility, but `pwsh` is recommended and is what the `Makefile`'s `PWSH` variable defaults to.
2. **Set the policy once for your user** (no admin required): `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`.
3. **Bypass per-invocation** without changing any persistent setting: `powershell -ExecutionPolicy Bypass -File scripts\00-check-tools.ps1` (this is exactly what the Makefile's default `PWSH` invocation does under the hood).
4. **Invoke `gcloud.cmd` explicitly** if only the gcloud shim is the problem.

### Step 00 reports CLIs missing that are definitely installed

**Symptom:** `scripts/00-check-tools.ps1` reports `terraform`, `helm`, `aws`,
or `gcloud` as missing even though all of them are installed.

**Why:** Their installation directories aren't on the `PATH` inherited by
your current shell. Installers commonly update the persistent user/machine
`PATH` without touching already-open terminals.

**Fix:** Open a new terminal (the simplest fix — persistent `PATH` changes
apply to new sessions only). If a directory genuinely isn't on the
persistent `PATH`, prepend it for the session:
```powershell
$env:PATH = "C:\Program Files\HashiCorp\Terraform;$env:PATH"
```
No reinstall is needed.

### Azure CLI `fleet` extension update fails on a checksum mismatch

**Symptom:** Updating the Azure CLI `fleet` extension fails because the
downloaded extension checksum doesn't match the expected value. Azure CLI
rolls back cleanly to the already-installed version.

**Why:** A temporarily inconsistent package index/mirror. Transient.

**Fix:** Continue with the already-installed version — this repo's commands
work with `fleet` 1.10.x and later. Retry the update later, and only
force a remove/reinstall if a specific command you need is actually
missing.

### Azure CLI and `connectedk8s` extension version incompatibility

**Symptom:** Step 05 fails with a Python import error, e.g. the CLI lacking
`azure.mgmt.core.tools.get_arm_endpoints` that `connectedk8s` requires. After
upgrading Azure CLI, a *previously installed* extension can then fail with a
binary incompatibility (e.g. a bundled `rpds` native module built for the
old Python runtime).

**Why:** Azure CLI extensions bind to the CLI's bundled Python runtime.
Upgrading the CLI across a runtime change invalidates any extension carrying
compiled native dependencies.

**Fix:** Upgrade Azure CLI first, then **remove and reinstall** the
extension so it rebuilds against the new runtime:
```powershell
az upgrade
az extension remove --name connectedk8s
az extension add --name connectedk8s
az connectedk8s list   # verify the extension loads before retrying step 05
```

### `az connectedk8s connect` times out but the cluster is actually connected

**Symptom:** Step 05 exits with a Helm `context deadline exceeded` error
after installing the Arc agents — but the Azure connected-cluster resource
reports `provisioningState=Succeeded` and `connectivityStatus=Connected`.

**Why:** The client-side Helm timeout can expire while the last agent pods
are still settling. The Azure-side onboarding already succeeded.

**Fix:** **Verify before you retry or delete anything:**
```powershell
az connectedk8s show --name eks-demo --resource-group flarc-demo-rg `
  --query "{state:provisioningState, connectivity:connectivityStatus}"
```
If it reports `Succeeded`/`Connected`, just re-run `scripts/05-connect-arc.ps1`
— it's idempotent and skips clusters already reporting connected. A
`kube-aad-proxy` pod still waiting on its generated certificate is normal
shortly after onboarding; it only matters if you need Arc's cluster-connect
proxy feature.

### `gke-gcloud-auth-plugin` is not installed

**Symptom:** GKE provisions fine and kubeconfig is written, but `kubectl`
can't authenticate to the cluster; `gcloud container clusters get-credentials`
warns that `gke-gcloud-auth-plugin` is missing.

**Why:** Since Kubernetes 1.26, GKE authentication requires this separate
Google Cloud CLI component. It is not installed by default.

**Fix:**
```powershell
gcloud components install gke-gcloud-auth-plugin
```
Ensure the Google Cloud SDK `bin` directory stays on your `PATH`, then
re-run `gcloud container clusters get-credentials ...`.

### GCP region discovery hangs on an "enable this API?" prompt

**Symptom:** Step 02 appears to hang. `gcloud` is waiting on an interactive
prompt asking whether to enable the Compute Engine API.

**Why:** `gcloud compute machine-types list` against a project where
`compute.googleapis.com` is disabled prompts to enable it — an interactive,
*mutating* action inside what is documented as a read-only step.

**Fix:** This repo passes `--quiet` to that query so it fails closed instead
of prompting, and step 02 falls back to the documented default region. If you
want dynamically verified GCP regions instead of the fallback, enable the API
yourself first:
```powershell
gcloud services enable compute.googleapis.com --project <your-project-id>
```
then re-run `scripts/02-select-regions.ps1`.

### GCP apply fails on `resourcemanager.projects.setIamPolicy`

**Symptom:** Step 04 fails for GCP while creating
`google_project_iam_member.gke_node_default`.

**Why:** That resource grants `roles/container.defaultNodeServiceAccount` to
the custom GKE node service account — a project-level IAM policy write.

**Fix:** Grant your identity `roles/resourcemanager.projectIamAdmin` on the
project (or a custom role containing `resourcemanager.projects.setIamPolicy`).
See [AUTHENTICATION-AND-PERMISSIONS.md](AUTHENTICATION-AND-PERMISSIONS.md#gcp).

### Fleet hub `kubectl` returns `Forbidden` despite subscription Owner

**Symptom:** Azure control-plane operations and Fleet member creation both
succeed, but step 07's `kubectl` calls against the Fleet hub context fail
with `Forbidden`.

**Why:** Azure RBAC at subscription scope governs the **control plane**. It
does not grant **Kubernetes data-plane** access to the Fleet hub. These are
separate authorization systems.

**Fix:** Assign `Azure Kubernetes Fleet Manager RBAC Cluster Admin` at the
Fleet **resource** scope, wait for propagation, and refresh credentials —
see [the runsheet's RBAC step](DEMO-RUNSHEET.md#one-manual-step-between-06-and-07-fleet-hub-rbac).

Because the assignment is scoped to the Fleet resource, it is deleted along
with the Fleet during teardown and **must be recreated after every fresh
`apply`**.

### Pods stuck `Pending` — node CPU requests exceed a two-node cluster

**Symptom:** After step 07, some pods (often `shippingservice`) never
schedule. Node CPU is at 97-98% *requested* even though actual utilization
is low.

**Why:** Online Boutique's ~12 pods, plus system pods, closely fit two
2-vCPU nodes. Scheduling uses **requests**, not actual usage, so a single
oversized request starves the rest. Compounding this: Kubernetes' default
`RollingUpdate` strategy keeps old pods (and their reservations) alive until
replacements are `Ready` — with no surge headroom, neither can start, and the
rollout deadlocks.

**Fix (already applied in this repo):** the load generator requests `50m`
CPU rather than upstream's `300m` (its `500m` limit is unchanged, so it can
still burst), and the singleton `frontend` and `loadgenerator` Deployments
use `strategy: Recreate` so a replacement never has to coexist with its
predecessor. If you extend the workload and hit this again, either raise the
node count (billable) or trim requests further — don't raise limits.

### AWS NLB never provisions, or provisions but isn't reachable

**Symptom (a):** The AWS Load Balancer Controller logs show it evaluating
zero candidate subnets, despite both public subnets carrying the documented
`kubernetes.io/role/elb` and cluster tags.

**Symptom (b):** The NLB provisions healthy, but its DNS name resolves to
private VPC addresses and external validation times out.

**Why:** (a) subnet auto-discovery is version-sensitive and can come up
empty even with correct tags; (b) the controller defaults to an `internal`
scheme unless told otherwise.

**Fix (already applied in this repo):** `kubernetes/overrides/frontend-service-override.yaml`
sets both explicitly for the AWS override rule —
`service.beta.kubernetes.io/aws-load-balancer-subnets` naming the two
Terraform-defined public subnets in distinct AZs, and
`service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing`.
Deterministic beats auto-discovery for a fixed demo topology.

### Corrupted Azure CLI MSAL token cache

**Symptom:** Every `az` command that touches actual data (e.g. `az group
list`) fails with a Python traceback ending in:
```
AttributeError: Can't get attribute 'NormalizedResponse' on <module
'msal.throttled_http_client' from '...\\site-packages\\msal\\throttled_http_client.py'>
```
`az login` itself still appears to succeed, which makes this confusing —
the break is in a *later* cached-token read, not the login flow.

**Why:** `~/.azure/msal_http_cache.bin` is a pickled HTTP response cache
used by MSAL to avoid redundant network calls. If it was written by a
different (incompatible) version of the `msal` library than the one your
current `az` CLI ships with — likely after an Azure CLI upgrade —
unpickling throws, and `az` has no fallback path.

**Fix:** Delete **only** `msal_http_cache.bin`, not
`msal_token_cache.bin`:
```powershell
Remove-Item "$env:USERPROFILE\.azure\msal_http_cache.bin" -Force
```
This is safe — it discards a disposable HTTP response cache, not your
actual login session/tokens. `az cache purge` does **not** fix this (it
doesn't touch the throttled-http-client cache specifically); direct file
removal does.

### CLI installer fails with exit code 1618

**Symptom:** `winget install Amazon.AWSCLI` (or any MSI-based install)
fails repeatedly with exit code `1618` — "another installation is already
in progress".

**Why:** Something else holds the Windows Installer mutex — background
updates, another package manager, or a concurrent install. Transient
contention, not a real blocker.

**Fix:** Wait a minute or two and retry. Don't loop tightly; that just
extends the contention.

### Cloud LoadBalancer endpoints take longer than expected

**Symptom:** Step 08 spends several minutes polling before printing URLs.

**Why:** This is normal. AWS in particular publishes an NLB hostname while
the load balancer is still provisioning, so the DNS name resolves before it
serves traffic. Step 08 therefore retries both endpoint *discovery* and HTTP
200 *readiness* until its timeout, rather than failing on the first attempt.

**Fix:** Wait. If the timeout is genuinely exceeded, step 08 reports the last
HTTP error it saw — check the Service events on that member
(`kubectl describe svc frontend-external -n online-boutique --context <ctx>`).

### After a pause/resume, endpoints changed

Cloud LoadBalancers can come back with new external IPs, and AKS can also
change its API server IP across an `az aks stop`/`start` cycle. Re-run
`az aks get-credentials --overwrite-existing` and then
`scripts/08-validate-demo.ps1` to refresh both. See the runsheet's
[pause/resume section](DEMO-RUNSHEET.md#pausing-and-resuming-clusters-without-deleting-them).

---

## Why the code looks like this

Defects already fixed in this repo. Documented so a fork or extension
doesn't reintroduce them.

### `terraform_remote_state` hard-errors on a missing state file

**Symptom:** `terraform/environments/demo` fails `terraform plan` entirely —
not gracefully — the moment any one of the three cloud roots hasn't been
applied yet, even though the `outputs.tf` `try()` wrapping intended it to
degrade to a placeholder.

**Why:** `try()` in an output expression only catches errors in evaluating
*that expression*. A `data "terraform_remote_state"` block with
`backend = "local"` pointing at a nonexistent state file fails during the
**data source read** itself — before any output expression referencing it is
evaluated. `try()` cannot intercept a failed data source read.

**Fix:** Gate the data source's existence, not just its downstream usage:
```hcl
data "terraform_remote_state" "azure" {
  count   = fileexists(var.azure_state_path) ? 1 : 0
  backend = "local"
  config  = { path = var.azure_state_path }
}
```
Then reference `data.terraform_remote_state.azure[0].outputs.x` — a missing
state file now makes the *reference* `[0]` fail with an index error, which
`try()` around that reference **does** catch, falling back to a placeholder.

### A single multi-provider Terraform root eagerly authenticates every provider

**Symptom:** An earlier combined `terraform/bootstrap/` (one root declaring
`azurerm` + `aws` + `google`, every resource guarded by
`count = var.create_x ? 1 : 0`) still attempted AWS IMDS credential
resolution and GCP ADC lookup during `terraform plan` — and failed on both —
with every `create_*` variable `false` and zero resources planned.

**Why:** Terraform initializes and validates **every declared provider
block** in a root during `plan`/`apply`, regardless of whether any resource
actually uses it. `count = 0` skips resource instantiation, not provider
initialization.

**Fix:** Split into three single-provider folders —
`terraform/bootstrap/{azure,aws,gcp}/` — each declaring only its own
provider, matching the independent-root pattern the three main cloud roots
already use.

### AKS: `network_policy = "cilium"` requires `network_data_plane = "cilium"`

**Symptom:** AKS creation fails with
`NetworkPolicyCiliumRequiresCiliumDataplane`.

**Why:** Selecting the Cilium *network policy* without also selecting the
Cilium *data plane* is an invalid combination Azure rejects at create time,
not at plan time.

**Fix:** Set both in the `network_profile` block, or pick a non-Cilium
policy. This repo sets both.

### AKS node-pool upgrade settings cause immediate plan drift

**Symptom:** Re-planning immediately after a successful AKS create proposes
an in-place update removing provider-observed defaults (`max_surge = "10%"`,
zero drain timeout, zero soak duration).

**Why:** Azure populates these server-side; Terraform sees them as
unmanaged drift on the next refresh.

**Fix:** Declare an explicit `upgrade_settings` block matching what Azure
creates, so re-runs are genuinely idempotent. Re-check when upgrading the
AzureRM provider.

### AKS drift from subscription-level security policy

**Symptom:** After deployment, `terraform plan` wants to revert
OIDC/workload identity and detach a Defender workspace it never created.

**Why:** Subscription security automation enables these out-of-band.

**Fix:** Adopt the settings that are beneficial and free (OIDC/workload
identity are declared as enabled here), and `ignore_changes` **only** the
externally-managed `microsoft_defender` block — rather than fighting policy
by trying to disable it.

### EC2 security-group descriptions reject `>`

**Symptom:** AWS apply fails on a security group rule whose description
contains `->`.

**Why:** EC2 restricts security-group rule descriptions to a documented
character set that excludes `>`.

**Fix:** Use ASCII words (`to`) instead of arrow glyphs in any
security-group description.

### `az fleet member create --member-labels` takes one argument, not many

**Symptom:** Step 06 rejects all but the first label as unrecognized
arguments.

**Why:** The `fleet` extension expects a single space-separated
`key=value key=value` expression as one argument value — not one process
argument per label.

**Fix:** Build one space-separated string and pass it as the single value
for `--member-labels`.

### AWS CLI does not accept `-o` for `--output`

**Symptom:**
```
aws: error: [-o] is not a valid option. Did you mean --output?
```

**Why:** Unlike `az` and `gcloud`, which both accept `-o` as an alias, the
AWS CLI only recognizes the long form. Code written by analogy across all
three clouds' CLIs breaks specifically on AWS.

**Fix:** Always use `--output json` with the AWS CLI, never `-o`. Watch for
this if you add new AWS CLI calls to these scripts.

### PowerShell function return-value leaking to console

**Symptom:** A helper ending in `return $true`/`return $false` (e.g.
`Test-Tool` in `scripts/00-check-tools.ps1`) prints a stray `True`/`False`
line when called without capturing its result. Similarly, native command
output inside a function flows into the function's return value — which is
how a member count once reported `72` instead of `2`.

**Why:** In PowerShell a function's return value is its entire *unconsumed
output stream*. Any statement whose result isn't assigned or piped is
implicitly written to that stream.

**Fix:** Wrap calls whose return value you intentionally ignore in
`[void](...)`, and pipe native command output you don't want to `Out-Null`:
```powershell
[void](Test-Tool -Name "terraform" -Command "terraform" -MinVersion "1.9.0")
az fleet member create @memberArgs | Out-Null
```

### Native command stderr capture grabbing a blank or wrong line

**Symptom:** Error handling like
```powershell
$err = & aws sts get-caller-identity 2>&1
$firstLine = $err | Select-Object -Last 1
```
reports an empty or unhelpful message even though the real error is in
`$err`.

**Why:** `2>&1` captures stderr as a stream of objects, and both AWS's and
GCP's CLIs sometimes emit a leading blank entry. `-Last 1` grabs the
*final* line, which for GCP is often a generic "see https://..." link
rather than the actual problem.

**Fix:** Filter blanks, then take the **first** non-blank line — matching
both CLIs' actual output shape (message first, elaboration after):
```powershell
$firstLine = $err | Where-Object { "$_".Trim() -ne "" } | Select-Object -First 1
```

### Strict-mode failures reading asynchronously-populated Kubernetes fields

**Symptom:** Step 08 throws immediately when it queries a freshly created
Job before the API server has attached its `status` object — dereferencing
`$job.status.succeeded` fails under `Set-StrictMode`.

**Fix:** Check for property existence before dereferencing anything
Kubernetes populates asynchronously (Job `status`, Service
`status.loadBalancer.ingress`), and handle **either** an `ip` or a
`hostname` on LoadBalancer ingress — AWS supplies a hostname, Azure and GCP
supply an IP.

### Hardcoded backslash paths break every script under cross-platform `pwsh`

**Symptom:** Not seen on Windows, but every `scripts/*.ps1` would fail
immediately on Linux/macOS with a "cannot find path" error on the
dot-sourced helper library.

**Why:** Scripts dot-sourced their helper with a hardcoded
`"$PSScriptRoot\lib\common.ps1"`. Windows accepts `\` as a separator; on
Linux/macOS `\` is an ordinary filename character, so the whole thing was
treated as one literal filename that doesn't exist.

**Fix:** Use nested `Join-Path` calls
(`Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1"`) or, for repo-root
computation, .NET `DirectoryInfo` navigation
(`(Get-Item $PSScriptRoot).Parent.Parent.FullName`) — both are
separator-agnostic by construction. Path lists are stored forward-slashed
and split/rejoined via `Join-Path` at use time.

### Upstream Online Boutique v0.10.6 requires `SHOPPING_ASSISTANT_SERVICE_ADDR`

**Symptom:** Both frontend pods crash-loop on startup.

**Why:** The pinned upstream v0.10.6 frontend requires this environment
variable to be present even when the optional shopping-assistant feature is
not deployed.

**Fix:** `kubernetes/base/frontend.yaml` sets it to the upstream value
`shoppingassistantservice:80`. Re-check this if you bump the pinned
Online Boutique release.
