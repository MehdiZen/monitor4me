<#
.SYNOPSIS
  Package le collecteur pre-compile pour la release GitHub.
  Genere collector-dist.zip contenant dist/ + node_modules (prod uniquement).
  A ajouter comme asset dans la release GitHub pour eviter que les
  utilisateurs aient a compiler le collecteur (npm install + tsc).

.NOTES
  Requiert que "npm run build" ait ete lance dans collector/ au prealable.
#>

$ErrorActionPreference = "Stop"
$ROOT         = "$PSScriptRoot\.."
$COLLECTOR    = "$ROOT\collector"
$DIST         = "$COLLECTOR\dist"
$NODEMODULES  = "$COLLECTOR\node_modules"
$OUTZIP       = "$ROOT\collector-dist.zip"

if (-not (Test-Path "$DIST\index.js")) {
    throw "dist/index.js introuvable. Lance d abord : cd collector && npm run build"
}

Write-Host ""
Write-Host "  Packaging du collecteur pre-compile..." -ForegroundColor Cyan

# Installe uniquement les deps de production dans un dossier temp
$tmpDir = "$env:TEMP\collector-package"
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
New-Item -ItemType Directory $tmpDir | Out-Null

# Copie dist/ et package.json
Copy-Item "$DIST"                   -Destination "$tmpDir\dist"        -Recurse
Copy-Item "$COLLECTOR\package.json" -Destination "$tmpDir\package.json"

# npm install --omit=dev dans le dossier temp
Write-Host "  Installation des dependances de production..."
Push-Location $tmpDir
& npm install --omit=dev --silent
Pop-Location

# Cree le zip
if (Test-Path $OUTZIP) { Remove-Item $OUTZIP -Force }
Compress-Archive -Path "$tmpDir\*" -DestinationPath $OUTZIP
Remove-Item $tmpDir -Recurse -Force

$size = [int]((Get-Item $OUTZIP).Length / 1MB)
Write-Host "  collector-dist.zip genere : $OUTZIP ($size MB)" -ForegroundColor Green
Write-Host ""
Write-Host "  Ajoute ce fichier a la release GitHub :"
Write-Host "  gh release upload vX.Y.Z collector-dist.zip"
Write-Host ""
