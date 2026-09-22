$ErrorActionPreference = 'SilentlyContinue'

$RunnerRoot = 'E:\\BlackGold_GitHub_Runner'
$RunCmd = Join-Path $RunnerRoot 'run.cmd'
$LogRoot = Join-Path $RunnerRoot '_blackgold_logs'
$LogPath = Join-Path $LogRoot 'runner-supervisor.log'
$RetrySeconds = 10

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-BGRunnerLog([string]$Message) {
    try {
        Add-Content -LiteralPath $LogPath -Value ('[' + (Get-Date).ToString('s') + '] ' + $Message) -Encoding UTF8
    } catch {}
}

if (-not (Test-Path -LiteralPath $RunCmd)) {
    Write-BGRunnerLog 'run.cmd not found'
    exit 2
}

Write-BGRunnerLog 'runner persistent supervisor start'

while ($true) {
    try {
        $listener = Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) {
            Start-Sleep -Seconds 10
            continue
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $env:ComSpec
        $psi.Arguments = '/d /s /c ""' + $RunCmd + '""'
        $psi.WorkingDirectory = $RunnerRoot
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi

        if (-not $p.Start()) {
            Write-BGRunnerLog 'failed to start run.cmd'
            Start-Sleep -Seconds $RetrySeconds
            continue
        }

        Write-BGRunnerLog ('runner child started pid=' + $p.Id)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()

        try { $stdout = $outTask.GetAwaiter().GetResult() } catch { $stdout = '' }
        try { $stderr = $errTask.GetAwaiter().GetResult() } catch { $stderr = '' }

        if ($stdout) { Add-Content -LiteralPath $LogPath -Value $stdout -Encoding UTF8 }
        if ($stderr) { Add-Content -LiteralPath $LogPath -Value $stderr -Encoding UTF8 }

        Write-BGRunnerLog ('runner child exited code=' + $p.ExitCode + '; restarting')
    }
    catch {
        Write-BGRunnerLog ('supervisor exception=' + $_.Exception.Message)
    }

    Start-Sleep -Seconds $RetrySeconds
}
