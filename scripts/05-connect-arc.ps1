#Requires -Version 5.1
<#
.SYNOPSIS
    Arc-connects the EKS and/or GKE clusters into the Azure resource group
    created by terraform/azure, so they can join Fleet Manager alongside the
    native AKS member. AKS itself never goes through Arc - it joins Fleet
    directly (see scripts/06-join-fleet.ps1).

.DESCRIPTION
    Requires: terraform/azure applied (for the target resource group +
    region), and each enabled non-Azure cloud's cluster already applied with
    its kubeconfig context present (eks-demo / gke-demo) and cluster-admin
    on that context - both are handled by scripts/04-apply.ps1.
#>
[CmdletBinding()]
param()

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$tfRoot = Get-TerraformDir

if (-not ($enabledClouds -contains "azure")) {
    Write-ErrMsg "ENABLE_AZURE is false - Arc onboarding has no Azure resource group to connect into. Enable Azure (Fleet Manager always lives there) or skip this step."
    exit 1
}

Push-Location (Join-Path $tfRoot "azure")
try {
    $arcResourceGroup = Get-EnvValue -DotEnv $dotEnv -Key "ARC_RESOURCE_GROUP"
    if (-not $arcResourceGroup) { $arcResourceGroup = (terraform output -raw arc_resource_group) }
    $arcLocation = Get-EnvValue -DotEnv $dotEnv -Key "ARC_REGION_OVERRIDE"
    if (-not $arcLocation) { $arcLocation = (terraform output -raw location) }
} finally { Pop-Location }

Write-Info "Arc resource group: $arcResourceGroup"
Write-Info "Arc region: $arcLocation"

function Connect-ArcCluster {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$KubeContext,
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$Infrastructure
    )
    Write-Step "Arc-connecting $Name (context: $KubeContext)"

    $existing = $null
    try { $existing = (az connectedk8s show --name $Name --resource-group $arcResourceGroup -o json 2>$null | ConvertFrom-Json) } catch { $existing = $null }
    if ($existing -and $existing.connectivityStatus -eq "Connected") {
        Write-Ok "$Name already Arc-connected (connectivityStatus=Connected) - skipping"
        return $true
    }

    Invoke-Checked -Command "az" -Arguments @(
        "connectedk8s", "connect",
        "--name", $Name,
        "--resource-group", $arcResourceGroup,
        "--location", $arcLocation,
        "--kube-context", $KubeContext,
        "--distribution", $Distribution,
        "--infrastructure", $Infrastructure
    ) -ErrorContext "az connectedk8s connect ($Name)"

    Write-Info "Waiting for connectivityStatus=Connected (this can take a few minutes)..."
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 15
        $status = (az connectedk8s show --name $Name --resource-group $arcResourceGroup --query "connectivityStatus" -o tsv 2>$null)
        Write-Info "  status: $status"
    } while ($status -ne "Connected" -and (Get-Date) -lt $deadline)

    if ($status -eq "Connected") {
        Write-Ok "$Name : Connected"
        return $true
    } else {
        Write-ErrMsg "$Name : did not reach Connected within 10 minutes (last status: $status). Check: az connectedk8s show --name $Name --resource-group $arcResourceGroup"
        return $false
    }
}

$results = @()
if ($enabledClouds -contains "aws") {
    $results += Connect-ArcCluster -Name "eks-demo" -KubeContext "eks-demo" -Distribution "eks" -Infrastructure "aws"
}
if ($enabledClouds -contains "gcp") {
    $results += Connect-ArcCluster -Name "gke-demo" -KubeContext "gke-demo" -Distribution "gke" -Infrastructure "gcp"
}

Write-Step "Summary"
if ($results.Count -eq 0) {
    Write-WarnMsg "Neither AWS nor GCP is enabled - nothing to Arc-connect (AKS joins Fleet natively, see scripts/06-join-fleet.ps1)."
    exit 0
} elseif ($results -contains $false) {
    Write-ErrMsg "One or more clusters failed to reach Connected. Re-run this script after investigating."
    exit 1
} else {
    Write-Ok "All enabled non-Azure clusters are Arc-connected."
    Write-Info "Next: scripts/06-join-fleet.ps1"
    exit 0
}
