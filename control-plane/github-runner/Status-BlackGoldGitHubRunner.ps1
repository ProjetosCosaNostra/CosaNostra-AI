$ErrorActionPreference = 'SilentlyContinue'

$RunnerRoot = 'E:\BlackGold_GitHub_Runner'
$StatePath = Join-Path $RunnerRoot 'BLACKGOLD_RUNNER_STATE.json'
$TaskName = 'BlackGold-GitHubRunner'

$state = $null
if (Test-Path -LiteralPath $StatePath) {
    try { $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$listener = Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue | Select-Object -First 1

$serverStatus = ''
$online = $null
if ($state -and $state.control_repository) {
    try {
        $gh = Get-Command gh.exe -ErrorAction Stop
        $json = & $gh.Source api ('repos/' + [string]$state.control_repository + '/actions/runners?per_page=100') 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            $obj = $json | ConvertFrom-Json
            $server = @($obj.runners | Where-Object { $_.name -eq [string]$state.runner_name } | Select-Object -First 1)
            if ($server) {
                $serverStatus = [string]$server.status
                $online = ($serverStatus -eq 'online')
            }
        }
    } catch {}
}

[ordered]@{
    ready = [bool]((Test-Path -LiteralPath (Join-Path $RunnerRoot '.runner')) -and $task)
    control_repository = if ($state) { [string]$state.control_repository } else { '' }
    runner_name = if ($state) { [string]$state.runner_name } else { 'BlackGold-FELIPE' }
    runner_version = if ($state) { [string]$state.runner_version } else { '' }
    runner_root = $RunnerRoot
    startup = if ($task) { 'ScheduledTask' } else { 'none' }
    listener_running = [bool]$listener
    listener_pid = if ($listener) { [int]$listener.Id } else { $null }
    server_status = $serverStatus
    server_online = $online
    desktop_commander_required = $false
} | ConvertTo-Json -Depth 4
