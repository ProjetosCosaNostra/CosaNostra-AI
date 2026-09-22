$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$PointerSource = Join-Path $InstallRoot 'project-pointer.json'
$AgentsTemplate = Join-Path $InstallRoot 'templates\AGENTS.md'

if (-not (Test-Path -LiteralPath $PointerSource)) { throw 'project-pointer.json not found' }

$skipNames = @('node_modules','.git','.gradle','build','dist','out','.venv','venv','target','bin','obj','AppData')
$markers = @('settings.gradle','settings.gradle.kts','build.gradle','build.gradle.kts','package.json','pubspec.yaml','pyproject.toml','Cargo.toml')

function Test-BGProject([string]$Path) {
    if (Test-Path (Join-Path $Path '.git')) { return $true }
    foreach ($m in $markers) {
        if (Test-Path (Join-Path $Path $m)) { return $true }
    }
    if (Get-ChildItem -Path $Path -Filter '*.sln' -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
        return $true
    }
    return $false
}

function Register-BGProject([string]$Path) {
    $bg = Join-Path $Path '.blackgold'
    New-Item -ItemType Directory -Force -Path $bg | Out-Null

    $pointer = Join-Path $bg 'control-plane.json'
    Copy-Item -LiteralPath $PointerSource -Destination $pointer -Force

    $agents = Join-Path $Path 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $agents)) {
        if (Test-Path -LiteralPath $AgentsTemplate) {
            Copy-Item -LiteralPath $AgentsTemplate -Destination $agents
        }
    }
}

$queue = New-Object System.Collections.Queue
if (Test-Path 'E:\') { $queue.Enqueue(@('E:\',0)) }

while ($queue.Count -gt 0) {
    $item = $queue.Dequeue()
    $path = [string]$item[0]
    $depth = [int]$item[1]

    if ($depth -gt 0 -and (Test-BGProject $path)) {
        Register-BGProject $path
    }

    if ($depth -ge 4) { continue }

    Get-ChildItem -Path $path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($skipNames -notcontains $_.Name) {
            $queue.Enqueue(@($_.FullName,$depth + 1))
        }
    }
}

if (Test-Path 'E:\') {
@'
# BlackGold Control Plane

Canonical source:
https://github.com/ProjetosCosaNostra/CosaNostra-AI/tree/main/control-plane

Agent entrypoint:
https://github.com/ProjetosCosaNostra/CosaNostra-AI/blob/main/control-plane/AGENT_ENTRYPOINT.md

Current truth:
https://github.com/ProjetosCosaNostra/CosaNostra-AI/blob/main/control-plane/CURRENT_TRUTH.json

Global execution rule:
Never open visible CMD windows for automation. Preserve required subprocesses and hide the visible window instead.

Local install:
%LOCALAPPDATA%\BlackGold\ControlPlane
'@ | Set-Content -Path 'E:\BLACKGOLD_SYSTEM.md' -Encoding UTF8
}
