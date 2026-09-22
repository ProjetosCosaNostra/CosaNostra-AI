$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$AgentPath = Join-Path $InstallRoot 'agent\BlackGold.Control.ps1'
$ManifestPath = Join-Path $InstallRoot 'manifest.json'
$LogPath = Join-Path $InstallRoot 'logs\control-plane.log'
$TaskName = 'BlackGold-ControlPlane'
$UpdateTaskName = 'BlackGold-ControlPlane-Update'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValueName = 'BlackGold-ControlPlane'
$UpdateRunValueName = 'BlackGold-ControlPlane-Update'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane'

$manifest = $null
if (Test-Path -LiteralPath $ManifestPath) {
    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch {}
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$updateTask = Get-ScheduledTask -TaskName $UpdateTaskName -ErrorAction SilentlyContinue
$runValue = Get-ItemPropertyValue -Path $RunKey -Name $RunValueName -ErrorAction SilentlyContinue
$updateRunValue = Get-ItemPropertyValue -Path $RunKey -Name $UpdateRunValueName -ErrorAction SilentlyContinue

$agentProcess = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*BlackGold.Control.ps1*' } |
    Select-Object -First 1

$startup = 'none'
if ($task) { $startup = 'ScheduledTask' }
elseif ($runValue) { $startup = 'HKCU/Run' }

$updateStartup = 'none'
if ($updateTask) { $updateStartup = 'ScheduledTask' }
elseif ($updateRunValue) { $updateStartup = 'HKCU/Run' }

$remoteVersion = 'unknown'
try {
    $nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $latest = Invoke-RestMethod -UseBasicParsing -Uri ($Base + '/LATEST.json?t=' + $nonce)
    $remoteVersion = [string]$latest.version
} catch {}

$localVersion = if ($manifest) { [string]$manifest.version } else { 'unknown' }

$latestLog = ''
$recentCmdOrigins = @()
if (Test-Path -LiteralPath $LogPath) {
    $lines = Get-Content -LiteralPath $LogPath -Tail 30 -ErrorAction SilentlyContinue
    if ($lines) { $latestLog = [string]$lines[-1] }
    $recentCmdOrigins = @($lines | Where-Object { $_ -like '*hidden-cmd*' } | Select-Object -Last 5)
}

$state = [ordered]@{
    ready = [bool]((Test-Path -LiteralPath $AgentPath) -and ($startup -ne 'none'))
    version = $localVersion
    latest_version = $remoteVersion
    update_required = [bool](($remoteVersion -ne 'unknown') -and ($localVersion -ne $remoteVersion))
    install_root = $InstallRoot
    startup = $startup
    updater = $updateStartup
    agent_running = [bool]$agentProcess
    agent_pid = if ($agentProcess) { [int]$agentProcess.ProcessId } else { $null }
    latest_log = $latestLog
    recent_cmd_origins = $recentCmdOrigins
}

$state | ConvertTo-Json -Depth 4
