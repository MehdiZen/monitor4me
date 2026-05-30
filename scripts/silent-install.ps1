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
$INFLUX_DATA   = "C:\ProgramData\monitor4me\influxdb"   # repertoire commun user+SYSTEM
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"
$GITHUB_REPO   = "MehdiZen/monitor4me"

# Arguments influxd pour pointer vers le repertoire de donnees commun
$INFLUX_ARGS   = "--bolt-path `"$INFLUX_DATA\influxd.bolt`" --engine-path `"$INFLUX_DATA\engine`""

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
        $allFiles = Get-ChildItem $extractTmp -Recurse -File | Select-Object -First 8
        LogInfo "ZIP contenu : $($allFiles.Name -join ', ')"
        $influxBin = $allFiles | Where-Object { $_.Name -eq 'influxd.exe' } | Select-Object -First 1
        if (-not $influxBin) { throw "influxd.exe absent du ZIP" }
        New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
        Copy-Item -Path $influxBin.FullName -Destination $INFLUX_DIR -Force
        $allFiles | Where-Object { $_.Name -ne 'influxd.exe' } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $INFLUX_DIR -Force
        }
        Remove-Item $extractTmp -Recurse -Force
        Remove-Item $zipTmp -Force
        if (Test-Path $influxExe) { LogOK "InfluxDB $INFLUX_VER installe" }
        else { LogErr "influxd.exe introuvable dans $INFLUX_DIR" }
    } catch { LogErr "Echec InfluxDB : $_" }
}

# -- 3. .NET Desktop Runtime (requis par LHM) --
LogStep ".NET Desktop Runtime"
$dotnetOk = $false
# Detection : cherche dans le registre (plus fiable que dotnet.exe en contexte eleve)
$dotnetKeys = @(
    "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App",
    "HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"
)
foreach ($key in $dotnetKeys) {
    if (Test-Path $key) {
        $versions = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($versions.PSObject.Properties | Where-Object { $_.Name -match "^[6-9]\." }) {
            $dotnetOk = $true; break
        }
    }
}
# Fallback : dotnet CLI
if (-not $dotnetOk) {
    try {
        $r = & "$env:ProgramFiles\dotnet\dotnet.exe" --list-runtimes 2>&1
        $dotnetOk = ($r | Where-Object { $_ -match "Microsoft\.WindowsDesktop\.App\s+[6-9]\." }) -ne $null
    } catch {}
}

if ($dotnetOk) {
    LogOK ".NET Desktop Runtime deja installe"
} else {
    LogInfo "Telechargement .NET Desktop Runtime 8..."
    $dotnetUrl = "https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe"
    $dotnetTmp  = "$env:TEMP\dotnet-desktop-runtime.exe"
    try {
        Invoke-WebRequest $dotnetUrl -OutFile $dotnetTmp -UseBasicParsing -TimeoutSec 120
        LogInfo "Installation .NET Desktop Runtime 8 (silencieuse)..."
        Start-Process $dotnetTmp -ArgumentList "/install /quiet /norestart" -Wait
        Remove-Item $dotnetTmp -Force -ErrorAction SilentlyContinue
        LogOK ".NET Desktop Runtime 8 installe"
    } catch {
        LogErr "Echec installation .NET : $_"
    }
}

# -- 4. LibreHardwareMonitor --
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
        Invoke-WebRequest $asset.browser_download_url -OutFile $lhmZip -UseBasicParsing -TimeoutSec 120
        New-Item -ItemType Directory -Force -Path $LHM_DIR | Out-Null
        Expand-Archive -Path $lhmZip -DestinationPath $LHM_DIR -Force
        Remove-Item $lhmZip -Force
        $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse |
                  Select-Object -First 1 -ExpandProperty FullName
        if ($lhmExe) { LogOK "LibreHardwareMonitor installe" }
        else { LogErr "LibreHardwareMonitor.exe introuvable apres extraction" }
    } catch { LogErr "Echec LHM : $_" }
}

