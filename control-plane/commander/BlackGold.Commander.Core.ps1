param(
    [Parameter(Mandatory=$true)][string]$JobFile
)

$ErrorActionPreference = 'Stop'
$MaxTextBytes = 262144

function Assert-EPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'path required' }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith('E:\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Only E:\ paths are allowed.'
    }
    return $full
}

function Assert-Serial([string]$Serial) {
    if ([string]::IsNullOrWhiteSpace($Serial)) { return '' }
    if ($Serial -notmatch '^emulator-\d+$') { throw 'Invalid emulator serial.' }
    return $Serial
}

function Invoke-Hidden {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 900
    )

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = New-Object Diagnostics.Process
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

function Get-Adb {
    $p = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $p)) { throw 'adb.exe not found.' }
    return $p
}

function Get-Emulator {
    $p = Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $p)) { throw 'emulator.exe not found.' }
    return $p
}

if (-not (Test-Path -LiteralPath $JobFile -PathType Leaf)) {
    throw ('Job file not found: ' + $JobFile)
}

$job = Get-Content -LiteralPath $JobFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$job.schema -ne 2) { throw 'Unsupported job schema.' }

$requestId = [string]$job.request_id
if ($requestId -notmatch '^[A-Za-z0-9._-]{6,128}$') { throw 'Invalid request_id.' }

$op = [string]$job.op
$serial = Assert-Serial ([string]$job.serial)

