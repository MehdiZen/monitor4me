#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installe les prérequis et build l'app Tauri PC Monitor.
  À lancer une seule fois depuis PowerShell élevé.
#>

$ErrorActionPreference = "Stop"

Write-Host "=== PC Monitor — Installation ===" -ForegroundColor Cyan

# ── 1. Rust ───────────────────────────────────────────────────────────────────
if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) {
  Write-Host "`n[1/4] Installation de Rust (rustup)..."
  Invoke-WebRequest "https://win.rustup.rs/x86_64" -OutFile "$env:TEMP\rustup-init.exe"
  & "$env:TEMP\rustup-init.exe" -y --default-toolchain stable
  $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
} else {
  Write-Host "[1/4] Rust déjà installé : $(rustc --version)"
}

# ── 2. WebView2 (normalement déjà présent sur Windows 11) ────────────────────
Write-Host "`n[2/4] Vérification WebView2..."
$wv2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
if ($wv2) {
  Write-Host "  WebView2 présent : $($wv2.pv)"
} else {
  Write-Host "  WebView2 non trouvé — installation..."
  $installer = "$env:TEMP\MicrosoftEdgeWebview2Setup.exe"
  Invoke-WebRequest "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $installer
  & $installer /silent /install
}

# ── 3. Collector (ws dependency) ─────────────────────────────────────────────
Write-Host "`n[3/4] Build du collector..."
Push-Location "C:\Dev\pc-monitor\collector"
npm install
npm run build
Pop-Location
Write-Host "  Collector OK"

# ── 4. App Tauri ──────────────────────────────────────────────────────────────
Write-Host "`n[4/4] Build de l'app Tauri..."
Push-Location "C:\Dev\pc-monitor\app"
npm install

Write-Host "  Compilation Rust + bundle... (5-10 min la première fois)"
npm run tauri build

$installer = Get-ChildItem "src-tauri\target\release\bundle\msi\*.msi" -ErrorAction SilentlyContinue |
             Select-Object -First 1
if ($installer) {
  Write-Host "`n  Installeur généré : $($installer.FullName)" -ForegroundColor Green
  $answer = Read-Host "  Lancer l'installation ? (o/N)"
  if ($answer -eq "o") { Start-Process $installer.FullName }
} else {
  Write-Host "  App portable : src-tauri\target\release\pc-monitor-app.exe" -ForegroundColor Green
}

Pop-Location

Write-Host "`n=== Installation terminée ===" -ForegroundColor Green
Write-Host "Pour lancer en mode dev (sans build Rust) :"
Write-Host "  cd C:\Dev\pc-monitor\app && npm run tauri dev"
