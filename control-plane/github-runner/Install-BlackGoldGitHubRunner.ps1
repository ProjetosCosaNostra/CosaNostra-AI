param(
    [string]$Owner = 'ProjetosCosaNostra'
)

$ErrorActionPreference = 'Stop'

$RunnerName = 'BlackGold-FELIPE'
$RunnerRoot = 'E:\BlackGold_GitHub_Runner'
$WorkRoot = 'E:\_blackgold_runner_work'
$TaskName = 'BlackGold-GitHubRunner'
$Labels = 'blackgold,felipe,android'
$ControlMarker = 'BLACKGOLD_RUNNER_CONTROL.json'
$CanonicalBase = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/control-plane-stable/control-plane/github-runner'

function Write-Step([string]$Message) {
    Write-Host ('[BlackGold Runner] ' + $Message)
}

function Get-GhExe {
    $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidate = 'C:\Program Files\GitHub CLI\gh.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }

    return $null
}

function Ensure-Gh {
    $gh = Get-GhExe
    if ($gh) { return $gh }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'GitHub CLI is not installed and winget is unavailable.'
    }

    Write-Step 'Installing GitHub CLI silently.'
    $p = Start-Process -FilePath $winget.Source -ArgumentList @(
        'install','--id','GitHub.cli','-e','--silent',
        '--accept-package-agreements','--accept-source-agreements'
    ) -Wait -PassThru -WindowStyle Hidden

    if ($p.ExitCode -ne 0) {
        throw ('GitHub CLI installation failed with exit code ' + $p.ExitCode)
    }

    $gh = Get-GhExe
    if (-not $gh) { throw 'GitHub CLI installed but gh.exe was not found.' }
    return $gh
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory=$true)][string]$Gh,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Gh
    $psi.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    if (-not $p.Start()) { throw 'Could not start GitHub CLI.' }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        throw ('gh failed: ' + $stderr.Trim())
    }

    return $stdout.Trim()
}

function Invoke-Hidden {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [string]$WorkingDirectory
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    if (-not $p.Start()) { throw ('Could not start ' + $FileName) }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Ensure-GhAuth([string]$Gh) {
    try {
        Invoke-Gh -Gh $Gh -Arguments @('auth','status','--hostname','github.com') | Out-Null
        return
    } catch {}

    Write-Host ''
    Write-Host 'BLACKGOLD_RUNNER_GITHUB_LOGIN'
    Write-Step 'GitHub authentication is required once.'

    & $Gh auth login --web --hostname github.com --git-protocol https --scopes repo
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub login was not completed.'
    }

    Invoke-Gh -Gh $Gh -Arguments @('auth','status','--hostname','github.com') | Out-Null
}

function Find-ControlRepository([string]$Gh) {
    Write-Step ('Discovering private control repository by marker ' + $ControlMarker + '.')

    $reposJson = Invoke-Gh -Gh $Gh -Arguments @(
        'repo','list',$Owner,'--limit','200','--json','nameWithOwner,isPrivate'
    )
    $repos = @($reposJson | ConvertFrom-Json)

    foreach ($repo in @($repos | Where-Object { $_.isPrivate -eq $true })) {
        $full = [string]$repo.nameWithOwner

        try {
            $contentJson = Invoke-Gh -Gh $Gh -Arguments @(
                'api',
                ('repos/' + $full + '/contents/' + $ControlMarker)
            )

            $contentObj = $contentJson | ConvertFrom-Json
            if (-not $contentObj.content) { continue }

            $bytes = [Convert]::FromBase64String(($contentObj.content -replace '\s',''))
            $markerJson = [Text.Encoding]::UTF8.GetString($bytes)
            $marker = $markerJson | ConvertFrom-Json

            if ([string]$marker.system -eq 'BlackGold GitHub Runner Control') {
                return [pscustomobject]@{
                    repository = $full
                    queue_path = [string]$marker.queue_path
                    workflow = [string]$marker.workflow
                }
            }
        } catch {}
    }

    throw ('No accessible private repository contains ' + $ControlMarker + '.')
}

