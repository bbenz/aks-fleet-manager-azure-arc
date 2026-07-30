#Requires -Version 5.1
<#
.SYNOPSIS
    Automatic region/zone discovery for every enabled cloud, with full
    rejected-candidate reasoning saved to artifacts/region-selection.json.

.DESCRIPTION
    For each enabled cloud:
      1. If a *_REGION_OVERRIDE is set in .env, uses it directly (no
         discovery) and records "user override" as the reason.
      2. Otherwise walks a preference-ordered candidate list and picks the
         first candidate that passes that cloud's availability checks
         (AKS + Fleet Manager for Azure; EKS + instance-type offering for
         AWS; GKE + machine-type offering for GCP), using real CLI calls
         when the tool is installed and authenticated.
      3. If the CLI isn't installed/authenticated, or every dynamic check
         fails unexpectedly, falls back to the documented static default
         (same value as that root's variables.tf default) so this script
         always produces a usable, non-fatal result.

    Every candidate considered - selected or rejected - is recorded with a
    human-readable reason in artifacts/region-selection.json. This script
    only reads cloud state; it never creates/modifies anything.
#>
[CmdletBinding()]
param()

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$selection = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    azure        = $null
    aws          = $null
    gcp          = $null
}

# --- Azure -----------------------------------------------------------------------
if ($enabledClouds -contains "azure") {
    Write-Step "Azure region discovery"
    $override = Get-EnvValue -DotEnv $dotEnv -Key "AZURE_REGION_OVERRIDE"
    $candidates = @("eastus2", "westus2", "westus3", "centralus", "eastus")
    $considered = @()

    if ($override) {
        Write-Ok "Using AZURE_REGION_OVERRIDE=$override"
        $selection.azure = [ordered]@{
            selected = $override
            reason   = "user override (.env AZURE_REGION_OVERRIDE)"
            considered = @()
        }
    } elseif (-not (Test-CommandExists "az")) {
        Write-WarnMsg "az CLI not found - falling back to documented default eastus2"
        $selection.azure = [ordered]@{
            selected   = "eastus2"
            reason     = "az CLI not installed - using terraform/azure/variables.tf documented default"
            considered = @()
        }
    } else {
        $fleetLocations = @()
        try {
            $fleetDisplayNames = (az provider show --namespace Microsoft.ContainerService --query "resourceTypes[?resourceType=='fleets'].locations[]" -o tsv 2>$null)
            $allLocations = (az account list-locations -o json 2>$null | ConvertFrom-Json)
            foreach ($displayName in $fleetDisplayNames) {
                $match = $allLocations | Where-Object { $_.displayName -eq $displayName }
                if ($match) { $fleetLocations += $match.name }
            }
        } catch { $fleetLocations = @() }

        $picked = $null
        foreach ($region in $candidates) {
            $aksOk = $false
            try {
                $versions = (az aks get-versions --location $region -o json 2>$null | ConvertFrom-Json)
                $aksOk = ($null -ne $versions -and $versions.values.Count -gt 0)
            } catch { $aksOk = $false }

            $fleetOk = ($fleetLocations.Count -eq 0) -or ($fleetLocations -contains $region)

            if ($aksOk -and $fleetOk) {
                $considered += [ordered]@{ region = $region; aks_available = $aksOk; fleet_available = $fleetOk; result = "selected" }
                $picked = $region
                Write-Ok "$region : AKS available, Fleet Manager available -> SELECTED"
                break
            } else {
                $reason = if (-not $aksOk) { "AKS not available or query failed" } else { "Fleet Manager not listed as available here" }
                $considered += [ordered]@{ region = $region; aks_available = $aksOk; fleet_available = $fleetOk; result = "rejected"; reason = $reason }
                Write-WarnMsg "$region : rejected ($reason)"
            }
        }
        if (-not $picked) {
            $picked = "eastus2"
            Write-WarnMsg "No candidate passed dynamic checks - falling back to documented default eastus2"
        }
        $selection.azure = [ordered]@{
            selected   = $picked
            reason     = "automatic discovery (AKS + Fleet Manager availability)"
            considered = $considered
        }
    }
}

