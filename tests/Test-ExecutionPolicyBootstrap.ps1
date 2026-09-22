$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$installPath = Join-Path $root 'control-plane\install.ps1'
$bootstrapPath = Join-Path $root 'control-plane\bootstrap.ps1'

$install = Get-Content -LiteralPath $installPath -Raw -Encoding UTF8
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8

foreach ($pair in @(
    @{ name='install'; text=$install },
    @{ name='bootstrap'; text=$bootstrap }
)) {
    if ($pair.text -notmatch [regex]::Escape('Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass')) {
        throw ($pair.name + ' must force process-scoped ExecutionPolicy Bypass.')
    }
}

foreach ($token in @(
    'function Invoke-BGLocalScript',
    '[ScriptBlock]::Create($source)',
    'Unblock-File -LiteralPath $Path'
)) {
    if ($bootstrap -notmatch [regex]::Escape($token)) {
        throw ('Bootstrap execution-policy invariant missing: ' + $token)
    }
}

# The bootstrap must not invoke its downloaded registration scripts as local .ps1 files.
foreach ($forbidden in @(
    '& (Join-Path $InstallRoot ''agent\Register-BlackGoldControl.ps1'')',
    '& (Join-Path $InstallRoot ''Register-BlackGoldProjects.ps1'')'
)) {
    if ($bootstrap -match [regex]::Escape($forbidden)) {
        throw ('Direct local script invocation reintroduced: ' + $forbidden)
    }
}

# The permanent installer must execute downloaded bootstrap/runner content as ScriptBlocks.
foreach ($token in @(
    '[ScriptBlock]::Create($bootstrapSource)',
    '[ScriptBlock]::Create($runnerSource)'
)) {
    if ($install -notmatch [regex]::Escape($token)) {
        throw ('Permanent installer ScriptBlock invariant missing: ' + $token)
    }
}

Write-Host 'BLACKGOLD_EXECUTION_POLICY_REGRESSION_PASS'
