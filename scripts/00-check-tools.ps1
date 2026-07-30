#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies local CLI tool versions and installs/upgrades the Azure CLI
    extensions this demo needs (connectedk8s, fleet). Non-destructive to any
    cloud resource - only touches the local machine's tool installation.

.DESCRIPTION
    Always checks: git, terraform, kubectl, az, helm (needed regardless of
    which clouds are enabled - az is required for Fleet Manager + Arc even
    when only AWS/GCP clusters need onboarding).
    Conditionally checks: aws (if ENABLE_AWS), gcloud (if ENABLE_GCP).

    Exits non-zero only if a tool required by a currently-enabled cloud is
    missing, so `make all` stops here with a clear, actionable message
    rather than failing confusingly several steps later.
#>
[CmdletBinding()]
param()

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

Write-Step "Checking local tool versions"

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$missingRequired = @()

function Test-Tool {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$VersionArgs,
        [bool]$Required = $true,
        # Optional: receives the full raw output lines, returns a display string.
        # Avoids passing tricky quoted query strings as native command
        # arguments (fragile across PowerShell 5.1/7 native-arg handling) -
        # do any parsing in PowerShell instead, e.g. JSON extraction.
        [scriptblock]$Parser
    )
    if (Test-CommandExists $Name) {
        try {
            $rawOutput = @(& $Name @VersionArgs 2>&1)
            if ($Parser) {
                $versionOutput = (& $Parser $rawOutput)
            } else {
                $versionOutput = $rawOutput | Select-Object -First 1
            }
            Write-Ok "$Name found: $versionOutput"
        } catch {
            Write-Ok "$Name found (version check failed to parse, but binary exists)"
        }
        return $true
    } else {
        if ($Required) {
            Write-ErrMsg "$Name NOT found (required)"
            $script:missingRequired += $Name
        } else {
            Write-WarnMsg "$Name NOT found (not required for currently-enabled clouds)"
        }
        return $false
    }
}

# Always required.
[void](Test-Tool -Name "git" -VersionArgs @("--version"))
[void](Test-Tool -Name "terraform" -VersionArgs @("version"))
[void](Test-Tool -Name "kubectl" -VersionArgs @("version", "--client"))
[void](Test-Tool -Name "az" -VersionArgs @("version", "-o", "json") -Parser {
    param($lines)
    try {
        $json = ($lines -join "`n") | ConvertFrom-Json
        "azure-cli $($json.'azure-cli')"
    } catch {
        $lines | Select-Object -First 1
    }
})
[void](Test-Tool -Name "helm" -VersionArgs @("version", "--short"))

# Conditionally required.
[void](Test-Tool -Name "aws" -VersionArgs @("--version") -Required:($enabledClouds -contains "aws"))
[void](Test-Tool -Name "gcloud" -VersionArgs @("version") -Required:($enabledClouds -contains "gcp"))
[void](Test-Tool -Name "gke-gcloud-auth-plugin" -VersionArgs @("--version") -Required:($enabledClouds -contains "gcp"))

Write-Step "Checking required az CLI extensions (connectedk8s, fleet)"
if (Test-CommandExists "az") {
    $extList = (az extension list -o json 2>$null | ConvertFrom-Json)
    $extNames = @($extList | ForEach-Object { $_.name })
    foreach ($ext in @("connectedk8s", "fleet")) {
        if ($extNames -contains $ext) {
            Write-Ok "az extension '$ext' already installed - upgrading if needed"
            az extension update --name $ext 2>&1 | Out-Null
        } else {
            Write-Info "Installing az extension '$ext'..."
            az extension add --name $ext --yes 2>&1 | Out-Null
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "az extension '$ext' ready"
        } else {
            Write-WarnMsg "az extension '$ext' install/upgrade reported a non-zero exit - re-run this script, or install manually: az extension add --name $ext"
        }
    }
} else {
    Write-WarnMsg "az CLI not found - skipping extension checks"
}

Write-Step "Summary"
Write-Info "Enabled clouds (from .env ENABLE_AZURE/ENABLE_AWS/ENABLE_GCP): $($enabledClouds -join ', ')"
if ($missingRequired.Count -gt 0) {
    Write-ErrMsg "Missing required tools: $($missingRequired -join ', ')"
    Write-Host ""
    Write-Host "Install guidance:" -ForegroundColor Yellow
    Write-Host "  git        - https://git-scm.com/downloads"
    Write-Host "  terraform  - winget install HashiCorp.Terraform  (or https://developer.hashicorp.com/terraform/install)"
    Write-Host "  kubectl    - winget install Kubernetes.kubectl"
    Write-Host "  az         - winget install Microsoft.AzureCLI"
    Write-Host "  helm       - winget install Helm.Helm"
    Write-Host "  aws        - winget install Amazon.AWSCLI  (or https://awscli.amazonaws.com/AWSCLIV2.msi)"
    Write-Host "  gcloud     - winget install Google.CloudSDK"
    Write-Host "  gke-gcloud-auth-plugin - gcloud components install gke-gcloud-auth-plugin"
    exit 1
}

Write-Ok "All tools required for the currently-enabled clouds are present."
exit 0
