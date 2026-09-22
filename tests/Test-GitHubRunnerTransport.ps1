$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$pkg = Join-Path $root 'control-plane\github-runner'

$required = @(
  'README.md',
  'defaults.json',
  'Install-BlackGoldGitHubRunner.ps1',
  'Start-BlackGoldGitHubRunner.ps1',
  'Watchdog-BlackGoldGitHubRunner.ps1',
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
foreach ($requiredOp in @('status','git_status','git_sync','gradle','adb_devices','adb_install','adb_launch','adb_launch_package','emulator_start','logcat_tail')) {
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


$bootstrap = Get-Content -LiteralPath (Join-Path $root 'control-plane\bootstrap.ps1') -Raw
foreach ($token in @(
  'github-runner/README.md',
  'github-runner/defaults.json',
  'github-runner/Install-BlackGoldGitHubRunner.ps1',
  'github-runner/Status-BlackGoldGitHubRunner.ps1',
  'github-runner/job.schema.json'
)) {
  if ($bootstrap -notmatch [regex]::Escape($token)) {
    throw ('Bootstrap runner package invariant missing: ' + $token)
  }
}

$install = Get-Content -LiteralPath (Join-Path $root 'control-plane\install.ps1') -Raw
foreach ($token in @(
  'Install-BlackGoldGitHubRunner.ps1',
  'BLACKGOLD_GITHUB_RUNNER_PENDING',
  'NonInteractive'
)) {
  if ($install -notmatch [regex]::Escape($token)) {
    throw ('Permanent installer runner integration missing: ' + $token)
  }
}

$status = Get-Content -LiteralPath (Join-Path $root 'control-plane\Status-BlackGoldControl.ps1') -Raw
foreach ($token in @('github_runner','remote_execution_ready','desktop_commander_required')) {
  if ($status -notmatch [regex]::Escape($token)) {
    throw ('Control Plane status runner integration missing: ' + $token)
  }
}

$runnerInstaller = Get-Content -LiteralPath (Join-Path $pkg 'Install-BlackGoldGitHubRunner.ps1') -Raw
if ($runnerInstaller -notmatch [regex]::Escape('[switch]$NonInteractive')) {
  throw 'Runner installer must support non-interactive background mode.'
}


foreach ($token in @(
  'Assert-Serial',
  'Invalid emulator port.',
  'wait_boot_sec',
  'android.intent.category.LAUNCHER',
  'Target serial is occupied by another AVD.',
  'AVD identity mismatch.'
)) {
  if ($executor -notmatch [regex]::Escape($token)) {
    throw ('Runner Android targeting invariant missing: ' + $token)
  }
}


foreach ($token in @(
  'Try-GhAuthFromGitCredential',
  'credential fill',
  '--with-token',
  'GCM_INTERACTIVE'
)) {
  if ($runnerInstaller -notmatch [regex]::Escape($token)) {
    throw ('Runner credential-recovery invariant missing: ' + $token)
  }
}

$doctor = Get-Content -LiteralPath (Join-Path $root 'control-plane\Doctor-BlackGoldControl.ps1') -Raw
foreach ($token in @(
  'Install-BlackGoldGitHubRunner.ps1',
  '-NonInteractive',
  'BLACKGOLD_DOCTOR_RUNNER_READY',
  'BLACKGOLD_DOCTOR_RUNNER_PENDING'
)) {
  if ($doctor -notmatch [regex]::Escape($token)) {
    throw ('Doctor runner self-heal invariant missing: ' + $token)
  }
}

$updater = Get-Content -LiteralPath (Join-Path $root 'control-plane\Update-BlackGoldControl.ps1') -Raw
foreach ($token in @('function Invoke-BGDoctor','Doctor-BlackGoldControl.ps1','Invoke-BGDoctor')) {
  if ($updater -notmatch [regex]::Escape($token)) {
    throw ('Updater Doctor chaining invariant missing: ' + $token)
  }
}


$supervisor = Get-Content -LiteralPath (Join-Path $pkg 'Start-BlackGoldGitHubRunner.ps1') -Raw
foreach ($token in @('while ($true)','runner child exited code=','Start-Sleep -Seconds $RetrySeconds')) {
  if ($supervisor -notmatch [regex]::Escape($token)) {
    throw ('Persistent runner supervisor invariant missing: ' + $token)
  }
}

$watchdog = Get-Content -LiteralPath (Join-Path $pkg 'Watchdog-BlackGoldGitHubRunner.ps1') -Raw
foreach ($token in @('BlackGold-GitHubRunner','Runner.Listener','Start-ScheduledTask')) {
  if ($watchdog -notmatch [regex]::Escape($token)) {
    throw ('Runner watchdog invariant missing: ' + $token)
  }
}

$launcher = Get-Content -LiteralPath (Join-Path $root 'control-plane\tools\Open-OrcamentoNoPonto.ps1') -Raw
foreach ($token in @('Orcamento_no_Ponto_API35','assembleDebug','install -r','android.intent.category.LAUNCHER','OPEN_ORCAMENTO_NO_PONTO_RECEIPT.json')) {
  if ($launcher -notmatch [regex]::Escape($token)) {
    throw ('Orcamento launcher invariant missing: ' + $token)
  }
}
