$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$PolicyPath = Join-Path $InstallRoot 'policies\windows.json'
$LogDir = Join-Path $InstallRoot 'logs'
$LogPath = Join-Path $LogDir 'control-plane.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BGWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@

function Write-BGLog([string]$Message) {
    $stamp = (Get-Date).ToString('s')
    Add-Content -Path $LogPath -Value "[$stamp] $Message"
}

function Get-BGPolicy {
    try { return Get-Content $PolicyPath -Raw | ConvertFrom-Json } catch {
        return [pscustomobject]@{
            hide_visible_cmd = $true
            trace_cmd_origin = $true
            poll_interval_ms = 100
            refresh_policy_seconds = 60
            log_retention_days = 7
        }
    }
}

function Get-BGProcessInfo([uint32]$ProcessId) {
    try {
        $p = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $ProcessId) -ErrorAction Stop
        if (-not $p) { return $null }
        $parent = $null
        if ($p.ParentProcessId) {
            $parent = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $p.ParentProcessId) -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{
            Name = $p.Name
            ProcessId = $p.ProcessId
            ParentProcessId = $p.ParentProcessId
            CommandLine = $p.CommandLine
            ParentName = if ($parent) { $parent.Name } else { '' }
            ParentCommandLine = if ($parent) { $parent.CommandLine } else { '' }
        }
    } catch { return $null }
}

$seen = @{}
$policy = Get-BGPolicy
$lastPolicyRead = Get-Date

Get-ChildItem -Path $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-[int]$policy.log_retention_days) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

Write-BGLog ('agent-start version=1.7.3 user=' + $env:USERNAME)

while ($true) {
    if (((Get-Date) - $lastPolicyRead).TotalSeconds -ge [int]$policy.refresh_policy_seconds) {
        $policy = Get-BGPolicy
        $lastPolicyRead = Get-Date
    }

    if ($policy.hide_visible_cmd -eq $true) {
        [BGWin32]::EnumWindows({
            param($hWnd, $lParam)
            if (-not [BGWin32]::IsWindowVisible($hWnd)) { return $true }

            [uint32]$windowProcessId = 0
            [BGWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId) | Out-Null

            try {
                $proc = Get-Process -Id $windowProcessId -ErrorAction Stop
                if ($proc.ProcessName -ieq 'cmd') {
                    [BGWin32]::ShowWindowAsync($hWnd, 0) | Out-Null

                    if (-not $seen.ContainsKey([string]$windowProcessId)) {
                        $seen[[string]$windowProcessId] = Get-Date
                        if ($policy.trace_cmd_origin -eq $true) {
                            $info = Get-BGProcessInfo $windowProcessId
                            if ($info) {
                                Write-BGLog ("hidden-cmd pid={0} ppid={1} parent={2} cmd={3} parent_cmd={4}" -f $info.ProcessId,$info.ParentProcessId,$info.ParentName,$info.CommandLine,$info.ParentCommandLine)
                            } else {
                                Write-BGLog ("hidden-cmd pid=" + $windowProcessId)
                            }
                        } else {
                            Write-BGLog ("hidden-cmd pid=" + $windowProcessId)
                        }
                    }
                }
            } catch {}

            return $true
        }, [IntPtr]::Zero) | Out-Null
    }

    $deadKeys = @($seen.Keys | Where-Object {
        try { Get-Process -Id ([int]$_) -ErrorAction Stop | Out-Null; $false } catch { $true }
    })
    foreach ($key in $deadKeys) { $seen.Remove($key) }

    Start-Sleep -Milliseconds ([Math]::Max(50, [int]$policy.poll_interval_ms))
}
