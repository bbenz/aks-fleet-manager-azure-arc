#Requires -Version 5.1
<#
.SYNOPSIS
    Reads .env and establishes cloud CLI authentication for every enabled
    cloud (ENABLE_AZURE/ENABLE_AWS/ENABLE_GCP).

.DESCRIPTION
    Azure, AWS console, and GCP console credentials are never convertible to
    CLI/API credentials programmatically - each cloud requires its own
    official, browser-interactive, MFA-capable login flow. This script
    detects whether you're already authenticated for each enabled cloud and,
    only when run interactively, offers to launch that cloud's official
    login command for you. It never scrapes, automates around, or bypasses
    any login/MFA flow - see docs/AUTHENTICATION-AND-PERMISSIONS.md.

.PARAMETER NonInteractive
    Only checks and reports current auth state for each enabled cloud; never
    launches a login flow or prompts for confirmation. Use this in CI or
    when re-running unattended - exits non-zero if any enabled cloud isn't
    already authenticated.
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive
)

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$allOk = $true

# --- Azure ---------------------------------------------------------------------
if ($enabledClouds -contains "azure") {
    Write-Step "Azure authentication"
    $expectedTenant = Get-EnvValue -DotEnv $dotEnv -Key "AZURE_EXPECTED_TENANT_ID"
    $expectedSub = Get-EnvValue -DotEnv $dotEnv -Key "AZURE_EXPECTED_SUBSCRIPTION_ID"

    $account = $null
    try { $account = (az account show -o json 2>$null | ConvertFrom-Json) } catch { $account = $null }

    if (-not $account) {
        Write-WarnMsg "Not logged in to Azure CLI."
        if (-not $NonInteractive) {
            Write-Info "Launching 'az login' (opens your default browser)..."
            az login | Out-Null
            try { $account = (az account show -o json 2>$null | ConvertFrom-Json) } catch { $account = $null }
        }
    }

    if ($account) {
        Write-Ok "Logged in as $($account.user.name) - tenant $($account.tenantId), subscription '$($account.name)' ($($account.id))"
        if ($expectedTenant -and $account.tenantId -ne $expectedTenant) {
            Write-WarnMsg "Active tenant ($($account.tenantId)) does not match AZURE_EXPECTED_TENANT_ID ($expectedTenant). Run: az login --tenant $expectedTenant"
            $allOk = $false
        }
        if ($expectedSub -and $account.id -ne $expectedSub) {
            if (-not $NonInteractive) {
                Write-Info "Switching to expected subscription $expectedSub ..."
                az account set --subscription $expectedSub
                $account = (az account show -o json | ConvertFrom-Json)
            } else {
                Write-WarnMsg "Active subscription ($($account.id)) does not match AZURE_EXPECTED_SUBSCRIPTION_ID ($expectedSub). Run: az account set --subscription $expectedSub"
                $allOk = $false
            }
        }
    } else {
        Write-ErrMsg "Azure CLI is still not authenticated."
        $allOk = $false
    }
}

