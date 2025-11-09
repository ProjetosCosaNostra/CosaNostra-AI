# ===============================
# LIMPAR_SUBMODULOS.PS1
# CosaNostra-AI - Ferramenta de limpeza e sincronização
# ===============================

$ErrorActionPreference = "Stop"
$startTime = Get-Date

Write-Host ""
Write-Host "===============================================" -ForegroundColor DarkGray
Write-Host "Iniciando limpeza de submódulos internos..." -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor DarkGray

# Lista de possíveis submódulos
$submodulos = @("Wav2Lip\.git", "backend\Wav2Lip\.git")

foreach ($sm in $submodulos) {
    if (Test-Path $sm) {
        Write-Host "Removendo repositório interno em: $sm" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $sm
    } else {
        Write-Host "Nenhum repositório interno encontrado em: $sm" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Atualizando repositório principal..." -ForegroundColor Cyan
git add . | Out-Null
git commit -m "fix: remover submódulos internos e sincronizar" | Out-Null

Write-Host ""
Write-Host "Verificando status atual..." -ForegroundColor Cyan
git status

Write-Host ""
Write-Host "Reconfigurando remoto..." -ForegroundColor Cyan
git remote remove origin -ErrorAction SilentlyContinue
git remote add origin https://github.com/ProjetosCosaNostra/CosaNostra-AI.git
git branch -M main

Write-Host ""
Write-Host "Enviando repositório limpo para o GitHub..." -ForegroundColor Cyan
git push origin main --force

# Finalização
$endTime = Get-Date
$elapsed = ($endTime - $startTime).ToString("mm\:ss")

Write-Host ""
Write-Host "===============================================" -ForegroundColor DarkGray
Write-Host "Operação concluída com sucesso!" -ForegroundColor Green
Write-Host ("Tempo total: {0} minutos" -f $elapsed) -ForegroundColor Yellow
Write-Host "Repositório sincronizado com honra e disciplina." -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor DarkGray

[console]::beep(800,250)
[console]::beep(1000,300)
