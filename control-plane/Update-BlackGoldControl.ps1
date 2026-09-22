$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$LocalManifestPath = Join-Path $InstallRoot 'manifest.json'
$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$remote = Invoke-RestMethod -UseBasicParsing -Uri ($Base + '/LATEST.json?t=' + $nonce)
$localVersion = '0.0.0'

if (Test-Path -LiteralPath $LocalManifestPath) {
    try {
        $local = Get-Content -LiteralPath $LocalManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $localVersion = [string]$local.version
    } catch {}
}

if ($localVersion -eq [string]$remote.version) {
    Write-Output ('BLACKGOLD_CONTROL_PLANE_UP_TO_DATE version=' + $localVersion)
    exit 0
}

Write-Output ('BLACKGOLD_CONTROL_PLANE_UPDATE ' + $localVersion + ' -> ' + [string]$remote.version)
$bootstrapSource = (Invoke-WebRequest -UseBasicParsing -Uri ($remote.bootstrap_url + '?v=' + $remote.version + '&t=' + $nonce)).Content
& ([ScriptBlock]::Create($bootstrapSource))
