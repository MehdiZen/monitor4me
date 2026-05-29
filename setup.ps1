#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Installeur interactif de monitor4me.
  Chaque etape demande confirmation avant d'agir.
.NOTES
  Pre-requis : Windows 10/11, PowerShell 5.1+
  Lancement :
    powershell -ExecutionPolicy Bypass -File "setup.ps1"
#>

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot

# ── Validation dossier ────────────────────────────────────────────────────────
if (-not (Test-Path "$ROOT\collector\package.json") -or
    -not (Test-Path "$ROOT\app\package.json")) {
    Write-Host ""
    Write-Host "  ERREUR : ce script doit etre dans le dossier racine de monitor4me." -ForegroundColor Red
    Write-Host "  Dossier detecte : $ROOT"
    exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step([string]$n, [string]$title) {
    Write-Host ""
    Write-Host "  ┌─ [$n]  $title" -ForegroundColor Cyan
}

function Write-OK  ([string]$msg) { Write-Host "  |  OK  $msg" -ForegroundColor Green  }
function Write-Info([string]$msg) { Write-Host "  |  ·   $msg" -ForegroundColor Gray   }
function Write-Warn([string]$msg) { Write-Host "  |  /!\ $msg" -ForegroundColor Yellow }
function Write-Err ([string]$msg) { Write-Host "  |  ERR $msg" -ForegroundColor Red    }

function Ask([string]$prompt, [bool]$defaultYes = $true) {
    $hint = if ($defaultYes) { "(O/n)" } else { "(o/N)" }
    $ans  = Read-Host "  └─ $prompt $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    return ($ans -match '^[oOyY]$')
}

function IsCmd([string]$cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function RefreshPath {
    $mp = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $up = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$mp;$up"
}

function FindFirst([string[]]$paths) {
    $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# ── Bienvenue ─────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    monitor4me  --  Installation                  " -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ce script installe toutes les dependances."
Write-Host "  Il demande ta confirmation avant chaque action."
Write-Host ""
Write-Host "  Etapes :"
Write-Host "    1. Node.js LTS           collecteur TypeScript        ~50 MB"
Write-Host "    2. InfluxDB 2.x          base de donnees series       ~100 MB"
Write-Host "    3. LibreHardwareMonitor  capteurs CPU / GPU / NVMe    ~10 MB"
Write-Host "    4. Build du collecteur   compilation TypeScript"
Write-Host "    5. Configuration DB      org, bucket, token auto"
Write-Host "    6. Taches planifiees     auto-demarrage a la connexion"
Write-Host "    7. Raccourci bureau"
Write-Host ""

if (-not (Ask "Commencer l'installation ?")) {
    Write-Host "  Annule." -ForegroundColor Yellow
    exit 0
}

# ── 1. Node.js ────────────────────────────────────────────────────────────────

Write-Step "1/7" "Node.js LTS"

$nodeOk = IsCmd "node"
if ($nodeOk) {
    Write-OK "Deja installe : $(node --version)"
} else {
    Write-Info "Requis pour executer le collecteur TypeScript."
    if (Ask "Installer Node.js via winget ?") {
        if (-not (IsCmd "winget")) {
            Write-Warn "winget absent. Installe Node.js manuellement : https://nodejs.org"
        } else {
            Write-Info "Installation en cours..."
            winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                --accept-package-agreements --accept-source-agreements
            RefreshPath
            $nodeOk = IsCmd "node"
            if ($nodeOk) { Write-OK "Node.js $(node --version) installe" }
            else          { Write-Warn "Echec. Installe manuellement : https://nodejs.org" }
        }
    } else {
        Write-Warn "Ignore. Le collecteur ne fonctionnera pas sans Node.js."
    }
}

# ── 2. InfluxDB ───────────────────────────────────────────────────────────────

Write-Step "2/7" "InfluxDB 2.x"

$influxSearchPaths = @(
    "C:\Program Files\InfluxDB\influxd.exe",
    "C:\Program Files\InfluxData\influxdb\influxd.exe",
    "$env:ProgramFiles\InfluxData\influxdb\influxd.exe",
    "$env:LOCALAPPDATA\InfluxDB\influxd.exe"
)
$influxExe = FindFirst $influxSearchPaths
if (-not $influxExe) {
    $fc = Get-Command "influxd" -ErrorAction SilentlyContinue
    if ($fc) { $influxExe = $fc.Source }
}

if ($influxExe) {
    Write-OK "Deja present : $influxExe"
} else {
    $influxTargetDir = "C:\Program Files\InfluxDB"
    Write-Info "Stocke toutes les metriques (CPU, couts, temperatures)."
    Write-Info "Destination : $influxTargetDir"

    if (Ask "Installer InfluxDB 2.7 ?") {
        $influxVer  = "2.7.11"
        $zipName    = "influxdb2-${influxVer}-windows.zip"
        $zipUrl     = "https://dl.influxdata.com/influxdb/releases/$zipName"
        $zipTmp     = "$env:TEMP\$zipName"
        $extractTmp = "$env:TEMP\influx_extract"
        $zipOk      = $false

        Write-Info "Telechargement de InfluxDB $influxVer..."
        try {
            Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
            $zipOk = $true
        } catch {
            Write-Warn "Telechargement direct echoue. Tentative via winget..."
            try {
                winget install --id InfluxData.InfluxDB -e --source winget --silent `
                    --accept-package-agreements --accept-source-agreements 2>$null
                RefreshPath
                $fc = Get-Command "influxd" -ErrorAction SilentlyContinue
                if ($fc) {
                    $influxExe = $fc.Source
                    Write-OK "Installe via winget : $influxExe"
                } else {
                    Write-Warn "Echec. Telechargement manuel : https://portal.influxdata.com/downloads/"
                }
            } catch {
                Write-Warn "Echec winget. Telechargement manuel : https://portal.influxdata.com/downloads/"
            }
        }

        if ($zipOk -and (Test-Path $zipTmp)) {
            Write-Info "Extraction vers $influxTargetDir..."
            if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
            Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
            $inner = Get-ChildItem $extractTmp | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path $influxTargetDir | Out-Null
            Get-ChildItem $inner.FullName | Copy-Item -Destination $influxTargetDir -Recurse -Force
            Remove-Item $extractTmp -Recurse -Force
            Remove-Item $zipTmp     -Force
            $influxExe = "$influxTargetDir\influxd.exe"
            if (Test-Path $influxExe) { Write-OK "InfluxDB $influxVer installe : $influxExe" }
            else                       { Write-Warn "influxd.exe introuvable apres extraction. Verifie $influxTargetDir" }
        }
    } else {
        Write-Warn "Ignore. Les metriques ne seront pas persistees."
    }
}

# ── 3. LibreHardwareMonitor ───────────────────────────────────────────────────

Write-Step "3/7" "LibreHardwareMonitor (LHM)"

$lhmSearchPaths = @(
    "C:\Program Files\LibreHardwareMonitor\LibreHardwareMonitor.exe",
    "C:\Tools\LibreHardwareMonitor\LibreHardwareMonitor.exe",
    "$env:ProgramFiles\LibreHardwareMonitor\LibreHardwareMonitor.exe",
    "$env:LOCALAPPDATA\LibreHardwareMonitor\LibreHardwareMonitor.exe"
)
$lhmExe = FindFirst $lhmSearchPaths

if ($lhmExe) {
    Write-OK "Deja present : $lhmExe"
} else {
    $lhmTargetDir = "C:\Program Files\LibreHardwareMonitor"
    Write-Info "Lit les capteurs CPU, GPU, NVMe via acces kernel (ring 0)."
    Write-Info "Destination : $lhmTargetDir"

    if (Ask "Telecharger LibreHardwareMonitor depuis GitHub ?") {
        Write-Info "Recuperation de la derniere release..."
        try {
            $release = Invoke-RestMethod `
                "https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest" `
                -TimeoutSec 20 -Headers @{ "User-Agent" = "monitor4me-setup/1.0" }
            $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
            if (-not $asset) { throw "Aucun asset .zip dans la release GitHub" }
            $lhmZip = "$env:TEMP\lhm.zip"
            Write-Info "Telechargement de $($asset.name) ($([int]($asset.size / 1MB)) MB)..."
            Invoke-WebRequest $asset.browser_download_url -OutFile $lhmZip -UseBasicParsing
            Write-Info "Extraction vers $lhmTargetDir..."
            New-Item -ItemType Directory -Force -Path $lhmTargetDir | Out-Null
            Expand-Archive -Path $lhmZip -DestinationPath $lhmTargetDir -Force
            Remove-Item $lhmZip -Force
            $lhmExe = Get-ChildItem $lhmTargetDir -Filter "LibreHardwareMonitor.exe" -Recurse |
                      Select-Object -First 1 -ExpandProperty FullName
            if ($lhmExe) { Write-OK "LHM installe : $lhmExe" }
            else          { Write-Warn "LibreHardwareMonitor.exe introuvable apres extraction." }
        } catch {
            Write-Warn "Echec : $_"
            Write-Warn "Telecharge manuellement : https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases"
        }
    } else {
        Write-Warn "Ignore. Les capteurs matériel ne seront pas disponibles."
        Write-Info "Indique le chemin de LHM.exe dans scripts\setup-task.ps1 (-LhmPath)."
    }
}

# ── 4. Build collecteur ───────────────────────────────────────────────────────

Write-Step "4/7" "Build du collecteur"

$collectorDist = "$ROOT\collector\dist\index.js"

if (Test-Path $collectorDist) {
    Write-OK "Deja compile : $collectorDist"
} elseif ($nodeOk) {
    Write-Info "Compile le collecteur TypeScript (npm install + tsc)."
    if (Ask "Compiler le collecteur ?") {
        Push-Location "$ROOT\collector"
        & npm install --silent
        & npm run build
        Pop-Location
        if (Test-Path $collectorDist) { Write-OK "Collecteur compile OK" }
        else { Write-Warn "Compilation echouee. Verifie les erreurs ci-dessus." }
    }
} else {
    Write-Warn "Node.js absent - compilation impossible."
}

# ── 5. Configuration InfluxDB ─────────────────────────────────────────────────

Write-Step "5/7" "Configuration InfluxDB"

$influxUrl = "http://localhost:8086"

if (-not $influxExe -or -not (Test-Path $influxExe)) {
    Write-Warn "InfluxDB non installe - etape ignoree."
    Write-Info "Lance scripts\setup-influx.ps1 apres avoir installe InfluxDB."
} else {
    Write-Info "Cree l'org 'home', le bucket 'pc-monitor' et un token d'acces."
    Write-Info "Le token sera sauvegarde dans la variable d'env INFLUX_TOKEN."

    if (Ask "Configurer InfluxDB maintenant ?") {
        # Verifie si InfluxDB tourne deja
        $influxRunning = $false
        try {
            $h = Invoke-RestMethod "$influxUrl/health" -TimeoutSec 3
            $influxRunning = ($h.status -eq "pass")
        } catch {}

        $tmpProc    = $null
        $influxReady = $influxRunning

        if (-not $influxRunning) {
            Write-Info "Demarrage temporaire d'InfluxDB..."
            $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep 3
                try {
                    $h = Invoke-RestMethod "$influxUrl/health" -TimeoutSec 3
                    if ($h.status -eq "pass") { $influxReady = $true; break }
                } catch {}
                Write-Info "  Attente... ($([int]($i * 3))s)"
            }
            if (-not $influxReady) {
                Write-Warn "InfluxDB ne repond pas. Configure manuellement avec scripts\setup-influx.ps1"
            }
        }

        if ($influxReady) {
            Write-Host ""
            Write-Host "  |  Choisis un mot de passe administrateur pour InfluxDB :" -ForegroundColor Gray
            Write-Host "  |  (base locale uniquement, non exposee sur internet)    " -ForegroundColor Gray
            $adminPass = Read-Host "  └─ Mot de passe admin [monitor4me-local]"
            if ([string]::IsNullOrWhiteSpace($adminPass)) { $adminPass = "monitor4me-local" }

            & "$ROOT\scripts\setup-influx.ps1" `
                -InfluxUrl  $influxUrl `
                -AdminPass  $adminPass
            Write-OK "InfluxDB configure"
        }

        if ($tmpProc) {
            Write-Info "Arret d'InfluxDB temporaire (les taches planifiees prendront le relais)."
            Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
    }
}

# ── 6. Taches planifiees ──────────────────────────────────────────────────────

Write-Step "6/7" "Taches planifiees (auto-demarrage)"

Write-Info "Trois taches seront creees dans le Planificateur de taches Windows :"
Write-Info "  PC-Monitor-InfluxDB  - influxd.exe          a la connexion"
Write-Info "  PC-Monitor-LHM       - LHM.exe dans le tray a la connexion"
Write-Info "  PC-Monitor-Collector - collecteur JS         25 s apres LHM"

if (Ask "Creer les 3 taches planifiees ?") {
    $nodePath = (Get-Command "node" -ErrorAction SilentlyContinue)
    if (-not $nodePath) {
        Write-Warn "node.exe introuvable. Installe Node.js d'abord."
    } else {
        $taskParams = @( "-ExecutionPolicy", "Bypass",
                         "-File", "$ROOT\scripts\setup-task.ps1",
                         "-CollectorDir", "$ROOT\collector",
                         "-StartNow", "false" )
        if ($influxExe -and (Test-Path $influxExe)) { $taskParams += "-InfluxdPath", $influxExe }
        if ($lhmExe    -and (Test-Path $lhmExe))    { $taskParams += "-LhmPath",     $lhmExe   }
        & powershell.exe @taskParams
        Write-OK "Taches enregistrees"
    }
} else {
    Write-Info "Ignore. Lance scripts\setup-task.ps1 manuellement quand tu voudras."
}

# ── 7. Raccourci bureau ───────────────────────────────────────────────────────

Write-Step "7/7" "Raccourci bureau"

$appExe = Get-ChildItem "$ROOT\app\src-tauri\target\release" -Filter "*.exe" `
              -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -notmatch "(_sa\.exe)$" -and $_.Name -notmatch "^build" } |
          Sort-Object Length -Descending |
          Select-Object -First 1 -ExpandProperty FullName

if ($appExe) {
    Write-Info "App trouvee : $appExe"
    if (Ask "Creer le raccourci 'monitor4me' sur le bureau ?") {
        $desktop = [System.Environment]::GetFolderPath("Desktop")
        $wsh     = New-Object -ComObject WScript.Shell
        $sc      = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
        $sc.TargetPath       = $appExe
        $sc.WorkingDirectory = Split-Path $appExe
        $sc.Description      = "monitor4me - PC Hardware Dashboard"
        $sc.Save()
        Write-OK "Raccourci cree sur le bureau"
    }
} else {
    Write-Warn "App non compilee - raccourci ignore."
    Write-Info "Pour compiler l'app (necessite Rust + VS Build Tools ~4 GB, ~20 min) :"
    Write-Info "  cd app && npm install && npm run tauri build"
}

# ── Resume ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "  Installation terminee !" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

$todo = [System.Collections.Generic.List[string]]::new()
if (-not $nodeOk)                        { $todo.Add("  · Node.js    : https://nodejs.org") }
if (-not $influxExe)                     { $todo.Add("  · InfluxDB   : https://portal.influxdata.com/downloads/") }
if (-not $lhmExe)                        { $todo.Add("  · LHM        : https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases") }
if (-not (Test-Path $collectorDist))     { $todo.Add("  · Collecteur : cd collector && npm install && npm run build") }
if (-not $appExe)                        { $todo.Add("  · App Tauri  : cd app && npm install && npm run tauri build") }

if ($todo.Count -gt 0) {
    Write-Host "  Etapes manuelles restantes :" -ForegroundColor Yellow
    $todo | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host ""
}

Write-Host "  Commandes utiles :"
Write-Host "    scripts\setup-influx.ps1         -- reconfigurer InfluxDB"
Write-Host "    scripts\setup-task.ps1            -- recrcer les taches planifiees"
Write-Host "    uninstall.ps1                     -- desinstaller monitor4me"
Write-Host "    Get-ScheduledTask 'PC-Monitor-*'  -- verifier l'etat des services"
Write-Host ""

if ($appExe -and (Test-Path $appExe)) {
    if (Ask "Lancer monitor4me maintenant ?") {
        Write-Info "Demarrage des services..."
        Start-ScheduledTask -TaskName "PC-Monitor-InfluxDB"  -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName "PC-Monitor-LHM"       -ErrorAction SilentlyContinue
        Write-Info "Attente 10 s (InfluxDB + LHM)..."
        Start-Sleep 10
        Start-ScheduledTask -TaskName "PC-Monitor-Collector" -ErrorAction SilentlyContinue
        Start-Sleep 3
        Start-Process -FilePath $appExe
        Write-OK "monitor4me demarre !"
    }
}

Write-Host ""
