#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the base Online Boutique app, the ResourceOverride/
    ClusterResourceOverride objects, and the ClusterResourcePlacement to the
    Fleet HUB cluster - Fleet then propagates everything to every joined,
    labeled member (AKS/EKS/GKE) automatically. Nothing in this script is
    applied directly to a member cluster; that would bypass Fleet entirely.

.DESCRIPTION
    Requires: scripts/06-join-fleet.ps1 already completed (fleet-hub-demo
    kubeconfig context exists and all enabled members have joined).
#>
[CmdletBinding()]
param(
    [int]$TimeoutMinutes = 10
)

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$k8sDir = Get-KubernetesDir
$hubContext = "fleet-hub-demo"

# The AWS override pins the NLB to this deployment's own public subnets rather
# than relying on the AWS Load Balancer Controller's tag-based auto-discovery.
# Those subnet IDs are only knowable after terraform/aws has been applied, so
# the committed YAML carries a placeholder and it is rendered here.
function Get-AwsPublicSubnetIds {
    $awsRoot = Join-Path (Get-TerraformDir) "aws"
    if (-not (Test-Path (Join-Path $awsRoot "terraform.tfstate"))) { return $null }
    Push-Location $awsRoot
    try {
        $json = (terraform output -json public_subnet_ids 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
        $ids = ($json | ConvertFrom-Json)
        if (-not $ids -or $ids.Count -eq 0) { return $null }
        return ($ids -join ",")
    } catch { return $null } finally { Pop-Location }
}

# Renders kubernetes/overrides into a temp directory with the AWS subnet
# placeholder resolved, so `kubectl apply -f` never sees the raw token.
function New-RenderedOverridesDir {
    $rendered = Join-Path ([System.IO.Path]::GetTempPath()) ("fleet-arc-overrides-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $rendered -Force)

    $subnetIds = Get-AwsPublicSubnetIds
    if ($subnetIds) {
        Write-Info "AWS NLB subnets pinned to: $subnetIds"
    } else {
        Write-WarnMsg "terraform/aws public_subnet_ids unavailable - dropping the aws-load-balancer-subnets annotation (controller will auto-discover)."
    }

    foreach ($file in (Get-ChildItem -Path (Join-Path $k8sDir "overrides") -Filter "*.yaml")) {
        $lines = Get-Content -Path $file.FullName
        if ($subnetIds) {
            $lines = $lines -replace "__AWS_PUBLIC_SUBNET_IDS__", $subnetIds
        } else {
            $lines = $lines | Where-Object { $_ -notmatch "__AWS_PUBLIC_SUBNET_IDS__" }
        }
        Set-Content -Path (Join-Path $rendered $file.Name) -Value $lines -Encoding UTF8
    }
    return $rendered
}

Write-Step "Applying base Online Boutique manifests to the Fleet hub"
Invoke-Checked -Command "kubectl" -Arguments @("apply", "-k", (Join-Path $k8sDir "base"), "--context", $hubContext) -ErrorContext "kubectl apply base"
Write-Ok "Base manifests applied to hub"

Write-Step "Applying ResourceOverride/ClusterResourceOverride objects to the Fleet hub"
$renderedOverrides = New-RenderedOverridesDir
try {
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", $renderedOverrides, "--context", $hubContext) -ErrorContext "kubectl apply overrides"
} finally {
    Remove-Item -Path $renderedOverrides -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Ok "Overrides applied to hub"

Write-Step "Applying ClusterResourcePlacement to the Fleet hub"
Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", (Join-Path (Join-Path $k8sDir "fleet") "cluster-resource-placement.yaml"), "--context", $hubContext) -ErrorContext "kubectl apply CRP"
Write-Ok "ClusterResourcePlacement applied to hub - propagation to joined members starting"

Write-Step "Waiting for propagation (up to $TimeoutMinutes minutes)"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$available = $false
do {
    Start-Sleep -Seconds 15
    $raw = (kubectl get clusterresourceplacement crp-online-boutique --context $hubContext -o json 2>$null)
    if ($raw) {
        $crp = ($raw | ConvertFrom-Json)
        $availableCondition = $crp.status.conditions | Where-Object { $_.type -eq "ClusterResourcePlacementAvailable" } | Select-Object -First 1
        $available = ($availableCondition -and $availableCondition.status -eq "True")
        $summary = ($crp.status.conditions | ForEach-Object { "$($_.type)=$($_.status)" }) -join ", "
        Write-Info $summary
    } else {
        Write-WarnMsg "Could not read ClusterResourcePlacement yet - retrying..."
    }
} while (-not $available -and (Get-Date) -lt $deadline)

Write-Step "Per-member placement status"
if ($raw) {
    $crp = ($raw | ConvertFrom-Json)
    foreach ($placement in $crp.status.placementStatuses) {
        $conds = ($placement.conditions | ForEach-Object { "$($_.type)=$($_.status)" }) -join ", "
        Write-Info "$($placement.clusterName): $conds"
    }
}

Write-Step "Summary"
if ($available) {
    Write-Ok "ClusterResourcePlacementAvailable=True - workload propagated to all matching members."
    Write-Info "Next: scripts/08-validate-demo.ps1"
    exit 0
} else {
    Write-ErrMsg "Placement did not reach Available within $TimeoutMinutes minutes. Inspect: kubectl describe clusterresourceplacement crp-online-boutique --context $hubContext"
    exit 1
}
