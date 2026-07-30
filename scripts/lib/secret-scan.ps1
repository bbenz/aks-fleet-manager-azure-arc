#Requires -Version 5.1
<#
.SYNOPSIS
    Scans every file that would actually be committed (git ls-files
    --others --cached --exclude-standard - i.e. tracked files plus
    untracked-but-not-gitignored files) for common secret patterns:
    AWS access key IDs, private key blocks, Google API keys/OAuth tokens,
    and JWT-shaped strings.

.DESCRIPTION
    High-confidence patterns only, chosen to keep false positives near
    zero - this is a safety net on top of .gitignore, not a replacement for
    it. Exits non-zero if anything matches.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "common.ps1")

Push-Location (Get-RepoRoot)
try {
    $files = @()
    if (Test-CommandExists "git") {
        # @(...) forces an array even when git emits nothing (e.g. the repo was
        # downloaded as a zip rather than cloned), so the .Count check below
        # can't fail on $null under strict mode.
        $files = @((git ls-files --others --cached --exclude-standard 2>$null) | Where-Object { $_ -ne "" })
    }
    if ($files.Count -eq 0) {
        Write-WarnMsg "git not available or returned no files - falling back to a full recursive file listing (slower, may include build/tool directories)."
        $files = @(Get-ChildItem -Recurse -File -Path (Get-RepoRoot) |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]|[\\/]\.terraform[\\/]' } |
            ForEach-Object { $_.FullName.Substring((Get-RepoRoot).Length + 1) })
    }
} finally {
    Pop-Location
}

$patterns = @(
    @{ Name = "AWS Access Key ID"; Regex = "AKIA[0-9A-Z]{16}" },
    @{ Name = "Private key block"; Regex = "-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----" },
    @{ Name = "Google API key"; Regex = "AIza[0-9A-Za-z\-_]{35}" },
    @{ Name = "Google OAuth token"; Regex = "ya29\.[0-9A-Za-z\-_]+" },
    @{ Name = "JWT-shaped string"; Regex = "eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}" }
)

$findings = @()
foreach ($relPath in $files) {
    $fullPath = Join-Path (Get-RepoRoot) $relPath
    if (-not (Test-Path $fullPath -PathType Leaf)) { continue }

    # Skip obvious binary files cheaply.
    if ($relPath -match '\.(png|jpg|jpeg|gif|ico|zip|tar|gz|exe|dll|pdf)$') { continue }

    try {
        $content = Get-Content -Path $fullPath -Raw -ErrorAction Stop
    } catch {
        continue
    }
    if ($null -eq $content) { continue }

    foreach ($pattern in $patterns) {
        if ($content -match $pattern.Regex) {
            $findings += [pscustomobject]@{ File = $relPath; Pattern = $pattern.Name }
        }
    }
}

Write-Step "Secret scan results"
if ($findings.Count -eq 0) {
    Write-Ok "No matches for $($patterns.Count) high-confidence secret patterns across $($files.Count) files."
    exit 0
} else {
    foreach ($f in $findings) {
        Write-ErrMsg "$($f.File) : matched pattern '$($f.Pattern)'"
    }
    Write-ErrMsg "Found $($findings.Count) potential secret(s). Review before committing - do not commit real credentials."
    exit 1
}
