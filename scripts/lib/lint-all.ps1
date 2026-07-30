#Requires -Version 5.1
<#
.SYNOPSIS
    terraform fmt -check + terraform validate across every Terraform root in
    the repo, plus tflint if it happens to be installed (optional - not a
    required tool for this demo).
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "common.ps1")

$tfRoot = Get-TerraformDir
# Each root is a forward-slash-joined label (used both for display and, split
# on "/" then rejoined via Join-Path, for the actual filesystem path) so this
# works unchanged on Windows and under pwsh on Linux/macOS.
$roots = @(
    "azure", "aws", "gcp",
    "bootstrap/azure", "bootstrap/aws", "bootstrap/gcp",
    "environments/demo"
)

function Get-RootDir([string]$root) {
    $path = $tfRoot
    foreach ($segment in ($root -split "/")) { $path = Join-Path $path $segment }
    return $path
}

$failures = @()
foreach ($root in $roots) {
    $dir = Get-RootDir $root
    if (-not (Test-Path $dir)) { continue }
    Write-Step "terraform fmt -check / validate: $root"
    Push-Location $dir
    try {
        & terraform fmt -check -diff | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrMsg "$root : terraform fmt -check failed (run 'terraform fmt' in $dir)"
            $failures += "$root (fmt)"
        } else {
            Write-Ok "$root : fmt OK"
        }

        if (-not (Test-Path ".terraform")) {
            terraform init -backend=false -input=false 2>&1 | Out-Null
        }
        & terraform validate -no-color | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrMsg "$root : terraform validate failed"
            $failures += "$root (validate)"
        } else {
            Write-Ok "$root : validate OK"
        }
    } finally {
        Pop-Location
    }
}

if (Test-CommandExists "tflint") {
    Write-Step "tflint (optional, installed)"
    foreach ($root in $roots) {
        $dir = Get-RootDir $root
        if (-not (Test-Path $dir)) { continue }
        Push-Location $dir
        try {
            & tflint 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-WarnMsg "$root : tflint reported findings" } else { Write-Ok "$root : tflint clean" }
        } finally { Pop-Location }
    }
} else {
    Write-Info "tflint not installed - skipping (optional, not required for this demo)"
}

Write-Step "Summary"
if ($failures.Count -gt 0) {
    Write-ErrMsg "Failures: $($failures -join ', ')"
    exit 1
} else {
    Write-Ok "All Terraform roots pass fmt + validate."
    exit 0
}
