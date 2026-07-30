# scripts/lib/common.ps1
#
# Shared helpers dot-sourced by every scripts/NN-*.ps1 step. Not meant to be
# run directly.
#
# Usage in a numbered script:
#   . (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Path resolution -----------------------------------------------------------
# This file lives at <repo>/scripts/lib/common.ps1, so the repo root is two
# levels up. Every numbered script should use $RepoRoot rather than assuming
# its own current directory. Built via .Parent.Parent (not a string Join-Path
# with ".." segments) and Join-Path throughout this file (not hardcoded "\"
# separators) so this works unchanged under pwsh on Linux/macOS, where "\" is
# a literal filename character, not a path separator.
$script:RepoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$script:ArtifactsDir = Join-Path $RepoRoot "artifacts"
$script:TerraformDir = Join-Path $RepoRoot "terraform"
$script:KubernetesDir = Join-Path $RepoRoot "kubernetes"

function Get-RepoRoot { return $script:RepoRoot }
function Get-ArtifactsDir {
    if (-not (Test-Path $script:ArtifactsDir)) {
        New-Item -ItemType Directory -Path $script:ArtifactsDir -Force | Out-Null
    }
    return $script:ArtifactsDir
}
function Get-TerraformDir { return $script:TerraformDir }
function Get-KubernetesDir { return $script:KubernetesDir }

# --- Console output --------------------------------------------------------------
function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}
function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}
function Write-WarnMsg {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}
function Write-ErrMsg {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}
function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  - $Message" -ForegroundColor Gray
}

# --- .env loading ------------------------------------------------------------
# Parses KEY=VALUE lines from .env (falling back to .env.example if .env
# doesn't exist yet, so scripts are still runnable/informative pre-setup).
# Returns a hashtable. Does NOT mutate $env: - callers use the returned
# hashtable explicitly, so behavior is identical however the script is
# invoked (make, pwsh -File, dot-sourced, etc).
function Get-DotEnv {
    $envPath = Join-Path $script:RepoRoot ".env"
    $usedExample = $false
    if (-not (Test-Path $envPath)) {
        $envPath = Join-Path $script:RepoRoot ".env.example"
        $usedExample = $true
    }

    $result = @{}
    if (Test-Path $envPath) {
        foreach ($line in Get-Content $envPath) {
            $trimmed = $line.Trim()
            if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
            $idx = $trimmed.IndexOf("=")
            if ($idx -lt 1) { continue }
            $key = $trimmed.Substring(0, $idx).Trim()
            $value = $trimmed.Substring($idx + 1).Trim()
            # Strip a single layer of matching quotes, if present.
            if ($value.Length -ge 2 -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            )) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $result[$key] = $value
        }
    }
    if ($usedExample) {
        Write-WarnMsg ".env not found - using .env.example defaults (OWNER, GCP_PROJECT_ID, etc. are blank). Copy .env.example to .env and fill it in for a real run."
    }
    return $result
}

# Reads one key from a Get-DotEnv hashtable, treating missing/blank as
# $Default. All .env values are strings; boolean-looking values are
# compared case-insensitively against "true".
function Get-EnvValue {
    param(
        [Parameter(Mandatory)][hashtable]$DotEnv,
        [Parameter(Mandatory)][string]$Key,
        [string]$Default = ""
    )
    if ($DotEnv.ContainsKey($Key) -and $DotEnv[$Key] -ne "") {
        return $DotEnv[$Key]
    }
    return $Default
}

function Get-EnvBool {
    param(
        [Parameter(Mandatory)][hashtable]$DotEnv,
        [Parameter(Mandatory)][string]$Key,
        [bool]$Default = $true
    )
    $raw = Get-EnvValue -DotEnv $DotEnv -Key $Key -Default ($Default.ToString())
    return $raw.Trim().ToLowerInvariant() -eq "true"
}

# --- Cloud enable/disable ------------------------------------------------------
# Every script loops over "enabled clouds" the same way - single source of
# truth so scripts/00 through scripts/99 always agree on which clouds are
# in scope for a given run.
function Get-EnabledClouds {
    param([Parameter(Mandatory)][hashtable]$DotEnv)
    $clouds = @()
    if (Get-EnvBool -DotEnv $DotEnv -Key "ENABLE_AZURE" -Default $true) { $clouds += "azure" }
    if (Get-EnvBool -DotEnv $DotEnv -Key "ENABLE_AWS" -Default $true) { $clouds += "aws" }
    if (Get-EnvBool -DotEnv $DotEnv -Key "ENABLE_GCP" -Default $true) { $clouds += "gcp" }
    return $clouds
}

# --- Tool detection --------------------------------------------------------------
function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# --- External command execution -----------------------------------------------
# Runs an external command and throws with a clear message on non-zero exit,
# instead of silently continuing (PowerShell's default for native commands).
# Use for anything whose failure should stop the current script step.
function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$ErrorContext = ""
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        $context = if ($ErrorContext) { " ($ErrorContext)" } else { "" }
        throw "Command failed with exit code $LASTEXITCODE${context}: $Command $($Arguments -join ' ')"
    }
}

# Same as Invoke-Checked but never throws - returns $true/$false. Use for
# preflight/validation steps that should report and continue rather than
# abort the whole script on one cloud's failure.
function Invoke-Tolerant {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    & $Command @Arguments
    return ($LASTEXITCODE -eq 0)
}

# --- Confirmation guard for billable / destructive actions --------------------
# Shared by 04-apply.ps1 and 99-destroy-all.ps1. Requires either -AutoApprove
# or an explicit typed confirmation - never proceeds silently.
function Confirm-BillableAction {
    param(
        [Parameter(Mandatory)][string]$ActionDescription,
        [Parameter(Mandatory)][bool]$AutoApprove,
        [string]$ConfirmationWord = "yes"
    )
    if ($AutoApprove) {
        Write-WarnMsg "-AutoApprove supplied - skipping interactive confirmation for: $ActionDescription"
        return $true
    }
    Write-Host ""
    Write-Host "$ActionDescription" -ForegroundColor Yellow
    $response = Read-Host "Type '$ConfirmationWord' to proceed, anything else to abort"
    return $response -eq $ConfirmationWord
}

# --- Region-selection artifact (produced by 02, consumed by 03) --------------
function Get-RegionSelectionPath {
    return (Join-Path (Get-ArtifactsDir) "region-selection.json")
}

function Read-RegionSelection {
    $path = Get-RegionSelectionPath
    if (-not (Test-Path $path)) { return $null }
    return (Get-Content $path -Raw | ConvertFrom-Json)
}
