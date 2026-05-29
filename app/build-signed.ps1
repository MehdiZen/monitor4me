<#
.SYNOPSIS
  Build de production avec signature Tauri.
  Lit la cle privee depuis $env:USERPROFILE\.monitor4me-signing-key
  et l'injecte comme contenu dans TAURI_SIGNING_PRIVATE_KEY.

.NOTES
  La cle doit avoir ete generee avec :
    npx tauri signer generate -w "$env:USERPROFILE\.monitor4me-signing-key"
  Ne jamais committer la cle dans le repo git.
#>

$ErrorActionPreference = "Stop"

# Chemin fixe hors repo
$keyFile = "$env:USERPROFILE\.monitor4me-signing-key"

if (-not (Test-Path $keyFile)) {
    Write-Error "Cle de signature introuvable : $keyFile"
    Write-Host ""
    Write-Host "Generez-la avec :" -ForegroundColor Yellow
    Write-Host "  cd C:\Dev\pc-monitor\app" -ForegroundColor Yellow
    Write-Host "  npx tauri signer generate -w `"$keyFile`"" -ForegroundColor Yellow
    exit 1
}

# Lire le contenu de la cle (base64 minisign) -- TAURI_SIGNING_PRIVATE_KEY attend le CONTENU, pas le chemin
$env:TAURI_SIGNING_PRIVATE_KEY          = (Get-Content $keyFile -Raw).Trim()
$env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = ""

# S'assurer que cargo + npm sont dans le PATH
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH","User")   + ";" +
            "$env:USERPROFILE\.cargo\bin"

Set-Location "C:\Dev\pc-monitor\app"

Write-Host ""
Write-Host "  Build de production monitor4me avec signature..." -ForegroundColor Cyan
Write-Host "  Cle : $keyFile" -ForegroundColor DarkGray
Write-Host ""

# tauri:release = "tauri build" (avec bundle + createUpdaterArtifacts)
npm run tauri:release 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  Build termine. Verifiez la presence des .sig dans :" -ForegroundColor Green
    Write-Host "  src-tauri\target\release\bundle\nsis\" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Etape suivante : scripts\generate-latest-json.ps1 -Version '1.0.0'" -ForegroundColor Cyan
} else {
    Write-Error "Build echoue (code $LASTEXITCODE)"
}
