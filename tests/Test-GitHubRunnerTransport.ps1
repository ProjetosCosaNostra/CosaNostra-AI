$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$pkg = Join-Path $root 'control-plane\github-runner'

$required = @(
  'README.md',
  'defaults.json',
  'Install-BlackGoldGitHubRunner.ps1',
  'Start-BlackGoldGitHubRunner.ps1',
  'Status-BlackGoldGitHubRunner.ps1',
  'Uninstall-BlackGoldGitHubRunner.ps1',
  'Invoke-BlackGoldRunnerJob.ps1',
  'job.schema.json'
)

foreach ($name in $required) {
    $path = Join-Path $pkg $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw ('Missing GitHub Runner component: ' + $name)
    }
}

$defaults = Get-Content -LiteralPath (Join-Path $pkg 'defaults.json') -Raw | ConvertFrom-Json
$schema = Get-Content -LiteralPath (Join-Path $pkg 'job.schema.json') -Raw | ConvertFrom-Json

if ($defaults.control_marker -ne 'BLACKGOLD_RUNNER_CONTROL.json') {
    throw 'Runner control marker mismatch.'
}
if ($defaults.desktop_commander_required -ne $false) {
    throw 'Desktop Commander must not be required.'
}

$installer = Get-Content -LiteralPath (Join-Path $pkg 'Install-BlackGoldGitHubRunner.ps1') -Raw
foreach ($token in @(
    'BLACKGOLD_RUNNER_CONTROL.json',
    '/actions/runners/registration-token',
    'actions/runner/releases/latest',
    'CreateNoWindow = $true',
    'BLACKGOLD_GITHUB_RUNNER_READY',
    'DesktopCommanderRequired=False'
)) {
    if ($installer -notmatch [regex]::Escape($token)) {
        throw ('Installer invariant missing: ' + $token)
    }
}

if ($installer -match '/orgs/.+/actions/runners/registration-token') {
    throw 'Installer must use repository-scoped runner registration.'
}
if ($installer -match 'BlackVault_Sentinel') {
    throw 'Public installer must not expose the private control repository name.'
}

$executor = Get-Content -LiteralPath (Join-Path $pkg 'Invoke-BlackGoldRunnerJob.ps1') -Raw
foreach ($forbidden in @('Invoke-Expression','script_b64','encodedcommand')) {
    if ($executor -match [regex]::Escape($forbidden)) {
        throw ('Forbidden arbitrary-execution primitive found: ' + $forbidden)
    }
}
if ($executor -notmatch [regex]::Escape("Only E:\ paths are allowed.")) {
    throw 'Executor must enforce E:\ path boundary.'
}

$ops = @($schema.properties.op.enum)
foreach ($requiredOp in @('status','git_status','git_sync','gradle','adb_devices','adb_install','adb_launch','emulator_start','logcat_tail')) {
    if ($ops -notcontains $requiredOp) {
        throw ('Missing controlled operation: ' + $requiredOp)
    }
}

$temp = Join-Path $env:TEMP ('blackgold-runner-status-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    @{
        schema = 1
        request_id = 'ci-status-001'
        op = 'status'
    } | ConvertTo-Json | Set-Content -LiteralPath $temp -Encoding UTF8

    $json = & (Join-Path $pkg 'Invoke-BlackGoldRunnerJob.ps1') -JobFile $temp | Out-String
    $result = $json | ConvertFrom-Json

    if ($result.request_id -ne 'ci-status-001') { throw 'Status job request_id mismatch.' }
    if ($result.op -ne 'status') { throw 'Status job op mismatch.' }
}
finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}

Write-Host 'BLACKGOLD_GITHUB_RUNNER_TRANSPORT_PASS'


$entry = Get-Content -LiteralPath (Join-Path $root 'control-plane\AGENT_ENTRYPOINT.md') -Raw
foreach ($token in @(
  'BLACKGOLD_RUNNER_CONTROL.json',
  'Liste os repositórios acessíveis',
  'Não dependa de code search',
  'BlackGold GitHub Runner Control'
)) {
  if ($entry -notmatch [regex]::Escape($token)) {
    throw ('Runner discovery entrypoint invariant missing: ' + $token)
  }
}
