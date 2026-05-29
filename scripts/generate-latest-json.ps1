<#
.SYNOPSIS
  Genere latest.json pour le Tauri auto-updater a partir du build signe.
  Prerequis : avoir lance build-signed.ps1 qui cree le .sig via createUpdaterArtifacts.

.PARAMETER Version
  Version de la release (ex: "1.0.0")

.PARAMETER Notes
  Notes de version (ex: "Corrections de bugs")

.EXAMPLE
  .\scripts\generate-latest-json.ps1 -Version "1.0.0" -Notes "Premiere release"
#>

param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$ROOT   = "$PSScriptRoot\.."
$BUNDLE = "$ROOT\app\src-tauri\target\release\bundle\nsis"
$OUT    = "$ROOT\latest.json"
$REPO   = "MehdiZen/monitor4me"

Write-Host ""
Write-Host "  Generation de latest.json pour v$Version..." -ForegroundColor Cyan

# ── Cherche le .nsis.zip.sig (cree par createUpdaterArtifacts) ────────────────
# Tauri v2 cree : monitor4me_X.Y.Z_x64-setup.nsis.zip + .nsis.zip.sig
$sigFile = Get-ChildItem $BUNDLE -Filter "*.nsis.zip.sig" -ErrorAction SilentlyContinue | Select-Object -First 1
$zipFile = Get-ChildItem $BUNDLE -Filter "*.nsis.zip"     -ErrorAction SilentlyContinue | Select-Object -First 1

# Fallback : certaines versions Tauri signent le .exe directement
if (-not $sigFile) {
    $sigFile = Get-ChildItem $BUNDLE -Filter "*-setup.exe.sig" -ErrorAction SilentlyContinue | Select-Object -First 1
    $zipFile = Get-ChildItem $BUNDLE -Filter "*-setup.exe"     -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not $sigFile) {
    Write-Host ""
    Write-Host "  ERREUR : aucun fichier .sig trouve dans $BUNDLE" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Solutions :" -ForegroundColor Yellow
    Write-Host "  1. Lance build-signed.ps1 (pas build:app qui utilise --no-bundle)" -ForegroundColor Yellow
    Write-Host "  2. Verifie que TAURI_SIGNING_PRIVATE_KEY est bien le CONTENU de la cle" -ForegroundColor Yellow
    Write-Host "  3. Verifie que createUpdaterArtifacts = true dans tauri.conf.json" -ForegroundColor Yellow
    exit 1
}

if (-not $zipFile) {
    throw "Fichier bundle introuvable dans $BUNDLE (attendu en meme temps que $($sigFile.Name))"
}

$signature   = (Get-Content $sigFile.FullName -Raw).Trim()
$downloadUrl = "https://github.com/$REPO/releases/download/v$Version/$($zipFile.Name)"
$pubDate     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "  Signature   : $($sigFile.Name)" -ForegroundColor DarkGray
Write-Host "  Bundle      : $($zipFile.Name)" -ForegroundColor DarkGray

# ── Genere latest.json ────────────────────────────────────────────────────────
$json = [ordered]@{
    version   = $Version
    notes     = $Notes
    pub_date  = $pubDate
    platforms = [ordered]@{
        "windows-x86_64" = [ordered]@{
            signature = $signature
            url       = $downloadUrl
        }
    }
} | ConvertTo-Json -Depth 5

$json | Set-Content $OUT -Encoding UTF8

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  latest.json genere : $OUT" -ForegroundColor Green
Write-Host "  Version   : $Version"
Write-Host "  Bundle    : $($zipFile.Name)"
Write-Host "  URL       : $downloadUrl"
Write-Host ""
Write-Host "  Etapes suivantes :" -ForegroundColor Cyan
Write-Host "  1. gh release create v$Version ``" -ForegroundColor White
Write-Host "       ""app\src-tauri\target\release\bundle\nsis\$($zipFile.Name)"" ``" -ForegroundColor White
Write-Host "       ""latest.json"" ""install.ps1"" ""monitor4me-install.bat"" ``" -ForegroundColor White
Write-Host "       --title ""monitor4me v$Version"" --notes ""$Notes""" -ForegroundColor White
Write-Host ""
