#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Enregistre 3 taches planifiees au demarrage de session :
    1. InfluxDB  (influxd.exe)
    2. LHM       (LibreHardwareMonitor.exe, minimise dans le tray)
    3. Collector (node dist/index.js, 25s apres LHM)
  Lance aussi les taches immediatement sans reboot.
.NOTES
  Lancer une seule fois depuis PowerShell eleve :
    powershell -ExecutionPolicy Bypass -File "C:\Dev\pc-monitor\scripts\setup-task.ps1"
#>

param(
  [string]$LhmPath       = "C:\Tools\LibreHardwareMonitor\LibreHardwareMonitor.exe",
  [string]$InfluxdPath   = "C:\Program Files\InfluxDB\influxd.exe",
  [string]$CollectorDir  = "C:\Dev\pc-monitor\collector",
  [string]$NodePath      = "",
  [string]$UserName      = $env:USERNAME
)

if (-not $NodePath) {
  $NodePath = (Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
}

$ErrorActionPreference = "Stop"

# ── Validation ────────────────────────────────────────────────────────────────
if (-not (Test-Path $LhmPath)) {
  Write-Warning "LHM introuvable : $LhmPath -- editez le parametre -LhmPath"
}
if (-not (Test-Path $InfluxdPath)) {
  Write-Warning "influxd.exe introuvable : $InfluxdPath -- editez le parametre -InfluxdPath"
}
if (-not $NodePath) {
  throw "node.exe absent du PATH. Installez Node.js 20 LTS : https://nodejs.org"
}

# ── Helper : enregistre ou remplace une tache ─────────────────────────────────
function Register-PCTask {
  param($Name, $Action, $Trigger, $Principal, $Settings, $Desc)
  if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $Name -Confirm:$false
  }
  Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger `
    -Principal $Principal -Settings $Settings -Description $Desc | Out-Null
  Write-Host "  Tache enregistree : $Name"
}

# Parametres communs
$atLogon  = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$userPrin = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Highest
$svcPrin  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$noLimit  = [TimeSpan]::Zero
$restart1 = New-TimeSpan -Minutes 1   # minimum accepte par Task Scheduler

# ── 1. InfluxDB ───────────────────────────────────────────────────────────────
$influxSettings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit $noLimit `
  -RestartCount 5 `
  -RestartInterval $restart1 `
  -StartWhenAvailable

Register-PCTask `
  -Name       "PC-Monitor-InfluxDB" `
  -Action     (New-ScheduledTaskAction -Execute $InfluxdPath -WorkingDirectory (Split-Path $InfluxdPath)) `
  -Trigger    $atLogon `
  -Principal  $svcPrin `
  -Settings   $influxSettings `
  -Desc       "InfluxDB 2.x pour PC Monitor (port 8086)"

# ── 2. LHM — demarre minimise dans le tray via PowerShell ────────────────────
# On appelle powershell -WindowStyle Hidden pour ne pas afficher de fenetre.
# LHM demarre dans le tray grace au flag de session utilisateur (config dans %APPDATA%).
$lhmCmd = "-NonInteractive -WindowStyle Hidden -Command `"Start-Process '$LhmPath' -WindowStyle Minimized`""
$lhmAction   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $lhmCmd
$lhmSettings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
  -StartWhenAvailable

Register-PCTask `
  -Name       "PC-Monitor-LHM" `
  -Action     $lhmAction `
  -Trigger    $atLogon `
  -Principal  $userPrin `
  -Settings   $lhmSettings `
  -Desc       "LibreHardwareMonitor REST :8085 pour PC Monitor"

# ── 3. Collector Node.js — demarre 25s apres la session ─────────────────────
# Delai pour laisser LHM et InfluxDB se lancer d'abord.
$collectorTrigger = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$collectorTrigger.Delay = "PT25S"

$collectorSettings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit $noLimit `
  -RestartCount 10 `
  -RestartInterval $restart1 `
  -StartWhenAvailable

Register-PCTask `
  -Name       "PC-Monitor-Collector" `
  -Action     (New-ScheduledTaskAction -Execute $NodePath -Argument "$CollectorDir\dist\index.js" -WorkingDirectory $CollectorDir) `
  -Trigger    $collectorTrigger `
  -Principal  $userPrin `
  -Settings   $collectorSettings `
  -Desc       "Collecteur PC Monitor : LHM -> InfluxDB + WebSocket :8088"

# ── Build du collector si pas encore fait ─────────────────────────────────────
if (-not (Test-Path "$CollectorDir\dist\index.js")) {
  Write-Host ""
  Write-Host "Build du collector (premiere fois)..."
  Push-Location $CollectorDir
  & npm install --silent
  & npm run build
  Pop-Location
  Write-Host "  Build termine."
}

# ── Demarrage immediat (sans reboot) ─────────────────────────────────────────
Write-Host ""
Write-Host "Demarrage des services..."

if (Test-Path $InfluxdPath) {
  Start-ScheduledTask -TaskName "PC-Monitor-InfluxDB"
  Write-Host "  InfluxDB lance."
}

if (Test-Path $LhmPath) {
  Start-ScheduledTask -TaskName "PC-Monitor-LHM"
  Write-Host "  LHM lance (tray)."
}

Write-Host "  Attente 25s avant le collector..."
Start-Sleep 25
Start-ScheduledTask -TaskName "PC-Monitor-Collector"
Write-Host "  Collector lance."

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Termine." -ForegroundColor Green
Write-Host "  A chaque demarrage de session Windows :"
Write-Host "    - InfluxDB   demarre en arriere-plan (port 8086)"
Write-Host "    - LHM        demarre dans le tray    (port 8085)"
Write-Host "    - Collector  demarre 25s apres       (port WebSocket 8088)"
Write-Host "    - PC Monitor demarre automatiquement (tauri autostart)"
Write-Host ""
Write-Host "  Pour verifier l'etat des taches :"
Write-Host "    Get-ScheduledTask -TaskName 'PC-Monitor-*' | Select TaskName, State"
