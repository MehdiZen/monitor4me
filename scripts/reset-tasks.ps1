#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Repart de zero : tue tous les process PC Monitor, supprime toutes les taches,
  nettoie le registre, puis recrée exactement 4 taches (une seule fois chacune).
.NOTES
  Lancer depuis PowerShell eleve :
    powershell -ExecutionPolicy Bypass -File "C:\Dev\pc-monitor\scripts\reset-tasks.ps1"
#>

param(
  [string]$LhmPath      = "C:\Tools\LibreHardwareMonitor\LibreHardwareMonitor.exe",
  [string]$InfluxdPath  = "C:\Program Files\InfluxDB\influxd.exe",
  [string]$CollectorDir = "C:\Dev\pc-monitor\collector",
  [string]$AppExe       = "C:\Dev\pc-monitor\app\src-tauri\target\release\pc-monitor-app.exe",
  [string]$NodePath     = "",
  [string]$UserName     = $env:USERNAME
)

$ErrorActionPreference = "Stop"

if (-not $NodePath) {
  $n = Get-Command node -ErrorAction SilentlyContinue
  if ($n) { $NodePath = $n.Source }
  else { throw "node.exe absent du PATH. Installez Node.js 20 LTS." }
}

# ── 1. Tuer tous les process lies au monitoring ───────────────────────────────
Write-Host "Arret des process..." -ForegroundColor Yellow

$toKill = @("LibreHardwareMonitor", "influxd", "node", "pc-monitor-app")
foreach ($name in $toKill) {
  $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
  if ($procs) {
    $procs | Stop-Process -Force
    Write-Host "  Killed : $name ($($procs.Count) instance(s))"
  }
}
Start-Sleep 2

# ── 2. Supprimer TOUTES les taches PC-Monitor-* ───────────────────────────────
Write-Host "Suppression des anciennes taches..." -ForegroundColor Yellow

Get-ScheduledTask -TaskName "PC-Monitor-*" -ErrorAction SilentlyContinue | ForEach-Object {
  Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
  Write-Host "  Supprime : $($_.TaskName)"
}

# ── 3. Nettoyer le registre autostart ────────────────────────────────────────
Write-Host "Nettoyage registre autostart..." -ForegroundColor Yellow

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
foreach ($name in @("PC Monitor", "LibreHardwareMonitor")) {
  if ((Get-ItemProperty $runKey -ErrorAction SilentlyContinue).$name) {
    Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
    Write-Host "  Supprime : HKCU Run > $name"
  }
}

# Desactiver le demarrage auto de LHM dans son propre fichier de config
$lhmConfig = "$env:APPDATA\LibreHardwareMonitor\LibreHardwareMonitor.config"
if (Test-Path $lhmConfig) {
  $xml = [xml](Get-Content $lhmConfig -Encoding UTF8)
  $node = $xml.SelectSingleNode("//setting[@name='runOnStartup']/value")
  if ($node -and $node.InnerText -ne "false") {
    $node.InnerText = "false"
    $xml.Save($lhmConfig)
    Write-Host "  LHM config : runOnStartup desactive"
  }
}

# ── 4. Creer les 4 taches proprement ─────────────────────────────────────────
Write-Host ""
Write-Host "Creation des taches..." -ForegroundColor Cyan

$noLimit  = [TimeSpan]::Zero
$restart1 = New-TimeSpan -Minutes 1
$userPrin = New-ScheduledTaskPrincipal -UserId $UserName -LogonType Interactive -RunLevel Highest
$svcPrin  = New-ScheduledTaskPrincipal -UserId "SYSTEM"  -LogonType ServiceAccount -RunLevel Highest

