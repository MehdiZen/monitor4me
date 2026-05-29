$env:TAURI_SIGNING_PRIVATE_KEY_PATH = [System.Environment]::GetEnvironmentVariable("TAURI_SIGNING_PRIVATE_KEY_PATH","User")
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User") + ";$env:USERPROFILE\.cargo\bin"
Set-Location "C:\Dev\pc-monitor\app"
Write-Host "Signing key path: $env:TAURI_SIGNING_PRIVATE_KEY_PATH"
npm run tauri build 2>&1
