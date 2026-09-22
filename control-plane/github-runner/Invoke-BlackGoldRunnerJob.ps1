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

function Assert-Serial([string]$Serial) {
    if (-not $Serial) { return '' }
    if ($Serial -notmatch '^emulator-\d+$') { throw 'Invalid emulator serial.' }
    return $Serial
}

function Get-Adb {
    $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }
    return $adb
}

function Get-Emulator {
    $emulator = Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $emulator)) { throw 'emulator.exe not found.' }
    return $emulator
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

function Get-AvdName {
    param(
        [Parameter(Mandatory=$true)][string]$Adb,
        [Parameter(Mandatory=$true)][string]$Serial
    )

    $r = Invoke-Hidden -FileName $Adb -Arguments ('-s ' + $Serial + ' emu avd name') -WorkingDirectory (Split-Path $Adb -Parent) -TimeoutSec 30
    if ($r.exit_code -ne 0) { return '' }

    $lines = @(([string]$r.stdout -split '[\r\n]+') | Where-Object { $_ -and $_.Trim() -ne 'OK' })
    if ($lines.Count -lt 1) { return '' }
    return ([string]$lines[0]).Trim()
}

function Find-AvdSerial {
    param(
        [Parameter(Mandatory=$true)][string]$Adb,
        [Parameter(Mandatory=$true)][string]$Avd
    )

    $devices = Invoke-Hidden -FileName $Adb -Arguments 'devices' -WorkingDirectory (Split-Path $Adb -Parent) -TimeoutSec 30
    if ($devices.exit_code -ne 0) { return '' }

    foreach ($line in ([string]$devices.stdout -split '[\r\n]+')) {
        if ($line -match '^(emulator-\d+)\s+device$') {
            $candidate = $matches[1]
            if ((Get-AvdName -Adb $Adb -Serial $candidate) -eq $Avd) {
                return $candidate
            }
        }
    }

    return ''
}

if (-not (Test-Path -LiteralPath $JobFile)) {
    throw ('Job file not found: ' + $JobFile)
}

$job = Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8 | ConvertFrom-Json

if ([int]$job.schema -ne 1) { throw 'Unsupported job schema.' }
$requestId = [string]$job.request_id
$op = [string]$job.op
$serial = Assert-Serial ([string]$job.serial)

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
        $adb = Get-Adb
        $r = Invoke-Hidden -FileName $adb -Arguments 'devices -l' -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; process=$r }
    }

    'adb_install' {
        $apk = Assert-EPath ([string]$job.apk_path)
        if (-not $apk.EndsWith('.apk',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'apk_path must be .apk' }
        if (-not (Test-Path -LiteralPath $apk)) { throw 'APK not found.' }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'install -r "' + $apk + '"') -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; serial=$serial; apk_path=$apk; process=$r }
    }

    'adb_launch' {
        $package = [string]$job.package
        $activity = [string]$job.activity

        if ($package -notmatch '^[A-Za-z0-9_.]+$') { throw 'Invalid package.' }
        if ($activity -notmatch '^[A-Za-z0-9_.$]+$') { throw 'Invalid activity.' }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'shell am start -n ' + $package + '/' + $activity) -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; serial=$serial; package=$package; activity=$activity; process=$r }
    }

    'adb_launch_package' {
        $package = [string]$job.package
        if ($package -notmatch '^[A-Za-z0-9_.]+$') { throw 'Invalid package.' }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'shell monkey -p ' + $package + ' -c android.intent.category.LAUNCHER 1') -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; serial=$serial; package=$package; process=$r }
    }

    'emulator_start' {
        $avd = [string]$job.avd
        if ($avd -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Invalid AVD name.' }

        $port = [int]$job.port
        if ($port -ne 0) {
            if ($port -lt 5554 -or $port -gt 5682 -or ($port % 2) -ne 0) {
                throw 'Invalid emulator port.'
            }
            $serial = 'emulator-' + $port
        }

        $waitBootSec = [int]$job.wait_boot_sec
        if ($waitBootSec -lt 1) { $waitBootSec = 240 }
        if ($waitBootSec -gt 600) { $waitBootSec = 600 }

        $adb = Get-Adb
        $emulator = Get-Emulator
        Invoke-Hidden -FileName $adb -Arguments 'start-server' -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30 | Out-Null

        $existingSerial = if ($serial) { $serial } else { Find-AvdSerial -Adb $adb -Avd $avd }
        $state = ''
        if ($existingSerial) {
            $stateResult = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $existingSerial + ' get-state') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
            if ($stateResult.exit_code -eq 0) { $state = ([string]$stateResult.stdout).Trim() }
        }

        if ($state -eq 'device') {
            $actualAvd = Get-AvdName -Adb $adb -Serial $existingSerial
            if ($actualAvd -ne $avd) {
                throw ('Target serial is occupied by another AVD. expected=' + $avd + ' actual=' + $actualAvd + ' serial=' + $existingSerial)
            }
        }
        else {
            $args = '-avd ' + $avd + ' -netdelay none -netspeed full -no-boot-anim'
            if ($port -ne 0) { $args += ' -port ' + $port }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $emulator
            $psi.Arguments = $args
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        }

        $deadline = (Get-Date).AddSeconds($waitBootSec)
        $boot = ''
        do {
            Start-Sleep -Seconds 3

            if (-not $serial) {
                $serial = Find-AvdSerial -Adb $adb -Avd $avd
            }

            if ($serial) {
                $stateResult = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' get-state') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
                if ($stateResult.exit_code -eq 0 -and ([string]$stateResult.stdout).Trim() -eq 'device') {
                    $bootResult = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell getprop sys.boot_completed') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
                    if ($bootResult.exit_code -eq 0) { $boot = ([string]$bootResult.stdout).Trim() }
                    if ($boot -eq '1') { break }
                }
            }
        } while ((Get-Date) -lt $deadline)

        if (-not $serial) { throw ('AVD not found after start: ' + $avd) }
        if ($boot -ne '1') { throw ('AVD boot timeout: ' + $serial) }

        $actualAvd = Get-AvdName -Adb $adb -Serial $serial
        if ($actualAvd -ne $avd) {
            throw ('AVD identity mismatch. expected=' + $avd + ' actual=' + $actualAvd + ' serial=' + $serial)
        }

        $result = [ordered]@{
            request_id=$requestId
            op=$op
            avd=$avd
            port=$port
            serial=$serial
            boot_completed=$true
            started=$true
        }
    }

    'logcat_tail' {
        $lines = [int]$job.lines
        if ($lines -lt 10) { $lines = 200 }
        if ($lines -gt 2000) { $lines = 2000 }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'logcat -d -t ' + $lines) -WorkingDirectory (Split-Path $adb -Parent)
        $result = [ordered]@{ request_id=$requestId; op=$op; serial=$serial; lines=$lines; process=$r }
    }

    default {
        throw ('Unsupported operation: ' + $op)
    }
}

$result | ConvertTo-Json -Depth 8
