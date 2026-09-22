param(
    [Parameter(Mandatory=$true)][string]$JobFile
)

$ErrorActionPreference = 'Stop'

function Assert-EPath([string]$Path) {
    if (-not $Path) { throw 'path required' }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith('E:\',[System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Only E:\ paths are allowed.'
    }
    return $full
}

function Invoke-Hidden {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 900
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

    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
        $exit = -408
        $timedOut = $true
    } else {
        $exit = $p.ExitCode
        $timedOut = $false
    }

    try { $stdout = $outTask.GetAwaiter().GetResult() } catch { $stdout = '' }
    try { $stderr = $errTask.GetAwaiter().GetResult() } catch { $stderr = '' }

    [ordered]@{
        exit_code = $exit
        timed_out = $timedOut
        stdout = $stdout
        stderr = $stderr
    }
}

if (-not (Test-Path -LiteralPath $JobFile)) {
    throw ('Job file not found: ' + $JobFile)
}

$job = Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8 | ConvertFrom-Json

if ([int]$job.schema -ne 1) { throw 'Unsupported job schema.' }
$requestId = [string]$job.request_id
$op = [string]$job.op

$result = $null

switch ($op) {
    'status' {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $result = [ordered]@{
            request_id = $requestId
            op = $op
            computer = $env:COMPUTERNAME
            user = $env:USERNAME
            os = if ($os) { $os.Caption } else { 'unknown' }
            powershell = $PSVersionTable.PSVersion.ToString()
            e_drive = [bool](Test-Path 'E:\')
        }
    }

    'git_status' {
        $path = Assert-EPath ([string]$job.project_path)
        $r = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" status --porcelain=v1 -b') -WorkingDirectory $path
        $result = [ordered]@{ request_id=$requestId; op=$op; project_path=$path; process=$r }
    }

    'git_sync' {
        $path = Assert-EPath ([string]$job.project_path)
        $check = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" status --porcelain') -WorkingDirectory $path
        if ($check.exit_code -ne 0) { throw 'git status failed.' }
        if ([string]$check.stdout) { throw 'Working tree is not clean; sync refused.' }

        $r = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" pull --ff-only') -WorkingDirectory $path
        $result = [ordered]@{ request_id=$requestId; op=$op; project_path=$path; process=$r }
    }

    'gradle' {
        $path = Assert-EPath ([string]$job.project_path)
        $task = [string]$job.task
        if (@('assembleDebug','test','lint','connectedDebugAndroidTest') -notcontains $task) {
            throw 'Gradle task not allowed.'
        }

        $gradlew = Join-Path $path 'gradlew.bat'
        if (-not (Test-Path -LiteralPath $gradlew)) { throw 'gradlew.bat not found.' }

        $r = Invoke-Hidden -FileName $gradlew -Arguments ($task + ' --no-daemon --console=plain') -WorkingDirectory $path -TimeoutSec 1800
        $result = [ordered]@{ request_id=$requestId; op=$op; task=$task; project_path=$path; process=$r }
    }

    'adb_devices' {
        $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }
        $r = Invoke-Hidden -FileName $adb -Arguments 'devices -l' -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; process=$r }
    }

    'adb_install' {
        $apk = Assert-EPath ([string]$job.apk_path)
        if (-not $apk.EndsWith('.apk',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'apk_path must be .apk' }
        if (-not (Test-Path -LiteralPath $apk)) { throw 'APK not found.' }

        $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }

        $r = Invoke-Hidden -FileName $adb -Arguments ('install -r "' + $apk + '"') -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; apk_path=$apk; process=$r }
    }

    'adb_launch' {
        $package = [string]$job.package
        $activity = [string]$job.activity

        if ($package -notmatch '^[A-Za-z0-9_.]+$') { throw 'Invalid package.' }
        if ($activity -notmatch '^[A-Za-z0-9_.$]+$') { throw 'Invalid activity.' }

        $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }

        $r = Invoke-Hidden -FileName $adb -Arguments ('shell am start -n ' + $package + '/' + $activity) -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; package=$package; activity=$activity; process=$r }
    }

    'emulator_start' {
        $avd = [string]$job.avd
        if ($avd -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Invalid AVD name.' }

        $emulator = Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe'
        if (-not (Test-Path -LiteralPath $emulator)) { throw 'emulator.exe not found.' }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $emulator
        $psi.Arguments = '-avd ' + $avd
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [System.Diagnostics.Process]::Start($psi) | Out-Null

        $result = [ordered]@{ request_id=$requestId; op=$op; avd=$avd; started=$true }
    }

    'logcat_tail' {
        $lines = [int]$job.lines
        if ($lines -lt 10) { $lines = 200 }
        if ($lines -gt 2000) { $lines = 2000 }

        $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }

        $r = Invoke-Hidden -FileName $adb -Arguments ('logcat -d -t ' + $lines) -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; lines=$lines; process=$r }
    }

    default {
        throw ('Unsupported operation: ' + $op)
    }
}

$result | ConvertTo-Json -Depth 8
