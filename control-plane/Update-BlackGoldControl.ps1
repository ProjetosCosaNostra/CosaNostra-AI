$ErrorActionPreference = 'Stop'

$Repository = 'ProjetosCosaNostra/CosaNostra-AI'
$StableRef = 'control-plane-stable'
$Headers = @{ 'User-Agent' = 'BlackGold-ControlPlane/1.6' }
$InstallRoot = Join-Path $env:LOCALAPPDATA 'BlackGold\ControlPlane'
$LocalManifestPath = Join-Path $InstallRoot 'manifest.json'
$InstallStatePath = Join-Path $InstallRoot 'install-state.json'
$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$branchInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/branches/' + $StableRef + '?t=' + $nonce)
$StableCommit = [string]$branchInfo.commit.sha
if ($StableCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve immutable stable commit.' }

$PinnedBase = 'https://raw.githubusercontent.com/' + $Repository + '/' + $StableCommit + '/control-plane'
$remote = Invoke-RestMethod -UseBasicParsing -Uri ($PinnedBase + '/LATEST.json?t=' + $nonce)

$localVersion = '0.0.0'
$localCommit = ''

if (Test-Path -LiteralPath $LocalManifestPath) {
    try {
        $local = Get-Content -LiteralPath $LocalManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $localVersion = [string]$local.version
    } catch {}
}

if (Test-Path -LiteralPath $InstallStatePath) {
    try {
        $state = Get-Content -LiteralPath $InstallStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $localCommit = [string]$state.stable_commit
    } catch {}
}

if (($localVersion -eq [string]$remote.version) -and ($localCommit -eq $StableCommit)) {
    Write-Output ('BLACKGOLD_CONTROL_PLANE_UP_TO_DATE version=' + $localVersion + ' commit=' + $StableCommit)
    exit 0
}

Write-Output ('BLACKGOLD_CONTROL_PLANE_UPDATE ' + $localVersion + ' -> ' + [string]$remote.version + ' commit=' + $StableCommit)
$bootstrapSource = (Invoke-WebRequest -UseBasicParsing -Uri ($PinnedBase + '/bootstrap.ps1?v=' + $remote.version + '&t=' + $nonce)).Content
& ([ScriptBlock]::Create($bootstrapSource)) -PinnedCommit $StableCommit
