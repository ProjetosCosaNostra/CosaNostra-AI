$ErrorActionPreference = 'SilentlyContinue'
$TaskName = 'BlackGold-ControlPlane'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValue = 'BlackGold-ControlPlane'

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $RunKey -Name $RunValue -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $null, 'User')

Write-Output 'BlackGold Control Plane startup removed. Local files were preserved.'
