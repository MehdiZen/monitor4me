#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Supprime l'ancienne tache planifiee PC-Monitor-App et met a jour
  les taches PC-Monitor-* pour pointer vers monitor4me.exe
  Lancement : powershell -ExecutionPolicy Bypass -File "scripts\fix-startup.ps1"
#>

$ErrorActionPreference = "Stop"
$ROOT = "$PSScriptRoot\.."

Write-Host ""
Write-Host "  fix-startup : nettoyage des anciennes taches" -ForegroundColor Cyan
Write-Host ""

# ── 1. Supprime l'ancienne tache PC-Monitor-App ───────────────────────────────
$old = Get-ScheduledTask -TaskName "PC-Monitor-App" -ErrorAction SilentlyContinue
if ($old) {
    Stop-ScheduledTask       -TaskName "PC-Monitor-App" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "PC-Monitor-App" -Confirm:$false
    Write-Host "  OK  PC-Monitor-App supprimee" -ForegroundColor Green
} else {
    Write-Host "  --  PC-Monitor-App absente" -ForegroundColor DarkGray
}

# ── 2. Recrée les 3 taches avec les bons chemins ─────────────────────────────
Write-Host "  ·   Recreation des taches PC-Monitor-*..."
& powershell.exe -ExecutionPolicy Bypass -File "$ROOT\scripts\setup-task.ps1" -StartNow false
Write-Host "  OK  Taches a jour" -ForegroundColor Green

# ── 3. Verifie le registre ────────────────────────────────────────────────────
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$oldReg = Get-ItemProperty $regKey -Name "PC Monitor" -ErrorAction SilentlyContinue
if ($oldReg) {
    Remove-ItemProperty $regKey -Name "PC Monitor"
    Write-Host "  OK  Registre 'PC Monitor' supprime" -ForegroundColor Green
} else {
    Write-Host "  --  Registre deja propre" -ForegroundColor DarkGray
}

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Get-ScheduledTask -TaskName "PC-Monitor-*" | Select-Object TaskName, State
Write-Host ""
Write-Host "  Tout est propre. Plus de doublon au demarrage." -ForegroundColor Green
Write-Host ""
