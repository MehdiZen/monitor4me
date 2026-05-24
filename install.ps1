#Requires -RunAsAdministrator
param()
$ErrorActionPreference = "Stop"
$ROOT = "C:\Dev\pc-monitor"

Write-Host ""
Write-Host "=== PC Monitor - Installation depuis zero ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ce script va installer :"
Write-Host "  - Node.js LTS           (~50 MB)"
Write-Host "  - VS Build Tools (C++)  (~4 GB)  <- le gros morceau, requis par Rust"
Write-Host "  - Rust                  (~1.5 GB)"
Write-Host "  - L'app PC Monitor"
Write-Host ""
Write-Host "Duree estimee : 20-30 min selon ta connexion." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Continuer ? (O/n)"
if ($confirm -eq "n" -or $confirm -eq "N") { exit 0 }

# Helper : recharger le PATH sans rouvrir le terminal
function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

function Is-Installed($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# ── 1. winget (present sur Windows 11, juste verifier) ────────────────────────
Write-Host ""
Write-Host "[1/4] Verification winget..." -ForegroundColor Yellow
if (-not (Is-Installed "winget")) {
    throw "winget introuvable. Mets a jour Windows 11 ou installe App Installer depuis le Microsoft Store."
}
Write-Host "      winget OK" -ForegroundColor Green

# ── 2. Node.js ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Installation Node.js LTS..." -ForegroundColor Yellow
if (Is-Installed "node") {
    Write-Host "      Node.js deja installe : $(node --version)" -ForegroundColor Green
} else {
    winget install --id OpenJS.NodeJS.LTS -e --source winget --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (-not (Is-Installed "node")) {
        throw "Node.js n'a pas pu etre installe. Installe-le manuellement depuis https://nodejs.org"
    }
    Write-Host "      Node.js $(node --version) installe OK" -ForegroundColor Green
}

# ── 3. Visual Studio Build Tools (C++) ────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Installation Visual Studio Build Tools (C++)..." -ForegroundColor Yellow
Write-Host "      ~4 GB - cela peut prendre 10-15 minutes..." -ForegroundColor Yellow

# Detecte si MSVC est deja dispo (cl.exe dans le PATH ou vswhere le trouve)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasMsvc = $false
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    $hasMsvc = [bool]$vsPath
}

if ($hasMsvc) {
    Write-Host "      VS Build Tools (C++) deja installe OK" -ForegroundColor Green
} else {
    # Telecharge le bootstrapper VS Build Tools
    $vsBtUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $vsBt    = "$env:TEMP\vs_BuildTools.exe"
    Write-Host "      Telechargement du bootstrapper..."
    Invoke-WebRequest $vsBtUrl -OutFile $vsBt -UseBasicParsing

    Write-Host "      Installation en cours (fenetre possible en arriere-plan)..."
    $proc = Start-Process -FilePath $vsBt -ArgumentList @(
        "--quiet", "--wait", "--norestart",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended"
    ) -Wait -PassThru

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "VS Build Tools a echoue (code $($proc.ExitCode)). Relance le script ou installe manuellement."
    }
    Write-Host "      VS Build Tools installe OK" -ForegroundColor Green
}

# ── 4. Rust ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Installation Rust..." -ForegroundColor Yellow
$cargoBin = "$env:USERPROFILE\.cargo\bin"
$env:PATH  = "$cargoBin;$env:PATH"

if (Is-Installed "rustc") {
    Write-Host "      Rust deja installe : $(rustc --version)" -ForegroundColor Green
} else {
    $rustupExe = "$env:TEMP\rustup-init.exe"
    Write-Host "      Telechargement de rustup..."
    Invoke-WebRequest "https://win.rustup.rs/x86_64" -OutFile $rustupExe -UseBasicParsing
    Write-Host "      Installation Rust stable..."
    & $rustupExe -y --default-toolchain stable --no-modify-path
    $env:PATH = "$cargoBin;$env:PATH"
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    [System.Environment]::SetEnvironmentVariable("PATH", "$cargoBin;$currentUserPath", "User")
    Refresh-Path
    Write-Host "      Rust $(rustc --version) installe OK" -ForegroundColor Green
}

# ── Build collector ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[Build 1/2] Collector TypeScript..." -ForegroundColor Yellow
Push-Location "$ROOT\collector"
npm install --silent
npm run build
Pop-Location
Write-Host "            OK" -ForegroundColor Green

# ── Build app Tauri ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[Build 2/2] App Tauri (Rust compile - 5-10 min)..." -ForegroundColor Yellow
Push-Location "$ROOT\app"
npm install --silent
npm run tauri build
Pop-Location

$exePath = "$ROOT\app\src-tauri\target\release\pc-monitor-app.exe"
if (-not (Test-Path $exePath)) {
    $found = Get-ChildItem "$ROOT\app\src-tauri\target\release" -Filter "pc-monitor-app.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $exePath = $found.FullName }
    else { throw "Exe introuvable apres build. Verifie les erreurs ci-dessus." }
}
Write-Host "            $exePath OK" -ForegroundColor Green

# ── Raccourci bureau ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Creation du raccourci bureau..." -ForegroundColor Yellow
$desktop = [System.Environment]::GetFolderPath("Desktop")
$lnkPath = Join-Path $desktop "PC Monitor.lnk"
$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($lnkPath)
$lnk.TargetPath       = $exePath
$lnk.Description      = "PC Power Monitor CODEC"
$lnk.WorkingDirectory = Split-Path $exePath
$lnk.Save()
Write-Host "  Raccourci cree : $lnkPath" -ForegroundColor Green

# ── Tache planifiee collector ──────────────────────────────────────────────────
Write-Host "Enregistrement tache collector..." -ForegroundColor Yellow
$taskName = "PC-Monitor-Collector"
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
$nodePath  = (Get-Command node).Source
$trigger   = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME
$trigger.Delay = "PT10S"
$action    = New-ScheduledTaskAction `
    -Execute $nodePath `
    -Argument "$ROOT\collector\dist\index.js" `
    -WorkingDirectory "$ROOT\collector"
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Seconds 15) `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "PC Monitor collector" | Out-Null
Write-Host "  Tache '$taskName' enregistree (demarre a la connexion)" -ForegroundColor Green

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Tout est installe !" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  - Raccourci bureau cree   -> double-clic pour ouvrir"
Write-Host "  - Tray icon               -> actif des le prochain demarrage"
Write-Host "  - Collector               -> demarre automatiquement a la connexion"
Write-Host ""
Write-Host "  Prochaine etape : lancer LHM.exe en administrateur"
Write-Host "  (scripts\setup-task.ps1 pour l'automatiser au demarrage)"
Write-Host ""

$answer = Read-Host "Demarrer PC Monitor maintenant ? (O/n)"
if ($answer -ne "n" -and $answer -ne "N") {
    Start-ScheduledTask -TaskName $taskName
    Start-Process -FilePath $exePath
    Write-Host ""
    Write-Host "PC Monitor demarre !" -ForegroundColor Green
}
