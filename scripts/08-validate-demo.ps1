#Requires -Version 5.1
<#
.SYNOPSIS
    Full demo validation: runs the in-cluster smoke-test Job on every
    enabled member cluster, checks each cluster's external frontend
    LoadBalancer endpoint over HTTP, and writes a consolidated pass/fail
    report to artifacts/validation-report.json.

.DESCRIPTION
    Requires: scripts/07-deploy-workload.ps1 already completed. Read-only
    with one exception: applies and then deletes the smoke-test Job
    (kubernetes/validation/smoke-test-job.yaml) on each member context - see
    that file's header comment for why it's applied per-run rather than
    being part of the Fleet-placed base workload.
#>
[CmdletBinding()]
param(
    [int]$ExternalCheckTimeoutMinutes = 5
)

. (Join-Path (Join-Path $PSScriptRoot "lib") "common.ps1")

$dotEnv = Get-DotEnv
$enabledClouds = Get-EnabledClouds -DotEnv $dotEnv
$k8sDir = Get-KubernetesDir
$smokeTestPath = Join-Path (Join-Path $k8sDir "validation") "smoke-test-job.yaml"

$contextByCloud = @{ azure = "aks-demo"; aws = "eks-demo"; gcp = "gke-demo" }
$report = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    clusters     = @()
}

function Test-SmokeJob {
    param([Parameter(Mandatory)][string]$KubeContext)

    kubectl delete -f $smokeTestPath --context $KubeContext --ignore-not-found=true 2>&1 | Out-Null
    Invoke-Checked -Command "kubectl" -Arguments @("apply", "-f", $smokeTestPath, "--context", $KubeContext) -ErrorContext "apply smoke test ($KubeContext)" | Out-Null

    $deadline = (Get-Date).AddSeconds(150)
    $status = "Unknown"
    do {
        Start-Sleep -Seconds 5
        $job = (kubectl get job fleet-arc-demo-smoke-test -n online-boutique --context $KubeContext -o json 2>$null | ConvertFrom-Json)
        $jobStatus = if ($job -and $job.PSObject.Properties["status"]) { $job.status } else { $null }
        if ($jobStatus -and $jobStatus.PSObject.Properties["succeeded"] -and $jobStatus.succeeded -ge 1) { $status = "Succeeded" }
        elseif ($jobStatus -and $jobStatus.PSObject.Properties["failed"] -and $jobStatus.failed -ge 2) { $status = "Failed" }
    } while ($status -eq "Unknown" -and (Get-Date) -lt $deadline)

    $logs = (kubectl logs job/fleet-arc-demo-smoke-test -n online-boutique --context $KubeContext 2>$null)
    kubectl delete -f $smokeTestPath --context $KubeContext --ignore-not-found=true 2>&1 | Out-Null

    return [ordered]@{ status = $status; logs = $logs }
}

function Test-ExternalFrontend {
    param([Parameter(Mandatory)][string]$KubeContext)

    $deadline = (Get-Date).AddMinutes($ExternalCheckTimeoutMinutes)
    $endpoint = $null
    $lastError = $null
    do {
        $svc = (kubectl get svc frontend-external -n online-boutique --context $KubeContext -o json 2>$null | ConvertFrom-Json)
        $svcStatus = if ($svc -and $svc.PSObject.Properties["status"]) { $svc.status } else { $null }
        $loadBalancer = if ($svcStatus -and $svcStatus.PSObject.Properties["loadBalancer"]) { $svcStatus.loadBalancer } else { $null }
        if ($loadBalancer -and $loadBalancer.PSObject.Properties["ingress"] -and $loadBalancer.ingress) {
            $ing = $loadBalancer.ingress[0]
            if ($ing.PSObject.Properties["ip"] -and $ing.ip) {
                $endpoint = $ing.ip
            } elseif ($ing.PSObject.Properties["hostname"] -and $ing.hostname) {
                $endpoint = $ing.hostname
            }
        }

        if ($endpoint) {
            try {
                $response = Invoke-WebRequest -Uri "http://$endpoint/" -TimeoutSec 15 -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                    return [ordered]@{ status = "OK"; endpoint = $endpoint; http_status = $response.StatusCode }
                }
                $lastError = "Unexpected HTTP status $($response.StatusCode)"
            } catch {
                $lastError = $_.Exception.Message
            }
        }

        if ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 15 }
    } while ((Get-Date) -lt $deadline)

    if (-not $endpoint) {
        return [ordered]@{ status = "NoExternalIP"; endpoint = $null; http_status = $null }
    }

    return [ordered]@{ status = "RequestFailed"; endpoint = $endpoint; http_status = $null; error = $lastError }
}

$allOk = $true
foreach ($cloud in $enabledClouds) {
    $ctx = $contextByCloud[$cloud]
    Write-Step "Validating $cloud ($ctx)"

    Write-Info "Running in-cluster smoke test..."
    $smoke = Test-SmokeJob -KubeContext $ctx
    if ($smoke.status -eq "Succeeded") { Write-Ok "Smoke test: Succeeded" } else { Write-ErrMsg "Smoke test: $($smoke.status)"; $allOk = $false }

    Write-Info "Checking external frontend endpoint..."
    $ext = Test-ExternalFrontend -KubeContext $ctx
    if ($ext.status -eq "OK") { Write-Ok "External frontend: HTTP $($ext.http_status) at $($ext.endpoint)" } else { Write-ErrMsg "External frontend: $($ext.status) ($($ext.endpoint))"; $allOk = $false }

    $report.clusters += [ordered]@{
        cloud             = $cloud
        context           = $ctx
        smoke_test        = $smoke
        external_frontend = $ext
    }
}

$reportPath = Join-Path (Get-ArtifactsDir) "validation-report.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding utf8

Write-Step "Summary"
Write-Ok "Validation report written to $reportPath"
if ($allOk) {
    Write-Ok "All enabled clusters ($($enabledClouds -join ', ')) passed validation."
    exit 0
} else {
    Write-ErrMsg "One or more clusters failed validation - see $reportPath and docs/TROUBLESHOOTING.md."
    exit 1
}
