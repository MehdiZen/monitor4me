#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Desinstalle completement PC Monitor et ses dependances.

.PARAMETER Full
  Si specifie, desinstalle aussi Node.js, Rust et VS Build Tools.
  ATTENTION : ces outils peuvent etre utilises par d'autres projets.

.EXAMPLE
  # Supprime l'app, les services, LHM, InfluxDB (garde Node/Rust/VSBuildTools)
  powershell -ExecutionPolicy Bypass -File ".\uninstall.ps1"

  # Supprime absolument tout
  powershell -ExecutionPolicy Bypass -File ".\uninstall.ps1" -Full
#>

param(
  [switch]$Full,
  [switch]$Force   # pas de confirmation
)

$ErrorActionPreference = "Continue"

function Ask {
  param([string]$Msg)
  if ($Force) { return $true }
  $r = Read-Host "$Msg [O/N]"
  return $r -match "^[oOyY]"
}

function Remove-IfExists {
  param([string]$Path, [string]$Label)
  if (Test-Path $Path) {
    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Supprime : $Label"
  }
}

Write-Host ""
Write-Host "=== PC Monitor Uninstaller ===" -ForegroundColor Cyan
if ($Full) {
  Write-Host "  Mode FULL : Node.js, Rust, VS Build Tools seront aussi supprimes." -ForegroundColor Yellow
}
Write-Host ""

if (-not $Force) {
  Write-Host "Cette operation supprime :" -ForegroundColor Yellow
  Write-Host "  - Les 3 taches planifiees (InfluxDB, LHM, Collector)"
  Write-Host "  - L'entree autostart registre de l'app"
  Write-Host "  - Le raccourci bureau"
  Write-Host "  - Les dossiers C:\Tools\influxdb et C:\Tools\LibreHardwareMonitor"
  Write-Host "  - Les donnees InfluxDB (%USERPROFILE%\.influxdbv2)"
  Write-Host "  - Le dossier source C:\Dev\pc-monitor"
  Write-Host "  - La variable d'environnement INFLUX_TOKEN"
  if ($Full) {
    Write-Host "  - Node.js, Rust + Cargo, VS Build Tools" -ForegroundColor Yellow
  }
  Write-Host ""
  if (-not (Ask "Continuer")) {
    Write-Host "Annule." -ForegroundColor Gray
    exit 0
  }
}

# ── 1. Taches planifiees ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/8] Arret et suppression des taches planifiees..."

foreach ($task in @("PC-Monitor-InfluxDB", "PC-Monitor-LHM", "PC-Monitor-Collector")) {
  $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if ($t) {
    Stop-ScheduledTask  -TaskName $task -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Supprime : tache $task"
  }
}

# ── 2. Processus en cours ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/8] Arret des processus..."

foreach ($proc in @("influxd", "LibreHardwareMonitor", "pc-monitor-app")) {
  $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
  if ($p) {
    Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    Write-Host "  Arrete : $proc"
  }
}

# ── 3. Entree autostart registre ──────────────────────────────────────────────
Write-Host ""
Write-Host "[3/8] Suppression autostart registre..."

$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "pc-monitor-app"
if (Get-ItemProperty -Path $regKey -Name $regName -ErrorAction SilentlyContinue) {
  Remove-ItemProperty -Path $regKey -Name $regName -ErrorAction SilentlyContinue
  Write-Host "  Supprime : HKCU\...\Run\$regName"
}

# ── 4. Raccourci bureau ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/8] Suppression raccourci bureau..."

$shortcut = "$env:USERPROFILE\Desktop\PC Monitor.lnk"
Remove-IfExists $shortcut "raccourci bureau"

# ── 5. Outils (LHM + InfluxDB) ───────────────────────────────────────────────
Write-Host ""
Write-Host "[5/8] Suppression des outils..."

Remove-IfExists "C:\Tools\LibreHardwareMonitor" "C:\Tools\LibreHardwareMonitor"
Remove-IfExists "C:\Tools\influxdb"             "C:\Tools\influxdb"

# Supprime C:\Tools si vide
if ((Test-Path "C:\Tools") -and (-not (Get-ChildItem "C:\Tools" -ErrorAction SilentlyContinue))) {
  Remove-Item "C:\Tools" -Force -ErrorAction SilentlyContinue
  Write-Host "  Supprime : C:\Tools (vide)"
}

# ── 6. Donnees InfluxDB ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "[6/8] Suppression des donnees InfluxDB..."

$influxData = "$env:USERPROFILE\.influxdbv2"
if (Test-Path $influxData) {
  if ($Force -or (Ask "Supprimer les donnees InfluxDB ($influxData) ?")) {
    Remove-IfExists $influxData "donnees InfluxDB (~/.influxdbv2)"
  }
}

# Variable INFLUX_TOKEN
[System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $null, "User")
Write-Host "  Supprime : variable env INFLUX_TOKEN"

# ── 7. Source de l'app ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[7/8] Suppression du code source..."

$appDir = "C:\Dev\pc-monitor"
if (Test-Path $appDir) {
  if ($Force -or (Ask "Supprimer le dossier source ($appDir) ?")) {
    Remove-IfExists $appDir "C:\Dev\pc-monitor (source)"
  }
}

# ── 8. Optionnel : Node.js, Rust, VS Build Tools ─────────────────────────────
if ($Full) {
  Write-Host ""
  Write-Host "[8/8] Desinstallation Node.js / Rust / VS Build Tools..." -ForegroundColor Yellow
  Write-Host "  ATTENTION : ces outils peuvent etre utilises par d'autres projets." -ForegroundColor Yellow

  # Node.js
  $node = Get-Package -Name "Node.js*" -ErrorAction SilentlyContinue
  if ($node) {
    if ($Force -or (Ask "Desinstaller Node.js ($($node.Version)) ?")) {
      winget uninstall --id OpenJS.NodeJS --silent --accept-source-agreements 2>$null
      Write-Host "  Desinstalle : Node.js"
    }
  }

  # Rust / Cargo (rustup)
  $rustup = Get-Command rustup -ErrorAction SilentlyContinue
  if ($rustup) {
    if ($Force -or (Ask "Desinstaller Rust + Cargo (rustup) ?")) {
      & rustup self uninstall -y 2>$null
      Write-Host "  Desinstalle : Rust + Cargo"
    }
  }

  # VS Build Tools
  $vs = Get-Package -Name "Microsoft Visual Studio*Build Tools*" -ErrorAction SilentlyContinue
  if ($vs) {
    if ($Force -or (Ask "Desinstaller VS Build Tools ? (long, ~4 GB liberes)")) {
      winget uninstall --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-source-agreements 2>$null
      Write-Host "  Desinstalle : VS Build Tools 2022"
    }
  }
} else {
  Write-Host ""
  Write-Host "[8/8] Node.js, Rust, VS Build Tools conserves (utiliser -Full pour les supprimer)."
}

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Desinstallation terminee." -ForegroundColor Green
Write-Host ""
Write-Host "Reste sur le systeme (si conserves) :"
if (-not $Full) {
  Write-Host "  - Node.js  : C:\Program Files\nodejs\"
  Write-Host "  - Rust     : %USERPROFILE%\.cargo\"
  Write-Host "  - VS BT    : C:\Program Files (x86)\Microsoft Visual Studio\"
}
Write-Host "  - WebView2 : composant Windows, non supprime (partage avec Edge)"
Write-Host ""
