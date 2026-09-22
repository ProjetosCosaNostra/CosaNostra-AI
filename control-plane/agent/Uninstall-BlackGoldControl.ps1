$ErrorActionPreference = 'SilentlyContinue'
$TaskName = 'BlackGold-ControlPlane'
$UpdateTaskName = 'BlackGold-ControlPlane-Update'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'BlackGold-ControlPlane'
$UpdateRunValue = 'BlackGold-ControlPlane-Update'

foreach ($name in @($TaskName,$UpdateTaskName)) {
    Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}

Remove-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $RunKey -Name $UpdateRunValue -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $null, 'User')

Write-Output 'BlackGold Control Plane startup and updater removed. Local files were preserved.'
