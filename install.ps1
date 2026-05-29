<#
.SYNOPSIS
  Installeur autonome de monitor4me.
  Un seul fichier a telecharger et executer — aucun clone de repo requis.
  Telecharge et installe automatiquement toutes les dependances.

.NOTES
  Lancement (double-clic ou depuis PowerShell) :
    powershell -ExecutionPolicy Bypass -File install.ps1

  L'elevation administrateur est demandee automatiquement (UAC).
#>

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # Invoke-WebRequest sans barre de progression

# ── Auto-elevation ────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal]
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Start-Process powershell `
        -Verb RunAs `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ── Constantes ────────────────────────────────────────────────────────────────
$GITHUB_REPO   = "MehdiZen/monitor4me"
$DEPS_DIR      = "$env:APPDATA\monitor4me"         # collector, config
$COLLECTOR_DIR = "$DEPS_DIR\collector"
$INFLUX_DIR    = "$env:ProgramFiles\InfluxDB"
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Ask([string]$prompt, [bool]$defaultYes = $true) {
    $hint = if ($defaultYes) { "(O/n)" } else { "(o/N)" }
    $ans  = Read-Host "`n  └─ $prompt $hint"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    return ($ans -match '^[oOyY]$')
}

function Step([string]$n, [string]$title) {
    Write-Host ""
    Write-Host "  +-[$n] $title" -ForegroundColor Cyan
}

function OK  ([string]$m) { Write-Host "  |  OK  $m" -ForegroundColor Green    }
function Info([string]$m) { Write-Host "  |  .   $m" -ForegroundColor Gray     }
function Warn([string]$m) { Write-Host "  |  /!\ $m" -ForegroundColor Yellow   }
function Err ([string]$m) { Write-Host "  |  ERR $m" -ForegroundColor Red      }

