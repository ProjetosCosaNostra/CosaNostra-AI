$ErrorActionPreference = 'SilentlyContinue'
$TaskNames = @(
  'BlackGold-ControlPlane',
  'BlackGold-ControlPlane-Update',
  'BlackGold-ControlPlane-Doctor',
  'BlackGold-GitHubRunner-Doctor'
)
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunValues = @(
  'BlackGold-ControlPlane',
  'BlackGold-ControlPlane-Update',
  'BlackGold-ControlPlane-Doctor',
  'BlackGold-GitHubRunner-Doctor'
)

foreach ($name in $TaskNames) {
    Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}

foreach ($name in $RunValues) {
    Remove-ItemProperty -Path $RunKey -Name $name -ErrorAction SilentlyContinue
}

[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $null, 'User')
Write-Output 'BlackGold Control Plane startup, updater and doctor removed. Local files were preserved.'
