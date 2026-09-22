param(
    [string]$PinnedCommit
)

$ErrorActionPreference = 'Stop'

$Repository = 'ProjetosCosaNostra/CosaNostra-AI'
$StableRef = 'control-plane-stable'
$Headers = @{ 'User-Agent' = 'BlackGold-ControlPlane/1.6' }

$Root = Join-Path $env:LOCALAPPDATA 'BlackGold'
$InstallRoot = Join-Path $Root 'ControlPlane'
$StageRoot = Join-Path $Root 'ControlPlane.__staging'
$PreviousRoot = Join-Path $Root 'ControlPlane.__previous'
$TransactionPath = Join-Path $Root 'ControlPlane.transaction.json'

$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

if (-not $PinnedCommit) {
    $branchInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/branches/' + $StableRef + '?t=' + $nonce)
    $PinnedCommit = [string]$branchInfo.commit.sha
}

if ($PinnedCommit -notmatch '^[0-9a-f]{40}$') {
    throw 'Pinned stable commit is invalid.'
}

$commitInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/commits/' + $PinnedCommit + '?t=' + $nonce)
$TreeSha = [string]$commitInfo.commit.tree.sha
if ($TreeSha -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not resolve Git tree for pinned commit.'
}

$treeInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/git/trees/' + $TreeSha + '?recursive=1&t=' + $nonce)
if ($treeInfo.truncated -eq $true) {
    throw 'Git tree response was truncated; integrity verification cannot continue.'
}

$blobMap = @{}
foreach ($entry in $treeInfo.tree) {
    if ($entry.type -eq 'blob') {
        $blobMap[[string]$entry.path] = [string]$entry.sha
    }
}

$PinnedBase = 'https://raw.githubusercontent.com/' + $Repository + '/' + $PinnedCommit + '/control-plane'
$latest = Invoke-RestMethod -UseBasicParsing -Uri ($PinnedBase + '/LATEST.json?t=' + $nonce)
$Version = [string]$latest.version
$swapped = $false
$previousVersion = $null