function IsCmd([string]$c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function RefreshPath {
    $mp = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $up = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$mp;$up"
}

function Find-AppExe {
    $paths = @(
        "$env:LOCALAPPDATA\monitor4me\monitor4me.exe",
        "$env:LOCALAPPDATA\Programs\monitor4me\monitor4me.exe",
        "$env:ProgramFiles\monitor4me\monitor4me.exe",
        "${env:ProgramFiles(x86)}\monitor4me\monitor4me.exe"
    )
    # Registre
    $regs = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $found = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }
    foreach ($r in $regs) {
        $key = Get-ChildItem $r -ErrorAction SilentlyContinue |
               Get-ItemProperty -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*monitor4me*" } |
               Select-Object -First 1
        if ($key -and $key.InstallLocation) {
            $exe = Join-Path $key.InstallLocation "monitor4me.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    return $null
}

function Register-PCTask {
    param($Name, $Action, $Trigger, $Principal, $Settings, $Desc)
    if (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask       -TaskName $Name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
    }
    Register-ScheduledTask `
        -TaskName $Name -Action $Action -Trigger $Trigger `
        -Principal $Principal -Settings $Settings -Description $Desc | Out-Null
    OK "Tache '$Name' enregistree"
}

# ── Bienvenue ─────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    monitor4me  --  Installation                  " -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ce script installe tout le necessaire pour monitor4me :"
Write-Host "    · Node.js LTS           pour le collecteur de metriques"
Write-Host "    · InfluxDB 2.x          base de donnees locale"
Write-Host "    · LibreHardwareMonitor  lecture des capteurs materiel"
Write-Host "    · monitor4me            l'application de monitoring"
Write-Host ""
Write-Host "  Chaque etape demande ta confirmation." -ForegroundColor Gray
Write-Host "  Duree estimee : 5-10 minutes selon ta connexion." -ForegroundColor Gray
Write-Host ""

if (-not (Ask "Commencer l'installation ?")) {
    Write-Host "  Annule." -ForegroundColor Gray
    exit 0
}

# ── Step 1 : Node.js ──────────────────────────────────────────────────────────

Step "1/8" "Node.js LTS"

$nodeOk = IsCmd "node"
if ($nodeOk) {
    OK "Deja installe : $(node --version)"
} else {
    Info "Requis pour le collecteur de metriques (~50 MB)."
    if (Ask "Installer Node.js ?") {
        if (-not (IsCmd "winget")) {
            Warn "winget introuvable. Installe Node.js manuellement : https://nodejs.org"
        } else {
            Info "Installation en cours..."
            winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                --accept-package-agreements --accept-source-agreements
            RefreshPath
            $nodeOk = IsCmd "node"
            if ($nodeOk) { OK "Node.js $(node --version) installe" }
            else          { Warn "Echec. Installe manuellement : https://nodejs.org" }
        }
    } else {
        Warn "Sans Node.js, le collecteur ne fonctionnera pas."
    }
}

# ── Step 2 : InfluxDB ─────────────────────────────────────────────────────────

Step "2/8" "InfluxDB 2.x"

$influxExe = "$INFLUX_DIR\influxd.exe"
if (-not (Test-Path $influxExe)) {
    $fc = Get-Command "influxd" -ErrorAction SilentlyContinue
    if ($fc) { $influxExe = $fc.Source }
}

if (Test-Path $influxExe) {
    OK "Deja installe : $influxExe"
} else {
    Info "Base de donnees locale pour toutes les metriques (~100 MB)."
    Info "Destination : $INFLUX_DIR"
    if (Ask "Installer InfluxDB $INFLUX_VER ?") {
        $zipUrl     = "https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUX_VER}-windows.zip"
        $zipTmp     = "$env:TEMP\influxdb.zip"
        $extractTmp = "$env:TEMP\influx_extract"
        Info "Telechargement..."
        try {
            Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
            if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
            Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
            $inner = Get-ChildItem $extractTmp | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
            Get-ChildItem $inner.FullName | Copy-Item -Destination $INFLUX_DIR -Recurse -Force
            Remove-Item $extractTmp -Recurse -Force
            Remove-Item $zipTmp     -Force
            if (Test-Path $influxExe) { OK "InfluxDB $INFLUX_VER installe : $INFLUX_DIR" }
            else                       { Warn "influxd.exe introuvable apres extraction." }
        } catch {
            Warn "Echec du telechargement : $_"
            Warn "Telecharge manuellement : https://portal.influxdata.com/downloads/"
        }
    } else {
        Warn "Sans InfluxDB, les metriques ne seront pas sauvegardees."
        $influxExe = ""
    }
}

# ── Step 3 : LibreHardwareMonitor ─────────────────────────────────────────────

Step "3/8" "LibreHardwareMonitor"

$lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse `
              -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

if ($lhmExe) {
    OK "Deja installe : $lhmExe"
} else {
    Info "Lit les capteurs CPU, GPU et NVMe en temps reel (~10 MB)."
    Info "Destination : $LHM_DIR"
    if (Ask "Telecharger LibreHardwareMonitor ?") {
        try {
            Info "Recuperation de la derniere version..."
            $rel   = Invoke-RestMethod `
                "https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest" `
                -TimeoutSec 20 -Headers @{"User-Agent" = "monitor4me-install/1.0"}
            $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
            if (-not $asset) { throw "Aucun asset zip dans la release" }
            $lhmZip = "$env:TEMP\lhm.zip"
            Info "Telechargement de $($asset.name) ($([int]($asset.size/1MB)) MB)..."
            Invoke-WebRequest $asset.browser_download_url -OutFile $lhmZip -UseBasicParsing
            New-Item -ItemType Directory -Force -Path $LHM_DIR | Out-Null
            Expand-Archive -Path $lhmZip -DestinationPath $LHM_DIR -Force
            Remove-Item $lhmZip -Force
            $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse |
                      Select-Object -First 1 -ExpandProperty FullName
            if ($lhmExe) { OK "LibreHardwareMonitor installe : $lhmExe" }
            else          { Warn "LibreHardwareMonitor.exe introuvable apres extraction." }
        } catch {
            Warn "Echec : $_"
            Warn "Telecharge manuellement : https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases"
        }
    } else {
        Warn "Sans LHM, les capteurs materiel ne seront pas disponibles."
    }
}

# ── Step 4 : App monitor4me ───────────────────────────────────────────────────

Step "4/8" "Application monitor4me"

$appExe = Find-AppExe
if ($appExe) {
    OK "Deja installee : $appExe"
} else {
    Info "L'interface graphique de monitoring."
    if (Ask "Telecharger et installer monitor4me ?") {
        try {
            Info "Recuperation de la derniere release GitHub..."
            $rel   = Invoke-RestMethod `
                "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                -TimeoutSec 20 -Headers @{"User-Agent" = "monitor4me-install/1.0"}
            $asset = $rel.assets | Where-Object { $_.name -like "*setup.exe" } | Select-Object -First 1
            if (-not $asset) { throw "Installeur introuvable dans la release GitHub" }
            $setupExe = "$env:TEMP\monitor4me-setup.exe"
            Info "Telechargement de $($asset.name) ($([int]($asset.size/1MB)) MB)..."
            Invoke-WebRequest $asset.browser_download_url -OutFile $setupExe -UseBasicParsing
            Info "Installation silencieuse en cours..."
            $proc = Start-Process $setupExe -ArgumentList "/S" -Wait -PassThru
            Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
            $appExe = Find-AppExe
            if ($appExe) { OK "monitor4me installe : $appExe" }
            else          { Warn "Installation terminee mais exe introuvable. Relance ce script." }
        } catch {
            Warn "Echec : $_"
            Warn "Telecharge manuellement : https://github.com/$GITHUB_REPO/releases/latest"
        }
    } else {
        Warn "Sans l'app, impossible d'afficher les metriques."
    }
}

