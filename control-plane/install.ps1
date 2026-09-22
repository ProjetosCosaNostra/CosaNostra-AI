$ErrorActionPreference = 'Stop'

$Repository = 'ProjetosCosaNostra/CosaNostra-AI'
$StableRef = 'control-plane-stable'
$Headers = @{ 'User-Agent' = 'BlackGold-ControlPlane/1.6' }
$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$branchInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/branches/' + $StableRef + '?t=' + $nonce)
$StableCommit = [string]$branchInfo.commit.sha
if ($StableCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve immutable stable commit.' }

$PinnedBase = 'https://raw.githubusercontent.com/' + $Repository + '/' + $StableCommit + '/control-plane'
$latest = Invoke-RestMethod -UseBasicParsing -Uri ($PinnedBase + '/LATEST.json?t=' + $nonce)

$bootstrapSource = (Invoke-WebRequest -UseBasicParsing -Uri ($PinnedBase + '/bootstrap.ps1?v=' + $latest.version + '&t=' + $nonce)).Content
& ([ScriptBlock]::Create($bootstrapSource)) -PinnedCommit $StableCommit
