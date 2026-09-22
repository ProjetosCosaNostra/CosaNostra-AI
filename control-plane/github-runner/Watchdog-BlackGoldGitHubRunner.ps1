$ErrorActionPreference = 'SilentlyContinue'

$RunnerRoot = 'E:\\BlackGold_GitHub_Runner'
$TaskName = 'BlackGold-GitHubRunner'
$StartScript = Join-Path $RunnerRoot 'Start-BlackGoldGitHubRunner.ps1'
$LogRoot = Join-Path $RunnerRoot '_blackgold_logs'
$LogPath = Join-Path $LogRoot 'runner-watchdog.log'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-Watchdog([string]$Message) {
    try {
        Add-Content -LiteralPath $LogPath -Value ('[' + (Get-Date).ToString('s') + '] ' + $Message) -Encoding UTF8
    } catch {}
}

$listener = Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    Write-Watchdog ('healthy listener_pid=' + $listener.Id)
    exit 0
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        Write-Watchdog 'listener missing; startup task triggered'
        exit 0
    } catch {
        Write-Watchdog ('startup task trigger failed=' + $_.Exception.Message)
    }
}

if (Test-Path -LiteralPath $StartScript) {
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
            '-File',('"' + $StartScript + '"')
        ) -WindowStyle Hidden
        Write-Watchdog 'listener missing; supervisor spawned directly'
        exit 0
    } catch {
        Write-Watchdog ('direct supervisor spawn failed=' + $_.Exception.Message)
    }
}

Write-Watchdog 'repair unavailable'
exit 1
