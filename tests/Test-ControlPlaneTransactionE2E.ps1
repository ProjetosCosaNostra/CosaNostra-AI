$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$source = Join-Path $repoRoot 'control-plane'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('BlackGold-Txn-E2E-' + [guid]::NewGuid().ToString('N'))

$active = Join-Path $root 'ControlPlane'
$stage = Join-Path $root 'ControlPlane.__staging'
$previous = Join-Path $root 'ControlPlane.__previous'

$targetManifest = Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw | ConvertFrom-Json
$targetVersion = [string]$targetManifest.version
$previousVersion = 'previous-test-version'

try {
    New-Item -ItemType Directory -Force -Path $active | Out-Null

    @{
        schema = 1
        name = 'BlackGold Control Plane'
        version = $previousVersion
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $active 'manifest.json') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $active 'LAST_GOOD.marker') -Value 'old-good' -Encoding UTF8

    Copy-Item -LiteralPath $source -Destination $stage -Recurse

    $stagedManifest = Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw | ConvertFrom-Json
    if ([string]$stagedManifest.version -ne $targetVersion) {
        throw ('Unexpected staged version: ' + [string]$stagedManifest.version)
    }

    Get-ChildItem -LiteralPath $stage -Recurse -Filter '*.ps1' -File | ForEach-Object {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            throw ('Staged script parse error: ' + $_.FullName)
        }
    }

    Move-Item -LiteralPath $active -Destination $previous
    Move-Item -LiteralPath $stage -Destination $active

    $activeManifest = Get-Content -LiteralPath (Join-Path $active 'manifest.json') -Raw | ConvertFrom-Json
    $previousManifest = Get-Content -LiteralPath (Join-Path $previous 'manifest.json') -Raw | ConvertFrom-Json

    if ([string]$activeManifest.version -ne $targetVersion) { throw 'Activation did not promote target version.' }
    if ([string]$previousManifest.version -ne $previousVersion) { throw 'Previous slot did not preserve old version.' }
    if (-not (Test-Path -LiteralPath (Join-Path $previous 'LAST_GOOD.marker'))) { throw 'Last-good marker was not preserved.' }

    Remove-Item -LiteralPath $active -Recurse -Force
    Move-Item -LiteralPath $previous -Destination $active

    $rolledBackManifest = Get-Content -LiteralPath (Join-Path $active 'manifest.json') -Raw | ConvertFrom-Json
    if ([string]$rolledBackManifest.version -ne $previousVersion) { throw 'Rollback did not restore prior version.' }
    if (-not (Test-Path -LiteralPath (Join-Path $active 'LAST_GOOD.marker'))) { throw 'Rollback lost last-good content.' }

    Write-Host ('BLACKGOLD_TRANSACTION_E2E_PASS active=' + $targetVersion + ' rollback=' + $previousVersion)
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