# --- AWS -------------------------------------------------------------------------
if ($enabledClouds -contains "aws") {
    Write-Step "AWS region discovery"
    $override = Get-EnvValue -DotEnv $dotEnv -Key "AWS_REGION_OVERRIDE"
    $profile = Get-EnvValue -DotEnv $dotEnv -Key "AWS_PROFILE"
    $profileArgs = if ($profile) { @("--profile", $profile) } else { @() }
    $candidates = @("us-east-1", "us-east-2", "us-west-2")
    $considered = @()

    if ($override) {
        Write-Ok "Using AWS_REGION_OVERRIDE=$override"
        $selection.aws = [ordered]@{
            selected   = $override
            reason     = "user override (.env AWS_REGION_OVERRIDE)"
            considered = @()
        }
    } elseif (-not (Test-CommandExists "aws")) {
        Write-WarnMsg "aws CLI not found - falling back to documented default us-east-1"
        $selection.aws = [ordered]@{
            selected   = "us-east-1"
            reason     = "aws CLI not installed - using terraform/aws/variables.tf documented default"
            considered = @()
        }
    } else {
        $picked = $null
        foreach ($region in $candidates) {
            $offeringOk = $false
            try {
                $offerings = (& aws ec2 describe-instance-type-offerings --region $region @profileArgs `
                        --location-type region --filters "Name=instance-type,Values=t3.large" --output json 2>$null | ConvertFrom-Json)
                $offeringOk = ($null -ne $offerings -and $offerings.InstanceTypeOfferings.Count -gt 0)
            } catch { $offeringOk = $false }

            if ($offeringOk) {
                $considered += [ordered]@{ region = $region; t3_large_available = $true; result = "selected" }
                $picked = $region
                Write-Ok "$region : t3.large available -> SELECTED"
                break
            } else {
                $considered += [ordered]@{ region = $region; t3_large_available = $false; result = "rejected"; reason = "t3.large offering query failed or unavailable (aws CLI unauthenticated or region lacks capacity)" }
                Write-WarnMsg "$region : rejected (t3.large offering query failed or unavailable)"
            }
        }
        if (-not $picked) {
            $picked = "us-east-1"
            Write-WarnMsg "No candidate passed dynamic checks (likely unauthenticated) - falling back to documented default us-east-1"
        }
        $selection.aws = [ordered]@{
            selected   = $picked
            reason     = if ($considered | Where-Object { $_.result -eq "selected" }) { "automatic discovery (t3.large instance-type offering availability)" } else { "no candidate could be dynamically verified (aws CLI unauthenticated or lacks EC2 describe permissions) - falling back to terraform/aws/variables.tf documented default" }
            considered = $considered
        }
    }
}

# --- GCP -------------------------------------------------------------------------
if ($enabledClouds -contains "gcp") {
    Write-Step "GCP region/zone discovery"
    $regionOverride = Get-EnvValue -DotEnv $dotEnv -Key "GCP_REGION_OVERRIDE"
    $zoneOverride = Get-EnvValue -DotEnv $dotEnv -Key "GCP_ZONE_OVERRIDE"
    $projectId = Get-EnvValue -DotEnv $dotEnv -Key "GCP_PROJECT_ID"
    $candidates = @(
        @{ region = "us-central1"; zone = "us-central1-a" },
        @{ region = "us-east1"; zone = "us-east1-b" },
        @{ region = "us-east4"; zone = "us-east4-a" }
    )
    $considered = @()

    if ($regionOverride -and $zoneOverride) {
        Write-Ok "Using GCP_REGION_OVERRIDE=$regionOverride / GCP_ZONE_OVERRIDE=$zoneOverride"
        $selection.gcp = [ordered]@{
            selected_region = $regionOverride
            selected_zone   = $zoneOverride
            reason          = "user override (.env GCP_REGION_OVERRIDE/GCP_ZONE_OVERRIDE)"
            considered      = @()
        }
    } elseif (-not (Test-CommandExists "gcloud") -or -not $projectId) {
        $why = if (-not (Test-CommandExists "gcloud")) { "gcloud CLI not installed" } else { "GCP_PROJECT_ID not set in .env" }
        Write-WarnMsg "$why - falling back to documented default us-central1 / us-central1-a"
        $selection.gcp = [ordered]@{
            selected_region = "us-central1"
            selected_zone   = "us-central1-a"
            reason          = "$why - using terraform/gcp/variables.tf documented default"
            considered      = @()
        }
    } else {
        $picked = $null
        foreach ($candidate in $candidates) {
            $machineOk = $false
            try {
                $result = (gcloud compute machine-types list --project $projectId `
                        --filter="zone:$($candidate.zone) AND name:e2-standard-2" --format="value(name)" --quiet 2>$null)
                $machineOk = [bool]$result
            } catch { $machineOk = $false }

            if ($machineOk) {
                $considered += [ordered]@{ region = $candidate.region; zone = $candidate.zone; e2_standard_2_available = $true; result = "selected" }
                $picked = $candidate
                Write-Ok "$($candidate.zone) : e2-standard-2 available -> SELECTED"
                break
            } else {
                $considered += [ordered]@{ region = $candidate.region; zone = $candidate.zone; e2_standard_2_available = $false; result = "rejected"; reason = "e2-standard-2 machine-type query failed or unavailable (gcloud unauthenticated or zone lacks capacity)" }
                Write-WarnMsg "$($candidate.zone) : rejected (e2-standard-2 machine-type query failed or unavailable)"
            }
        }
        if (-not $picked) {
            $picked = @{ region = "us-central1"; zone = "us-central1-a" }
            Write-WarnMsg "No candidate passed dynamic checks (likely unauthenticated) - falling back to documented default us-central1 / us-central1-a"
        }
        $selection.gcp = [ordered]@{
            selected_region = $picked.region
            selected_zone   = $picked.zone
            reason          = if ($considered | Where-Object { $_.result -eq "selected" }) { "automatic discovery (e2-standard-2 machine-type availability)" } else { "no candidate could be dynamically verified (gcloud unauthenticated or lacks Compute viewer permissions) - falling back to terraform/gcp/variables.tf documented default" }
            considered      = $considered
        }
    }
}

$outPath = Get-RegionSelectionPath
$selection | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding utf8
Write-Step "Summary"
Write-Ok "Region selection written to $outPath"
if ($selection.azure) { Write-Info "Azure: $($selection.azure.selected)" }
if ($selection.aws) { Write-Info "AWS:   $($selection.aws.selected)" }
if ($selection.gcp) { Write-Info "GCP:   $($selection.gcp.selected_region) / $($selection.gcp.selected_zone)" }
exit 0
