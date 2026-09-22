$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ControlPlane = Join-Path $RepoRoot 'control-plane'

$manifest = Get-Content (Join-Path $ControlPlane 'manifest.json') -Raw | ConvertFrom-Json
$latest = Get-Content (Join-Path $ControlPlane 'LATEST.json') -Raw | ConvertFrom-Json
$truth = Get-Content (Join-Path $ControlPlane 'CURRENT_TRUTH.json') -Raw | ConvertFrom-Json
$registry = Get-Content (Join-Path $ControlPlane 'PROJECT_REGISTRY.json') -Raw | ConvertFrom-Json

if ($manifest.transactional_install -ne $true) { throw 'transactional_install=false' }
if ($manifest.rollback_enabled -ne $true) { throw 'rollback_enabled=false' }

$versions = @(
  [string]$manifest.version,
  [string]$latest.version,
  [string]$truth.version,
  [string]$registry.control_plane_version
)

if (($versions | Select-Object -Unique).Count -ne 1) {
    throw ('Version divergence: ' + ($versions -join ','))
}

$bootstrap = Get-Content (Join-Path $ControlPlane 'bootstrap.ps1') -Raw
$rollback = Get-Content (Join-Path $ControlPlane 'Rollback-BlackGoldControl.ps1') -Raw
$doctor = Get-Content (Join-Path $ControlPlane 'Doctor-BlackGoldControl.ps1') -Raw

$bootstrapTokens = @(
  'ControlPlane.__staging',
  'ControlPlane.__previous',
  'staged_validated',
  'activated_pending_healthcheck',
  'committed',
  'rolled_back_after_failure'
)
foreach ($token in $bootstrapTokens) {
    if ($bootstrap -notmatch [regex]::Escape($token)) {
        throw "bootstrap missing token: $token"
    }
}

foreach ($token in @('rollback_started','rollback_committed','ControlPlane.__failed')) {
    if ($rollback -notmatch [regex]::Escape($token)) {
        throw "rollback missing token: $token"
    }
}

if ($doctor -notmatch 'BLACKGOLD_DOCTOR_ROLLBACK_OK') {
    throw 'Doctor does not verify local rollback success.'
}

$requiredFiles = @(
  'bootstrap.ps1',
  'Rollback-BlackGoldControl.ps1',
  'Status-BlackGoldControl.ps1',
  'Doctor-BlackGoldControl.ps1',
  'agent/Register-BlackGoldControl.ps1'
)

foreach ($relative in $requiredFiles) {
    if (-not (Test-Path (Join-Path $ControlPlane $relative))) {
        throw "Missing transactional component: $relative"
    }
}

Write-Host ('BLACKGOLD_TRANSACTION_MODEL_PASS version=' + [string]$manifest.version)
