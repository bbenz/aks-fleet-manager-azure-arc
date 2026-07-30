#Requires -Version 5.1
<#
.SYNOPSIS
    Tears down everything this demo created, in reverse order: Fleet
    placement/overrides/workload -> Fleet membership -> Arc connections ->
    terraform destroy (gcp, aws, then azure last, since Fleet Manager and
    the Arc-onboarding resource group live in azure).

.PARAMETER AutoApprove
    Skip the interactive typed confirmation. Use only in CI or once you're
    confident you want to destroy everything currently enabled in .env.

.DESCRIPTION
    Every step is best-effort and continues past "already gone" / "never
    created" conditions (kubectl --ignore-not-found, az ... || true
    equivalents) so this script is safe to re-run if a previous teardown
    was interrupted partway through.
#>
[CmdletBinding()]
param(
    [switch]$AutoApprove
)

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$tfRoot = Get-TerraformDir
$k8sDir = Get-KubernetesDir

Write-Step "Destroy notice"
Write-Host "This PERMANENTLY deletes all Fleet Manager, AKS, EKS, and GKE" -ForegroundColor Yellow
Write-Host "resources created by this demo for the currently-enabled clouds:" -ForegroundColor Yellow
Write-Host "  $($enabledClouds -join ', ')" -ForegroundColor Yellow
Write-Host "This cannot be undone." -ForegroundColor Yellow

if (-not (Confirm-BillableAction -ActionDescription "About to destroy ALL demo infrastructure for: $($enabledClouds -join ', ')." -AutoApprove:$AutoApprove.IsPresent -ConfirmationWord "destroy")) {
    Write-WarnMsg "Aborted - no changes made."
    exit 1
}

# --- 1. Remove Fleet-placed workload from the hub -----------------------------
Write-Step "Removing Fleet placement/overrides/workload from the hub"
$hubContextExists = (kubectl config get-contexts fleet-hub-demo 2>$null)
if ($hubContextExists) {
    kubectl delete -f (Join-Path (Join-Path $k8sDir "fleet") "cluster-resource-placement.yaml") --context fleet-hub-demo --ignore-not-found=true 2>&1 | Out-Null
    kubectl delete -f (Join-Path $k8sDir "overrides") --context fleet-hub-demo --ignore-not-found=true 2>&1 | Out-Null
    kubectl delete -k (Join-Path $k8sDir "base") --context fleet-hub-demo --ignore-not-found=true 2>&1 | Out-Null
    Write-Ok "Hub workload/placement removed (or already absent)"
} else {
    Write-WarnMsg "fleet-hub-demo kubeconfig context not found - skipping (Fleet may never have been joined)"
}

# --- 2. Remove Fleet members ---------------------------------------------------
if ($enabledClouds -contains "azure") {
    Write-Step "Removing Fleet members"
    Push-Location (Join-Path $tfRoot "azure")
    try {
        $rg = $null
        $fleetName = $null
        try {
            $rg = (terraform output -raw resource_group_name 2>$null)
            $fleetName = (terraform output -raw fleet_name 2>$null)
        } catch { }
    } finally { Pop-Location }

    if ($rg -and $fleetName) {
        foreach ($member in @("aks-demo", "eks-demo", "gke-demo")) {
            az fleet member delete --resource-group $rg --fleet-name $fleetName --name $member --yes 2>&1 | Out-Null
            Write-Ok "Fleet member '$member' removed (or already absent)"
        }
    } else {
        Write-WarnMsg "Could not read azure Terraform outputs (root may not be applied) - skipping Fleet member removal"
    }
}

# --- 3. Disconnect Arc ---------------------------------------------------------
if ($rg) {
    Write-Step "Disconnecting Arc clusters"
    foreach ($cloud in @("aws", "gcp")) {
        if ($enabledClouds -contains $cloud) {
            $name = if ($cloud -eq "aws") { "eks-demo" } else { "gke-demo" }
            az connectedk8s delete --name $name --resource-group $rg --yes 2>&1 | Out-Null
            Write-Ok "Arc connection '$name' removed (or already absent)"
        }
    }
}

# --- 4. terraform destroy: gcp, aws, then azure last ---------------------------
function Invoke-DestroyRoot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RootDir
    )
    if (-not (Test-Path (Join-Path $RootDir "terraform.tfstate"))) {
        Write-WarnMsg "$Label : no local state found - nothing to destroy, skipping"
        return
    }
    Write-Step "terraform destroy: $Label"
    Push-Location $RootDir
    try {
        Invoke-Checked -Command "terraform" -Arguments @("destroy", "-input=false", "-auto-approve") -ErrorContext "$Label destroy"
        Remove-Item -Path (Join-Path $RootDir "tfplan") -ErrorAction SilentlyContinue
        Write-Ok "$Label : destroyed"
    } finally {
        Pop-Location
    }
}

if ($enabledClouds -contains "gcp") { Invoke-DestroyRoot -Label "gcp" -RootDir (Join-Path $tfRoot "gcp") }
if ($enabledClouds -contains "aws") { Invoke-DestroyRoot -Label "aws" -RootDir (Join-Path $tfRoot "aws") }
if ($enabledClouds -contains "azure") { Invoke-DestroyRoot -Label "azure" -RootDir (Join-Path $tfRoot "azure") }

# Refresh the consolidated outputs to reflect the now-empty state.
$envDemoDir = Join-Path (Join-Path $tfRoot "environments") "demo"
if (Test-Path (Join-Path $envDemoDir "terraform.tfstate")) {
    Push-Location $envDemoDir
    try { terraform apply -input=false -auto-approve 2>&1 | Out-Null } finally { Pop-Location }
}

Write-Step "Summary"
Write-Ok "Teardown complete for: $($enabledClouds -join ', ')"
Write-Info "kubeconfig contexts (aks-demo/eks-demo/gke-demo/fleet-hub-demo) were left in your kubeconfig pointing at now-deleted clusters - run 'kubectl config delete-context <name>' to clean them up if you like."
exit 0
