@echo off
echo.
echo  monitor4me - Installeur
echo  ========================
echo.
echo  Telechargement de l'installeur depuis GitHub...
echo.
powershell -ExecutionPolicy Bypass -Command ^
  "$tmp = Join-Path $env:TEMP 'monitor4me-install.ps1';" ^
  "try {" ^
  "  Invoke-WebRequest -Uri 'https://github.com/MehdiZen/monitor4me/releases/latest/download/install.ps1' -OutFile $tmp -UseBasicParsing;" ^
  "  & powershell -ExecutionPolicy Bypass -File $tmp;" ^
  "  Remove-Item $tmp -Force -ErrorAction SilentlyContinue;" ^
  "} catch {" ^
  "  Write-Host '' ;" ^
  "  Write-Host '  ERREUR : impossible de telecharger l installeur.' -ForegroundColor Red;" ^
  "  Write-Host '  Verifie ta connexion internet et reessaie.' -ForegroundColor Yellow;" ^
  "  Write-Host '' ;" ^
  "}"
pause