# ── Step 5 : Collecteur ───────────────────────────────────────────────────────

Step "5/8" "Collecteur de metriques"

$collectorDist = "$COLLECTOR_DIR\dist\index.js"
if (Test-Path $collectorDist) {
    OK "Deja installe : $collectorDist"
} elseif ($nodeOk) {
    Info "Le collecteur lit LHM et envoie les donnees dans InfluxDB."
    if (Ask "Installer le collecteur ?") {
        try {
            Info "Recuperation de la derniere release GitHub..."
            $rel = Invoke-RestMethod `
                "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                -TimeoutSec 20 -Headers @{"User-Agent" = "monitor4me-install/1.0"}

            # Cherche d abord le collecteur pre-compile (collector-dist.zip)
            $prebuilt = $rel.assets | Where-Object { $_.name -eq "collector-dist.zip" } | Select-Object -First 1

            if ($prebuilt) {
                # Collecteur pre-compile disponible — pas besoin de compiler
                Info "Telechargement du collecteur pre-compile ($([int]($prebuilt.size/1MB)) MB)..."
                $zipTmp = "$env:TEMP\collector-dist.zip"
                Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing
                if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
                New-Item -ItemType Directory $COLLECTOR_DIR | Out-Null
                Expand-Archive -Path $zipTmp -DestinationPath $COLLECTOR_DIR -Force
                Remove-Item $zipTmp -Force
                OK "Collecteur installe (pre-compile)"
            } elseif ($nodeOk) {
                # Fallback : telecharge le source et compile
                Warn "Collecteur pre-compile absent dans la release. Compilation depuis les sources..."
                $srcZip = "$env:TEMP\monitor4me-src.zip"
                $srcTmp = "$env:TEMP\monitor4me-src"
                Invoke-WebRequest $rel.zipball_url -OutFile $srcZip -UseBasicParsing
                if (Test-Path $srcTmp) { Remove-Item $srcTmp -Recurse -Force }
                Expand-Archive -Path $srcZip -DestinationPath $srcTmp -Force
                Remove-Item $srcZip -Force
                $inner        = Get-ChildItem $srcTmp -Directory | Select-Object -First 1
                $collectorSrc = Join-Path $inner.FullName "collector"
                if (-not (Test-Path $collectorSrc)) { throw "Dossier collector introuvable dans le zip" }
                if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
                Copy-Item $collectorSrc -Destination $COLLECTOR_DIR -Recurse -Force
                Remove-Item $srcTmp -Recurse -Force
                Push-Location $COLLECTOR_DIR
                Info "npm install..."
                & npm install --silent
                Info "Compilation TypeScript..."
                & npm run build
                & npm prune --production --silent
                Pop-Location
            } else {
                Warn "Node.js absent et collecteur pre-compile non trouve dans la release."
                Warn "Installe Node.js puis relance ce script."
            }
            if (Test-Path $collectorDist) { OK "Collecteur pret : $collectorDist" }
            else                           { Warn "dist/index.js introuvable. Verifie les erreurs ci-dessus." }
        } catch {
            Warn "Echec : $_"
        }
    }
} else {
    Warn "Node.js absent — impossible de compiler le collecteur si pas de pre-compile."
}

# ── Step 6 : Configuration InfluxDB ──────────────────────────────────────────

Step "6/8" "Configuration InfluxDB"

if (-not (Test-Path $influxExe)) {
    Warn "InfluxDB non installe — etape ignoree."
} else {
    Info "Creation de l'organisation, du bucket et du token d'acces."
    if (Ask "Configurer InfluxDB ?") {
        # Demande le mot de passe admin
        Write-Host ""
        Write-Host "  |  Choisis un mot de passe pour le compte admin InfluxDB." -ForegroundColor Gray
        Write-Host "  |  (base locale uniquement, jamais exposee sur internet)" -ForegroundColor Gray
        $secPass   = Read-Host "  └─ Mot de passe [monitor4me-local]" -AsSecureString
        $bstr      = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
        $adminPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        if ([string]::IsNullOrWhiteSpace($adminPass)) { $adminPass = "monitor4me-local" }

        # Demarre InfluxDB temporairement
        $influxRunning = $false
        try {
            $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
            $influxRunning = ($h.status -eq "pass")
        } catch {}

        $tmpProc    = $null
        $influxReady = $influxRunning
        if (-not $influxRunning) {
            Info "Demarrage temporaire d'InfluxDB..."
            $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep 3
                try {
                    $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
                    if ($h.status -eq "pass") { $influxReady = $true; break }
                } catch {}
                Info "  Attente... ($([int]($i*3))s)"
            }
        }

        if ($influxReady) {
            $token = $null
            $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET
            if ($status.allowed -eq $true) {
                # Premiere installation
                $body = @{
                    username = "admin"; password = $adminPass
                    org = "home"; bucket = "pc-monitor"
                    retentionPeriodSeconds = 2592000
                } | ConvertTo-Json
                $result = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" `
                    -Method POST -Body $body -ContentType "application/json"
                $token = $result.auth.token
                OK "InfluxDB configure (org: home, bucket: pc-monitor)"
            } else {
                # Deja configure — connexion et recuperation token
                $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$adminPass"))
                $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" `
                    -Method POST -Headers @{Authorization = "Basic $cred"} -UseBasicParsing
                $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                $authHdr = @{Cookie = $cookie}
                $orgs    = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                $orgId   = $orgs.orgs[0].id
                $auths   = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                $existing = $auths.authorizations | Where-Object { $_.description -eq "pc-monitor-collector" } |
                            Select-Object -First 1
                if ($existing) {
                    $token = $existing.token
                    OK "Token existant recupere"
                } else {
                    $bkts  = Invoke-RestMethod "$INFLUX_URL/api/v2/buckets?org=home" -Headers $authHdr
                    $bktId = ($bkts.buckets | Where-Object { $_.name -eq "pc-monitor" } | Select-Object -First 1).id
                    $tBody = @{
                        orgID = $orgId; description = "pc-monitor-collector"
                        permissions = @(
                            @{action="read";  resource=@{type="buckets";orgID=$orgId;id=$bktId}},
                            @{action="write"; resource=@{type="buckets";orgID=$orgId;id=$bktId}}
                        )
                    } | ConvertTo-Json -Depth 5
                    $auth  = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations" `
                        -Method POST -Body $tBody -Headers @{Cookie=$cookie;"Content-Type"="application/json"}
                    $token = $auth.token
                    OK "Nouveau token cree"
                }
            }
            if ($token) {
                [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "User")
                $env:INFLUX_TOKEN = $token
                OK "INFLUX_TOKEN sauvegarde en variable d'environnement"
            }
        } else {
            Warn "InfluxDB ne repond pas. Relance ce script apres l'avoir demarrer manuellement."
        }

        if ($tmpProc) {
            Info "Arret d'InfluxDB temporaire..."
            Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
    }
}

