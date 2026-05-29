[CmdletBinding()]
param(
    [string]$AdminPass = "monitor4me-local",
    [double]$TarifKwh  = 0.2516,
    [string]$LogFile   = ""
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

$DEPS_DIR      = "$env:APPDATA\monitor4me"
$COLLECTOR_DIR = "$DEPS_DIR\collector"
$INFLUX_DIR    = "$env:ProgramFiles\InfluxDB"
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"
$GITHUB_REPO   = "MehdiZen/monitor4me"

function LogLine {
    param([string]$line)
    Write-Output $line
    if (-not [string]::IsNullOrEmpty($LogFile)) {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

function LogStep { param([string]$m) LogLine "STEP: $m" }
function LogOK   { param([string]$m) LogLine "OK: $m"   }
function LogInfo { param([string]$m) LogLine "INFO: $m" }
function LogWarn { param([string]$m) LogLine "WARN: $m" }
function LogErr  { param([string]$m) LogLine "ERR: $m"  }

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
    return $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

LogStep "Debut de la configuration"

# -- 1. Node.js --
LogStep "Node.js LTS"
if (IsCmd "node") {
    $v = & node --version 2>&1
    LogOK "Node.js deja installe : $v"
} else {
    try {
        LogInfo "Recuperation de la version LTS courante..."
        $nodeMeta = Invoke-RestMethod "https://nodejs.org/dist/index.json" -TimeoutSec 15 |
                    Where-Object { $_.lts -is [string] } | Select-Object -First 1
        $nodeVer  = $nodeMeta.version
        $nodeMsi  = "$env:TEMP\node-install.msi"
        $nodeUrl  = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi"
        LogInfo "Telechargement de Node.js $nodeVer..."
        Invoke-WebRequest $nodeUrl -OutFile $nodeMsi -UseBasicParsing
        LogInfo "Installation de Node.js (MSI silencieux)..."
        Start-Process msiexec.exe -ArgumentList "/i `"$nodeMsi`" /qn ADDLOCAL=ALL" -Wait
        Remove-Item $nodeMsi -Force -ErrorAction SilentlyContinue
        RefreshPath
        $nodeOk = IsCmd "node"
        if (-not $nodeOk) {
            $nf = @("$env:ProgramFiles\nodejs\node.exe","${env:ProgramFiles(x86)}\nodejs\node.exe") |
                  Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($nf) { $env:PATH = $env:PATH + ";" + (Split-Path $nf); $nodeOk = $true }
        }
        if ($nodeOk) { $v = & node --version 2>&1; LogOK "Node.js $v installe" }
        else { LogWarn "Node.js installe - redemarre si node.exe reste introuvable" }
    } catch {
        LogWarn "Echec MSI : $_"
        if (IsCmd "winget") {
            winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            RefreshPath
            if (IsCmd "node") { LogOK "Node.js installe via winget" }
            else { LogErr "Impossible d'installer Node.js automatiquement" }
        } else { LogErr "Installe Node.js manuellement : https://nodejs.org" }
    }
}

$nodeOk = IsCmd "node"

# -- 2. InfluxDB --
LogStep "InfluxDB 2.x"
$influxExe = "$INFLUX_DIR\influxd.exe"
$fc = Get-Command "influxd" -ErrorAction SilentlyContinue
if ($fc) { $influxExe = $fc.Source }

if (Test-Path $influxExe) {
    LogOK "InfluxDB deja installe : $influxExe"
} else {
    try {
        $zipUrl     = "https://dl.influxdata.com/influxdb/releases/influxdb2-" + $INFLUX_VER + "-windows.zip"
        $zipTmp     = "$env:TEMP\influxdb.zip"
        $extractTmp = "$env:TEMP\influx_extract"
        LogInfo "Telechargement InfluxDB $INFLUX_VER..."
        Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
        if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
        LogInfo "Extraction..."
        Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
        $inner = Get-ChildItem $extractTmp | Select-Object -First 1
        New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
        Copy-Item -Path "$($inner.FullName)\*" -Destination $INFLUX_DIR -Recurse -Force
        Remove-Item $extractTmp -Recurse -Force
        Remove-Item $zipTmp -Force
        if (Test-Path $influxExe) { LogOK "InfluxDB $INFLUX_VER installe" }
        else { LogErr "influxd.exe introuvable apres extraction" }
    } catch { LogErr "Echec InfluxDB : $_" }
}

# -- 3. LibreHardwareMonitor --
LogStep "LibreHardwareMonitor"
$lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse `
              -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

if ($lhmExe) {
    LogOK "LHM deja installe : $lhmExe"
} else {
    try {
        LogInfo "Recuperation derniere version GitHub..."
        $rel   = Invoke-RestMethod `
            "https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest" `
            -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
        $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        $lhmZip = "$env:TEMP\lhm.zip"
        LogInfo "Telechargement $($asset.name)..."
        Invoke-WebRequest $asset.browser_download_url -OutFile $lhmZip -UseBasicParsing
        New-Item -ItemType Directory -Force -Path $LHM_DIR | Out-Null
        Expand-Archive -Path $lhmZip -DestinationPath $LHM_DIR -Force
        Remove-Item $lhmZip -Force
        $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse |
                  Select-Object -First 1 -ExpandProperty FullName
        if ($lhmExe) { LogOK "LibreHardwareMonitor installe" }
        else { LogErr "LibreHardwareMonitor.exe introuvable apres extraction" }
    } catch { LogErr "Echec LHM : $_" }
}

# -- 4. Collecteur --
LogStep "Collecteur de metriques"
$collectorDist = "$COLLECTOR_DIR\dist\index.js"

if (Test-Path $collectorDist) {
    LogOK "Collecteur deja installe"
} elseif ($nodeOk) {
    try {
        LogInfo "Recuperation release GitHub..."
        $rel = Invoke-RestMethod `
            "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
            -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
        $prebuilt = $rel.assets | Where-Object { $_.name -eq "collector-dist.zip" } | Select-Object -First 1
        if ($prebuilt) {
            LogInfo "Telechargement collecteur pre-compile..."
            $zipTmp = "$env:TEMP\collector-dist.zip"
            Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing
            if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
            New-Item -ItemType Directory -Force $COLLECTOR_DIR | Out-Null
            Expand-Archive -Path $zipTmp -DestinationPath $COLLECTOR_DIR -Force
            Remove-Item $zipTmp -Force
            if (Test-Path $collectorDist) { LogOK "Collecteur installe" }
            else { LogErr "dist/index.js introuvable apres extraction" }
        } else { LogWarn "collector-dist.zip absent de la release GitHub" }
    } catch { LogErr "Echec collecteur : $_" }
} else {
    LogWarn "Collecteur ignore : Node.js non disponible"
}

# -- 5. Configuration InfluxDB --
if ((Test-Path $influxExe) -and -not [string]::IsNullOrWhiteSpace($AdminPass)) {
    LogStep "Configuration InfluxDB"
    $influxRunning = $false
    try {
        $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
        $influxRunning = ($h.status -eq "pass")
    } catch {}

    $tmpProc     = $null
    $influxReady = $influxRunning
    if (-not $influxRunning) {
        LogInfo "Demarrage temporaire InfluxDB..."
        $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep 3
            try {
                $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
                if ($h.status -eq "pass") { $influxReady = $true; break }
            } catch {}
            LogInfo "Attente InfluxDB... ($($i * 3)s)"
        }
    }

    if ($influxReady) {
        try {
            $token  = $null
            $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET
            if ($status.allowed -eq $true) {
                $body = @{
                    username="admin"; password=$AdminPass
                    org="home"; bucket="pc-monitor"
                    retentionPeriodSeconds=2592000
                } | ConvertTo-Json
                $result = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" `
                    -Method POST -Body $body -ContentType "application/json"
                $token = $result.auth.token
                LogOK "InfluxDB configure (org:home, bucket:pc-monitor)"
            } else {
                $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$AdminPass"))
                $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" `
                    -Method POST -Headers @{Authorization="Basic $cred"} -UseBasicParsing
                $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                $authHdr = @{Cookie=$cookie}
                $orgs    = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                $orgId   = $orgs.orgs[0].id
                $auths   = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                $ex      = $auths.authorizations |
                           Where-Object { $_.description -eq "pc-monitor-collector" } |
                           Select-Object -First 1
                if ($ex) {
                    $token = $ex.token; LogOK "Token existant recupere"
                } else {
                    $bkts  = Invoke-RestMethod "$INFLUX_URL/api/v2/buckets?org=home" -Headers $authHdr
                    $bktId = ($bkts.buckets | Where-Object { $_.name -eq "pc-monitor" } | Select-Object -First 1).id
                    $tBody = @{
                        orgID=$orgId; description="pc-monitor-collector"
                        permissions=@(
                            @{action="read";  resource=@{type="buckets";orgID=$orgId;id=$bktId}},
                            @{action="write"; resource=@{type="buckets";orgID=$orgId;id=$bktId}}
                        )
                    } | ConvertTo-Json -Depth 5
                    $auth  = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations" `
                        -Method POST -Body $tBody `
                        -Headers @{Cookie=$cookie; "Content-Type"="application/json"}
                    $token = $auth.token; LogOK "Nouveau token cree"
                }
            }
            if ($token) {
                [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "User")
                $env:INFLUX_TOKEN = $token
                LogOK "INFLUX_TOKEN sauvegarde"
            }
        } catch { LogErr "Config InfluxDB : $_" }
    } else { LogWarn "InfluxDB ne repond pas apres 60s" }

    if ($tmpProc) { Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue }
}

# -- 6. Taches planifiees --
LogStep "Taches planifiees (boot)"
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
        LogOK "Tache '$N' creee"
    }

    if (Test-Path $influxExe) {
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 5 -RestartInterval $restart1 -StartWhenAvailable
        RegTask "PC-Monitor-InfluxDB" (New-ScheduledTaskAction -Execute $influxExe -WorkingDirectory (Split-Path $influxExe)) $atLogon $svcPrin $s "InfluxDB 2.x pour monitor4me"
    }

    if ($lhmExe) {
        $lhmCmd = "-NonInteractive -WindowStyle Hidden -Command `"Start-Process '$lhmExe' -WindowStyle Minimized`""
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -StartWhenAvailable
        RegTask "PC-Monitor-LHM" (New-ScheduledTaskAction -Execute "powershell.exe" -Argument $lhmCmd) $atLogon $userPrin $s "LibreHardwareMonitor REST :8085"
    }

    $nodePath = Get-Command "node" -ErrorAction SilentlyContinue
    $nodeExe  = if ($nodePath) { $nodePath.Source } else { "$env:ProgramFiles\nodejs\node.exe" }
    if ((Test-Path $nodeExe) -and (Test-Path $collectorDist)) {
        $cTrig = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $cTrig.Delay = "PT25S"
        $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
        RegTask "PC-Monitor-Collector" (New-ScheduledTaskAction -Execute $nodeExe -Argument "$COLLECTOR_DIR\dist\index.js" -WorkingDirectory $COLLECTOR_DIR) $cTrig $userPrin $s "Collecteur monitor4me"
    }

    LogOK "Taches de boot configurees"
} catch { LogErr "Erreur taches planifiees : $_" }

# -- 7. Raccourci bureau --
LogStep "Raccourci bureau"
try {
    $appExe = Find-AppExe
    if ($appExe) {
        $desktop = [System.Environment]::GetFolderPath("Desktop")
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
        $sc.TargetPath       = $appExe
        $sc.WorkingDirectory = Split-Path $appExe
        $sc.Description      = "monitor4me - PC Hardware Dashboard"
        $sc.Save()
        LogOK "Raccourci cree sur le bureau"
    } else { LogWarn "App introuvable - raccourci ignore" }
} catch { LogWarn "Raccourci ignore : $_" }

# -- 8. Config tarifaire collecteur --
try {
    if (Test-Path $COLLECTOR_DIR) {
        $cfgPath = "$COLLECTOR_DIR\user-config.json"
        @{tarifKwh=$TarifKwh; periphWatts=0} | ConvertTo-Json | Out-File $cfgPath -Encoding UTF8 -Force
        LogOK "Config tarifaire sauvegardee : $TarifKwh EUR/kWh"
    }
} catch {}

LogStep "INSTALLATION_SUCCESS"
