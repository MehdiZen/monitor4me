#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Desinstalle monitor4me et ses dependances, etape par etape avec confirmation.
  Chaque outil (Node.js, InfluxDB, LHM, Rust) peut etre supprime ou conserve.
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

function Write-OK  ([string]$m) { Write-Host "  |  OK  $m" -ForegroundColor Green    }
function Write-Info([string]$m) { Write-Host "  |  ·   $m" -ForegroundColor Gray     }
function Write-Skip([string]$m) { Write-Host "  |  --  $m" -ForegroundColor DarkGray }
function Write-Warn([string]$m) { Write-Host "  |  /!\ $m" -ForegroundColor Yellow   }

# ── Bienvenue ─────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host "    monitor4me  --  Desinstallation               " -ForegroundColor Yellow
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Ce script supprime monitor4me et toutes ses dependances."
Write-Host "  Chaque etape demandera ta confirmation."
Write-Host ""
Write-Host "  Tu pourras choisir de :"
Write-Host "    · supprimer uniquement les fichiers monitor4me"
Write-Host "    · desinstaller aussi Node.js, InfluxDB, LHM, Rust"
Write-Host "      -> machine remise a zero, comme avant l installation"
Write-Host ""

if (-not (Ask "Continuer ?" $false)) {
    Write-Host "  Annule." -ForegroundColor Gray
    exit 0
}

# ── 1. Arret des processus ────────────────────────────────────────────────────

Write-Step "1  Arret des processus"

$procs   = @("influxd", "LibreHardwareMonitor", "node")
$running = $procs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }

if ($running.Count -gt 0) {
    Write-Info "Processus actifs : $($running -join ', ')"
    if (Ask "Arreter ces processus ?") {
        foreach ($p in $running) {
            Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
            Write-OK "Arrete : $p"
        }
    } else {
        Write-Skip "Conserves."
    }
} else {
    Write-Skip "Aucun processus monitor4me actif."
}

# ── 2. Taches planifiees ──────────────────────────────────────────────────────

Write-Step "2  Taches planifiees"

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
        Write-Skip "Conservees."
    }
} else {
    Write-Skip "Aucune tache PC-Monitor-* trouvee."
}

# ── 3. Variable INFLUX_TOKEN ──────────────────────────────────────────────────

Write-Step "3  Variable d'environnement INFLUX_TOKEN"

$token = [System.Environment]::GetEnvironmentVariable("INFLUX_TOKEN", "User")
if ($token) {
    Write-Info "INFLUX_TOKEN presente (debut : $($token.Substring(0, [Math]::Min(16, $token.Length)))...)"
    if (Ask "Supprimer INFLUX_TOKEN ?") {
        [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $null, "User")
        Write-OK "INFLUX_TOKEN supprimee"
    } else {
        Write-Skip "Conservee."
    }
} else {
    Write-Skip "INFLUX_TOKEN non presente."
}

# ── 4. Raccourcis et registre ─────────────────────────────────────────────────

Write-Step "4  Raccourcis bureau et autostart"

$desktop  = [System.Environment]::GetFolderPath("Desktop")
$lnkPaths = @("$desktop\monitor4me.lnk", "$desktop\PC Monitor.lnk")
$foundLnk = $lnkPaths | Where-Object { Test-Path $_ }

if ($foundLnk.Count -gt 0) {
    foreach ($l in $foundLnk) {
        Write-Info "Raccourci : $l"
        if (Ask "Supprimer ?") {
            Remove-Item $l -Force -ErrorAction SilentlyContinue
            Write-OK "Supprime."
        } else { Write-Skip "Conserve." }
    }
} else {
    Write-Skip "Aucun raccourci monitor4me sur le bureau."
}

$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
foreach ($name in @("pc-monitor-app", "monitor4me")) {
    if (Get-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue) {
        Write-Info "Autostart registre : $name"
        if (Ask "Supprimer l'entree autostart '$name' ?") {
            Remove-ItemProperty -Path $regKey -Name $name -ErrorAction SilentlyContinue
            Write-OK "Supprimee."
        } else { Write-Skip "Conservee." }
    }
}

# ── 5. Fichiers de build ──────────────────────────────────────────────────────

Write-Step "5  Fichiers de build (regenerables avec npm run build)"

$buildDirs     = @(
    "$ROOT\collector\dist",
    "$ROOT\collector\node_modules",
    "$ROOT\app\dist",
    "$ROOT\app\node_modules",
    "$ROOT\app\src-tauri\target"
)
$presentBuilds = $buildDirs | Where-Object { Test-Path $_ }

if ($presentBuilds.Count -gt 0) {
    $presentBuilds | ForEach-Object { Write-Info $_ }
    if (Ask "Supprimer ces dossiers ?" $false) {
        foreach ($d in $presentBuilds) {
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Supprime : $(Split-Path $d -Leaf)  ($d)"
        }
    } else { Write-Skip "Conserves." }
} else {
    Write-Skip "Aucun dossier de build present."
}

# ── 6. Configuration utilisateur ─────────────────────────────────────────────

Write-Step "6  Configuration utilisateur"

$userConfig = "$ROOT\collector\user-config.json"
if (Test-Path $userConfig) {
    Write-Info "user-config.json contient : tarif kWh, periph watts, seuils."
    if (Ask "Supprimer user-config.json ?" $false) {
        Remove-Item $userConfig -Force -ErrorAction SilentlyContinue
        Write-OK "Supprime."
    } else { Write-Skip "Conserve." }
} else {
    Write-Skip "user-config.json absent."
}

