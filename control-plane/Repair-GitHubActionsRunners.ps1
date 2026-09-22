[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Results = New-Object System.Collections.Generic.List[object]

function Get-BGRunnerRoots {
    $found = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    function Add-BGRunnerRoot([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return }
        if ($seen.ContainsKey($full)) { return }

        $config = Join-Path $full '.runner'
        $listener = Join-Path $full 'bin\Runner.Listener.exe'
        if ((Test-Path -LiteralPath $config) -and (Test-Path -LiteralPath $listener)) {
            $seen[$full] = $true
            $found.Add($full)
        }
    }

    $localBase = Join-Path $env:LOCALAPPDATA 'GitHubActionsRunner'
    if (Test-Path -LiteralPath $localBase) {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue(@($localBase,0))
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $dir = [string]$item[0]
            $depth = [int]$item[1]
            Add-BGRunnerRoot $dir
            if ($depth -ge 3) { continue }

            Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $queue.Enqueue(@($_.FullName,$depth + 1))
            }
        }
    }

    if (Test-Path -LiteralPath $env:USERPROFILE) {
        Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'actions-runner*' } |
            ForEach-Object { Add-BGRunnerRoot $_.FullName }
    }

    if (Test-Path -LiteralPath 'C:\') {
        Get-ChildItem -LiteralPath 'C:\' -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'actions-runner*' } |
            ForEach-Object { Add-BGRunnerRoot $_.FullName }
    }

    return @($found)
}

function Get-BGShortHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return (($hash[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-BGListenerActive([string]$Listener) {
    $target = [System.IO.Path]::GetFullPath($Listener)
    $proc = Get-CimInstance Win32_Process -Filter "Name = 'Runner.Listener.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            ([System.IO.Path]::GetFullPath([string]$_.ExecutablePath) -eq $target)
        } |
        Select-Object -First 1
    return $proc
}

function Write-BGSupervisor([string]$Root,[string]$Id) {
    $path = Join-Path $Root 'Run-BlackGoldRunnerSupervisor.ps1'
    $mutexName = 'Local\BlackGold-GitHubRunner-' + $Id

    $body = @"
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$env:RUNNER_TRACKING_ID = ''

`$root = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$listener = Join-Path `$root 'bin\Runner.Listener.exe'
`$disabled = Join-Path `$root 'blackgold-runner.disabled'
`$log = Join-Path `$root 'blackgold-runner-supervisor.log'

`$createdNew = `$false
`$mutex = New-Object System.Threading.Mutex(`$true, '$mutexName', [ref]`$createdNew)
if (-not `$createdNew) { exit 0 }

function Write-BGRunnerLog([string]`$Message) {
    Add-Content -LiteralPath `$log -Value ('[' + (Get-Date -Format o) + '] ' + `$Message) -Encoding UTF8
}

try {
    while (-not (Test-Path -LiteralPath `$disabled)) {
        if (-not (Test-Path -LiteralPath `$listener)) {
            Write-BGRunnerLog ('listener missing: ' + `$listener)
            Start-Sleep -Seconds 30
            continue
        }

        `$target = [System.IO.Path]::GetFullPath(`$listener)
        `$existing = Get-CimInstance Win32_Process -Filter "Name = 'Runner.Listener.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                `$_.ExecutablePath -and
                ([System.IO.Path]::GetFullPath([string]`$_.ExecutablePath) -eq `$target)
            } |
            Select-Object -First 1

        if (`$existing) {
            Write-BGRunnerLog ('listener active pid=' + [string]`$existing.ProcessId + '; waiting')
            Start-Sleep -Seconds 10
            continue
        }

        Write-BGRunnerLog 'starting Runner.Listener.exe run'
        Push-Location `$root
        try {
            & `$listener run
            `$code = `$LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        Write-BGRunnerLog ('listener exit=' + [string]`$code)
        switch (`$code) {
            2 { Start-Sleep -Seconds 5 }
            3 { Start-Sleep -Seconds 5 }
            4 { Start-Sleep -Seconds 5 }
            5 { Start-Sleep -Seconds 15 }
            7 { Start-Sleep -Seconds 60 }
            default { Start-Sleep -Seconds 15 }
        }
    }
}
finally {
    try { `$mutex.ReleaseMutex() } catch {}
    `$mutex.Dispose()
}
"@

    $body | Set-Content -LiteralPath $path -Encoding UTF8
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw ('RUNNER_SUPERVISOR_PARSE_FAILED: ' + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }

    return $path
}

$roots = @(Get-BGRunnerRoots)

foreach ($root in $roots) {
    try {
        $id = Get-BGShortHash $root
        $listener = Join-Path $root 'bin\Runner.Listener.exe'
        $supervisor = Write-BGSupervisor -Root $root -Id $id
        $taskName = 'BlackGold-GitHubRunner-' + $id
        $runValue = $taskName
        $arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $supervisor + '"'

        Import-Module ScheduledTasks -ErrorAction Stop
        $action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments -WorkingDirectory $root
        $triggers = @(
            (New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)),
            (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650))
        )
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null

        New-Item -Path $RunKey -Force | Out-Null
        $runCommand = '"' + $PowerShell + '" ' + $arguments
        Set-ItemProperty -Path $RunKey -Name $runValue -Value $runCommand -Force

        $env:RUNNER_TRACKING_ID = ''
        Start-Process -FilePath $PowerShell -ArgumentList @(
            '-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden',
            '-ExecutionPolicy','Bypass','-File',('"' + $supervisor + '"')
        ) -WindowStyle Hidden | Out-Null

        $active = Test-BGListenerActive $listener
        $Results.Add([pscustomobject]@{
            root = $root
            task = $taskName
            configured = $true
            listener_active = [bool]$active
            listener_pid = if ($active) { [int]$active.ProcessId } else { $null }
            supervisor = $supervisor
            status = 'READY'
        })
    }
    catch {
        $Results.Add([pscustomobject]@{
            root = $root
            configured = $true
            listener_active = $false
            status = 'ERROR'
            error = $_.Exception.Message
        })
    }
}

[ordered]@{
    schema = 1
    configured_runner_count = $roots.Count
    ready_count = @($Results | Where-Object { $_.status -eq 'READY' }).Count
    error_count = @($Results | Where-Object { $_.status -eq 'ERROR' }).Count
    runners = @($Results)
    timestamp = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 6
