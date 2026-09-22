$ErrorActionPreference = 'SilentlyContinue'

$Root = Join-Path $env:LOCALAPPDATA 'BlackGold\Commander'
$StatePath = Join-Path $Root 'state.json'
$HeartbeatPath = Join-Path $Root 'heartbeat.json'
$TaskName = 'BlackGold-Commander'

$state = $null
$heartbeat = $null

if (Test-Path -LiteralPath $StatePath) {
    try { $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

if (Test-Path -LiteralPath $HeartbeatPath) {
    try { $heartbeat = Get-Content -LiteralPath $HeartbeatPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$proc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*BlackGold.Commander.ps1*' } |
    Select-Object -First 1

[ordered]@{
    ready = [bool]($state -and $task)
    task_present = [bool]$task
    task_state = if ($task) { [string]$task.State } else { '' }
    agent_running = [bool]$proc
    agent_pid = if ($proc) { [int]$proc.ProcessId } else { $null }
    root = $Root
    control_repository = if ($state) { [string]$state.control_repository } else { '' }
    queue_path = if ($state) { [string]$state.queue_path } else { '' }
    results_path = if ($state) { [string]$state.results_path } else { '' }
    last_heartbeat = if ($heartbeat) { [string]$heartbeat.timestamp } else { '' }
    last_error = if ($heartbeat) { [string]$heartbeat.last_error } else { '' }
    desktop_commander_required = $false
} | ConvertTo-Json -Depth 5