# Active le web server LHM sur :8085 (ecrit le fichier config avant le premier lancement)
$lhmCfgDir = "$env:APPDATA\LibreHardwareMonitor"
$lhmCfg    = "$lhmCfgDir\LibreHardwareMonitor.config"
if (-not (Test-Path $lhmCfg)) {
    New-Item -ItemType Directory -Force -Path $lhmCfgDir | Out-Null
    @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <userSettings>
    <LibreHardwareMonitor.Properties.Settings>
      <setting name="runWebServer" serializeAs="String">
        <value>True</value>
      </setting>
      <setting name="listenerPort" serializeAs="String">
        <value>8085</value>
      </setting>
      <setting name="startMinimized" serializeAs="String">
        <value>True</value>
      </setting>
    </LibreHardwareMonitor.Properties.Settings>
  </userSettings>
</configuration>
'@ | Out-File $lhmCfg -Encoding UTF8 -Force
    LogOK "LHM web server configure (:8085)"
} else {
    # Fichier existant : s'assure que runWebServer=True et port=8085
    [xml]$xml = Get-Content $lhmCfg
    $ns = $xml.configuration.userSettings.'LibreHardwareMonitor.Properties.Settings'
    function Set-LhmSetting($name, $val) {
        $node = $ns.setting | Where-Object { $_.name -eq $name }
        if ($node) { $node.value = $val }
        else {
            $s = $xml.CreateElement("setting")
            $s.SetAttribute("name", $name); $s.SetAttribute("serializeAs", "String")
            $v = $xml.CreateElement("value"); $v.InnerText = $val
            $s.AppendChild($v) | Out-Null
            $ns.AppendChild($s) | Out-Null
        }
    }
    Set-LhmSetting "runWebServer" "True"
    Set-LhmSetting "listenerPort" "8085"
    $xml.Save($lhmCfg)
    LogOK "LHM web server verifie (:8085)"
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
            Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing -TimeoutSec 120
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
if (Test-Path $influxExe) {
    LogStep "Configuration InfluxDB"
    $influxRunning = $false
    try {
        $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
        $influxRunning = ($h.status -eq "pass")
    } catch {}

    # Demarre influxd avec le repertoire de donnees commun (user + SYSTEM)
    function Start-InfluxTemp {
        New-Item -ItemType Directory -Force -Path $INFLUX_DATA | Out-Null
        $p = Start-Process -FilePath $influxExe -ArgumentList $INFLUX_ARGS `
                 -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep 3
            try {
                $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3
                if ($h.status -eq "pass") { return $p }
            } catch {}
        }
        return $p
    }

    # Configure depuis zero (setup POST)
    function Setup-InfluxFresh {
        $body = @{
            username="admin"; password=$AdminPass
            org="home"; bucket="pc-monitor"
            retentionPeriodSeconds=2592000
        } | ConvertTo-Json
        $r = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" `
                 -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
        return $r.auth.token
    }

    $tmpProc     = $null
    $influxReady = $influxRunning
    if (-not $influxRunning) {
        LogInfo "Demarrage temporaire InfluxDB..."
        $tmpProc = Start-InfluxTemp
        try { $influxReady = ((Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3).status -eq "pass") } catch {}
    }

    if ($influxReady) {
        $token      = $null
        $tokenCache = "$DEPS_DIR\influx-token.txt"

        # 0. Token cache valide ?
        if (Test-Path $tokenCache) {
            $cached = (Get-Content $tokenCache -Raw -ErrorAction SilentlyContinue).Trim()
            if ($cached) {
                try {
                    Invoke-RestMethod "$INFLUX_URL/api/v2/me" `
                        -Headers @{Authorization="Token $cached"} -TimeoutSec 5 | Out-Null
                    $token = $cached
                    LogOK "Token cache valide"
                } catch { $token = $null }
            }
        }

        if (-not $token) {
            $status = $null
            try { $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET -TimeoutSec 5 } catch {}

            if ($status.allowed -eq $true) {
                # Installation fraiche
                try {
                    $token = Setup-InfluxFresh
                    LogOK "InfluxDB configure (org:home, bucket:pc-monitor)"
                } catch { LogErr "Setup InfluxDB : $_" }
            } else {
                # Deja configure — essaie plusieurs mots de passe
                $candidates = @($AdminPass, "", "monitor4me-local") | Select-Object -Unique
                foreach ($pwd in $candidates) {
                    try {
                        $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$pwd"))
                        $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" `
                            -Method POST -Headers @{Authorization="Basic $cred"} `
                            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                        $authHdr = @{Cookie=$cookie}

                        $orgs  = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                        $orgId = $orgs.orgs[0].id
                        $auths = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                        $ex    = $auths.authorizations |
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
                        break
                    } catch { continue }
                }

                if (-not $token) {
                    # Toujours bloque : donnees incompatibles dans $INFLUX_DATA
                    # Reset complet : arret, suppression, reconfiguration
                    LogInfo "Reset donnees InfluxDB ($INFLUX_DATA)..."
                    if ($tmpProc) { Stop-Process -Id $tmpProc.Id -Force -ErrorAction SilentlyContinue; Start-Sleep 2 }
                    Get-Process influxd -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep 2
                    Remove-Item $INFLUX_DATA -Recurse -Force -ErrorAction SilentlyContinue
                    $tmpProc = Start-InfluxTemp
                    $readyAfterReset = $false
                    try { $readyAfterReset = ((Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3).status -eq "pass") } catch {}
                    if ($readyAfterReset) {
                        try {
                            $token = Setup-InfluxFresh
                            LogOK "InfluxDB reconfigure apres reset"
                        } catch { LogErr "Reconfiguration InfluxDB : $_" }
                    } else { LogErr "InfluxDB ne repond plus apres reset" }
                }
            }
        }

        if ($token) {
            [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "User")
            $env:INFLUX_TOKEN = $token
            New-Item -ItemType Directory -Force -Path $DEPS_DIR | Out-Null
            Set-Content $tokenCache $token -Encoding UTF8 -NoNewline
            LogOK "INFLUX_TOKEN sauvegarde"
        }
    } else { LogWarn "InfluxDB ne repond pas" }

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
        RegTask "PC-Monitor-InfluxDB" (New-ScheduledTaskAction -Execute $influxExe -Argument $INFLUX_ARGS -WorkingDirectory (Split-Path $influxExe)) $atLogon $svcPrin $s "InfluxDB 2.x pour monitor4me"
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

# -- 9. Demarrage immediat des services (sans attendre le prochain logon) --
LogStep "Demarrage des services"
try {
    Start-ScheduledTask "PC-Monitor-InfluxDB" -ErrorAction SilentlyContinue
    LogInfo "InfluxDB demarre"
    Start-Sleep 8
    Start-ScheduledTask "PC-Monitor-LHM" -ErrorAction SilentlyContinue
    LogInfo "LHM demarre"
    Start-Sleep 5
    Start-ScheduledTask "PC-Monitor-Collector" -ErrorAction SilentlyContinue
    LogInfo "Collecteur demarre"
    LogOK "Services lances"
} catch { LogWarn "Demarrage services : $_" }

LogStep "INSTALLATION_SUCCESS"
