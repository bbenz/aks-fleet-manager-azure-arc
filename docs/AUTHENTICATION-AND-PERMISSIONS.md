# Authentication and Permissions

## The core constraint: console credentials are not CLI credentials

If all you have for a cloud is a **console** login (a Google account +
password, or an IAM console username + password), that cannot be converted
into CLI authentication programmatically:

- Most accounts are protected by **MFA**, which requires a real browser and a real human.
- Even without MFA, exchanging a plain username/password for API credentials outside each provider's official, interactive login flow would mean scripting around the login form — which this project will not do, on principle as much as practicality.
- Azure is no different: a fresh environment needs the same interactive `az login` step before anything here works.

**What this means in practice:** `scripts/00-bootstrap-auth.ps1` can check
whether each cloud is already authenticated and can *launch* the correct
official interactive command for you, but a human has to complete the
browser/device-code/MFA step themselves. This is not a workaround to remove
— it is required, correct behavior.

Every script is scoped by the `ENABLE_AZURE`/`ENABLE_AWS`/`ENABLE_GCP` flags
in `.env`, so you can run Azure-only (or any other subset) while you sort out
interactive login for the remaining clouds, then enable them later and re-run
the same numbered scripts.

## Azure

```powershell
az login
# Optionally target a specific tenant/subscription if you have more than one:
az account set --subscription "<name-or-id>"
```

**Required permissions** on the target subscription (or a resource group
you pre-create and set via `.env` `AZURE_RESOURCE_GROUP`):

- `Contributor` (or narrower: `Azure Kubernetes Service Contributor Role` + `Azure Kubernetes Fleet Manager Contributor Role` + resource-group-level `Contributor` for the VNet/RG itself) to create the resource group, AKS cluster, and Fleet Manager.
- `Azure Kubernetes Fleet Manager RBAC Cluster Admin` (or equivalent) on the Fleet hub, to apply `ClusterResourcePlacement`/`ResourceOverride` objects via `scripts/07-deploy-workload.ps1`.
- `Kubernetes Cluster - Azure Arc Onboarding` role (or `Contributor`) at the resource group scope, required by `az connectedk8s connect` to create the `Microsoft.Kubernetes/connectedClusters` resource for EKS/GKE.
- Resource provider registration for `Microsoft.ContainerService`, `Microsoft.Kubernetes`, and `Microsoft.KubernetesConfiguration` (Terraform/`az` register these automatically on first use if you have `Contributor`; `scripts/01-test-cloud-access.ps1` checks and reports current state).

> **Subscription `Owner` is not enough for step 07.** Azure RBAC roles at the
> subscription scope grant *control-plane* access; they do not grant
> *Kubernetes data-plane* access to the Fleet hub. Without an explicit
> `Azure Kubernetes Fleet Manager RBAC Cluster Admin` assignment **at the
> Fleet resource scope**, `kubectl` against the hub context returns
> `Forbidden`. Note also that this assignment is scoped to the Fleet
> resource itself, so it is deleted along with the Fleet during teardown and
> must be recreated after each fresh `apply`:
>
> ```powershell
> az role assignment create `
>   --role "Azure Kubernetes Fleet Manager RBAC Cluster Admin" `
>   --assignee "<your-user-or-object-id>" `
>   --scope "$(az fleet show -g <resource-group> -n <fleet-name> --query id -o tsv)"
> ```
>
> Allow a minute or two for RBAC propagation, then re-run
> `az fleet get-credentials` before `scripts/07-deploy-workload.ps1`.

## AWS

This repo does not pre-configure an AWS CLI profile. Recommended, in order of
preference:

```powershell
# Preferred: AWS IAM Identity Center / SSO, if your account has it configured
aws configure sso --profile fleet-arc-demo
aws sso login --profile fleet-arc-demo

# Fallback: a long-lived access key you generate yourself in the console
# (IAM -> Users -> Security credentials -> Create access key)
aws configure --profile fleet-arc-demo
```

Set `AWS_PROFILE=fleet-arc-demo` in `.env` either way. Long-lived access
keys are a real, supported AWS mechanism when SSO isn't available — but
they are **not** something this automation can generate or retrieve for
you; you must create them yourself in the console after logging in
interactively.

**Required IAM permissions** (attach to the SSO permission set, IAM user, or
role used above):

- VPC: create/manage VPC, subnets, route tables, internet gateway, security groups.
- IAM: create roles/policies for the EKS cluster role, node role, and (if `enable_aws_load_balancer_controller = true`) the IRSA role + OIDC provider.
- EKS: `eks:CreateCluster`, `eks:CreateNodegroup`, and associated read/describe/tag permissions.
- STS: `sts:GetCallerIdentity` (used by `scripts/01-test-cloud-access.ps1`'s read-only check).
- If using `AWS_ASSUME_ROLE_ARN`: `sts:AssumeRole` on that role from your base credentials.

The AWS-managed `AdministratorAccess` policy satisfies all of the above for
a demo account. A least-privilege policy set is intentionally not spelled
out further here since it depends on your account's existing guardrails and
organization SCPs — if your account enforces least privilege, translate the
bullets above into a managed/inline policy before running
`scripts/03-init-plan.ps1`.

## GCP

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

Both commands are required and serve different purposes: `gcloud auth
login` authenticates the `gcloud` CLI itself (used by `scripts/*.ps1` for
read-only checks and post-apply kubeconfig fetch); `gcloud auth
application-default login` populates Application Default Credentials, which
is what the Terraform `google` provider actually uses.

**Required IAM roles** on the target project (`GCP_PROJECT_ID` in `.env`):

- `roles/container.admin` — create/manage the GKE cluster and node pool.
- `roles/compute.networkAdmin` — create the custom VPC, subnet, and firewall rules.
- `roles/iam.serviceAccountAdmin` + `roles/iam.serviceAccountUser` — create and attach the least-privilege node service account.
- `roles/serviceusage.serviceUsageAdmin` — enable the required APIs (`container.googleapis.com`, `compute.googleapis.com`, etc.) that `terraform/gcp/main.tf` declares via `google_project_service`.
- `roles/resourcemanager.projectIamAdmin` — **required**. `terraform/gcp/main.tf` declares `google_project_iam_member.gke_node_default`, which grants `roles/container.defaultNodeServiceAccount` to the custom GKE node service account. That is a project-level IAM policy write, so it needs `resourcemanager.projects.setIamPolicy`. A custom role containing just that permission works too if your organization policy forbids the full Project IAM Admin role.

If using `GCP_IMPERSONATE_SERVICE_ACCOUNT`, your own user additionally needs
`roles/iam.serviceAccountTokenCreator` on that service account.

## Arc onboarding permissions (cross-cutting)

`az connectedk8s connect` needs **cluster-admin** on the target Kubernetes
cluster's *own* kubeconfig context (to install the Arc agents into
`azure-arc` namespace) **and** the Azure-side Arc onboarding role described
in the Azure section above. `scripts/05-connect-arc.ps1` assumes both are
already satisfied (cluster-admin comes for free as the creator of a fresh
EKS/GKE cluster; the Azure-side role is whatever your `az login` identity
already has on the resource group).
