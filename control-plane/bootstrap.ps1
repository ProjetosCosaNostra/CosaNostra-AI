$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'

function Invoke-BGLocalScript {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "BlackGold script not found: $Path" }
    Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    & ([ScriptBlock]::Create($source))
}

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

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

foreach ($relative in $files) {
    $target = Join-Path $InstallRoot ($relative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri ($Base + '/' + $relative) -OutFile $target
    Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
}

[Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $InstallRoot, 'User')

Invoke-BGLocalScript (Join-Path $InstallRoot 'agent\Register-BlackGoldControl.ps1')
Invoke-BGLocalScript (Join-Path $InstallRoot 'Register-BlackGoldProjects.ps1')

$task = Get-ScheduledTask -TaskName 'BlackGold-ControlPlane' -ErrorAction SilentlyContinue
$runValue = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BlackGold-ControlPlane' -ErrorAction SilentlyContinue

if (-not $task -and -not $runValue) {
    throw 'BlackGold Control Plane startup was not registered.'
}

Write-Output 'BLACKGOLD_CONTROL_PLANE_READY'
Write-Output ('InstallRoot=' + $InstallRoot)
if ($task) { Write-Output ('Startup=ScheduledTask/' + $task.TaskName) }
elseif ($runValue) { Write-Output 'Startup=HKCU/Run' }
