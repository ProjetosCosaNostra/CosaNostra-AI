$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$StatusPath = Join-Path $InstallRoot 'Status-BlackGoldControl.ps1'
$RepairPath = Join-Path $InstallRoot 'Repair-BlackGoldControl.ps1'

Start-Sleep -Seconds 5

function Invoke-BGScriptJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $output = & ([ScriptBlock]::Create($source)) | Out-String
        return $output | ConvertFrom-Json
    } catch { return $null }
}

$state = Invoke-BGScriptJson $StatusPath
$needsRepair = $false
$reasons = New-Object System.Collections.Generic.List[string]

if (-not $state) {
    $needsRepair = $true
    $reasons.Add('status_unavailable')
} else {
    if (-not $state.ready) {
        $needsRepair = $true
        $reasons.Add('not_ready')
    }
    if (-not $state.agent_running) {
        $needsRepair = $true
        $reasons.Add('agent_not_running')
    }
    if ($state.update_required) {
        $needsRepair = $true
        $reasons.Add('update_required')
    }
    if ($state.startup -eq 'none') {
        $needsRepair = $true
        $reasons.Add('startup_missing')
    }
}

if ($needsRepair) {
    Write-Output ('BLACKGOLD_DOCTOR_REPAIR reasons=' + ($reasons -join ','))
    if (Test-Path -LiteralPath $RepairPath) {
        $repairSource = Get-Content -LiteralPath $RepairPath -Raw -Encoding UTF8
        & ([ScriptBlock]::Create($repairSource))
    } else {
        $url = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/control-plane-stable/control-plane/install.ps1'
        $remote = (Invoke-WebRequest -UseBasicParsing -Uri ($url + '?doctor=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content
        & ([ScriptBlock]::Create($remote))
    }
} else {
    Write-Output ('BLACKGOLD_DOCTOR_OK version=' + [string]$state.version)
}
