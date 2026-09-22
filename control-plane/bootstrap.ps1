$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'

$files = @(
  'BLACKGOLD_CONTROL_PLANE.md',
  'manifest.json',
  'project-pointer.json',
  'policies/windows.json',
  'agent/BlackGold.Control.ps1',
  'agent/Register-BlackGoldControl.ps1',
  'agent/Uninstall-BlackGoldControl.ps1',
  'Register-BlackGoldProjects.ps1'
)

foreach ($relative in $files) {
    $target = Join-Path $InstallRoot ($relative -replace '/', '\')
    $dir = Split-Path $target -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri ($Base + '/' + $relative) -OutFile $target
}

[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $InstallRoot, 'User')
& (Join-Path $InstallRoot 'agent\Register-BlackGoldControl.ps1')
& (Join-Path $InstallRoot 'Register-BlackGoldProjects.ps1')

Write-Output 'BLACKGOLD_CONTROL_PLANE_READY'
Write-Output ('InstallRoot=' + $InstallRoot)