switch ($op) {
    'status' {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            computer = $env:COMPUTERNAME
            user = $env:USERNAME
            os = if ($os) { $os.Caption } else { 'unknown' }
            powershell = $PSVersionTable.PSVersion.ToString()
            e_drive = [bool](Test-Path 'E:\')
        }
    }

    'fs_list' {
        $path = Assert-EPath ([string]$job.path)
        if (-not (Test-Path -LiteralPath $path)) { throw 'Path not found.' }

        $depth = [int]$job.depth
        if ($depth -lt 1) { $depth = 2 }
        if ($depth -gt 5) { $depth = 5 }

        $rootDepth = ($path.TrimEnd('\') -split '\\').Count
        $items = New-Object Collections.Generic.List[object]

        Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $d = (($_.FullName.TrimEnd('\') -split '\\').Count - $rootDepth)
            if ($d -le $depth -and $items.Count -lt 2000) {
                $items.Add([ordered]@{
                    path = $_.FullName
                    type = if ($_.PSIsContainer) { 'dir' } else { 'file' }
                    length = if ($_.PSIsContainer) { $null } else { [long]$_.Length }
                    modified = $_.LastWriteTime.ToString('o')
                })
            }
        }

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            path = $path
            items = $items
        }
    }

    'fs_read_text' {
        $path = Assert-EPath ([string]$job.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'File not found.' }

        $max = [int]$job.max_bytes
        if ($max -lt 1) { $max = 131072 }
        if ($max -gt $MaxTextBytes) { $max = $MaxTextBytes }

        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes -contains 0) { throw 'Binary file refused by fs_read_text.' }

        $truncated = $false
        if ($bytes.Length -gt $max) {
            $bytes = $bytes[0..($max - 1)]
            $truncated = $true
        }

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            path = $path
            truncated = $truncated
            content = [Text.Encoding]::UTF8.GetString($bytes)
        }
    }

    'fs_write_text' {
        $path = Assert-EPath ([string]$job.path)
        $content = [string]$job.content
        if ($content.Length -gt $MaxTextBytes) { throw 'Content too large.' }

        $parent = Split-Path -Parent $path
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }

        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($path, $content, $utf8)

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            path = $path
            bytes = (Get-Item -LiteralPath $path).Length
        }
    }

    'fs_mkdir' {
        $path = Assert-EPath ([string]$job.path)
        New-Item -ItemType Directory -Force -Path $path | Out-Null

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            path = $path
        }
    }

    'git_status' {
        $path = Assert-EPath ([string]$job.project_path)
        $r = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" status --porcelain=v1 -b') -WorkingDirectory $path

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            project_path = $path
            process = $r
        }
    }

    'git_pull_ff' {
        $path = Assert-EPath ([string]$job.project_path)

        $check = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" status --porcelain') -WorkingDirectory $path
        if ($check.exit_code -ne 0) { throw 'git status failed.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$check.stdout)) { throw 'Working tree is not clean; pull refused.' }

        $r = Invoke-Hidden -FileName 'git.exe' -Arguments ('-C "' + $path + '" pull --ff-only') -WorkingDirectory $path

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            project_path = $path
            process = $r
        }
    }

    'gradle' {
        $path = Assert-EPath ([string]$job.project_path)
        $task = [string]$job.task
        if (@('assembleDebug','test','lint','connectedDebugAndroidTest') -notcontains $task) {
            throw 'Gradle task not allowed.'
        }

        $gradlew = Join-Path $path 'gradlew.bat'
        if (-not (Test-Path -LiteralPath $gradlew)) { throw 'gradlew.bat not found.' }

        $args = '/d /s /c ""' + $gradlew + '" ' + $task + ' --no-daemon --console=plain"'
        $r = Invoke-Hidden -FileName $env:ComSpec -Arguments $args -WorkingDirectory $path -TimeoutSec 1800

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            task = $task
            project_path = $path
            process = $r
        }
    }

    'adb_devices' {
        $adb = Get-Adb
        $r = Invoke-Hidden -FileName $adb -Arguments 'devices -l' -WorkingDirectory (Split-Path $adb -Parent)

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            process = $r
        }
    }

    'adb_install' {
        $apk = Assert-EPath ([string]$job.apk_path)
        if (-not $apk.EndsWith('.apk',[StringComparison]::OrdinalIgnoreCase)) { throw 'apk_path must be .apk' }
        if (-not (Test-Path -LiteralPath $apk)) { throw 'APK not found.' }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'install -r "' + $apk + '"') -WorkingDirectory (Split-Path $adb -Parent)

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            serial = $serial
            apk_path = $apk
            process = $r
        }
    }

    'adb_launch_package' {
        $package = [string]$job.package
        if ($package -notmatch '^[A-Za-z0-9_.]+$') { throw 'Invalid package.' }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'shell monkey -p ' + $package + ' -c android.intent.category.LAUNCHER 1') -WorkingDirectory (Split-Path $adb -Parent)

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            serial = $serial
            package = $package
            process = $r
        }
    }

    'emulator_start' {
        $avd = [string]$job.avd
        if ($avd -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Invalid AVD name.' }

        $port = [int]$job.port
        if ($port -ne 0 -and ($port -lt 5554 -or $port -gt 5682 -or ($port % 2) -ne 0)) {
            throw 'Invalid emulator port.'
        }

        $wait = [int]$job.wait_boot_sec
        if ($wait -lt 1) { $wait = 240 }
        if ($wait -gt 600) { $wait = 600 }

        $adb = Get-Adb
        $emulator = Get-Emulator

        Invoke-Hidden -FileName $adb -Arguments 'start-server' -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30 | Out-Null

        $args = '-avd ' + $avd + ' -netdelay none -netspeed full -no-boot-anim'
        if ($port -ne 0) {
            $args += ' -port ' + $port
            $serial = 'emulator-' + $port
        }

        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $emulator
        $psi.Arguments = $args
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        [Diagnostics.Process]::Start($psi) | Out-Null

        $deadline = (Get-Date).AddSeconds($wait)
        $boot = ''

        do {
            Start-Sleep -Seconds 3
            if ($serial) {
                $b = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell getprop sys.boot_completed') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
                if ($b.exit_code -eq 0) { $boot = ([string]$b.stdout).Trim() }
            }
            if ($boot -eq '1') { break }
        } while ((Get-Date) -lt $deadline)

        if ($boot -ne '1') { throw 'AVD boot timeout.' }

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = $true
            avd = $avd
            serial = $serial
            boot_completed = $true
        }
    }

    'logcat_tail' {
        $lines = [int]$job.lines
        if ($lines -lt 10) { $lines = 200 }
        if ($lines -gt 2000) { $lines = 2000 }

        $adb = Get-Adb
        $prefix = if ($serial) { '-s ' + $serial + ' ' } else { '' }
        $r = Invoke-Hidden -FileName $adb -Arguments ($prefix + 'logcat -d -t ' + $lines) -WorkingDirectory (Split-Path $adb -Parent)

        $result = [ordered]@{
            request_id = $requestId
            op = $op
            ok = ($r.exit_code -eq 0)
            serial = $serial
            lines = $lines
            process = $r
        }
    }

    default {
        throw ('Unsupported operation: ' + $op)
    }
}

$result | ConvertTo-Json -Depth 12
