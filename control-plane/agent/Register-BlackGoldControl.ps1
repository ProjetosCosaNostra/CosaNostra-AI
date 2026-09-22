$ErrorActionPreference = 'Stop'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$AgentPath = Join-Path $InstallRoot 'agent\BlackGold.Control.ps1'
$UpdatePath = Join-Path $InstallRoot 'Update-BlackGoldControl.ps1'
$TaskName = 'BlackGold-ControlPlane'
$UpdateTaskName = 'BlackGold-ControlPlane-Update'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'BlackGold-ControlPlane'
$UpdateRunValue = 'BlackGold-ControlPlane-Update'
$AgentArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $AgentPath + '"'
$UpdateArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $UpdatePath + '"'

if (-not (Test-Path -LiteralPath $AgentPath)) { throw "Agent not found: $AgentPath" }
if (-not (Test-Path -LiteralPath $UpdatePath)) { throw "Updater not found: $UpdatePath" }

Unblock-File -LiteralPath $AgentPath -ErrorAction SilentlyContinue
Unblock-File -LiteralPath $UpdatePath -ErrorAction SilentlyContinue

$registered = $false

try {
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    $agentAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $AgentArgs
    $agentTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $agentSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $agentAction -Trigger $agentTrigger -Settings $agentSettings -Principal $principal -Force | Out-Null

    $updateAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $UpdateArgs
    $updateTriggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
        (New-ScheduledTaskTrigger -Daily -At 12:00)
    )
    $updateSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $UpdateTaskName -Action $updateAction -Trigger $updateTriggers -Settings $updateSettings -Principal $principal -Force | Out-Null

    Remove-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $RunKey -Name $UpdateRunValue -ErrorAction SilentlyContinue

    Start-ScheduledTask -TaskName $TaskName
    $registered = $true
    Write-Output "BlackGold Control Plane startup: ScheduledTask/$TaskName"
    Write-Output "BlackGold Control Plane updater: ScheduledTask/$UpdateTaskName"
}
catch {
    New-Item -Path $RunKey -Force | Out-Null
    Set-ItemProperty -Path $RunKey -Name $RunValue -Value ('powershell.exe ' + $AgentArgs) -Force
    Set-ItemProperty -Path $RunKey -Name $UpdateRunValue -Value ('powershell.exe ' + $UpdateArgs) -Force
    Start-Process -FilePath 'powershell.exe' -ArgumentList $AgentArgs -WindowStyle Hidden
    Start-Process -FilePath 'powershell.exe' -ArgumentList $UpdateArgs -WindowStyle Hidden
    $registered = $true
    Write-Output "BlackGold Control Plane startup: HKCU/Run"
    Write-Output "BlackGold Control Plane updater: HKCU/Run"
}

if (-not $registered) { throw 'BlackGold Control Plane could not be registered.' }
