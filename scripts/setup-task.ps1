#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Enregistre 3 taches planifiees au demarrage de session :
    1. PC-Monitor-InfluxDB  (influxd.exe)
    2. PC-Monitor-LHM       (LibreHardwareMonitor.exe, minimise dans le tray)
    3. PC-Monitor-Collector (node dist/index.js, 25s apres LHM)
.NOTES
  Lancement direct depuis PowerShell eleve :
    powershell -ExecutionPolicy Bypass -File "scripts\setup-task.ps1"
  Parametres facultatifs si les chemins ne sont pas dans les emplacements par defaut.
#>

param(
    [string]$InfluxdPath  = "C:\Program Files\InfluxDB\influxd.exe",
    [string]$LhmPath      = "C:\Program Files\LibreHardwareMonitor\LibreHardwareMonitor.exe",
    [string]$CollectorDir = "",          # vide = auto-detecte depuis $PSScriptRoot
    [string]$UserName     = $env:USERNAME,
    [bool]  $StartNow     = $true        # $false quand appele depuis setup.ps1
)

$ErrorActionPreference = "Stop"

# Auto-detecte CollectorDir si non fourni
if (-not $CollectorDir) {
    $CollectorDir = (Resolve-Path "$PSScriptRoot\..\collector").Path
}

$NodePath = (Get-Command "node" -ErrorAction SilentlyContinue)?.Source
if (-not $NodePath) {
    throw "node.exe absent du PATH. Installe Node.js 20 LTS : https://nodejs.org"
}

# ── Avertissements chemins manquants ─────────────────────────────────────────
if (-not (Test-Path $InfluxdPath)) {
    Write-Warning "influxd.exe introuvable : $InfluxdPath"
    Write-Warning "Relance avec -InfluxdPath <chemin> ou installe InfluxDB."
}
if (-not (Test-Path $LhmPath)) {
    Write-Warning "LibreHardwareMonitor.exe introuvable : $LhmPath"
    Write-Warning "Relance avec -LhmPath <chemin> ou installe LHM."
}

# ── Helper : enregistre ou remplace une tache ─────────────────────────────────
function Register-PCTask {
    param($Name, $Action, $Trigger, $Principal, $Settings, $Desc)
    if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    }
    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger `
        -Principal $Principal -Settings $Settings -Description $Desc | Out-Null
    Write-Host "  OK  Tache enregistree : $Name" -ForegroundColor Green
}

# ── Parametres communs ────────────────────────────────────────────────────────
$atLogon  = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$userPrin = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Highest
$svcPrin  = New-ScheduledTaskPrincipal -UserId "SYSTEM"  -LogonType ServiceAccount -RunLevel Highest
$noLimit  = [TimeSpan]::Zero
$restart1 = New-TimeSpan -Minutes 1

Write-Host ""
Write-Host "  Enregistrement des taches planifiees..." -ForegroundColor Cyan
Write-Host "  Utilisateur : $UserName"
Write-Host "  Collector   : $CollectorDir"
Write-Host "  InfluxDB    : $InfluxdPath"
Write-Host "  LHM         : $LhmPath"
Write-Host ""

# ── 1. InfluxDB ───────────────────────────────────────────────────────────────
if (Test-Path $InfluxdPath) {
    $influxSettings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit $noLimit `
        -RestartCount 5 `
        -RestartInterval $restart1 `
        -StartWhenAvailable

    Register-PCTask `
        -Name      "PC-Monitor-InfluxDB" `
        -Action    (New-ScheduledTaskAction -Execute $InfluxdPath `
                        -WorkingDirectory (Split-Path $InfluxdPath)) `
        -Trigger   $atLogon `
        -Principal $svcPrin `
        -Settings  $influxSettings `
        -Desc      "InfluxDB 2.x pour monitor4me (port 8086)"
} else {
    Write-Host "  /!\ Tache PC-Monitor-InfluxDB ignoree (influxd.exe introuvable)" -ForegroundColor Yellow
}

# ── 2. LHM -- demarre minimise dans le tray via PowerShell ───────────────────
# Utilise un wrapper PS pour lancer LHM en fenetre minimisee (mode tray).
if (Test-Path $LhmPath) {
    $lhmCmd = "-NonInteractive -WindowStyle Hidden " +
              "-Command `"Start-Process '$LhmPath' -WindowStyle Minimized`""
    $lhmSettings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -StartWhenAvailable

    Register-PCTask `
        -Name      "PC-Monitor-LHM" `
        -Action    (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $lhmCmd) `
        -Trigger   $atLogon `
        -Principal $userPrin `
        -Settings  $lhmSettings `
        -Desc      "LibreHardwareMonitor REST :8085 pour monitor4me"
} else {
    Write-Host "  /!\ Tache PC-Monitor-LHM ignoree (LHM.exe introuvable)" -ForegroundColor Yellow
}