function New-PCTask {
  param($Name, $Action, $Trigger, $Principal, $Settings, $Desc)
  Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger `
    -Principal $Principal -Settings $Settings -Description $Desc -Force | Out-Null
  Write-Host "  OK : $Name"
}

# --- InfluxDB (utilisateur courant, demarre a la connexion, fenetre cachee) ---
if (Test-Path $InfluxdPath) {
  $t      = New-ScheduledTaskTrigger -AtLogOn -User $UserName
  $s      = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 5 -RestartInterval $restart1 -StartWhenAvailable
  $influxCmd = "-NonInteractive -WindowStyle Hidden -Command `"& '$InfluxdPath'`""
  New-PCTask "PC-Monitor-InfluxDB" `
    (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $influxCmd -WorkingDirectory (Split-Path $InfluxdPath)) `
    $t $userPrin $s "InfluxDB 2.x pour PC Monitor (port 8086)"
} else {
  Write-Warning "influxd.exe introuvable ($InfluxdPath) -- tache InfluxDB ignoree"
}

# --- LHM (utilisateur, demarre a la connexion) ---
if (Test-Path $LhmPath) {
  $t   = New-ScheduledTaskTrigger -AtLogOn -User $UserName
  $s   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
  $cmd = "-NonInteractive -WindowStyle Hidden -Command `"Start-Process '$LhmPath' -WindowStyle Minimized`""
  New-PCTask "PC-Monitor-LHM" `
    (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $cmd) `
    $t $userPrin $s "LibreHardwareMonitor REST :8085"
} else {
  Write-Warning "LHM introuvable ($LhmPath) -- tache LHM ignoree"
}

# --- Collector (utilisateur, 25s apres connexion, fenetre cachee) ---
$t = New-ScheduledTaskTrigger -AtLogOn -User $UserName
$t.Delay = "PT25S"
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
$collectorCmd = "-NonInteractive -WindowStyle Hidden -Command `"& '$NodePath' '$CollectorDir\dist\index.js'`""
New-PCTask "PC-Monitor-Collector" `
  (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $collectorCmd -WorkingDirectory $CollectorDir) `
  $t $userPrin $s "Collecteur PC Monitor : LHM -> InfluxDB + WS :8088"

# --- App PC Monitor (utilisateur, 30s apres connexion) ---
if (Test-Path $AppExe) {
  $t = New-ScheduledTaskTrigger -AtLogOn -User $UserName
  $t.Delay = "PT30S"
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -StartWhenAvailable
  New-PCTask "PC-Monitor-App" `
    (New-ScheduledTaskAction -Execute $AppExe -WorkingDirectory (Split-Path $AppExe)) `
    $t $userPrin $s "PC Monitor dashboard (Tauri)"
} else {
  Write-Warning "App introuvable ($AppExe) -- tache App ignoree. Lance npm run build:app d'abord."
}

# ── 5. Verification ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Taches enregistrees :" -ForegroundColor Green
Get-ScheduledTask -TaskName "PC-Monitor-*" | Select-Object TaskName, State | Format-Table -AutoSize

# ── 6. Demarrage immediat ─────────────────────────────────────────────────────
Write-Host "Demarrage immediat..." -ForegroundColor Cyan

if (Get-ScheduledTask -TaskName "PC-Monitor-InfluxDB" -ErrorAction SilentlyContinue) {
  Start-ScheduledTask -TaskName "PC-Monitor-InfluxDB"
  Write-Host "  InfluxDB lance."
  Start-Sleep 3
}
if (Get-ScheduledTask -TaskName "PC-Monitor-LHM" -ErrorAction SilentlyContinue) {
  Start-ScheduledTask -TaskName "PC-Monitor-LHM"
  Write-Host "  LHM lance."
}
Write-Host "  Attente 25s pour le collector..."
Start-Sleep 25
Start-ScheduledTask -TaskName "PC-Monitor-Collector"
Write-Host "  Collector lance."

if (Get-ScheduledTask -TaskName "PC-Monitor-App" -ErrorAction SilentlyContinue) {
  Start-Sleep 5
  Start-ScheduledTask -TaskName "PC-Monitor-App"
  Write-Host "  App lancee."
}

Write-Host ""
Write-Host "Termine. A chaque demarrage Windows exactement :" -ForegroundColor Green
Write-Host "  1. InfluxDB   (SYSTEM, port 8086)"
Write-Host "  2. LHM        (tray, port 8085)"
Write-Host "  3. Collector  (+25s, WS port 8088)"
Write-Host "  4. PC Monitor (+30s, dashboard)"
