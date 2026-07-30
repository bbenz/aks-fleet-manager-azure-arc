#Requires -Version 5.1
<#
.SYNOPSIS
    Joins the AKS cluster and every enabled Arc-connected cluster (EKS/GKE)
    to Fleet Manager, applying the repo's standard member labels
    (cloud/provider/demo/location/environment) at creation time via
    `az fleet member create --member-labels` - see
    kubernetes/fleet/member-labels-reference.yaml.

.DESCRIPTION
    Requires: terraform/azure applied (Fleet Manager + AKS), and for each
    enabled non-Azure cloud, scripts/05-connect-arc.ps1 already completed
    (Arc-connected cluster exists in the same resource group).
    Also fetches the Fleet hub's own kubeconfig into the 'fleet-hub-demo'
    context - required by scripts/07-deploy-workload.ps1.
#>
[CmdletBinding()]
param()

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$tfRoot = Get-TerraformDir
$regionSelection = Read-RegionSelection

if (-not ($enabledClouds -contains "azure")) {
    Write-ErrMsg "ENABLE_AZURE is false - Fleet Manager itself lives in terraform/azure. Enable Azure to use Fleet."
    exit 1
}

Push-Location (Join-Path $tfRoot "azure")
try {
    $rg = (terraform output -raw resource_group_name)
    $fleetName = (terraform output -raw fleet_name)
    $aksClusterId = (terraform output -raw aks_cluster_id)
    $aksClusterName = (terraform output -raw aks_cluster_name)
    $azureLocation = (terraform output -raw location)
} finally { Pop-Location }

Write-Info "Resource group: $rg"
Write-Info "Fleet: $fleetName"

function Add-FleetMember {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ClusterId,
        [Parameter(Mandatory)][string]$Cloud,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Location
    )
    Write-Step "Joining $Name to Fleet ($fleetName)"
    $labels = "cloud=$Cloud provider=$Provider demo=fleet-arc-online-boutique location=$Location environment=demo"

    Invoke-Checked -Command "az" -Arguments (@(
        "fleet", "member", "create",
        "--resource-group", $rg,
        "--fleet-name", $fleetName,
        "--name", $Name,
        "--member-cluster-id", $ClusterId,
        "--update-group", $Cloud,
        "--member-labels", $labels
    )) -ErrorContext "az fleet member create ($Name)" | Out-Null

    Write-Info "Waiting for provisioningState=Succeeded..."
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 10
        $state = (az fleet member show --resource-group $rg --fleet-name $fleetName --name $Name --query "provisioningState" -o tsv 2>$null)
        Write-Info "  provisioningState: $state"
    } while ($state -ne "Succeeded" -and $state -ne "Failed" -and (Get-Date) -lt $deadline)

    if ($state -eq "Succeeded") {
        Write-Ok "$Name : Succeeded"
        return $true
    } else {
        Write-ErrMsg "$Name : did not reach Succeeded (last state: $state). Check: az fleet member show --resource-group $rg --fleet-name $fleetName --name $Name"
        return $false
    }
}

$results = @()
$results += Add-FleetMember -Name "aks-demo" -ClusterId $aksClusterId -Cloud "azure" -Provider "aks" -Location $azureLocation

if ($enabledClouds -contains "aws") {
    $eksClusterId = (az connectedk8s show --name "eks-demo" --resource-group $rg --query "id" -o tsv)
    $awsLocation = if ($regionSelection -and $regionSelection.aws) { $regionSelection.aws.selected } else { "us-east-1" }
    $results += Add-FleetMember -Name "eks-demo" -ClusterId $eksClusterId -Cloud "aws" -Provider "eks" -Location $awsLocation
}

if ($enabledClouds -contains "gcp") {
    $gkeClusterId = (az connectedk8s show --name "gke-demo" --resource-group $rg --query "id" -o tsv)
    $gcpLocation = if ($regionSelection -and $regionSelection.gcp) { $regionSelection.gcp.selected_region } else { "us-central1" }
    $results += Add-FleetMember -Name "gke-demo" -ClusterId $gkeClusterId -Cloud "gcp" -Provider "gke" -Location $gcpLocation
}

Write-Step "Fetching Fleet hub kubeconfig"
Invoke-Checked -Command "az" -Arguments @(
    "fleet", "get-credentials",
    "--resource-group", $rg,
    "--name", $fleetName,
    "--context", "fleet-hub-demo",
    "--overwrite-existing"
) -ErrorContext "az fleet get-credentials"
Write-Ok "kubeconfig context 'fleet-hub-demo' ready"

Write-Step "Summary"
if ($results -contains $false) {
    Write-ErrMsg "One or more members failed to join. Re-run this script after investigating."
    exit 1
} else {
    Write-Ok "All enabled clusters joined Fleet: $(($results.Count)) member(s)."
    Write-Info "Next: scripts/07-deploy-workload.ps1"
    exit 0
}
