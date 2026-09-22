$ErrorActionPreference = 'Stop'

$Repository = 'ProjetosCosaNostra/CosaNostra-AI'
$StableRef = 'control-plane-stable'
$Headers = @{ 'User-Agent' = 'BlackGold-ControlPlane/1.6' }
$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$branchInfo = Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri ('https://api.github.com/repos/' + $Repository + '/branches/' + $StableRef + '?t=' + $nonce)
$StableCommit = [string]$branchInfo.commit.sha
if ($StableCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve immutable stable commit.' }

$BootstrapUrl = 'https://raw.githubusercontent.com/' + $Repository + '/' + $StableCommit + '/control-plane/bootstrap.ps1'
$source = (Invoke-WebRequest -UseBasicParsing -Uri ($BootstrapUrl + '?repair=' + $nonce)).Content
& ([ScriptBlock]::Create($source)) -PinnedCommit $StableCommit
