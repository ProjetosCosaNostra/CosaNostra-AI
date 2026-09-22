$ErrorActionPreference = 'SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'BlackGold'
$InstallRoot = Join-Path $Root 'ControlPlane'
$PreviousRoot = Join-Path $Root 'ControlPlane.__previous'
$StageRoot = Join-Path $Root 'ControlPlane.__staging'
$TransactionPath = Join-Path $Root 'ControlPlane.transaction.json'

$AgentPath = Join-Path $InstallRoot 'agent\BlackGold.Control.ps1'
$ManifestPath = Join-Path $InstallRoot 'manifest.json'
$LogPath = Join-Path $InstallRoot 'logs\control-plane.log'

$TaskName = 'BlackGold-ControlPlane'
$UpdateTaskName = 'BlackGold-ControlPlane-Update'
$DoctorTaskName = 'BlackGold-ControlPlane-Doctor'

$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValueName = 'BlackGold-ControlPlane'
$UpdateRunValueName = 'BlackGold-ControlPlane-Update'
$DoctorRunValueName = 'BlackGold-ControlPlane-Doctor'

$StableRef = 'control-plane-stable'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/' + $StableRef + '/control-plane'

$manifest = $null
if (Test-Path -LiteralPath $ManifestPath) {
    try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json } catch {}
}

$previousManifest = $null
$previousManifestPath = Join-Path $PreviousRoot 'manifest.json'
if (Test-Path -LiteralPath $previousManifestPath) {
    try { $previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json } catch {}
}

$transaction = $null
if (Test-Path -LiteralPath $TransactionPath) {
    try { $transaction = Get-Content -LiteralPath $TransactionPath -Raw | ConvertFrom-Json } catch {}
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$updateTask = Get-ScheduledTask -TaskName $UpdateTaskName -ErrorAction SilentlyContinue
$doctorTask = Get-ScheduledTask -TaskName $DoctorTaskName -ErrorAction SilentlyContinue

$runValue = Get-ItemPropertyValue -Path $RunKey -Name $RunValueName -ErrorAction SilentlyContinue
$updateRunValue = Get-ItemPropertyValue -Path $RunKey -Name $UpdateRunValueName -ErrorAction SilentlyContinue
$doctorRunValue = Get-ItemPropertyValue -Path $RunKey -Name $DoctorRunValueName -ErrorAction SilentlyContinue

$agentProcess = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*BlackGold.Control.ps1*' } |
    Select-Object -First 1

function Resolve-Startup($Task,$RunValue) {
    if ($Task) { return 'ScheduledTask' }
    if ($RunValue) { return 'HKCU/Run' }
    return 'none'
}

$startup = Resolve-Startup $task $runValue
$updateStartup = Resolve-Startup $updateTask $updateRunValue
$doctorStartup = Resolve-Startup $doctorTask $doctorRunValue

$remoteVersion = 'unknown'
try {
    $nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $latest = Invoke-RestMethod -UseBasicParsing -Uri ($Base + '/LATEST.json?t=' + $nonce)
    $remoteVersion = [string]$latest.version
} catch {}

$localVersion = if ($manifest) { [string]$manifest.version } else { 'unknown' }
$previousVersion = if ($previousManifest) { [string]$previousManifest.version } else { 'none' }

$latestLog = ''
$recentCmdOrigins = @()
if (Test-Path -LiteralPath $LogPath) {
    $lines = Get-Content -LiteralPath $LogPath -Tail 30 -ErrorAction SilentlyContinue
    if ($lines) { $latestLog = [string]$lines[-1] }
    $recentCmdOrigins = @($lines | Where-Object { $_ -like '*hidden-cmd*' } | Select-Object -Last 5)
}

$transactionState = if ($transaction) { [string]$transaction.state } else { 'none' }
$transactionMessage = if ($transaction) { [string]$transaction.message } else { '' }
$transactionTimestamp = if ($transaction) { [string]$transaction.timestamp } else { '' }

$state = [ordered]@{
    ready = [bool]((Test-Path -LiteralPath $AgentPath) -and $manifest -and ($startup -ne 'none'))
    version = $localVersion
    latest_version = $remoteVersion
    update_required = [bool](($remoteVersion -ne 'unknown') -and ($localVersion -ne $remoteVersion))
    stable_branch = $StableRef
    install_root = $InstallRoot
    startup = $startup
    updater = $updateStartup
    doctor = $doctorStartup
    agent_running = [bool]$agentProcess
    agent_pid = if ($agentProcess) { [int]$agentProcess.ProcessId } else { $null }
    transactional_install = [bool]($manifest -and $manifest.transactional_install)
    rollback_enabled = [bool]($manifest -and $manifest.rollback_enabled)
    previous_available = [bool]$previousManifest
    previous_version = $previousVersion
    staging_present = [bool](Test-Path -LiteralPath $StageRoot)
    transaction_state = $transactionState
    transaction_message = $transactionMessage
    transaction_timestamp = $transactionTimestamp
    latest_log = $latestLog
    recent_cmd_origins = $recentCmdOrigins
}

$state | ConvertTo-Json -Depth 5