# --- AWS -------------------------------------------------------------------------
if ($enabledClouds -contains "aws") {
    Write-Step "AWS authentication"
    if (-not (Test-CommandExists "aws")) {
        Write-ErrMsg "aws CLI not installed - run scripts/00-check-tools.ps1 install guidance first."
        $allOk = $false
    } else {
        $profile = Get-EnvValue -DotEnv $dotEnv -Key "AWS_PROFILE"
        $profileArgs = if ($profile) { @("--profile", $profile) } else { @() }
        $expectedAccount = Get-EnvValue -DotEnv $dotEnv -Key "AWS_EXPECTED_ACCOUNT_ID"

        $identity = $null
        try {
            $identity = (& aws sts get-caller-identity @profileArgs --output json 2>$null | ConvertFrom-Json)
        } catch { $identity = $null }

        if (-not $identity -and -not $NonInteractive) {
            Write-WarnMsg "Not authenticated to AWS$(if ($profile) { " (profile '$profile')" })."
            Write-Host ""
            Write-Host "AWS console credentials (username/password) cannot be converted into CLI" -ForegroundColor Yellow
            Write-Host "credentials programmatically - this requires YOUR interactive, MFA-capable" -ForegroundColor Yellow
            Write-Host "login. Recommended: AWS IAM Identity Center / SSO if your account has it" -ForegroundColor Yellow
            Write-Host "configured; otherwise 'aws configure' with a long-lived access key you" -ForegroundColor Yellow
            Write-Host "generate yourself in the console (Security credentials -> Access keys)." -ForegroundColor Yellow
            Write-Host ""
            $choice = Read-Host "Launch 'aws configure sso'$(if ($profile) { " --profile $profile" }) now? [y/N]"
            if ($choice -eq "y" -or $choice -eq "Y") {
                if ($profile) { aws configure sso --profile $profile } else { aws configure sso }
                try { $identity = (& aws sts get-caller-identity @profileArgs --output json 2>$null | ConvertFrom-Json) } catch { $identity = $null }
            }
        }

        if ($identity) {
            Write-Ok "Authenticated as $($identity.Arn) - account $($identity.Account)"
            if ($expectedAccount -and $identity.Account -ne $expectedAccount) {
                Write-WarnMsg "Active account ($($identity.Account)) does not match AWS_EXPECTED_ACCOUNT_ID ($expectedAccount)."
                $allOk = $false
            }
        } else {
            Write-ErrMsg "AWS CLI is still not authenticated$(if ($profile) { " for profile '$profile'" }). This is a genuine manual blocker - see docs/AUTHENTICATION-AND-PERMISSIONS.md."
            $allOk = $false
        }
    }
}

# --- GCP -------------------------------------------------------------------------
if ($enabledClouds -contains "gcp") {
    Write-Step "GCP authentication"
    if (-not (Test-CommandExists "gcloud")) {
        Write-ErrMsg "gcloud CLI not installed - run scripts/00-check-tools.ps1 install guidance first."
        $allOk = $false
    } else {
        $projectId = Get-EnvValue -DotEnv $dotEnv -Key "GCP_PROJECT_ID"

        $hasAdc = $false
        try {
            & gcloud auth application-default print-access-token 2>$null | Out-Null
            $hasAdc = ($LASTEXITCODE -eq 0)
        } catch { $hasAdc = $false }

        if (-not $hasAdc -and -not $NonInteractive) {
            Write-WarnMsg "No Application Default Credentials found."
            Write-Host ""
            Write-Host "GCP console credentials (Google account/password) cannot be converted into" -ForegroundColor Yellow
            Write-Host "CLI credentials programmatically - this requires YOUR interactive," -ForegroundColor Yellow
            Write-Host "MFA-capable browser login." -ForegroundColor Yellow
            Write-Host ""
            $choice = Read-Host "Launch 'gcloud auth login' + 'gcloud auth application-default login' now? [y/N]"
            if ($choice -eq "y" -or $choice -eq "Y") {
                gcloud auth login
                gcloud auth application-default login
                try {
                    & gcloud auth application-default print-access-token 2>$null | Out-Null
                    $hasAdc = ($LASTEXITCODE -eq 0)
                } catch { $hasAdc = $false }
            }
        }

        if ($hasAdc) {
            $activeAccount = (gcloud config get-value account 2>$null)
            Write-Ok "Application Default Credentials present (active account: $activeAccount)"
            if ($projectId) {
                gcloud config set project $projectId 2>&1 | Out-Null
                Write-Ok "gcloud project set to $projectId"
            } else {
                Write-WarnMsg "GCP_PROJECT_ID is blank in .env - set it before running scripts/03-init-plan.ps1."
            }
        } else {
            Write-ErrMsg "gcloud Application Default Credentials still not present. This is a genuine manual blocker - see docs/AUTHENTICATION-AND-PERMISSIONS.md."
            $allOk = $false
        }
    }
}

Write-Step "Summary"
if ($allOk) {
    Write-Ok "All enabled clouds ($($enabledClouds -join ', ')) are authenticated."
    exit 0
} else {
    Write-ErrMsg "One or more enabled clouds are not authenticated yet. Re-run this script after completing the login flow(s) above, or disable that cloud in .env (ENABLE_AZURE/ENABLE_AWS/ENABLE_GCP=false) to proceed with the rest."
    exit 1
}
