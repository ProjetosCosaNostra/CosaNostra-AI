$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$target = Join-Path $repoRoot 'control-plane\bootstrap.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('BlackGold-Integrity-' + [guid]::NewGuid().ToString('N') + '.bin')

function Get-BGGitBlobSha {
    param([Parameter(Mandatory=$true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes(('blob ' + [string]$bytes.Length))

    $payload = New-Object byte[] ($header.Length + 1 + $bytes.Length)
    [System.Array]::Copy($header, 0, $payload, 0, $header.Length)
    $payload[$header.Length] = 0
    [System.Array]::Copy($bytes, 0, $payload, $header.Length + 1, $bytes.Length)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        return (($sha1.ComputeHash($payload) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha1.Dispose()
    }
}

try {
    $calculated = Get-BGGitBlobSha -Path $target
    $git = (& git hash-object -- $target).Trim()

    if ($LASTEXITCODE -ne 0) { throw 'git hash-object failed.' }
    if ($calculated -ne $git) {
        throw ('Git blob implementation mismatch calculated=' + $calculated + ' git=' + $git)
    }

    Copy-Item -LiteralPath $target -Destination $temp
    [System.IO.File]::AppendAllText($temp, [Environment]::NewLine + 'tamper')
    $tampered = Get-BGGitBlobSha -Path $temp

    if ($tampered -eq $git) {
        throw 'Tampered file unexpectedly preserved Git blob identity.'
    }

    $bootstrap = Get-Content -LiteralPath $target -Raw
    foreach ($token in @('PinnedCommit','git/trees/','Get-BGGitBlobSha','integrity_verified','install-state.json')) {
        if ($bootstrap -notmatch [regex]::Escape($token)) {
            throw ('Integrity bootstrap token missing: ' + $token)
        }
    }

    Write-Host ('BLACKGOLD_GIT_BLOB_INTEGRITY_PASS blob=' + $git)
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
