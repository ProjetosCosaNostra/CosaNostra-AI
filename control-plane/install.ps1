$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane'
$nonce = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$latest = Invoke-RestMethod -UseBasicParsing -Uri ($Base + '/LATEST.json?t=' + $nonce)
$bootstrapSource = (Invoke-WebRequest -UseBasicParsing -Uri ($latest.bootstrap_url + '?v=' + $latest.version + '&t=' + $nonce)).Content
& ([ScriptBlock]::Create($bootstrapSource))
