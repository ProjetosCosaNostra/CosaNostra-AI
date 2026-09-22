$ErrorActionPreference = 'Stop'
$BootstrapUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/CosaNostra-AI/main/control-plane/bootstrap.ps1'
$source = (Invoke-WebRequest -UseBasicParsing -Uri ($BootstrapUrl + '?repair=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())).Content
& ([ScriptBlock]::Create($source))
