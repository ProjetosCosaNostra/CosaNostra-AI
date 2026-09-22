$ErrorActionPreference = 'Stop'
$StableRef = 'control-plane-stable'
$BootstrapUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/' + $StableRef + '/control-plane/bootstrap.ps1'
$source = (Invoke-WebRequest -UseBasicParsing -Uri ($BootstrapUrl + '?repair=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content
& ([ScriptBlock]::Create($source))
