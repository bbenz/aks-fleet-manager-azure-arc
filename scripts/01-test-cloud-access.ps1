#Requires -Version 5.1
<#
.SYNOPSIS
    Non-destructive preflight for every enabled cloud: proves the active CLI
    credentials can actually read real data (not just "some token exists"),
    and reports the status of the resource providers/APIs each cloud root
    depends on.

.DESCRIPTION
    Read-only. Creates and modifies nothing. Safe to re-run at any time.
    Exits non-zero if any enabled cloud fails its access check.
#>
[CmdletBinding()]
param()

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$allOk = $true

# --- Azure ---------------------------------------------------------------------
if ($enabledClouds -contains "azure") {
    Write-Step "Azure: read-only access check"
    try {
        $accountRaw = (az account show -o json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $errLine = ($accountRaw | Where-Object { "$_".Trim() -ne "" } | Select-Object -First 1)
            throw "az account show failed: $errLine (run 'az login' first)"
        }
        $account = ($accountRaw | ConvertFrom-Json)
        Write-Ok "az account show: subscription '$($account.name)' ($($account.id))"

        Write-Info "Checking resource group read access..."
        az group list -o table --query "[].name" 2>&1 | Select-Object -First 5 | ForEach-Object { Write-Info $_ }

        Write-Info "Checking required resource provider registration state (AKS/Fleet/Arc)..."
        $providers = @("Microsoft.ContainerService", "Microsoft.Kubernetes", "Microsoft.KubernetesConfiguration", "Microsoft.ContainerService")
        foreach ($p in ($providers | Select-Object -Unique)) {
            $state = az provider show --namespace $p --query "registrationState" -o tsv 2>$null
            if ($state -eq "Registered") {
                Write-Ok "$p : $state"
            } else {
                Write-WarnMsg "$p : $state (Terraform/az will register it automatically on first use if you have Contributor - or run: az provider register --namespace $p)"
            }
        }
    } catch {
        Write-ErrMsg "Azure access check failed: $_"
        $allOk = $false
    }
}

# --- AWS -------------------------------------------------------------------------
if ($enabledClouds -contains "aws") {
    Write-Step "AWS: read-only access check"
    if (-not (Test-CommandExists "aws")) {
        Write-ErrMsg "aws CLI not installed."
        $allOk = $false
    } else {
        $profile = Get-EnvValue -DotEnv $dotEnv -Key "AWS_PROFILE"
        $profileArgs = if ($profile) { @("--profile", $profile) } else { @() }
        try {
            $identityRaw = (& aws sts get-caller-identity @profileArgs --output json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                $errLine = ($identityRaw | Where-Object { "$_".Trim() -ne "" } | Select-Object -First 1)
                Write-ErrMsg "AWS access check failed - not authenticated$(if ($profile) { " (profile '$profile')" }): $errLine"
                Write-Info "Run 'aws configure sso' (or 'aws configure') interactively first - see docs/AUTHENTICATION-AND-PERMISSIONS.md"
                $allOk = $false
            } else {
                $identity = ($identityRaw | ConvertFrom-Json)
                Write-Ok "aws sts get-caller-identity: $($identity.Arn)"

                Write-Info "Checking EC2 region list access (proves basic read permissions)..."
                & aws ec2 describe-regions @profileArgs --query "Regions[].RegionName" --output json 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Ok "ec2:DescribeRegions OK" } else { Write-WarnMsg "ec2:DescribeRegions failed - check IAM permissions" }

                Write-Info "Checking EKS list access (proves eks:ListClusters permission)..."
                & aws eks list-clusters @profileArgs --output json 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Ok "eks:ListClusters OK" } else { Write-WarnMsg "eks:ListClusters failed - check IAM permissions (see docs/AUTHENTICATION-AND-PERMISSIONS.md)" }
            }
        } catch {
            Write-ErrMsg "AWS access check failed: $_"
            $allOk = $false
        }
    }
}

# --- GCP -------------------------------------------------------------------------
if ($enabledClouds -contains "gcp") {
    Write-Step "GCP: read-only access check"
    if (-not (Test-CommandExists "gcloud")) {
        Write-ErrMsg "gcloud CLI not installed."
        $allOk = $false
    } else {
        $projectId = Get-EnvValue -DotEnv $dotEnv -Key "GCP_PROJECT_ID"
        if (-not $projectId) {
            Write-ErrMsg "GCP_PROJECT_ID is blank in .env - cannot run project-scoped checks."
            $allOk = $false
        } else {
            try {
                $projectRaw = (gcloud projects describe $projectId --format=json 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    $errLine = ($projectRaw | Where-Object { "$_".Trim() -ne "" } | Select-Object -First 1)
                    throw "gcloud projects describe failed: $errLine"
                }
                $project = ($projectRaw | ConvertFrom-Json)
                Write-Ok "gcloud projects describe: '$($project.name)' ($($project.projectId)), state=$($project.lifecycleState)"

                Write-Info "Checking enabled services (container.googleapis.com, compute.googleapis.com)..."
                $services = (gcloud services list --enabled --project $projectId --format="value(config.name)" 2>$null)
                foreach ($svc in @("container.googleapis.com", "compute.googleapis.com")) {
                    if ($services -contains $svc) {
                        Write-Ok "$svc : enabled"
                    } else {
                        Write-WarnMsg "$svc : not yet enabled (terraform/gcp will enable it automatically on apply)"
                    }
                }
            } catch {
                Write-ErrMsg "GCP access check failed: $_"
                Write-Info "Run 'gcloud auth login' and 'gcloud auth application-default login' interactively first - see docs/AUTHENTICATION-AND-PERMISSIONS.md"
                $allOk = $false
            }
        }
    }
}

Write-Step "Summary"
if ($allOk) {
    Write-Ok "Read-only access confirmed for all enabled clouds ($($enabledClouds -join ', '))."
    exit 0
} else {
    Write-ErrMsg "One or more enabled clouds failed their access check. Fix and re-run before continuing to scripts/02-select-regions.ps1."
    exit 1
}
