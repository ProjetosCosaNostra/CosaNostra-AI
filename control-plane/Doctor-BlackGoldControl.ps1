$ErrorActionPreference = 'SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'BlackGold'
$InstallRoot = Join-Path $Root 'ControlPlane'
$PreviousRoot = Join-Path $Root 'ControlPlane.__previous'
$StatusPath = Join-Path $InstallRoot 'Status-BlackGoldControl.ps1'
$RepairPath = Join-Path $InstallRoot 'Repair-BlackGoldControl.ps1'
$RollbackPath = Join-Path $InstallRoot 'Rollback-BlackGoldControl.ps1'

Start-Sleep -Seconds 5

function Invoke-BGScriptJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $output = & ([ScriptBlock]::Create($source)) | Out-String
        return $output | ConvertFrom-Json
    } catch { return $null }
}

function Invoke-BGScript([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        & ([ScriptBlock]::Create($source)) | Out-Null
        return $true
    } catch { return $false }
}

$state = Invoke-BGScriptJson $StatusPath
$needsRepair = $false
$localFailure = $false
$reasons = New-Object System.Collections.Generic.List[string]

if (-not $state) {
    $needsRepair = $true
    $localFailure = $true
    $reasons.Add('status_unavailable')
} else {
    if (-not $state.ready) {
        $needsRepair = $true
        $localFailure = $true
        $reasons.Add('not_ready')
    }
    if (-not $state.agent_running) {
        $needsRepair = $true
        $localFailure = $true
        $reasons.Add('agent_not_running')
    }
    if ($state.startup -eq 'none') {
        $needsRepair = $true
        $localFailure = $true
        $reasons.Add('startup_missing')
    }
    if ($state.update_required) {
        $needsRepair = $true
        $reasons.Add('update_required')
    }
    if ($state.transaction_state -in @('failed','rollback_failed_after_activation_failure')) {
        $needsRepair = $true
        $localFailure = $true
        $reasons.Add('transaction_failed')
    }
    if (-not $state.integrity_verified) {
        $needsRepair = $true
        $localFailure = $true
        $reasons.Add('integrity_unverified')
    }
    if ($state.stable_commit -and $state.installed_commit -and (-not $state.commit_match)) {
        $needsRepair = $true
        $reasons.Add('commit_drift')
    }
}

if (-not $needsRepair) {
    Write-Output ('BLACKGOLD_DOCTOR_OK version=' + [string]$state.version)
    exit 0
}

Write-Output ('BLACKGOLD_DOCTOR_ACTION reasons=' + ($reasons -join ','))

if ($localFailure -and (Test-Path -LiteralPath $PreviousRoot) -and (Test-Path -LiteralPath $RollbackPath)) {
    if (Invoke-BGScript $RollbackPath) {
        Start-Sleep -Seconds 2
        $afterRollback = Invoke-BGScriptJson (Join-Path $InstallRoot 'Status-BlackGoldControl.ps1')
        if ($afterRollback -and $afterRollback.ready -and $afterRollback.agent_running) {
            Write-Output ('BLACKGOLD_DOCTOR_ROLLBACK_OK version=' + [string]$afterRollback.version)
            exit 0
        }
    }
}

$activeRepair = Join-Path $InstallRoot 'Repair-BlackGoldControl.ps1'
if (Test-Path -LiteralPath $activeRepair) {
    if (Invoke-BGScript $activeRepair) {
        Write-Output 'BLACKGOLD_DOCTOR_REPAIR_TRIGGERED'
        exit 0
    }
}

$url = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/control-plane-stable/control-plane/install.ps1'
try {
    $remote = (Invoke-WebRequest -UseBasicParsing -Uri ($url + '?doctor=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content
    & ([ScriptBlock]::Create($remote))
    Write-Output 'BLACKGOLD_DOCTOR_REMOTE_REPAIR_TRIGGERED'
} catch {
    Write-Output ('BLACKGOLD_DOCTOR_FAILED ' + $_.Exception.Message)
    exit 1
}
