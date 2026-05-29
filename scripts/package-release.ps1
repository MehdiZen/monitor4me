<#
.SYNOPSIS
  Cree monitor4me-v{Version}.zip — le seul fichier que l'utilisateur doit telecharger.
  Contient : monitor4me-install.bat + install.ps1

.PARAMETER Version
  Version de la release (ex: "1.0.0")

.EXAMPLE
  .\scripts\package-release.ps1 -Version "1.0.0"
#>

param(
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = "Stop"
$ROOT   = "$PSScriptRoot\.."
$OUTZIP = "$ROOT\monitor4me-v$Version.zip"

if (Test-Path $OUTZIP) { Remove-Item $OUTZIP -Force }

Compress-Archive -Path "$ROOT\monitor4me-install.bat", "$ROOT\install.ps1" -DestinationPath $OUTZIP

$size = [int]((Get-Item $OUTZIP).Length / 1KB)
Write-Host ""
Write-Host "  monitor4me-v$Version.zip cree ($size KB)" -ForegroundColor Green
Write-Host "  Contenu : monitor4me-install.bat + install.ps1"
Write-Host ""
Write-Host "  Uploade sur la release :"
Write-Host "  gh release upload v$Version monitor4me-v$Version.zip --clobber"
Write-Host ""
