$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$PolicyPath = Join-Path $InstallRoot 'policies\windows.json'
$LogDir = Join-Path $InstallRoot 'logs'
$LogPath = Join-Path $LogDir 'control-plane.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BGWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
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
        return [pscustomobject]@{ hide_visible_cmd = $true; poll_interval_ms = 250; refresh_policy_seconds = 60 }
    }
}

Write-BGLog 'agent-start'
$policy = Get-BGPolicy
$lastPolicyRead = Get-Date

while ($true) {
    if (((Get-Date) - $lastPolicyRead).TotalSeconds -ge [int]$policy.refresh_policy_seconds) {
        $policy = Get-BGPolicy
        $lastPolicyRead = Get-Date
    }

    if ($policy.hide_visible_cmd -eq $true) {
        [BGWin32]::EnumWindows({
            param($hWnd, $lParam)
            if (-not [BGWin32]::IsWindowVisible($hWnd)) { return $true }
            [uint32]$pid = 0
            [BGWin32]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null
            try {
                $p = Get-Process -Id $pid -ErrorAction Stop
                if ($p.ProcessName -ieq 'cmd') {
                    [BGWin32]::ShowWindowAsync($hWnd, 0) | Out-Null
                    Write-BGLog ("hidden-cmd pid=" + $pid)
                }
            } catch {}
            return $true
        }, [IntPtr]::Zero) | Out-Null
    }

    Start-Sleep -Milliseconds ([Math]::Max(100, [int]$policy.poll_interval_ms))
}
