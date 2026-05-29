<#
.SYNOPSIS
  Genere le fichier latest.json requis par le Tauri auto-updater.
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
$ROOT      = "$PSScriptRoot\.."
$BUNDLE    = "$ROOT\app\src-tauri\target\release\bundle"
$NSIS_DIR  = "$BUNDLE\nsis"
$OUT       = "$ROOT\latest.json"
$REPO      = "MehdiZen/monitor4me"

# Trouve le setup.exe et son .sig
$nsisExe = Get-ChildItem $NSIS_DIR -Filter "*-setup.exe" | Select-Object -First 1
$nsisSig = Get-ChildItem $NSIS_DIR -Filter "*-setup.exe.sig" | Select-Object -First 1

if (-not $nsisExe) { throw "Setup NSIS introuvable dans $NSIS_DIR. Lance d abord npm run tauri build." }
if (-not $nsisSig) { throw "Fichier .sig introuvable. Assure-toi que TAURI_SIGNING_PRIVATE_KEY est definie lors du build." }

$signature   = Get-Content $nsisSig.FullName -Raw
$downloadUrl = "https://github.com/$REPO/releases/download/v$Version/$($nsisExe.Name)"
$pubDate     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$json = @{
    version  = $Version
    notes    = $Notes
    pub_date = $pubDate
    platforms = @{
        "windows-x86_64" = @{
            signature = $signature.Trim()
            url       = $downloadUrl
        }
    }
} | ConvertTo-Json -Depth 5

$json | Set-Content $OUT -Encoding UTF8
Write-Host ""
Write-Host "  latest.json genere : $OUT" -ForegroundColor Green
Write-Host "  Version  : $Version"
Write-Host "  Download : $downloadUrl"
Write-Host ""
Write-Host "  Pour publier la release :"
Write-Host "  gh release create v$Version ``"
Write-Host "    `"app\src-tauri\target\release\bundle\nsis\$($nsisExe.Name)`" ``"
Write-Host "    `"latest.json`" ``"
Write-Host "    `"install.ps1`" ``"
Write-Host "    `"monitor4me-install.bat`" ``"
Write-Host "    --title `"monitor4me v$Version`" ``"
Write-Host "    --notes `"$Notes`""
Write-Host ""