# ── 3. Collector Node.js -- demarre 25s apres la session ─────────────────────
# Delai pour laisser LHM et InfluxDB demarrer d'abord.
$collectorTrigger       = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$collectorTrigger.Delay = "PT25S"

$collectorSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit $noLimit `
    -RestartCount 10 `
    -RestartInterval $restart1 `
    -StartWhenAvailable

Register-PCTask `
    -Name      "PC-Monitor-Collector" `
    -Action    (New-ScheduledTaskAction `
                    -Execute $NodePath `
                    -Argument "$CollectorDir\dist\index.js" `
                    -WorkingDirectory $CollectorDir) `
    -Trigger   $collectorTrigger `
    -Principal $userPrin `
    -Settings  $collectorSettings `
    -Desc      "Collecteur monitor4me : LHM -> InfluxDB + WebSocket :8088"

# ── Build collecteur si dist/ absent ─────────────────────────────────────────
if (-not (Test-Path "$CollectorDir\dist\index.js")) {
    Write-Host ""
    Write-Host "  dist\index.js absent -- build du collecteur..." -ForegroundColor Yellow
    Push-Location $CollectorDir
    & npm install --silent
    & npm run build
    Pop-Location
    Write-Host "  OK  Build termine." -ForegroundColor Green
}

# ── Demarrage immediat (optionnel, desactive quand appele depuis setup.ps1) ───
if ($StartNow) {
    Write-Host ""
    Write-Host "  Demarrage immediat des services..." -ForegroundColor Cyan

    if (Test-Path $InfluxdPath) {
        Start-ScheduledTask -TaskName "PC-Monitor-InfluxDB" -ErrorAction SilentlyContinue
        Write-Host "  OK  InfluxDB lance." -ForegroundColor Green
    }
    if (Test-Path $LhmPath) {
        Start-ScheduledTask -TaskName "PC-Monitor-LHM" -ErrorAction SilentlyContinue
        Write-Host "  OK  LHM lance (tray)." -ForegroundColor Green
    }

    Write-Host "  ·   Attente 25s (LHM + InfluxDB)..." -ForegroundColor Gray
    Start-Sleep 25
    Start-ScheduledTask -TaskName "PC-Monitor-Collector" -ErrorAction SilentlyContinue
    Write-Host "  OK  Collector lance." -ForegroundColor Green
}

Write-Host ""
Write-Host "  Taches enregistrees. A la prochaine connexion Windows :" -ForegroundColor Cyan
Write-Host "    - InfluxDB   demarre en arriere-plan (port 8086)"
Write-Host "    - LHM        demarre dans le tray    (port 8085)"
Write-Host "    - Collector  demarre 25s apres       (WebSocket :8088)"
Write-Host ""
Write-Host "  Verification :"
Write-Host "    Get-ScheduledTask -TaskName 'PC-Monitor-*' | Select TaskName, State"
Write-Host ""
