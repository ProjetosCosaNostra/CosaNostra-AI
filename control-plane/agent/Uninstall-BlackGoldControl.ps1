$ErrorActionPreference = 'SilentlyContinue'
$TaskName = 'BlackGold-ControlPlane'
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $null, 'User')
Write-Output 'BlackGold Control Plane task removed. Local files were preserved.'
