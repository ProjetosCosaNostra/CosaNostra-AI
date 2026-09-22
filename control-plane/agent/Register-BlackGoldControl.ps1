$ErrorActionPreference = 'Stop'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$AgentPath = Join-Path $InstallRoot 'agent\BlackGold.Control.ps1'
$TaskName = 'BlackGold-ControlPlane'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'BlackGold-ControlPlane'
$AgentArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $AgentPath + '"'

if (-not (Test-Path -LiteralPath $AgentPath)) { throw "Agent not found: $AgentPath" }
Unblock-File -LiteralPath $AgentPath -ErrorAction SilentlyContinue

$registered = $false

try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $AgentArgs
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    $registered = $true
    Write-Output "BlackGold Control Plane startup: ScheduledTask/$TaskName"
}
catch {
    New-Item -Path $RunKey -Force | Out-Null
    Set-ItemProperty -Path $RunKey -Name $RunValue -Value ('powershell.exe ' + $AgentArgs) -Force
    Start-Process -FilePath 'powershell.exe' -ArgumentList $AgentArgs -WindowStyle Hidden
    $registered = $true
    Write-Output "BlackGold Control Plane startup: HKCU/Run"
}

if (-not $registered) { throw 'BlackGold Control Plane could not be registered.' }