function Get-BGGitBlobSha {
    param([Parameter(Mandatory=$true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes(('blob ' + [string]$bytes.Length))

    $stream = New-Object System.IO.MemoryStream
    $sha1 = [System.Security.Cryptography.SHA1]::Create()

    try {
        $stream.Write($header, 0, $header.Length)
        $stream.WriteByte(0)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Position = 0

        return (($sha1.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha1.Dispose()
        $stream.Dispose()
    }
}

function Write-BGTransaction([string]$State,[string]$Message) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $data = [ordered]@{
        schema = 1
        state = $State
        version = $Version
        stable_commit = $PinnedCommit
        tree_sha = $TreeSha
        previous_version = $previousVersion
        message = $Message
        timestamp = (Get-Date).ToString('o')
    }
    $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $TransactionPath -Encoding UTF8
}

function Invoke-BGLocalScript {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "BlackGold script not found: $Path" }
    Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    & ([ScriptBlock]::Create($source))
}

function Test-BGStage {
    param([Parameter(Mandatory=$true)][string]$Path)

    $jsonFiles = @(
        'LATEST.json',
        'manifest.json',
        'CURRENT_TRUTH.json',
        'PROJECT_REGISTRY.json',
        'project-pointer.json',
        'policies/windows.json',
        'templates/control-plane.json',
        'install-state.json'
    )

    foreach ($relative in $jsonFiles) {
        $file = Join-Path $Path ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $file)) { throw "Missing staged JSON: $relative" }
        Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }

    $manifest = Get-Content -LiteralPath (Join-Path $Path 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $latestLocal = Get-Content -LiteralPath (Join-Path $Path 'LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $truth = Get-Content -LiteralPath (Join-Path $Path 'CURRENT_TRUTH.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry = Get-Content -LiteralPath (Join-Path $Path 'PROJECT_REGISTRY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $installState = Get-Content -LiteralPath (Join-Path $Path 'install-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($candidate in @([string]$manifest.version,[string]$latestLocal.version,[string]$truth.version,[string]$registry.control_plane_version,[string]$installState.version)) {
        if ($candidate -ne $Version) {
            throw "Staged version mismatch. Expected $Version, found $candidate"
        }
    }

    if ([string]$installState.stable_commit -ne $PinnedCommit) { throw 'Install state commit mismatch.' }
    if ([string]$installState.tree_sha -ne $TreeSha) { throw 'Install state tree mismatch.' }
    if ($installState.integrity_verified -ne $true) { throw 'Install state is not integrity verified.' }

    if ($manifest.transactional_install -ne $true) { throw 'transactional_install must be true' }
    if ($manifest.rollback_enabled -ne $true) { throw 'rollback_enabled must be true' }
    if ($manifest.commit_pinning -ne $true) { throw 'commit_pinning must be true' }
    if ($manifest.git_blob_integrity -ne $true) { throw 'git_blob_integrity must be true' }
    if ($manifest.stable_branch -ne 'control-plane-stable') { throw 'stable_branch mismatch' }

    $scripts = Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.ps1' -File
    foreach ($script in $scripts) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script.FullName,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null

        if ($errors.Count -gt 0) {
            throw ('PowerShell parse failure in ' + $script.FullName + ': ' + $errors[0].Message)
        }
    }
}

$files = @(
  'BLACKGOLD_CONTROL_PLANE.md',
  'AGENT_ENTRYPOINT.md',
  'CURRENT_TRUTH.json',
  'PROJECT_REGISTRY.json',
  'RELEASE_PROCESS.md',
  'security/PUBLIC_PRIVATE_DATA_BOUNDARY.md',
  'LATEST.json',
  'manifest.json',
  'project-pointer.json',
  'policies/windows.json',
  'templates/AGENTS.md',
  'templates/control-plane.json',
  'install.ps1',
  'bootstrap.ps1',
  'Update-BlackGoldControl.ps1',
  'agent/BlackGold.Control.ps1',
  'agent/Register-BlackGoldControl.ps1',
  'agent/Uninstall-BlackGoldControl.ps1',
  'Register-BlackGoldProjects.ps1',
  'Status-BlackGoldControl.ps1',
  'Repair-BlackGoldControl.ps1',
  'Doctor-BlackGoldControl.ps1',
  'Rollback-BlackGoldControl.ps1'
)

try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    if (Test-Path -LiteralPath $InstallRoot) {
        try {
            $oldManifest = Get-Content -LiteralPath (Join-Path $InstallRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $previousVersion = [string]$oldManifest.version
        } catch {}
    }

    Write-BGTransaction 'staging' 'Downloading pinned stable payload with Git blob verification.'

    if (Test-Path -LiteralPath $StageRoot) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null

    $verifiedCount = 0

    foreach ($relative in $files) {
        $repoPath = 'control-plane/' + $relative
        $expectedBlob = [string]$blobMap[$repoPath]

        if ($expectedBlob -notmatch '^[0-9a-f]{40}$') {
            throw "No Git blob identity found for $repoPath"
        }

        $target = Join-Path $StageRoot ($relative -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null

        Invoke-WebRequest -UseBasicParsing -Uri ($PinnedBase + '/' + $relative + '?v=' + $Version + '&t=' + $nonce) -OutFile $target
        if ((Get-Item -LiteralPath $target).Length -le 0) { throw "Downloaded empty file: $relative" }

        $actualBlob = Get-BGGitBlobSha -Path $target
        if ($actualBlob -ne $expectedBlob) {
            throw "Git blob integrity mismatch for $relative expected=$expectedBlob actual=$actualBlob"
        }

        Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
        $verifiedCount++
    }

    $installState = [ordered]@{
        schema = 1
        version = $Version
        stable_branch = $StableRef
        stable_commit = $PinnedCommit
        tree_sha = $TreeSha
        integrity_model = 'pinned_commit_git_blob_sha1'
        integrity_verified = $true
        verified_file_count = $verifiedCount
        installed_at = (Get-Date).ToString('o')
    }
    $installState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $StageRoot 'install-state.json') -Encoding UTF8

    Test-BGStage -Path $StageRoot
    Write-BGTransaction 'staged_integrity_verified' ('Verified files=' + $verifiedCount)
    Write-BGTransaction 'staged_validated' 'All staged files passed integrity and structural validation.'

    foreach ($taskName in @('BlackGold-ControlPlane','BlackGold-ControlPlane-Update','BlackGold-ControlPlane-Doctor')) {
        Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
    }

    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*BlackGold.Control.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    if (Test-Path -LiteralPath $PreviousRoot) {
        Remove-Item -LiteralPath $PreviousRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        Move-Item -LiteralPath $InstallRoot -Destination $PreviousRoot
    }

    Move-Item -LiteralPath $StageRoot -Destination $InstallRoot
    $swapped = $true
    Write-BGTransaction 'activated_pending_healthcheck' 'Integrity-verified staging slot promoted to active.'

    if (Test-Path -LiteralPath (Join-Path $PreviousRoot 'logs')) {
        Copy-Item -LiteralPath (Join-Path $PreviousRoot 'logs') -Destination (Join-Path $InstallRoot 'logs') -Recurse -Force -ErrorAction SilentlyContinue
    }

    [Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $InstallRoot, 'User')

    Invoke-BGLocalScript (Join-Path $InstallRoot 'agent\Register-BlackGoldControl.ps1')
    Invoke-BGLocalScript (Join-Path $InstallRoot 'Register-BlackGoldProjects.ps1')

    Start-Sleep -Seconds 2

    $task = Get-ScheduledTask -TaskName 'BlackGold-ControlPlane' -ErrorAction SilentlyContinue
    $runValue = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BlackGold-ControlPlane' -ErrorAction SilentlyContinue
    if (-not $task -and -not $runValue) { throw 'BlackGold startup was not registered after activation.' }

    $activeManifest = Get-Content -LiteralPath (Join-Path $InstallRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $activeState = Get-Content -LiteralPath (Join-Path $InstallRoot 'install-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    if ([string]$activeManifest.version -ne $Version) { throw 'Active version does not match staged version.' }
    if ([string]$activeState.stable_commit -ne $PinnedCommit) { throw 'Active commit does not match pinned stable commit.' }
    if ($activeState.integrity_verified -ne $true) { throw 'Active integrity state is not verified.' }

    Write-BGTransaction 'committed' ('Transaction committed at immutable commit ' + $PinnedCommit)

    Write-Output ('BLACKGOLD_CONTROL_PLANE_READY version=' + $Version)
    Write-Output ('StableCommit=' + $PinnedCommit)
    Write-Output ('VerifiedFiles=' + $verifiedCount)
    Write-Output ('InstallRoot=' + $InstallRoot)
    Write-Output ('PreviousVersion=' + $(if ($previousVersion) { $previousVersion } else { 'none' }))
    if ($task) { Write-Output ('Startup=ScheduledTask/' + $task.TaskName) }
    elseif ($runValue) { Write-Output 'Startup=HKCU/Run' }

    Invoke-BGLocalScript (Join-Path $InstallRoot 'Status-BlackGoldControl.ps1')
}
catch {
    $errorMessage = $_.Exception.Message
    Write-BGTransaction 'failed' $errorMessage

    if ($swapped) {
        foreach ($taskName in @('BlackGold-ControlPlane','BlackGold-ControlPlane-Update','BlackGold-ControlPlane-Doctor')) {
            Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
        }

        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like '*BlackGold.Control.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

        if (Test-Path -LiteralPath $InstallRoot) {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $PreviousRoot) {
            Move-Item -LiteralPath $PreviousRoot -Destination $InstallRoot -ErrorAction SilentlyContinue

            try {
                [Environment]::SetEnvironmentVariable('BLACKGOLD_CONTROL_PLANE', $InstallRoot, 'User')
                Invoke-BGLocalScript (Join-Path $InstallRoot 'agent\Register-BlackGoldControl.ps1')
                Invoke-BGLocalScript (Join-Path $InstallRoot 'Register-BlackGoldProjects.ps1')
                Write-BGTransaction 'rolled_back_after_failure' $errorMessage
            } catch {
                Write-BGTransaction 'rollback_failed_after_activation_failure' ($errorMessage + ' | rollback=' + $_.Exception.Message)
            }
        }
    }

    if (Test-Path -LiteralPath $StageRoot) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    throw
}
