# ============================================
# COSANOSTRA AI - Limpeza de Submódulos Internos
# ============================================
# Autor: Don Felipe
# Data: 08/11/2025
# Descrição: Remove submódulos Git internos e sincroniza o repositório principal.
# ============================================

Write-Host ""
Write-Host "==== Iniciando limpeza dos submódulos internos ====" -ForegroundColor Cyan

# 1️⃣ Remover .git internos
$submodulos = @("Wav2Lip\.git", "backend\Wav2Lip\.git")

foreach ($sm in $submodulos) {
    if (Test-Path $sm) {
        Write-Host "Removendo repositório interno: $sm" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $sm -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "Nenhum repositório interno encontrado em: $sm" -ForegroundColor Green
    }
}

# 2️⃣ Atualizar e commitar
Write-Host ""
Write-Host "Atualizando repositório principal..." -ForegroundColor Cyan
git add .
git commit -m "fix: remover submódulos internos Wav2Lip e backend/Wav2Lip" | Out-Null

# 3️⃣ Verificar status
Write-Host ""
Write-Host "Verificando status atual do repositório..." -ForegroundColor Cyan
git status

# 4️⃣ Reconfigurar remoto e fazer push
Write-Host ""
Write-Host "Conectando ao repositório remoto..." -ForegroundColor Cyan
git remote remove origin -ErrorAction SilentlyContinue
git remote add origin https://github.com/ProjetosCosaNostra/CosaNostra-AI.git
git branch -M main

Write-Host ""
Write-Host "Enviando repositório limpo para o GitHub..." -ForegroundColor Cyan
git push origin main --force

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "Repositório limpo e sincronizado com sucesso!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