# ── 7. Donnees InfluxDB ───────────────────────────────────────────────────────

Write-Step "7  Donnees InfluxDB (metriques historiques)"

$influxData = "$env:USERPROFILE\.influxdbv2"
if (Test-Path $influxData) {
    Write-Warn "Efface tout l'historique des metriques (irreversible)."
    Write-Info "Dossier : $influxData"
    if (Ask "Supprimer les donnees InfluxDB ?" $false) {
        Remove-Item $influxData -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Donnees InfluxDB supprimees."
    } else { Write-Skip "Conservees." }
} else {
    Write-Skip "Donnees InfluxDB absentes."
}

# ── 8. LibreHardwareMonitor ───────────────────────────────────────────────────

Write-Step "8  LibreHardwareMonitor"

$lhmSearchPaths = @(
    "C:\Program Files\LibreHardwareMonitor",
    "C:\Tools\LibreHardwareMonitor",
    "$env:ProgramFiles\LibreHardwareMonitor",
    "$env:LOCALAPPDATA\LibreHardwareMonitor"
)
$lhmDir = $lhmSearchPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($lhmDir) {
    Write-Info "LHM trouve : $lhmDir"
    if (Ask "Supprimer LibreHardwareMonitor ?") {
        Stop-Process -Name "LibreHardwareMonitor" -Force -ErrorAction SilentlyContinue
        Start-Sleep 1
        Remove-Item $lhmDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "LibreHardwareMonitor supprime."
    } else { Write-Skip "Conserve." }
} else {
    Write-Skip "LibreHardwareMonitor non trouve dans les emplacements connus."
}

# ── 9. InfluxDB ───────────────────────────────────────────────────────────────

Write-Step "9  InfluxDB (binaire)"

$influxSearchPaths = @(
    "C:\Program Files\InfluxDB",
    "C:\Program Files\InfluxData\influxdb",
    "$env:ProgramFiles\InfluxData\influxdb",
    "$env:LOCALAPPDATA\InfluxDB"
)
$influxDir = $influxSearchPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

# Verifie aussi une installation winget
$influxWinget = $null
try {
    $result = winget list --id InfluxData.InfluxDB 2>$null
    if ($result -match "InfluxData") { $influxWinget = $true }
} catch {}

if ($influxDir -or $influxWinget) {
    if ($influxDir) { Write-Info "Dossier trouve : $influxDir" }
    if ($influxWinget) { Write-Info "Installation winget detectee." }
    if (Ask "Desinstaller InfluxDB ?") {
        Stop-Process -Name "influxd" -Force -ErrorAction SilentlyContinue
        Start-Sleep 1
        # Desinstallation winget si applicable
        if ($influxWinget) {
            Write-Info "Desinstallation via winget..."
            winget uninstall --id InfluxData.InfluxDB --silent --accept-source-agreements 2>$null
        }
        # Supprime le dossier dans tous les cas
        if ($influxDir -and (Test-Path $influxDir)) {
            Remove-Item $influxDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-OK "InfluxDB supprime."
    } else { Write-Skip "Conserve." }
} else {
    Write-Skip "InfluxDB non trouve dans les emplacements connus."
}

# ── 10. Node.js ───────────────────────────────────────────────────────────────

Write-Step "10  Node.js"

$nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeVer = & node --version 2>$null
    Write-Info "Node.js installe : $nodeVer ($($nodeCmd.Source))"
    Write-Warn "Verifie que Node.js n'est pas utilise par d'autres projets."
    if (Ask "Desinstaller Node.js $nodeVer ?") {
        Write-Info "Desinstallation via winget..."
        winget uninstall --id OpenJS.NodeJS.LTS --silent --accept-source-agreements 2>$null
        winget uninstall --id OpenJS.NodeJS     --silent --accept-source-agreements 2>$null
        # Fallback : recherche dans Programmes
        $nodeMsi = Get-Package -Name "Node.js*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($nodeMsi) { $nodeMsi | Uninstall-Package -Force -ErrorAction SilentlyContinue }
        Write-OK "Node.js desinstalle (redemarrage peut etre necessaire)."
    } else { Write-Skip "Conserve." }
} else {
    Write-Skip "Node.js non presente."
}

# ── 11. Rust ──────────────────────────────────────────────────────────────────

Write-Step "11  Rust"

$rustup = Get-Command "rustup" -ErrorAction SilentlyContinue
if ($rustup) {
    $rustVer = & rustc --version 2>$null
    Write-Info "Rust installe : $rustVer"
    Write-Warn "Verifie que Rust n'est pas utilise par d'autres projets."
    if (Ask "Desinstaller Rust + Cargo (rustup self uninstall) ?") {
        & rustup self uninstall -y 2>$null
        Write-OK "Rust et Cargo desinstalles."
    } else { Write-Skip "Conserve." }
} else {
    Write-Skip "Rust non present."
}

# ── Resume ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "  Desinstallation terminee." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note : WebView2 (composant Windows/Edge) n'a pas ete supprime."
Write-Host "  Si necessaire : Parametres > Applications > Microsoft Edge WebView2 Runtime"
Write-Host ""
