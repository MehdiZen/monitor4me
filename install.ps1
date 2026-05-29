<#
.SYNOPSIS
  Installeur graphique monitor4me (Windows Forms).
  Cochez les composants, cliquez Installer.
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$GITHUB_REPO   = "MehdiZen/monitor4me"
$DEPS_DIR      = "$env:APPDATA\monitor4me"
$COLLECTOR_DIR = "$DEPS_DIR\collector"
$INFLUX_DIR    = "$env:ProgramFiles\InfluxDB"
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"

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
    $regs = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
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
    $broad = Get-ChildItem "$env:LOCALAPPDATA" -Filter "monitor4me.exe" -Recurse `
             -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($broad) { return $broad.FullName }
    return $null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text            = "monitor4me -- Installation"
$form.Size            = New-Object System.Drawing.Size(520, 640)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor       = [System.Drawing.Color]::White

function MkLabel {
    param([string]$text, [int]$x, [int]$y, [int]$w = 460, [int]$h = 20)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, $h)
    $l.ForeColor = [System.Drawing.Color]::White
    return $l
}

function MkCheck {
    param([string]$text, [int]$x, [int]$y, [bool]$chk = $true)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Location  = New-Object System.Drawing.Point($x, $y)
    $c.Size      = New-Object System.Drawing.Size(460, 22)
    $c.Checked   = $chk
    $c.ForeColor = [System.Drawing.Color]::White
    $c.FlatStyle = "Flat"
    return $c
}

$lblTitle = MkLabel "  monitor4me -- Installation" 0 0 520 45
$lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$form.Controls.Add($lblTitle)

$y = 58
$lbl = MkLabel "Selectionnez les composants a installer :" 20 $y
$lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lbl)

$y += 28
$chkNode = MkCheck "Node.js LTS  (requis pour le collecteur)" 20 $y
$form.Controls.Add($chkNode)

$y += 28
$chkInflux = MkCheck "InfluxDB 2.x  (base de donnees locale)" 20 $y
$form.Controls.Add($chkInflux)

$y += 26
$lblPass = MkLabel "    Mot de passe admin InfluxDB :" 20 $y 230 22
$lblPass.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
$form.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.TextBox
$txtPass.Location     = New-Object System.Drawing.Point(255, $y)
$txtPass.Size         = New-Object System.Drawing.Size(200, 22)
$txtPass.Text         = "monitor4me-local"
$txtPass.PasswordChar = [char]42
$txtPass.BackColor    = [System.Drawing.Color]::FromArgb(50, 50, 50)
$txtPass.ForeColor    = [System.Drawing.Color]::White
$txtPass.BorderStyle  = "FixedSingle"
$form.Controls.Add($txtPass)

$y += 32
$chkLhm = MkCheck "LibreHardwareMonitor  (lecture des capteurs CPU/GPU)" 20 $y
$form.Controls.Add($chkLhm)

$y += 28
$chkApp = MkCheck "Application monitor4me  (interface graphique)" 20 $y
$form.Controls.Add($chkApp)

$y += 28
$chkCollector = MkCheck "Collecteur de metriques  (LHM -> InfluxDB)" 20 $y
$form.Controls.Add($chkCollector)

$y += 28
$chkShortcut = MkCheck "Raccourci sur le bureau" 20 $y
$form.Controls.Add($chkShortcut)

$y += 28
$chkTasks = MkCheck "Demarrage automatique au boot  (taches planifiees)" 20 $y
$form.Controls.Add($chkTasks)

$y += 38
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "Installer"
$btnInstall.Location  = New-Object System.Drawing.Point(20, $y)
$btnInstall.Size      = New-Object System.Drawing.Size(460, 36)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$btnInstall.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$y += 46
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point(20, $y)
$txtLog.Size       = New-Object System.Drawing.Size(460, 165)
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(15, 15, 15)
$txtLog.ForeColor  = [System.Drawing.Color]::FromArgb(200, 200, 200)
$txtLog.ReadOnly   = $true
$txtLog.Font       = New-Object System.Drawing.Font("Consolas", 8)
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

$y += 175
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = "Fermer"
$btnClose.Location  = New-Object System.Drawing.Point(20, $y)
$btnClose.Size      = New-Object System.Drawing.Size(460, 32)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.FlatStyle = "Flat"
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Log {
    param([string]$msg, [string]$col = "White")
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    switch ($col) {
        "Green"  { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(80, 220, 80)  }
        "Yellow" { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(220, 200, 60) }
        "Red"    { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(220, 80, 80)  }
        "Gray"   { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(140, 140, 140)}
        default  { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(200, 200, 200)}
    }
    $txtLog.AppendText($msg + "`n")
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function LogOK   { param([string]$m) Log "  [OK]  $m" "Green"  }
function LogInfo { param([string]$m) Log "  ...   $m" "Gray"   }
function LogWarn { param([string]$m) Log "  /!\   $m" "Yellow" }
function LogErr  { param([string]$m) Log "  ERR   $m" "Red"    }
function LogStep { param([string]$m) Log ""; Log "--- $m ---"  }

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnInstall.Text    = "Installation en cours..."
    $appExe        = $null
    $influxExe     = "$INFLUX_DIR\influxd.exe"
    $lhmExe        = $null
    $collectorDist = "$COLLECTOR_DIR\dist\index.js"
    $nodeOk        = IsCmd "node"

    if ($chkNode.Checked) {
        LogStep "Node.js LTS"
        if (IsCmd "node") {
            $v = & node --version 2>&1; LogOK "Deja installe : $v"; $nodeOk = $true
        } else {
            try {
                LogInfo "Recuperation version LTS courante..."
                $nodeMeta = Invoke-RestMethod "https://nodejs.org/dist/index.json" -TimeoutSec 15 |
                            Where-Object { <#
.SYNOPSIS
  Installeur graphique monitor4me (Windows Forms).
  Cochez les composants, cliquez Installer.
#>

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$GITHUB_REPO   = "MehdiZen/monitor4me"
$DEPS_DIR      = "$env:APPDATA\monitor4me"
$COLLECTOR_DIR = "$DEPS_DIR\collector"
$INFLUX_DIR    = "$env:ProgramFiles\InfluxDB"
$LHM_DIR       = "$env:ProgramFiles\LibreHardwareMonitor"
$INFLUX_URL    = "http://localhost:8086"
$INFLUX_VER    = "2.7.11"

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
    $regs = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
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
    $broad = Get-ChildItem "$env:LOCALAPPDATA" -Filter "monitor4me.exe" -Recurse `
             -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($broad) { return $broad.FullName }
    return $null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text            = "monitor4me -- Installation"
$form.Size            = New-Object System.Drawing.Size(520, 640)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor       = [System.Drawing.Color]::White

function MkLabel {
    param([string]$text, [int]$x, [int]$y, [int]$w = 460, [int]$h = 20)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, $h)
    $l.ForeColor = [System.Drawing.Color]::White
    return $l
}

function MkCheck {
    param([string]$text, [int]$x, [int]$y, [bool]$chk = $true)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Location  = New-Object System.Drawing.Point($x, $y)
    $c.Size      = New-Object System.Drawing.Size(460, 22)
    $c.Checked   = $chk
    $c.ForeColor = [System.Drawing.Color]::White
    $c.FlatStyle = "Flat"
    return $c
}

$lblTitle = MkLabel "  monitor4me -- Installation" 0 0 520 45
$lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$form.Controls.Add($lblTitle)

$y = 58
$lbl = MkLabel "Selectionnez les composants a installer :" 20 $y
$lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lbl)

$y += 28
$chkNode = MkCheck "Node.js LTS  (requis pour le collecteur)" 20 $y
$form.Controls.Add($chkNode)

$y += 28
$chkInflux = MkCheck "InfluxDB 2.x  (base de donnees locale)" 20 $y
$form.Controls.Add($chkInflux)

$y += 26
$lblPass = MkLabel "    Mot de passe admin InfluxDB :" 20 $y 230 22
$lblPass.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
$form.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.TextBox
$txtPass.Location     = New-Object System.Drawing.Point(255, $y)
$txtPass.Size         = New-Object System.Drawing.Size(200, 22)
$txtPass.Text         = "monitor4me-local"
$txtPass.PasswordChar = [char]42
$txtPass.BackColor    = [System.Drawing.Color]::FromArgb(50, 50, 50)
$txtPass.ForeColor    = [System.Drawing.Color]::White
$txtPass.BorderStyle  = "FixedSingle"
$form.Controls.Add($txtPass)

$y += 32
$chkLhm = MkCheck "LibreHardwareMonitor  (lecture des capteurs CPU/GPU)" 20 $y
$form.Controls.Add($chkLhm)

$y += 28
$chkApp = MkCheck "Application monitor4me  (interface graphique)" 20 $y
$form.Controls.Add($chkApp)

$y += 28
$chkCollector = MkCheck "Collecteur de metriques  (LHM -> InfluxDB)" 20 $y
$form.Controls.Add($chkCollector)

$y += 28
$chkShortcut = MkCheck "Raccourci sur le bureau" 20 $y
$form.Controls.Add($chkShortcut)

$y += 28
$chkTasks = MkCheck "Demarrage automatique au boot  (taches planifiees)" 20 $y
$form.Controls.Add($chkTasks)

$y += 38
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text      = "Installer"
$btnInstall.Location  = New-Object System.Drawing.Point(20, $y)
$btnInstall.Size      = New-Object System.Drawing.Size(460, 36)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$btnInstall.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$y += 46
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point(20, $y)
$txtLog.Size       = New-Object System.Drawing.Size(460, 165)
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(15, 15, 15)
$txtLog.ForeColor  = [System.Drawing.Color]::FromArgb(200, 200, 200)
$txtLog.ReadOnly   = $true
$txtLog.Font       = New-Object System.Drawing.Font("Consolas", 8)
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

$y += 175
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = "Fermer"
$btnClose.Location  = New-Object System.Drawing.Point(20, $y)
$btnClose.Size      = New-Object System.Drawing.Size(460, 32)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.FlatStyle = "Flat"
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

function Log {
    param([string]$msg, [string]$col = "White")
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    switch ($col) {
        "Green"  { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(80, 220, 80)  }
        "Yellow" { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(220, 200, 60) }
        "Red"    { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(220, 80, 80)  }
        "Gray"   { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(140, 140, 140)}
        default  { $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(200, 200, 200)}
    }
    $txtLog.AppendText($msg + "`n")
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function LogOK   { param([string]$m) Log "  [OK]  $m" "Green"  }
function LogInfo { param([string]$m) Log "  ...   $m" "Gray"   }
function LogWarn { param([string]$m) Log "  /!\   $m" "Yellow" }
function LogErr  { param([string]$m) Log "  ERR   $m" "Red"    }
function LogStep { param([string]$m) Log ""; Log "--- $m ---"  }

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnInstall.Text    = "Installation en cours..."
    $appExe        = $null
    $influxExe     = "$INFLUX_DIR\influxd.exe"
    $lhmExe        = $null
    $collectorDist = "$COLLECTOR_DIR\dist\index.js"
    $nodeOk        = IsCmd "node"

    if ($chkNode.Checked) {
        LogStep "Node.js LTS"
        if (IsCmd "node") {
            $v = & node --version 2>&1; LogOK "Deja installe : $v"; $nodeOk = $true
        } else {
            try {
                LogInfo "Recuperation version LTS courante..."
                $nodeMeta = Invoke-RestMethod "https://nodejs.org/dist/index.json" -TimeoutSec 15 |
                            Where-Object { $_.lts -ne $false } | Select-Object -First 1
                $nodeVer  = $nodeMeta.version
                $nodeMsi  = "$env:TEMP\node-install.msi"
                $nodeUrl  = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi"
                LogInfo "Telechargement Node.js $nodeVer..."
                Invoke-WebRequest $nodeUrl -OutFile $nodeMsi -UseBasicParsing
                LogInfo "Installation MSI (quelques minutes)..."
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
                else { LogWarn "MSI installe - redemarre le PC si node reste introuvable" }
            } catch {
                LogErr "Echec MSI : $_"
                if (IsCmd "winget") {
                    LogInfo "Tentative winget..."
                    winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                        --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    RefreshPath; $nodeOk = IsCmd "node"
                    if ($nodeOk) { LogOK "Node.js installe via winget" }
                    else { LogWarn "Echec. Installe manuellement : https://nodejs.org" }
                } else { LogWarn "Installe manuellement : https://nodejs.org" }
            }
        }
    }

    if ($chkInflux.Checked) {
        LogStep "InfluxDB 2.x"
        $fc = Get-Command "influxd" -ErrorAction SilentlyContinue
        if ($fc) { $influxExe = $fc.Source }
        if (Test-Path $influxExe) { LogOK "Deja installe : $influxExe" } else {
            try {
                $zipUrl     = "https://dl.influxdata.com/influxdb/releases/influxdb2-" + $INFLUX_VER + "-windows.zip"
                $zipTmp     = "$env:TEMP\influxdb.zip"
                $extractTmp = "$env:TEMP\influx_extract"
                LogInfo "Telechargement InfluxDB $INFLUX_VER..."
                Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
                if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
                Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
                $inner = Get-ChildItem $extractTmp | Select-Object -First 1
                New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
                Get-ChildItem $inner.FullName | Copy-Item -Destination $INFLUX_DIR -Recurse -Force
                Remove-Item $extractTmp -Recurse -Force; Remove-Item $zipTmp -Force
                if (Test-Path $influxExe) { LogOK "InfluxDB $INFLUX_VER installe" }
                else { LogWarn "influxd.exe introuvable apres extraction." }
            } catch { LogErr "Echec InfluxDB : $_"; $influxExe = "" }
        }
    }

    if ($chkLhm.Checked) {
        LogStep "LibreHardwareMonitor"
        $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse `
                      -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($lhmExe) { LogOK "Deja installe : $lhmExe" } else {
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
                else { LogWarn "LibreHardwareMonitor.exe introuvable." }
            } catch { LogErr "Echec LHM : $_" }
        }
    }

    if ($chkApp.Checked) {
        LogStep "Application monitor4me"
        $appExe = Find-AppExe
        if ($appExe) { LogOK "Deja installee : $appExe" } else {
            try {
                LogInfo "Recuperation release GitHub..."
                $rel   = Invoke-RestMethod `
                    "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                    -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
                $asset = $rel.assets | Where-Object { $_.name -like "*setup.exe" } | Select-Object -First 1
                $setupExe = "$env:TEMP\monitor4me-setup.exe"
                LogInfo "Telechargement $($asset.name)..."
                Invoke-WebRequest $asset.browser_download_url -OutFile $setupExe -UseBasicParsing
                LogInfo "Installation..."
                Start-Process $setupExe -ArgumentList "/S" -Wait
                Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
                $appExe = Find-AppExe
                if ($appExe) { LogOK "monitor4me installe : $appExe" }
                else { LogWarn "Exe introuvable apres install - relance ce script." }
            } catch { LogErr "Echec app : $_" }
        }
    }

    if ($chkCollector.Checked) {
        if (-not $nodeOk) { LogWarn "Collecteur ignore : Node.js non installe." } else {
            LogStep "Collecteur de metriques"
            if (Test-Path $collectorDist) { LogOK "Deja installe" } else {
                try {
                    $rel = Invoke-RestMethod `
                        "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                        -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
                    $prebuilt = $rel.assets | Where-Object { $_.name -eq "collector-dist.zip" } | Select-Object -First 1
                    if ($prebuilt) {
                        LogInfo "Telechargement collecteur pre-compile..."
                        $zipTmp = "$env:TEMP\collector-dist.zip"
                        Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing
                        if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
                        New-Item -ItemType Directory $COLLECTOR_DIR | Out-Null
                        Expand-Archive -Path $zipTmp -DestinationPath $COLLECTOR_DIR -Force
                        Remove-Item $zipTmp -Force
                        if (Test-Path $collectorDist) { LogOK "Collecteur installe" }
                        else { LogWarn "dist/index.js introuvable." }
                    } else { LogWarn "Collecteur pre-compile absent de la release GitHub." }
                } catch { LogErr "Echec collecteur : $_" }
            }
        }
    }

    if ($chkInflux.Checked -and $influxExe -and (Test-Path $influxExe)) {
        LogStep "Configuration InfluxDB"
        $adminPass = $txtPass.Text
        if ([string]::IsNullOrWhiteSpace($adminPass)) { $adminPass = "monitor4me-local" }
        $influxRunning = $false
        try { $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3; $influxRunning = ($h.status -eq "pass") } catch {}
        $tmpProc = $null; $influxReady = $influxRunning
        if (-not $influxRunning) {
            LogInfo "Demarrage temporaire d'InfluxDB..."
            $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep 3; [System.Windows.Forms.Application]::DoEvents()
                try { $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3; if ($h.status -eq "pass") { $influxReady = $true; break } } catch {}
                LogInfo "Attente InfluxDB... ($($i * 3)s)"
            }
        }
        if ($influxReady) {
            try {
                $token = $null
                $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET
                if ($status.allowed -eq $true) {
                    $body = @{username="admin";password=$adminPass;org="home";bucket="pc-monitor";retentionPeriodSeconds=2592000} | ConvertTo-Json
                    $result = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method POST -Body $body -ContentType "application/json"
                    $token = $result.auth.token; LogOK "InfluxDB configure (org:home, bucket:pc-monitor)"
                } else {
                    $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$adminPass"))
                    $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" -Method POST -Headers @{Authorization="Basic $cred"} -UseBasicParsing
                    $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                    $authHdr = @{Cookie=$cookie}
                    $orgs    = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                    $orgId   = $orgs.orgs[0].id
                    $auths   = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                    $ex      = $auths.authorizations | Where-Object { $_.description -eq "pc-monitor-collector" } | Select-Object -First 1
                    if ($ex) { $token = $ex.token; LogOK "Token existant recupere" } else {
                        $bkts  = Invoke-RestMethod "$INFLUX_URL/api/v2/buckets?org=home" -Headers $authHdr
                        $bktId = ($bkts.buckets | Where-Object { $_.name -eq "pc-monitor" } | Select-Object -First 1).id
                        $tBody = @{orgID=$orgId;description="pc-monitor-collector";permissions=@(@{action="read";resource=@{type="buckets";orgID=$orgId;id=$bktId}},@{action="write";resource=@{type="buckets";orgID=$orgId;id=$bktId}})} | ConvertTo-Json -Depth 5
                        $auth  = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations" -Method POST -Body $tBody -Headers @{Cookie=$cookie;"Content-Type"="application/json"}
                        $token = $auth.token; LogOK "Nouveau token cree"
                    }
                }
                if ($token) { [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN",$token,"User"); $env:INFLUX_TOKEN=$token; LogOK "INFLUX_TOKEN sauvegarde" }
            } catch { LogErr "Config InfluxDB : $_" }
        } else { LogWarn "InfluxDB ne repond pas apres 60s." }
        if ($tmpProc) { Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue }
    }

    if ($chkTasks.Checked) {
        LogStep "Taches planifiees (boot)"
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
        if ($influxExe -and (Test-Path $influxExe)) {
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
        if ($nodeExe -and (Test-Path $collectorDist)) {
            $cTrig = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $cTrig.Delay = "PT25S"
            $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
            RegTask "PC-Monitor-Collector" (New-ScheduledTaskAction -Execute $nodeExe -Argument "$COLLECTOR_DIR\dist\index.js" -WorkingDirectory $COLLECTOR_DIR) $cTrig $userPrin $s "Collecteur monitor4me"
        }
    }

    if ($chkShortcut.Checked) {
        if (-not $appExe) { $appExe = Find-AppExe }
        if ($appExe) {
            $desktop = [System.Environment]::GetFolderPath("Desktop")
            $wsh = New-Object -ComObject WScript.Shell
            $sc  = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
            $sc.TargetPath = $appExe; $sc.WorkingDirectory = Split-Path $appExe
            $sc.Description = "monitor4me - PC Hardware Dashboard"; $sc.Save()
            LogOK "Raccourci cree sur le bureau"
        } else { LogWarn "App introuvable - raccourci ignore." }
    }

    Log ""
    LogOK "Installation terminee ! Redemarrez le PC pour activer le demarrage automatique."
    $btnInstall.Text      = "Installation terminee !"
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 80)
})

[System.Windows.Forms.Application]::Run($form)
.lts -is [string] } | Select-Object -First 1
                $nodeVer  = $nodeMeta.version
                $nodeMsi  = "$env:TEMP\node-install.msi"
                $nodeUrl  = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi"
                LogInfo "Telechargement Node.js $nodeVer..."
                Invoke-WebRequest $nodeUrl -OutFile $nodeMsi -UseBasicParsing
                LogInfo "Installation MSI (quelques minutes)..."
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
                else { LogWarn "MSI installe - redemarre le PC si node reste introuvable" }
            } catch {
                LogErr "Echec MSI : $_"
                if (IsCmd "winget") {
                    LogInfo "Tentative winget..."
                    winget install --id OpenJS.NodeJS.LTS -e --source winget --silent `
                        --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    RefreshPath; $nodeOk = IsCmd "node"
                    if ($nodeOk) { LogOK "Node.js installe via winget" }
                    else { LogWarn "Echec. Installe manuellement : https://nodejs.org" }
                } else { LogWarn "Installe manuellement : https://nodejs.org" }
            }
        }
    }

    if ($chkInflux.Checked) {
        LogStep "InfluxDB 2.x"
        $fc = Get-Command "influxd" -ErrorAction SilentlyContinue
        if ($fc) { $influxExe = $fc.Source }
        if (Test-Path $influxExe) { LogOK "Deja installe : $influxExe" } else {
            try {
                $zipUrl     = "https://dl.influxdata.com/influxdb/releases/influxdb2-" + $INFLUX_VER + "-windows.zip"
                $zipTmp     = "$env:TEMP\influxdb.zip"
                $extractTmp = "$env:TEMP\influx_extract"
                LogInfo "Telechargement InfluxDB $INFLUX_VER..."
                Invoke-WebRequest $zipUrl -OutFile $zipTmp -UseBasicParsing
                if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
                Expand-Archive -Path $zipTmp -DestinationPath $extractTmp -Force
                $inner = Get-ChildItem $extractTmp | Select-Object -First 1
                New-Item -ItemType Directory -Force -Path $INFLUX_DIR | Out-Null
                Get-ChildItem $inner.FullName | Copy-Item -Destination $INFLUX_DIR -Recurse -Force
                Remove-Item $extractTmp -Recurse -Force; Remove-Item $zipTmp -Force
                if (Test-Path $influxExe) { LogOK "InfluxDB $INFLUX_VER installe" }
                else { LogWarn "influxd.exe introuvable apres extraction." }
            } catch { LogErr "Echec InfluxDB : $_"; $influxExe = "" }
        }
    }

    if ($chkLhm.Checked) {
        LogStep "LibreHardwareMonitor"
        $lhmExe = Get-ChildItem $LHM_DIR -Filter "LibreHardwareMonitor.exe" -Recurse `
                      -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($lhmExe) { LogOK "Deja installe : $lhmExe" } else {
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
                else { LogWarn "LibreHardwareMonitor.exe introuvable." }
            } catch { LogErr "Echec LHM : $_" }
        }
    }

    if ($chkApp.Checked) {
        LogStep "Application monitor4me"
        $appExe = Find-AppExe
        if ($appExe) { LogOK "Deja installee : $appExe" } else {
            try {
                LogInfo "Recuperation release GitHub..."
                $rel   = Invoke-RestMethod `
                    "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                    -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
                $asset = $rel.assets | Where-Object { $_.name -like "*setup.exe" } | Select-Object -First 1
                $setupExe = "$env:TEMP\monitor4me-setup.exe"
                LogInfo "Telechargement $($asset.name)..."
                Invoke-WebRequest $asset.browser_download_url -OutFile $setupExe -UseBasicParsing
                LogInfo "Installation..."
                Start-Process $setupExe -ArgumentList "/S" -Wait
                Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
                $appExe = Find-AppExe
                if ($appExe) { LogOK "monitor4me installe : $appExe" }
                else { LogWarn "Exe introuvable apres install - relance ce script." }
            } catch { LogErr "Echec app : $_" }
        }
    }

    if ($chkCollector.Checked) {
        if (-not $nodeOk) { LogWarn "Collecteur ignore : Node.js non installe." } else {
            LogStep "Collecteur de metriques"
            if (Test-Path $collectorDist) { LogOK "Deja installe" } else {
                try {
                    $rel = Invoke-RestMethod `
                        "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
                        -TimeoutSec 20 -Headers @{"User-Agent"="monitor4me-install/1.0"}
                    $prebuilt = $rel.assets | Where-Object { $_.name -eq "collector-dist.zip" } | Select-Object -First 1
                    if ($prebuilt) {
                        LogInfo "Telechargement collecteur pre-compile..."
                        $zipTmp = "$env:TEMP\collector-dist.zip"
                        Invoke-WebRequest $prebuilt.browser_download_url -OutFile $zipTmp -UseBasicParsing
                        if (Test-Path $COLLECTOR_DIR) { Remove-Item $COLLECTOR_DIR -Recurse -Force }
                        New-Item -ItemType Directory $COLLECTOR_DIR | Out-Null
                        Expand-Archive -Path $zipTmp -DestinationPath $COLLECTOR_DIR -Force
                        Remove-Item $zipTmp -Force
                        if (Test-Path $collectorDist) { LogOK "Collecteur installe" }
                        else { LogWarn "dist/index.js introuvable." }
                    } else { LogWarn "Collecteur pre-compile absent de la release GitHub." }
                } catch { LogErr "Echec collecteur : $_" }
            }
        }
    }

    if ($chkInflux.Checked -and $influxExe -and (Test-Path $influxExe)) {
        LogStep "Configuration InfluxDB"
        $adminPass = $txtPass.Text
        if ([string]::IsNullOrWhiteSpace($adminPass)) { $adminPass = "monitor4me-local" }
        $influxRunning = $false
        try { $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3; $influxRunning = ($h.status -eq "pass") } catch {}
        $tmpProc = $null; $influxReady = $influxRunning
        if (-not $influxRunning) {
            LogInfo "Demarrage temporaire d'InfluxDB..."
            $tmpProc = Start-Process -FilePath $influxExe -PassThru -WindowStyle Hidden
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep 3; [System.Windows.Forms.Application]::DoEvents()
                try { $h = Invoke-RestMethod "$INFLUX_URL/health" -TimeoutSec 3; if ($h.status -eq "pass") { $influxReady = $true; break } } catch {}
                LogInfo "Attente InfluxDB... ($($i * 3)s)"
            }
        }
        if ($influxReady) {
            try {
                $token = $null
                $status = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method GET
                if ($status.allowed -eq $true) {
                    $body = @{username="admin";password=$adminPass;org="home";bucket="pc-monitor";retentionPeriodSeconds=2592000} | ConvertTo-Json
                    $result = Invoke-RestMethod "$INFLUX_URL/api/v2/setup" -Method POST -Body $body -ContentType "application/json"
                    $token = $result.auth.token; LogOK "InfluxDB configure (org:home, bucket:pc-monitor)"
                } else {
                    $cred   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$adminPass"))
                    $signin = Invoke-WebRequest "$INFLUX_URL/api/v2/signin" -Method POST -Headers @{Authorization="Basic $cred"} -UseBasicParsing
                    $cookie  = ($signin.Headers["Set-Cookie"] -split ";")[0]
                    $authHdr = @{Cookie=$cookie}
                    $orgs    = Invoke-RestMethod "$INFLUX_URL/api/v2/orgs?org=home" -Headers $authHdr
                    $orgId   = $orgs.orgs[0].id
                    $auths   = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations?org=home" -Headers $authHdr
                    $ex      = $auths.authorizations | Where-Object { $_.description -eq "pc-monitor-collector" } | Select-Object -First 1
                    if ($ex) { $token = $ex.token; LogOK "Token existant recupere" } else {
                        $bkts  = Invoke-RestMethod "$INFLUX_URL/api/v2/buckets?org=home" -Headers $authHdr
                        $bktId = ($bkts.buckets | Where-Object { $_.name -eq "pc-monitor" } | Select-Object -First 1).id
                        $tBody = @{orgID=$orgId;description="pc-monitor-collector";permissions=@(@{action="read";resource=@{type="buckets";orgID=$orgId;id=$bktId}},@{action="write";resource=@{type="buckets";orgID=$orgId;id=$bktId}})} | ConvertTo-Json -Depth 5
                        $auth  = Invoke-RestMethod "$INFLUX_URL/api/v2/authorizations" -Method POST -Body $tBody -Headers @{Cookie=$cookie;"Content-Type"="application/json"}
                        $token = $auth.token; LogOK "Nouveau token cree"
                    }
                }
                if ($token) { [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN",$token,"User"); $env:INFLUX_TOKEN=$token; LogOK "INFLUX_TOKEN sauvegarde" }
            } catch { LogErr "Config InfluxDB : $_" }
        } else { LogWarn "InfluxDB ne repond pas apres 60s." }
        if ($tmpProc) { Stop-Process -Id $tmpProc.Id -ErrorAction SilentlyContinue }
    }

    if ($chkTasks.Checked) {
        LogStep "Taches planifiees (boot)"
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
        if ($influxExe -and (Test-Path $influxExe)) {
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
        if ($nodeExe -and (Test-Path $collectorDist)) {
            $cTrig = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $cTrig.Delay = "PT25S"
            $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $noLimit -RestartCount 10 -RestartInterval $restart1 -StartWhenAvailable
            RegTask "PC-Monitor-Collector" (New-ScheduledTaskAction -Execute $nodeExe -Argument "$COLLECTOR_DIR\dist\index.js" -WorkingDirectory $COLLECTOR_DIR) $cTrig $userPrin $s "Collecteur monitor4me"
        }
    }

    if ($chkShortcut.Checked) {
        if (-not $appExe) { $appExe = Find-AppExe }
        if ($appExe) {
            $desktop = [System.Environment]::GetFolderPath("Desktop")
            $wsh = New-Object -ComObject WScript.Shell
            $sc  = $wsh.CreateShortcut("$desktop\monitor4me.lnk")
            $sc.TargetPath = $appExe; $sc.WorkingDirectory = Split-Path $appExe
            $sc.Description = "monitor4me - PC Hardware Dashboard"; $sc.Save()
            LogOK "Raccourci cree sur le bureau"
        } else { LogWarn "App introuvable - raccourci ignore." }
    }

    Log ""
    LogOK "Installation terminee ! Redemarrez le PC pour activer le demarrage automatique."
    $btnInstall.Text      = "Installation terminee !"
    $btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 80)
})

[System.Windows.Forms.Application]::Run($form)
