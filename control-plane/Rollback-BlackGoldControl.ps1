$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:LOCALAPPDATA 'BlackGold'
$InstallRoot = Join-Path $Root 'ControlPlane'
$PreviousRoot = Join-Path $Root 'ControlPlane.__previous'
$FailedRoot = Join-Path $Root 'ControlPlane.__failed'
$TransactionPath = Join-Path $Root 'ControlPlane.transaction.json'

function Write-BGTransaction([string]$State,[string]$Message) {
    $data = [ordered]@{
        schema = 1
        state = $State
        message = $Message
        timestamp = (Get-Date).ToString('o')
    }
    $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $TransactionPath -Encoding UTF8
}

function Invoke-BGScript([string]$Path) {
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    & ([ScriptBlock]::Create($source))
}

if (-not (Test-Path -LiteralPath $PreviousRoot)) {
    throw 'No previous BlackGold Control Plane slot is available.'
}

$previousManifest = Join-Path $PreviousRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $previousManifest)) {
    throw 'Previous slot does not contain manifest.json.'
}

$previous = Get-Content -LiteralPath $previousManifest -Raw -Encoding UTF8 | ConvertFrom-Json
Write-BGTransaction 'rollback_started' ('target=' + [string]$previous.version)

foreach ($taskName in @('BlackGold-ControlPlane','BlackGold-ControlPlane-Update','BlackGold-ControlPlane-Doctor','BlackGold-GitHubRunner-Doctor')) {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*BlackGold.Control.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if (Test-Path -LiteralPath $FailedRoot) {
    Remove-Item -LiteralPath $FailedRoot -Recurse -Force
}

if (Test-Path -LiteralPath $InstallRoot) {
    Move-Item -LiteralPath $InstallRoot -Destination $FailedRoot
}

try {
    Move-Item -LiteralPath $PreviousRoot -Destination $InstallRoot

    [Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $InstallRoot, 'User')

    Invoke-BGScript (Join-Path $InstallRoot 'agent\Register-BlackGoldControl.ps1')
    Invoke-BGScript (Join-Path $InstallRoot 'Register-BlackGoldProjects.ps1')

    $activeManifest = Get-Content -LiteralPath (Join-Path $InstallRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-BGTransaction 'rollback_committed' ('active=' + [string]$activeManifest.version)
    Write-Output ('BLACKGOLD_ROLLBACK_OK version=' + [string]$activeManifest.version)
}
catch {
    if (Test-Path -LiteralPath $InstallRoot) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $FailedRoot) {
        Move-Item -LiteralPath $FailedRoot -Destination $InstallRoot -ErrorAction SilentlyContinue
    }
    Write-BGTransaction 'rollback_failed' $_.Exception.Message
    throw
}