# ── Step 7 : Taches planifiees ────────────────────────────────────────────────

Step "7/8" "Taches planifiees (auto-demarrage)"

Info "PC-Monitor-InfluxDB  : influxd.exe         au demarrage de session"
Info "PC-Monitor-LHM       : LHM dans le tray    au demarrage de session"
Info "PC-Monitor-Collector : collecteur JS        25s apres LHM"

if (Ask "Creer les taches planifiees ?") {
    $nodePath = (Get-Command "node" -ErrorAction SilentlyContinue)
    $nodeExe  = if ($nodePath) { $nodePath.Source } else { $null }

    if (-not $nodeExe) {
        Warn "node.exe introuvable — tache collecteur ignoree."
    }

    $atLogon  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $userPrin = New-ScheduledTaskPrincipal -UserId $env:USERNAME `
                    -LogonType Interactive -RunLevel Highest
    $svcPrin  = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
                    -LogonType ServiceAccount -RunLevel Highest
    $noLimit  = [TimeSpan]::Zero
    $restart1 = New-TimeSpan -Minutes 1

    # InfluxDB
    if (Test-Path $influxExe) {
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit `
             -RestartCount 5 -RestartInterval $restart1 -StartWhenAvailable
        Register-PCTask -Name "PC-Monitor-InfluxDB" `
            -Action    (New-ScheduledTaskAction -Execute $influxExe `
                            -WorkingDirectory (Split-Path $influxExe)) `
            -Trigger   $atLogon -Principal $svcPrin -Settings $s `
            -Desc      "InfluxDB 2.x pour monitor4me (port 8086)"
    }

    # LHM
    if ($lhmExe) {
        $lhmCmd = "-NonInteractive -WindowStyle Hidden " +
                  "-Command `"Start-Process '$lhmExe' -WindowStyle Minimized`""
        $s = New-ScheduledTaskSettingsSet `
             -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
        Register-PCTask -Name "PC-Monitor-LHM" `
            -Action    (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $lhmCmd) `
            -Trigger   $atLogon -Principal $userPrin -Settings $s `
            -Desc      "LibreHardwareMonitor REST :8085 pour monitor4me"
    }

    # Collector
    if ($nodeExe -and (Test-Path $collectorDist)) {
        $cTrigger       = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $cTrigger.Delay = "PT25S"
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit `
             -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
        Register-PCTask -Name "PC-Monitor-Collector" `
            -Action    (New-ScheduledTaskAction -Execute $nodeExe `
                            -Argument "$COLLECTOR_DIR\dist\index.js" `
                            -WorkingDirectory $COLLECTOR_DIR) `
            -Trigger   $cTrigger -Principal $userPrin -Settings $s `
            -Desc      "Collecteur monitor4me : LHM -> InfluxDB + WebSocket :8088"
    }
}

# ── Step 8 : Raccourci bureau ─────────────────────────────────────────────────

Step "8/8" "Raccourci bureau"

if ($appExe) {
    if (Ask "Creer le raccourci 'monitor4me' sur le bureau ?") {
        $desktop = [System.Environment]::GetFolderPath("Desktop")
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
        $sc.TargetPath       = $appExe
        $sc.WorkingDirectory = Split-Path $appExe
        $sc.Description      = "monitor4me - PC Hardware Dashboard"
        $sc.Save()
        OK "Raccourci cree sur le bureau"
    }
} else {
    Warn "App non installee — raccourci ignore."
}

# ── Resume ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "  Installation terminee !" -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

$todo = [System.Collections.Generic.List[string]]::new()
if (-not $nodeOk)                    { $todo.Add("  · Node.js        : https://nodejs.org") }
if (-not (Test-Path $influxExe))     { $todo.Add("  · InfluxDB       : https://portal.influxdata.com/downloads/") }
if (-not $lhmExe)                    { $todo.Add("  · LHM            : https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases") }
if (-not (Test-Path $collectorDist)) { $todo.Add("  · Collecteur     : relance ce script (Node.js requis)") }
if (-not $appExe)                    { $todo.Add("  · monitor4me.exe : https://github.com/$GITHUB_REPO/releases/latest") }

if ($todo.Count -gt 0) {
    Write-Host "  Etapes restantes a finaliser :" -ForegroundColor Yellow
    $todo | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host ""
}

Write-Host "  Note : au prochain demarrage de Windows, tout se lancera"
Write-Host "  automatiquement en arriere-plan."
Write-Host ""
Write-Host "  En cas de probleme :"
Write-Host "    · Antivirus : LHM peut etre signale (faux positif connu)"
Write-Host "      Ajoute une exception pour LibreHardwareMonitor.exe"
Write-Host "    · Relance ce script pour reparer une etape echouee"
Write-Host ""

if ($appExe -and (Test-Path $appExe)) {
    if (Ask "Lancer monitor4me maintenant ?") {
        Info "Demarrage des services..."
        Start-ScheduledTask -TaskName "PC-Monitor-InfluxDB"  -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName "PC-Monitor-LHM"       -ErrorAction SilentlyContinue
        Info "Attente 10s (InfluxDB + LHM)..."
        Start-Sleep 10
        Start-ScheduledTask -TaskName "PC-Monitor-Collector" -ErrorAction SilentlyContinue
        Start-Sleep 3
        Start-Process -FilePath $appExe
        OK "monitor4me demarre !"
    }
}

Write-Host ""
Write-Host "  Pour desinstaller : powershell -ExecutionPolicy Bypass -File uninstall.ps1" -ForegroundColor Gray
Write-Host ""
