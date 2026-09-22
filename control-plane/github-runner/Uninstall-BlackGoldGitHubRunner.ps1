$ErrorActionPreference = 'Stop'

$RunnerRoot = 'E:\BlackGold_GitHub_Runner'
$StatePath = Join-Path $RunnerRoot 'BLACKGOLD_RUNNER_STATE.json'
$TaskName = 'BlackGold-GitHubRunner'
$ConfigCmd = Join-Path $RunnerRoot 'config.cmd'

$state = $null
if (Test-Path -LiteralPath $StatePath) {
    try { $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if ($state -and $state.control_repository -and (Test-Path -LiteralPath $ConfigCmd) -and (Test-Path -LiteralPath (Join-Path $RunnerRoot '.runner'))) {
    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($gh) {
        try {
            $json = & $gh.Source api --method POST ('repos/' + [string]$state.control_repository + '/actions/runners/remove-token') 2>$null
            if ($LASTEXITCODE -eq 0 -and $json) {
                $token = [string](($json | ConvertFrom-Json).token)
                if ($token) {
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $env:ComSpec
                    $psi.Arguments = '/d /s /c ""' + $ConfigCmd + '" remove --token "' + $token + '""'
                    $psi.WorkingDirectory = $RunnerRoot
                    $psi.UseShellExecute = $false
                    $psi.CreateNoWindow = $true
                    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                    $p = [System.Diagnostics.Process]::Start($psi)
                    $p.WaitForExit()
                    $token = $null
                }
            }
        } catch {}
    }
}

Write-Output 'BLACKGOLD_GITHUB_RUNNER_STARTUP_REMOVED'
Write-Output ('RunnerRootPreserved=' + $RunnerRoot)
