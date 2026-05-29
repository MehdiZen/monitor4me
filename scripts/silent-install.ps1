[CmdletBinding()]
param(
    [string]$AdminPass = "monitor4me-local",
    [double]$TarifKwh  = 0.2516
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

# Définitions de dossiers
$DEPS_DIR      = "$env:APPDATA\monitor4me"
$COLLECTOR_DIR = "$DEPS_DIR\collector"
$INFLUX_DIR    = "$env:ProgramFiles\InfluxDB"
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"
$GITHUB_REPO   = "MehdiZen/monitor4me"

# Helper pour écrire des logs structurés décodables par Rust
function LogStep { param([string]$m) Write-Output "STEP: $m" }
function LogOK   { param([string]$m) Write-Output "OK: $m" }
function LogInfo { param([string]$m) Write-Output "INFO: $m" }
function LogWarn { param([string]$m) Write-Output "WARN: $m" }
function LogErr  { param([string]$m) Write-Output "ERR: $m" }

function IsCmd { param([string]$c) return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function RefreshPath {
    $mp = [System.Environment]::GetEnvironmentVariable("PATH","Machine")
    $up = [System.Environment]::GetEnvironmentVariable("PATH","User")
    $env:PATH = $mp + ";" + $up
}

function Find-AppExe {
    $paths = @(
        "$env:LOCALAPPDATA\monitor4me\monitor4me.exe",
        "$env:LOCALAPPDATA\Programs\monitor4me\monitor4me.exe",
        "$env:ProgramFiles\monitor4me\monitor4me.exe",
        "${env:ProgramFiles(x86)}\monitor4me\monitor4me.exe",
        "$env:APPDATA\monitor4me\monitor4me.exe"
    )
    $found = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }
    return $null
}

LogStep "Début de la configuration silencieuse"
$nodeOk = IsCmd "node"

# ── 1. Node.js ───────────────────────────────────────────────────────────────
LogStep "Vérification de Node.js"
if (IsCmd "node") {
    $v = & node --version 2>&1
    LogOK "Node.js déjà installé : $v"
} else {
    try {
        LogInfo "Récupération de la version LTS de Node.js..."
        $nodeMeta = Invoke-RestMethod "https://nodejs.org/dist/index.json" -TimeoutSec 15 |
                    Where-Object { $_.lts -ne $false } | Select-Object -First 1
        $nodeVer  = $nodeMeta.version
        $nodeMsi  = "$env:TEMP\node-install.msi"
        $nodeUrl  = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi"
        
        LogInfo "Téléchargement de Node.js $nodeVer..."
        Invoke-WebRequest $nodeUrl -OutFile $nodeMsi -UseBasicParsing
        LogInfo "Installation silencieuse de Node.js (via MSI)..."
        Start-Process msiexec.exe -ArgumentList "/i `"$nodeMsi`" /qn ADDLOCAL=ALL" -Wait
        Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue
        RefreshPath
        $nodeOk = IsCmd "node"
        if ($nodeOk) {
            $v = & node --version 2>&1
            LogOK "Node.js $v installé avec succès !"
        } else {
            LogWarn "L'installateur a terminé, mais Node.js n'est pas encore visible. Il faudra peut-être redémarrer."
        }
    } catch {
        LogWarn "L'installation par MSI a échoué. Tentative via winget..."
        if (IsCmd "winget") {
            winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            RefreshPath
            $nodeOk = IsCmd "node"
            if ($nodeOk) { LogOK "Node.js installé via winget !" }
            else { LogErr "Impossible d'installer Node.js automatiquement." }
        } else {
            LogErr "Winget non disponible et MSI en échec."
        }
    }
}

# ── 2. InfluxDB ───────────────────────────────────────────────────────────────
LogStep "Vérification d'InfluxDB"
$influxExe = "$INFLUX_DIR\influxd.exe"
$fc = Get-Command "influxd" -ErrorAction SilentlyContinue
if ($fc) { $influxExe = $fc.Source }

if (Test-Path $influxExe) {
    LogOK "InfluxDB déjà installé : $influxExe"
} else {
    try {
        $zipUrl = "https://dl.influxdata.com/influxdb/releases/influxdb2-" + $INFLUX_VER + "-windows.zip"
        $zipTmp = "$env:TEMP\influxdb.zip"
        $extractTmp = "$env:TEMP\influx_extract"
        
        LogInfo "Téléchargement d'InfluxDB $INFLUX_VER..."
        Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
        if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
        LogInfo "Extraction de l'archive..."
        Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
        
        $inner = Get-ChildItem $extractTmp | Select-Object -First 1
        New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
        Copy-Item -Path "$($inner.FullName)\*" -Destination $INFLUX_DIR -Recurse -Force
        
        Remove-Item $extractTmp -Recurse -Force
        Remove-Item $zipTmp -Force
        
        if (Test-Path $influxExe) {
            LogOK "InfluxDB installé avec succès !"
        } else {
            LogErr "Erreur lors de l'installation d'InfluxDB."
        }
    } catch {
        LogErr "Erreur de téléchargement/extraction d'InfluxDB : $_"
    }
}

# ── 3. LibreHardwareMonitor ───────────────────────────────────────────────────
LogStep "Vérification de LibreHardwareMonitor"
$lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse `
              -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

if ($lhmExe) {
    LogOK "LibreHardwareMonitor déjà installé : $lhmExe"
} else {
    try {
        LogInfo "Récupération de la dernière version sur GitHub..."
        $rel = Invoke-RestMethod `
            "https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest" `
            -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
        $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        $lhmZip = "$env:TEMP\lhm.zip"
        
        LogInfo "Téléchargement de $($asset.name)..."
        Invoke-WebRequest $asset.browser_download_url -OutFile $lhmZip -UseBasicParsing
        New-Item -ItemType Directory -Force -Path $LHM_DIR | Out-Null
        Expand-Archive -Path $lhmZip -DestinationPath $LHM_DIR -Force
        Remove-Item $lhmZip -Force
        
        $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse |
                  Select-Object -First 1 -ExpandProperty FullName
        if ($lhmExe) {
            LogOK "LibreHardwareMonitor installé avec succès !"
        } else {
            LogErr "LibreHardwareMonitor.exe introuvable après extraction."
        }
    } catch {
        LogErr "Erreur d'installation de LHM : $_"
    }
}

# ── 4. Collecteur de Métriques ────────────────────────────────────────────────
LogStep "Vérification du collecteur"
$collectorDist = "$COLLECTOR_DIR\dist\index.js"

if (Test-Path $collectorDist) {
    LogOK "Collecteur déjà installé dans $COLLECTOR_DIR"
} else {
    if (-not $nodeOk) {
        LogWarn "Impossible d'installer le collecteur : Node.js est absent."
    } else {
        try {
            LogInfo "Récupération du collecteur pré-compilé sur GitHub..."
            $rel = Invoke-RestMethod `
                "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
            $prebuilt = $rel.assets | Where-Object { $_.name -eq "collector-dist.zip" } | Select-Object -First 1
            if ($prebuilt) {
                $zipTmp = "$env:TEMP\collector-dist.zip"
                Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing
                if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $COLLECTOR_DIR | Out-Null
                Expand-Archive -Path $zipTmp -DestinationPath $COLLECTOR_DIR -Force
                Remove-Item $zipTmp -Force
                if (Test-Path $collectorDist) {
                    LogOK "Collecteur installé avec succès !"
                } else {
                    LogErr "Le collecteur est extrait mais dist/index.js reste introuvable."
                }
            } else {
                LogWarn "Aucun collecteur pré-compilé (collector-dist.zip) disponible dans la dernière release. Construction locale nécessaire."
            }
        } catch {
            LogErr "Erreur lors du téléchargement du collecteur : $_"
        }
    }
}

# ── 5. Configuration d'InfluxDB ───────────────────────────────────────────────
if ((Test-Path $influxExe) -and -not [string]::IsNullOrWhiteSpace($AdminPass)) {
    LogStep "Configuration de la base de données InfluxDB"
    $influxRunning = $false
    try {
        $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
        $influxRunning = ($h.status -eq "pass")
    } catch {}
    
    $tmpProc = $null
    $influxReady = $influxRunning
    
    if (-not $influxRunning) {
        LogInfo "Démarrage temporaire d'InfluxDB..."
        $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep 3
            try {
                $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
                if ($h.status -eq "pass") {
                    $influxReady = $true
                    break
                }
            } catch {}
            LogInfo "Attente de démarrage d'InfluxDB... ($($i * 3)s)"
        }
    }
    
    if ($influxReady) {
        try {
            $token = $null
            $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET
            
            if ($status.allowed -eq $true) {
                LogInfo "Configuration de l'organisation et du bucket..."
                $body = @{
                    username="admin";
                    password=$AdminPass;
                    org="home";
                    bucket="pc-monitor";
                    retentionPeriodSeconds=2592000
                } | ConvertTo-Json
                $result = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method POST -Body $body -ContentType "application/json"
                $token = $result.auth.token
                LogOK "InfluxDB configuré avec succès !"
            } else {
                LogInfo "Récupération du token existant..."
                $cred = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$AdminPass"))
                $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" -Method POST -Headers @{Authorization="Basic $cred"} -UseBasicParsing
                $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                $authHdr = @{Cookie=$cookie}
                
                $orgs    = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                $orgId   = $orgs.orgs[0].id
                
                $auths   = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                $ex      = $auths.authorizations | Where-Object { $_.description -eq "pc-monitor-collector" } | Select-Object -First 1
                if ($ex) {
                    $token = $ex.token
                    LogOK "Token existant récupéré !"
                } else {
                    $bkts  = Invoke-RestMethod "$INFLUX_URL/api/v2/buckets?org=home" -Headers $authHdr
                    $bktId = ($bkts.buckets | Where-Object { $_.name -eq "pc-monitor" } | Select-Object -First 1).id
                    $tBody = @{
                        orgID=$orgId;
                        description="pc-monitor-collector";
                        permissions=@(
                            @{action="read";resource=@{type="buckets";orgID=$orgId;id=$bktId}},
                            @{action="write";resource=@{type="buckets";orgID=$orgId;id=$bktId}}
                        )
                    } | ConvertTo-Json -Depth 5
                    $auth  = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations" -Method POST -Body $tBody -Headers @{Cookie=$cookie;"Content-Type"="application/json"}
                    $token = $auth.token
                    LogOK "Nouveau token API généré !"
                }
            }
            
            if ($token) {
                [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "User")
                $env:INFLUX_TOKEN = $token
                LogOK "Token enregistré dans l'environnement utilisateur."
            }
        } catch {
            LogErr "Erreur de configuration de la base de données : $_"
        }
    } else {
        LogErr "Impossible de contacter l'instance InfluxDB temporaire."
    }
    
    if ($tmpProc) {
        LogInfo "Arrêt de l'instance temporaire..."
        Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue
    }
}

# ── 6. Tâches Planifiées (Démarrage silencieux au Boot) ───────────────────────
LogStep "Enregistrement des tâches de démarrage en tâche de fond"
try {
    $atLogon  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $userPrin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $svcPrin  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $noLimit  = [TimeSpan]::Zero
    $restart1 = New-TimeSpan -Minutes 1
    
    function RegTask { param($N,$A,$T,$P,$S,$D)
        if (Get-ScheduledTask -TaskName $N -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $N -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $N -Confirm:$false -ErrorAction SilentlyContinue
        }
        Register-ScheduledTask -TaskName $N -Action $A -Trigger $T -Principal $P -Settings $S -Description $D | Out-Null
        LogOK "Tâche '$N' enregistrée avec succès."
    }
    
    if (Test-Path $influxExe) {
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 5 -RestartInterval $restart1 -StartWhenAvailable
        RegTask "PC-Monitor-InfluxDB" (New-ScheduledTaskAction -Execute $influxExe -WorkingDirectory (Split-Path $influxExe)) $atLogon $svcPrin $s "Base InfluxDB locale pour monitor4me"
    }
    
    if ($lhmExe) {
        $lhmCmd = "-NonInteractive -WindowStyle Hidden -Command `"Start-Process '$lhmExe' -WindowStyle Minimized`""
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
        RegTask "PC-Monitor-LHM" (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $lhmCmd) $atLogon $userPrin $s "LibreHardwareMonitor REST"
    }
    
    $nodePath = Get-Command "node" -ErrorAction SilentlyContinue
    $nodeExe  = if ($nodePath) { $nodePath.Source } else { "$env:ProgramFiles\nodejs\node.exe" }
    
    if ((Test-Path $nodeExe) -and (Test-Path $collectorDist)) {
        $cTrig = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $cTrig.Delay = "PT25S"
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
        RegTask "PC-Monitor-Collector" (New-ScheduledTaskAction -Execute $nodeExe -Argument "$COLLECTOR_DIR\dist\index.js" -WorkingDirectory $COLLECTOR_DIR) $cTrig $userPrin $s "Collecteur monitor4me"
    }
    
    LogOK "Toutes les tâches de fond configurées !"
} catch {
    LogErr "Erreur lors de la configuration des tâches système : $_"
}

# ── 7. Raccourci Bureau ────────────────────────────────────────────────────────
LogStep "Création du raccourci"
try {
    $appExe = Find-AppExe
    if ($appExe) {
        $desktop = [System.Environment]::GetFolderPath("Desktop")
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
        $sc.TargetPath = $appExe
        $sc.WorkingDirectory = Split-Path $appExe
        $sc.Description = "monitor4me - PC Hardware Dashboard"
        $sc.Save()
        LogOK "Raccourci de l'application créé sur le bureau."
    } else {
        LogWarn "Impossible de créer le raccourci : exécutable monitor4me introuvable."
    }
} catch {
    LogWarn "Création du raccourci ignorée."
}

# Écriture finale de la configuration tarifaire du collecteur
try {
    if (Test-Path $COLLECTOR_DIR) {
        $configPath = "$COLLECTOR_DIR\user-config.json"
        $cfgJson = @{tarifKwh = $TarifKwh; periphWatts = 0} | ConvertTo-Json
        $cfgJson | Out-File $configPath -Encoding UTF8 -Force
        LogOK "Configuration tarifaire enregistrée : $TarifKwh €/kWh."
    }
} catch {}

LogStep "INSTALLATION_SUCCESS"
