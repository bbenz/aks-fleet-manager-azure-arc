#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the saved Terraform plans produced by scripts/03-init-plan.ps1
    for every enabled cloud. THIS CREATES REAL, BILLABLE CLOUD
    INFRASTRUCTURE (AKS + Fleet Manager hub, EKS, and/or GKE clusters).

.PARAMETER AutoApprove
    Skip the interactive confirmation prompt. Use only in CI or once you're
    confident in the plan - review `terraform show <root>/tfplan` first.

.DESCRIPTION
    After each cloud applies successfully, runs that root's
    kubeconfig_command output to merge the new cluster into your local
    kubeconfig under the repo-wide context name (aks-demo / eks-demo /
    gke-demo), then re-applies terraform/environments/demo so its
    consolidated outputs immediately reflect the newly-created cluster(s).
#>
[CmdletBinding()]
param(
    [switch]$AutoApprove
)

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$tfRoot = Get-TerraformDir

Write-Step "Cost notice"
Write-Host "This step creates real, billable cloud infrastructure for every enabled cloud:" -ForegroundColor Yellow
Write-Host "  azure (if enabled): AKS cluster + Fleet Manager hub cluster"
Write-Host "  aws   (if enabled): EKS cluster + 2x t3.large nodes"
Write-Host "  gcp   (if enabled): GKE cluster + 2-4x e2-standard-2 nodes"
Write-Host "Each also creates a public load balancer. Price these with your provider's own calculator." -ForegroundColor Yellow
Write-Host "See docs/ARCHITECTURE.md for the cost-conscious choices made. Run scripts/99-destroy-all.ps1 when done." -ForegroundColor Yellow
Write-Host "Currently enabled: $($enabledClouds -join ', ')" -ForegroundColor Yellow

if (-not (Confirm-BillableAction -ActionDescription "About to run 'terraform apply' for: $($enabledClouds -join ', ')." -AutoApprove:$AutoApprove.IsPresent)) {
    Write-WarnMsg "Aborted - no changes made."
    exit 1
}

function Invoke-ApplyRoot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RootDir,
        [switch]$RequirePlan
    )
    $planPath = Join-Path $RootDir "tfplan"
    if ($RequirePlan -and -not (Test-Path $planPath)) {
        Write-ErrMsg "$Label : no saved plan at $planPath - run scripts/03-init-plan.ps1 first. Skipping."
        return $false
    }
    Write-Step "terraform apply: $Label"
    Push-Location $RootDir
    try {
        if (Test-Path $planPath) {
            Invoke-Checked -Command "terraform" -Arguments @("apply", "-input=false", "tfplan") -ErrorContext "$Label apply"
        } else {
            Invoke-Checked -Command "terraform" -Arguments @("apply", "-input=false", "-auto-approve") -ErrorContext "$Label apply"
        }
        Write-Ok "$Label : apply complete"
        return $true
    } finally {
        Pop-Location
    }
}

$applied = @()

if ($enabledClouds -contains "azure") {
    if (Invoke-ApplyRoot -Label "azure" -RootDir (Join-Path $tfRoot "azure") -RequirePlan) {
        $applied += "azure"
        Push-Location (Join-Path $tfRoot "azure")
        try {
            $cmd = (terraform output -raw kubeconfig_command)
            Write-Info "Fetching AKS kubeconfig: $cmd"
            Invoke-Expression $cmd
            Write-Ok "kubeconfig context 'aks-demo' ready"
        } finally { Pop-Location }
    }
}

if ($enabledClouds -contains "aws") {
    if (Invoke-ApplyRoot -Label "aws" -RootDir (Join-Path $tfRoot "aws") -RequirePlan) {
        $applied += "aws"
        Push-Location (Join-Path $tfRoot "aws")
        try {
            $cmd = (terraform output -raw kubeconfig_command)
            Write-Info "Fetching EKS kubeconfig: $cmd"
            Invoke-Expression $cmd
            Write-Ok "kubeconfig context 'eks-demo' ready"
        } finally { Pop-Location }
    }
}

if ($enabledClouds -contains "gcp") {
    if (Invoke-ApplyRoot -Label "gcp" -RootDir (Join-Path $tfRoot "gcp") -RequirePlan) {
        $applied += "gcp"
        Push-Location (Join-Path $tfRoot "gcp")
        try {
            $cmd = (terraform output -raw kubeconfig_command)
            Write-Info "Fetching GKE kubeconfig: $cmd"
            Invoke-Expression $cmd
            $renameCmd = (terraform output -raw kubeconfig_rename_context_command)
            Invoke-Expression $renameCmd
            Write-Ok "kubeconfig context 'gke-demo' ready"
        } finally { Pop-Location }
    }
}

# Refresh the consolidated outputs now that new cluster(s) exist in state.
# Its step-03 plan predates newly-created state files, so always evaluate this
# resource-free root again after cloud applies.
$demoRoot = Join-Path (Join-Path $tfRoot "environments") "demo"
Remove-Item (Join-Path $demoRoot "tfplan") -Force -ErrorAction SilentlyContinue
Invoke-ApplyRoot -Label "environments/demo" -RootDir $demoRoot | Out-Null

Write-Step "Summary"
if ($applied.Count -gt 0) {
    Write-Ok "Applied: $($applied -join ', ')"
    Write-Info "Next: scripts/05-connect-arc.ps1 (Arc-connect EKS/GKE), then scripts/06-join-fleet.ps1."
    exit 0
} else {
    Write-ErrMsg "Nothing applied - no enabled cloud had a saved plan. Run scripts/03-init-plan.ps1 first."
    exit 1
}
