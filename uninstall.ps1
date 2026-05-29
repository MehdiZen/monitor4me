#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Desinstalle monitor4me etape par etape avec confirmation.
  Ne supprime PAS Node.js, InfluxDB (binaire) ou LHM (outils independants).
.NOTES
  Lancement :
    powershell -ExecutionPolicy Bypass -File "uninstall.ps1"
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ROOT = $PSScriptRoot

function Ask([string]$prompt, [bool]$defaultYes = $false) {
    $hint = if ($defaultYes) { "(O/n)" } else { "(o/N)" }
    $ans  = Read-Host "  └─ $prompt $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    return ($ans -match '^[oOyY]$')
}

function Write-Step([string]$title) {
    Write-Host ""
    Write-Host "  ┌─ $title" -ForegroundColor Cyan
}

function Write-OK  ([string]$m) { Write-Host "  |  OK  $m" -ForegroundColor Green   }
function Write-Info([string]$m) { Write-Host "  |  ·   $m" -ForegroundColor Gray    }
function Write-Skip([string]$m) { Write-Host "  |  --  $m" -ForegroundColor DarkGray }
function Write-Warn([string]$m) { Write-Host "  |  /!\ $m" -ForegroundColor Yellow  }

# ── Bienvenue ─────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host "    monitor4me  --  Desinstallation               " -ForegroundColor Yellow
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Ce script supprime uniquement les elements propres a monitor4me."
Write-Host "  Node.js, InfluxDB (binaire) et LHM ne seront PAS touches."
Write-Host "  Chaque etape demandera ta confirmation."
Write-Host ""

if (-not (Ask "Continuer ?" $false)) {
    Write-Host "  Annule." -ForegroundColor Gray
    exit 0
}

# ── 1. Arret des processus ────────────────────────────────────────────────────

Write-Step "Arret des processus monitor4me"

$procs = @("influxd", "LibreHardwareMonitor", "node")
$running = $procs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }

if ($running.Count -gt 0) {
    Write-Info "Processus actifs detectes : $($running -join ', ')"
    if (Ask "Arreter ces processus maintenant ?") {
        foreach ($p in $running) {
            Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
            Write-OK "Arrete : $p"
        }
    } else {
        Write-Skip "Processus conserves."
    }
} else {
    Write-Skip "Aucun processus monitor4me actif."
}

# ── 2. Taches planifiees ──────────────────────────────────────────────────────

Write-Step "Taches planifiees"

$taskNames = @("PC-Monitor-Collector", "PC-Monitor-LHM", "PC-Monitor-InfluxDB")
$existing  = $taskNames | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue }

if ($existing.Count -gt 0) {
    Write-Info "Taches trouvees : $($existing -join ', ')"
    if (Ask "Supprimer ces taches planifiees ?") {
        foreach ($t in $existing) {
            Stop-ScheduledTask       -TaskName $t -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
            Write-OK "Supprimee : $t"
        }
    } else {
        Write-Skip "Taches conservees."
    }
} else {
    Write-Skip "Aucune tache PC-Monitor-* trouvee."
}

# ── 3. Variable INFLUX_TOKEN ──────────────────────────────────────────────────

Write-Step "Variable d'environnement INFLUX_TOKEN"

$token = [System.Environment]::GetEnvironmentVariable("INFLUX_TOKEN", "User")
if ($token) {
    Write-Info "INFLUX_TOKEN presente (debut : $($token.Substring(0, [Math]::Min(16, $token.Length)))...)"
    if (Ask "Supprimer INFLUX_TOKEN ?") {
        [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $null, "User")
        Write-OK "INFLUX_TOKEN supprimee"
    } else {
        Write-Skip "INFLUX_TOKEN conservee."
    }
} else {
    Write-Skip "INFLUX_TOKEN non presente."
}

# ── 4. Raccourcis bureau ──────────────────────────────────────────────────────

Write-Step "Raccourcis bureau"

$desktop  = [System.Environment]::GetFolderPath("Desktop")
$lnkPaths = @("$desktop\monitor4me.lnk", "$desktop\PC Monitor.lnk")
$foundLnk = $lnkPaths | Where-Object { Test-Path $_ }

if ($foundLnk.Count -gt 0) {
    foreach ($l in $foundLnk) {
        Write-Info "Trouve : $l"
        if (Ask "Supprimer ce raccourci ?") {
            Remove-Item $l -Force -ErrorAction SilentlyContinue
            Write-OK "Supprime."
        } else {
            Write-Skip "Conserve."
        }
    }
} else {
    Write-Skip "Aucun raccourci monitor4me sur le bureau."
}

# ── 5. Autostart registre ─────────────────────────────────────────────────────

Write-Step "Entree autostart registre (si presente)"

$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
foreach ($name in @("pc-monitor-app", "monitor4me")) {
    if (Get-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue) {
        Write-Info "Entree registre trouvee : $name"
        if (Ask "Supprimer l'entree autostart '$name' ?") {
            Remove-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue
            Write-OK "Supprimee."
        } else {
            Write-Skip "Conservee."
        }
    }
}

# ── 6. Fichiers de build ──────────────────────────────────────────────────────

Write-Step "Fichiers de build (regenerables)"

$buildDirs = @(
    "$ROOT\collector\dist",
    "$ROOT\collector\node_modules",
    "$ROOT\app\dist",
    "$ROOT\app\node_modules",
    "$ROOT\app\src-tauri\target"
)
$presentBuilds = $buildDirs | Where-Object { Test-Path $_ }

if ($presentBuilds.Count -gt 0) {
    Write-Info "Ces dossiers peuvent etre regeneres avec npm run build."
    $presentBuilds | ForEach-Object { Write-Info "  · $_" }
    if (Ask "Supprimer les dossiers de build (dist/, node_modules/, target/) ?" $false) {
        foreach ($d in $presentBuilds) {
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Supprime : $d"
        }
    } else {
        Write-Skip "Dossiers de build conserves."
    }
} else {
    Write-Skip "Aucun dossier de build present."
}

# ── 7. Configuration utilisateur ─────────────────────────────────────────────

Write-Step "Configuration utilisateur"

$userConfig = "$ROOT\collector\user-config.json"
if (Test-Path $userConfig) {
    Write-Info "user-config.json contient : tarif kWh, periph watts, seuils."
    if (Ask "Supprimer user-config.json (perdu definitivement) ?" $false) {
        Remove-Item $userConfig -Force -ErrorAction SilentlyContinue
        Write-OK "Supprime."
    } else {
        Write-Skip "Conserve."
    }
} else {
    Write-Skip "user-config.json absent."
}

# ── 8. Donnees InfluxDB ───────────────────────────────────────────────────────

Write-Step "Donnees InfluxDB (metriques historiques)"

$influxData = "$env:USERPROFILE\.influxdbv2"
if (Test-Path $influxData) {
    Write-Warn "ATTENTION : cette action efface tout l'historique des metriques."
    Write-Info "Dossier : $influxData"
    if (Ask "Supprimer les donnees InfluxDB (IRREVERSIBLE) ?" $false) {
        Remove-Item $influxData -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Donnees InfluxDB supprimees."
    } else {
        Write-Skip "Donnees InfluxDB conservees."
    }
} else {
    Write-Skip "Dossier de donnees InfluxDB absent."
}

# ── Resume ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "  Desinstallation terminee." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Outils independants conserves (non touches) :"
Write-Host "    - Node.js     Parametres Windows > Applications"
Write-Host "    - InfluxDB    Parametres Windows > Applications"
Write-Host "    - LHM         supprime son dossier manuellement"
Write-Host "    - Rust        rustup self uninstall"
Write-Host ""
