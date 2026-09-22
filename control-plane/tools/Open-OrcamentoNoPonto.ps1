param(
    [string]$ProjectPath = 'E:\\Orcamento_no_Ponto\\01_Android_App\\orcamento_no_ponto',
    [string]$Avd = 'Orcamento_no_Ponto_API35'
)

$ErrorActionPreference = 'Stop'
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}

$Root = 'E:\\Orcamento_no_Ponto'
$Exchange = Join-Path $Root '00_CODEX_EXCHANGE'
$Log = Join-Path $Exchange 'OPEN_ORCAMENTO_NO_PONTO.log'
$Receipt = Join-Path $Exchange 'OPEN_ORCAMENTO_NO_PONTO_RECEIPT.json'
$Shot = Join-Path $Exchange 'OPEN_ORCAMENTO_NO_PONTO.png'
$PackageFallback = 'br.com.lafamigliaplayworks.orcamentonoponto'

New-Item -ItemType Directory -Force -Path $Exchange | Out-Null

function Write-Log([string]$Message) {
    Add-Content -LiteralPath $Log -Value ('[' + (Get-Date).ToString('s') + '] ' + $Message) -Encoding UTF8
}

function Invoke-Hidden {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 1800
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
        throw ('Process timeout: ' + $FileName)
    }
    try { $stdout = $outTask.GetAwaiter().GetResult() } catch { $stdout = '' }
    try { $stderr = $errTask.GetAwaiter().GetResult() } catch { $stderr = '' }
    if ($p.ExitCode -ne 0) {
        throw ('Process failed exit=' + $p.ExitCode + ' file=' + $FileName + ' stderr=' + $stderr + ' stdout=' + $stdout)
    }
    return [pscustomobject]@{ stdout=$stdout; stderr=$stderr; exit_code=$p.ExitCode }
}

function Get-AvdName([string]$Adb,[string]$Serial) {
    try {
        $r = Invoke-Hidden -FileName $Adb -Arguments ('-s ' + $Serial + ' emu avd name') -WorkingDirectory (Split-Path $Adb -Parent) -TimeoutSec 20
        $line = @(([string]$r.stdout -split '[\r\n]+') | Where-Object { $_ -and $_.Trim() -ne 'OK' } | Select-Object -First 1)
        if ($line) { return ([string]$line).Trim() }
    } catch {}
    return ''
}

function Find-TargetSerial([string]$Adb,[string]$TargetAvd) {
    $r = Invoke-Hidden -FileName $Adb -Arguments 'devices' -WorkingDirectory (Split-Path $Adb -Parent) -TimeoutSec 30
    foreach ($line in ([string]$r.stdout -split '[\r\n]+')) {
        if ($line -match '^(emulator-\d+)\s+device$') {
            $s = $matches[1]
            if ((Get-AvdName -Adb $Adb -Serial $s) -eq $TargetAvd) { return $s }
        }
    }
    return ''
}

function Find-FreePort([string]$Adb) {
    $used = @{}
    try {
        $r = Invoke-Hidden -FileName $Adb -Arguments 'devices' -WorkingDirectory (Split-Path $Adb -Parent) -TimeoutSec 30
        foreach ($line in ([string]$r.stdout -split '[\r\n]+')) {
            if ($line -match '^emulator-(\d+)\s+') { $used[[int]$matches[1]] = $true }
        }
    } catch {}
    foreach ($p in 5556..5682) {
        if (($p % 2) -eq 0 -and -not $used.ContainsKey($p)) { return $p }
    }
    throw 'No free Android emulator port.'
}

function Resolve-Package([string]$Path) {
    foreach ($file in @('app\\build.gradle','app\\build.gradle.kts')) {
        $candidate = Join-Path $Path $file
        if (Test-Path -LiteralPath $candidate) {
            $raw = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8
            $m = [regex]::Match($raw, 'applicationId\s*(?:=\s*)?["'']([^"'']+)["'']')
            if ($m.Success) { return $m.Groups[1].Value }
        }
    }
    return $PackageFallback
}

