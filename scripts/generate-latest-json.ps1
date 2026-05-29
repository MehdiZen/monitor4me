<#
.SYNOPSIS
  Signe le bundle NSIS et genere latest.json pour le Tauri auto-updater.
  A executer apres chaque build, avant de publier la release GitHub.

.PARAMETER Version
  Version de la release (ex: "1.1.0")

.PARAMETER Notes
  Notes de version (ex: "Corrections de bugs")

.EXAMPLE
  .\scripts\generate-latest-json.ps1 -Version "1.1.0" -Notes "Bug fixes"
#>

param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$ROOT     = "$PSScriptRoot\.."
$BUNDLE   = "$ROOT\app\src-tauri\target\release\bundle\nsis"
$OUT      = "$ROOT\latest.json"
$REPO     = "MehdiZen/monitor4me"
$KEY_FILE = "$env:USERPROFILE\.monitor4me-signing-key"

# ── Verifications ─────────────────────────────────────────────────────────────
$nsisExe = Get-ChildItem $BUNDLE -Filter "monitor4me*-setup.exe" | Select-Object -First 1
if (-not $nsisExe) { throw "Setup NSIS introuvable dans $BUNDLE. Lance d abord build-signed.ps1." }
if (-not (Test-Path $KEY_FILE)) { throw "Cle de signature introuvable : $KEY_FILE" }

# ── Signature ─────────────────────────────────────────────────────────────────
$sigFile = "$($nsisExe.FullName).sig"
Write-Host ""
Write-Host "  Signature de $($nsisExe.Name)..." -ForegroundColor Cyan
Set-Location "$ROOT\app"
& npx tauri signer sign -k $KEY_FILE "$($nsisExe.FullName)" 2>&1 | ForEach-Object { Write-Host "  $_" }

if (-not (Test-Path $sigFile)) {
    throw "Fichier .sig non genere. Verifie que la cle est valide."
}
$signature = Get-Content $sigFile -Raw
Write-Host "  Signature OK" -ForegroundColor Green

# ── Genere latest.json ────────────────────────────────────────────────────────
$downloadUrl = "https://github.com/$REPO/releases/download/v$Version/$($nsisExe.Name)"
$pubDate     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$json = [ordered]@{
    version   = $Version
    notes     = $Notes
    pub_date  = $pubDate
    platforms = [ordered]@{
        "windows-x86_64" = [ordered]@{
            signature = $signature.Trim()
            url       = $downloadUrl
        }
    }
} | ConvertTo-Json -Depth 5

$json | Set-Content $OUT -Encoding UTF8

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  latest.json genere : $OUT" -ForegroundColor Green
Write-Host "  Version   : $Version"
Write-Host "  Installer : $($nsisExe.Name)"
Write-Host "  URL       : $downloadUrl"
Write-Host ""
Write-Host "  Publication de la release :" -ForegroundColor Cyan
Write-Host "    gh release create v$Version \"app\src-tauri\target\release\bundle\nsis\$($nsisExe.Name)\" latest.json install.ps1 monitor4me-install.bat --title ""monitor4me v$Version"" --notes ""$Notes"""
Write-Host ""
