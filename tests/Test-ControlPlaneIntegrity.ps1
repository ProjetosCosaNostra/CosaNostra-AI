$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$target = Join-Path $repoRoot 'control-plane\bootstrap.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('BlackGold-Integrity-' + [guid]::NewGuid().ToString('N') + '.bin')

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