try {
    Write-Log 'START'

    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        $candidate = 'E:\\Orcamento_no_Ponto\\01_Android_App'
        if (Test-Path -LiteralPath (Join-Path $candidate 'gradlew.bat')) { $ProjectPath = $candidate }
    }
    $gradlew = Join-Path $ProjectPath 'gradlew.bat'
    if (-not (Test-Path -LiteralPath $gradlew)) { throw ('gradlew.bat not found at ' + $ProjectPath) }

    $sdk = Join-Path $env:LOCALAPPDATA 'Android\\Sdk'
    $adb = Join-Path $sdk 'platform-tools\\adb.exe'
    $emulator = Join-Path $sdk 'emulator\\emulator.exe'
    if (-not (Test-Path -LiteralPath $adb)) { throw 'adb.exe not found.' }
    if (-not (Test-Path -LiteralPath $emulator)) { throw 'emulator.exe not found.' }

    foreach ($jbr in @(
        'C:\\Program Files\\Android\\Android Studio\\jbr',
        'C:\\Program Files\\Android\\Android Studio\\jre'
    )) {
        if (Test-Path -LiteralPath (Join-Path $jbr 'bin\\java.exe')) {
            $env:JAVA_HOME = $jbr
            $env:PATH = (Join-Path $jbr 'bin') + ';' + $env:PATH
            break
        }
    }

    Invoke-Hidden -FileName $adb -Arguments 'start-server' -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30 | Out-Null

    $avdList = Invoke-Hidden -FileName $emulator -Arguments '-list-avds' -WorkingDirectory (Split-Path $emulator -Parent) -TimeoutSec 30
    $avds = @(([string]$avdList.stdout -split '[\r\n]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($avds -notcontains $Avd) {
        throw ('Required AVD not found: ' + $Avd + '. Available=' + ($avds -join ','))
    }

    $serial = Find-TargetSerial -Adb $adb -TargetAvd $Avd
    if (-not $serial) {
        $port = Find-FreePort -Adb $adb
        Write-Log ('START_AVD name=' + $Avd + ' port=' + $port)
        Start-Process -FilePath $emulator -ArgumentList @('-avd',$Avd,'-port',[string]$port,'-netdelay','none','-netspeed','full','-no-boot-anim') | Out-Null
        $serial = 'emulator-' + $port
    }

    $deadline = (Get-Date).AddMinutes(6)
    $boot = ''
    do {
        Start-Sleep -Seconds 3
        try {
            $state = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' get-state') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
            if ([string]$state.stdout -match 'device') {
                $bootResult = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell getprop sys.boot_completed') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 15
                $boot = ([string]$bootResult.stdout).Trim()
            }
        } catch {}
    } while ($boot -ne '1' -and (Get-Date) -lt $deadline)
    if ($boot -ne '1') { throw ('AVD boot timeout: ' + $serial) }

    $actualAvd = Get-AvdName -Adb $adb -Serial $serial
    if ($actualAvd -ne $Avd) { throw ('AVD mismatch expected=' + $Avd + ' actual=' + $actualAvd) }

    Write-Log ('BUILD project=' + $ProjectPath)
    $build = Invoke-Hidden -FileName $gradlew -Arguments 'assembleDebug --no-daemon --console=plain' -WorkingDirectory $ProjectPath -TimeoutSec 1800
    if ($build.stdout) { Add-Content -LiteralPath $Log -Value $build.stdout -Encoding UTF8 }

    $apk = Join-Path $ProjectPath 'app\\build\\outputs\\apk\\debug\\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) {
        $apk = Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter '*debug*.apk' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $apk -or -not (Test-Path -LiteralPath $apk)) { throw 'Debug APK not found after build.' }

    Write-Log ('INSTALL apk=' + $apk + ' serial=' + $serial)
    Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' install -r "' + $apk + '"') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 300 | Out-Null

    $package = Resolve-Package -Path $ProjectPath
    Write-Log ('LAUNCH package=' + $package)
    Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell monkey -p ' + $package + ' -c android.intent.category.LAUNCHER 1') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 60 | Out-Null
    Start-Sleep -Seconds 3

    $pidResult = Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell pidof ' + $package) -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30
    $pid = ([string]$pidResult.stdout).Trim()
    if (-not $pid) { throw ('App did not remain running: ' + $package) }

    try {
        $remoteShot = '/sdcard/orcamento-no-ponto.png'
        Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell screencap -p ' + $remoteShot) -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30 | Out-Null
        Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' pull ' + $remoteShot + ' "' + $Shot + '"') -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 60 | Out-Null
        Invoke-Hidden -FileName $adb -Arguments ('-s ' + $serial + ' shell rm ' + $remoteShot) -WorkingDirectory (Split-Path $adb -Parent) -TimeoutSec 30 | Out-Null
    } catch {
        Write-Log ('SCREENSHOT_WARNING ' + $_.Exception.Message)
    }

    $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $receiptObj = [ordered]@{
        schema = 1
        status = 'SUCCESS'
        time = (Get-Date).ToString('o')
        project = 'Orcamento no Ponto'
        project_path = $ProjectPath
        avd = $Avd
        serial = $serial
        package = $package
        pid = $pid
        apk = $apk
        apk_sha256 = $apkHash
        screenshot = if (Test-Path -LiteralPath $Shot) { $Shot } else { '' }
    }
    $receiptObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Receipt -Encoding UTF8
    Write-Log ('SUCCESS serial=' + $serial + ' package=' + $package + ' pid=' + $pid)

    try {
        $runnerInstaller = Join-Path $env:LOCALAPPDATA 'BlackGold\\ControlPlane\\github-runner\\Install-BlackGoldGitHubRunner.ps1'
        if (Test-Path -LiteralPath $runnerInstaller) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
                '-File',('"' + $runnerInstaller + '"'),'-NonInteractive'
            ) -WindowStyle Hidden
            Write-Log 'RUNNER_REPAIR_DISPATCHED'
        } else {
            $runnerTask = Get-ScheduledTask -TaskName 'BlackGold-GitHubRunner' -ErrorAction SilentlyContinue
            if ($runnerTask) {
                Start-ScheduledTask -TaskName 'BlackGold-GitHubRunner'
                Write-Log 'RUNNER_START_TASK_DISPATCHED'
            }
        }
    } catch {
        Write-Log ('RUNNER_REPAIR_WARNING ' + $_.Exception.Message)
    }
}
catch {
    $message = $_.Exception.Message
    Write-Log ('FAILED ' + $message)
    [ordered]@{
        schema = 1
        status = 'FAILED'
        time = (Get-Date).ToString('o')
        project = 'Orcamento no Ponto'
        error = $message
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Receipt -Encoding UTF8
    exit 1
}