if (-not (Test-Path -LiteralPath 'E:\')) {
    throw 'Drive E: is required for the BlackGold runner.'
}

$gh = Ensure-Gh
Ensure-GhAuth -Gh $gh

$control = Find-ControlRepository -Gh $gh
$ControlRepo = [string]$control.repository

Write-Step ('Control repository discovered: ' + $ControlRepo)

Write-Step 'Requesting temporary repository runner registration token.'
$registrationJson = Invoke-Gh -Gh $gh -Arguments @(
    'api','--method','POST',
    ('repos/' + $ControlRepo + '/actions/runners/registration-token')
)
$registration = $registrationJson | ConvertFrom-Json
$registrationToken = [string]$registration.token

if (-not $registrationToken) {
    throw 'GitHub did not return a runner registration token.'
}

Write-Step 'Discovering latest official GitHub Actions runner release.'
$release = Invoke-RestMethod -UseBasicParsing -Headers @{ 'User-Agent'='BlackGold-GitHubRunner/1.0' } -Uri 'https://api.github.com/repos/actions/runner/releases/latest'
$asset = @($release.assets | Where-Object { $_.name -match '^actions-runner-win-x64-.*\.zip$' } | Select-Object -First 1)

if (-not $asset) {
    throw 'Could not find the official Windows x64 runner package.'
}

$version = [string]$release.tag_name
$zipPath = Join-Path $env:TEMP ('blackgold-actions-runner-' + $version + '.zip')
$stage = Join-Path $env:TEMP ('BlackGoldRunnerStage-' + [guid]::NewGuid().ToString('N'))

Write-Step ('Downloading official runner ' + $version + '.')
Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zipPath

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Expand-Archive -LiteralPath $zipPath -DestinationPath $stage -Force

if (-not (Test-Path -LiteralPath (Join-Path $stage 'config.cmd'))) {
    throw 'Downloaded runner package is incomplete.'
}

if (-not (Test-Path -LiteralPath $RunnerRoot)) {
    New-Item -ItemType Directory -Force -Path $RunnerRoot | Out-Null
}

if (-not (Test-Path -LiteralPath (Join-Path $RunnerRoot '.runner'))) {
    Write-Step 'Installing runner files.'
    Copy-Item -Path (Join-Path $stage '*') -Destination $RunnerRoot -Recurse -Force
    New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

    Write-Step 'Registering runner in private control repository.'
    $configCmd = Join-Path $RunnerRoot 'config.cmd'
    $args = @(
        '--unattended',
        '--replace',
        '--url',('https://github.com/' + $ControlRepo),
        '--token',$registrationToken,
        '--name',$RunnerName,
        '--labels',$Labels,
        '--work',$WorkRoot
    )

    $quoted = ($args | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"','""') + '"' } else { $_ }
    }) -join ' '

    $cfg = Invoke-Hidden -FileName $env:ComSpec -Arguments ('/d /s /c ""' + $configCmd + '" ' + $quoted + '"') -WorkingDirectory $RunnerRoot

    if ($cfg.ExitCode -ne 0) {
        throw ('Runner configuration failed: ' + $cfg.StdErr + $cfg.StdOut)
    }
}
else {
    Write-Step 'Runner already configured locally; preserving registration.'
}

foreach ($name in @(
    'Start-BlackGoldGitHubRunner.ps1',
    'Status-BlackGoldGitHubRunner.ps1',
    'Uninstall-BlackGoldGitHubRunner.ps1'
)) {
    Invoke-WebRequest -UseBasicParsing -Uri ($CanonicalBase + '/' + $name + '?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -OutFile (Join-Path $RunnerRoot $name)
    Unblock-File -LiteralPath (Join-Path $RunnerRoot $name) -ErrorAction SilentlyContinue
}

$startScript = Join-Path $RunnerRoot 'Start-BlackGoldGitHubRunner.ps1'

Write-Step 'Registering hidden startup task.'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $startScript + '"')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

$localState = [ordered]@{
    schema = 1
    owner = $Owner
    control_repository = $ControlRepo
    queue_path = [string]$control.queue_path
    workflow = [string]$control.workflow
    runner_name = $RunnerName
    labels = $Labels -split ','
    runner_version = $version
    runner_root = $RunnerRoot
    work_root = $WorkRoot
    task_name = $TaskName
    installed_at = (Get-Date).ToString('o')
    desktop_commander_required = $false
}

$localState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RunnerRoot 'BLACKGOLD_RUNNER_STATE.json') -Encoding UTF8

Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
$registrationToken = $null

$serverStatus = 'unknown'
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 2
    try {
        $runnerJson = Invoke-Gh -Gh $gh -Arguments @(
            'api',
            ('repos/' + $ControlRepo + '/actions/runners?per_page=100')
        )
        $runnerObj = $runnerJson | ConvertFrom-Json
        $server = @($runnerObj.runners | Where-Object { $_.name -eq $RunnerName } | Select-Object -First 1)
        if ($server) {
            $serverStatus = [string]$server.status
            if ($serverStatus -eq 'online') { break }
        }
    } catch {}
}

$listener = Get-Process -Name 'Runner.Listener' -ErrorAction SilentlyContinue | Select-Object -First 1
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-not $task) {
    throw 'Runner startup task was not created.'
}

Write-Host ''
Write-Host 'BLACKGOLD_GITHUB_RUNNER_READY'
Write-Host ('ControlRepository=' + $ControlRepo)
Write-Host ('Runner=' + $RunnerName)
Write-Host ('Version=' + $version)
Write-Host ('Startup=' + $TaskName)
Write-Host ('ListenerRunning=' + [bool]$listener)
Write-Host ('ServerStatus=' + $serverStatus)
Write-Host 'DesktopCommanderRequired=False'
