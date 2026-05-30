use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};
use std::process::Command;
use std::os::windows::process::CommandExt;

// creation flag to prevent console window flashing under Windows
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[tauri::command]
fn get_influx_token() -> String {
    std::env::var("INFLUX_TOKEN").unwrap_or_default()
}

#[tauri::command]
fn minimize_win(window: tauri::Window) { let _ = window.minimize(); }

#[tauri::command]
fn maximize_win(window: tauri::Window) {
    if window.is_maximized().unwrap_or(false) {
        let _ = window.unmaximize();
    } else {
        let _ = window.maximize();
    }
}

#[tauri::command]
fn hide_win(window: tauri::Window) { let _ = window.hide(); }

#[tauri::command]
async fn install_update(app: tauri::AppHandle) -> Result<(), String> {
    use tauri_plugin_updater::UpdaterExt;
    let updater = app.updater().map_err(|e| e.to_string())?;
    if let Some(update) = updater.check().await.map_err(|e| e.to_string())? {
        update
            .download_and_install(|_, _| {}, || {})
            .await
            .map_err(|e| e.to_string())?;
        app.restart();
    }
    Ok(())
}

#[tauri::command]
fn get_install_log() -> String {
    let log_file = std::env::temp_dir().join("monitor4me-setup.log");
    std::fs::read_to_string(log_file).unwrap_or_default()
}

#[tauri::command]
async fn run_silent_install(
    admin_pass: String,
    tarif_kwh: f64,
    app: tauri::AppHandle,
) -> Result<(), String> {
    // Diagnostic immediat ecrit dans le fichier (pas d'event) :
    // si le frontend poll get_install_log et voit cette ligne,
    // on sait que l'invoke atteint Rust et que les fichiers sont accessibles.

    // 1. Localiser silent-install.ps1
    let mut script_path = std::env::current_dir()
        .unwrap_or_default()
        .join("scripts")
        .join("silent-install.ps1");

    if !script_path.exists() {
        if let Ok(res_dir) = app.path().resource_dir() {
            for p in &[
                res_dir.join("silent-install.ps1"),
                res_dir.join("scripts").join("silent-install.ps1"),
            ] {
                if p.exists() { script_path = p.clone(); break; }
            }
        }
    }

    if !script_path.exists() {
        let cwd  = std::env::current_dir().map(|p| p.display().to_string()).unwrap_or_default();
        let rdir = app.path().resource_dir().map(|p| p.display().to_string()).unwrap_or_default();
        return Err(format!("silent-install.ps1 introuvable (cwd={} resource_dir={})", cwd, rdir));
    }

    // 2. Fichier de log — on ecrit le diagnostic directement dedans
    let log_file = std::env::temp_dir().join("monitor4me-setup.log");
    let script_str = script_path.to_string_lossy().into_owned();
    let init_log = format!(
        "STEP: Demarrage de l installation\r\nINFO: Script = {}\r\n",
        script_str
    );
    std::fs::write(&log_file, init_log.as_bytes()).map_err(|e| e.to_string())?;

    let log_str = log_file.to_string_lossy().into_owned();

    // 3. Launcher auto-elevant.
    //    - Verifie si deja admin -> execute directement
    //    - Sinon -> se relance lui-meme avec Start-Process -Verb RunAs
    //    - Plus de wrapper intermediaire
    //    - $ErrorActionPreference = Continue pour voir les erreurs
    let launcher_content = format!(
        "$ErrorActionPreference = 'Continue'\r\n\
         $log = '{}'\r\n\
         $isAdmin = ([Security.Principal.WindowsPrincipal]\
           [Security.Principal.WindowsIdentity]::GetCurrent()\
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)\r\n\
         Add-Content $log ('INFO: isAdmin=' + $isAdmin) -Encoding UTF8\r\n\
         if (-not $isAdmin) {{\r\n\
           Add-Content $log 'STEP: Demande elevation UAC' -Encoding UTF8\r\n\
           try {{\r\n\
             Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait `\r\n\
               -ArgumentList ('-ExecutionPolicy Bypass -NonInteractive -File \"' + $PSCommandPath + '\"')\r\n\
           }} catch {{\r\n\
             Add-Content $log ('ERR: Elevation echouee - ' + $_.Exception.Message) -Encoding UTF8\r\n\
           }}\r\n\
           exit\r\n\
         }}\r\n\
         Add-Content $log 'STEP: Elevation obtenue, lancement du script' -Encoding UTF8\r\n\
         & '{}' -AdminPass '{}' -TarifKwh {} -LogFile '{}'\r\n",
        log_str.replace('\'', "''"),
        script_str.replace('\'', "''"),
        admin_pass.replace('\'', "''"),
        tarif_kwh,
        log_str.replace('\'', "''"),
    );

    let launcher_path = std::env::temp_dir().join("monitor4me-launcher.ps1");
    std::fs::write(&launcher_path, launcher_content.as_bytes())
        .map_err(|e| format!("Echec creation launcher : {}", e))?;
    let launcher_str = launcher_path.to_string_lossy().into_owned();

    // 4. Lancer le launcher directement — il gere sa propre elevation
    //    Le frontend poll get_install_log() toutes les 500ms pour afficher la progression
    let mut child = Command::new("powershell")
        .creation_flags(CREATE_NO_WINDOW)
        .args(&["-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                "-NonInteractive", "-File", &launcher_str])
        .spawn()
        .map_err(|e| format!("Echec spawn PowerShell : {}", e))?;

    // 5. Attendre la fin du launcher (qui attend l'eventuel processus eleve via -Wait)
    child.wait().map_err(|e| format!("Attente echouee : {}", e))?;

    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_influx_token, minimize_win, maximize_win, hide_win,
            install_update, run_silent_install, get_install_log
        ])
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(win) = app.get_webview_window("main") {
                let _ = win.show();
                let _ = win.unminimize();
                let _ = win.set_focus();
            }
        }))
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let quit = MenuItem::with_id(app, "quit", "Quitter monitor4me", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Afficher la fenêtre", true, None::<&str>)?;
            let sep  = tauri::menu::PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&show, &sep, &quit])?;

            let icon = app.default_window_icon().cloned()
                .expect("no app icon — check bundle.icon in tauri.conf.json");

            TrayIconBuilder::new()
                .icon(icon)
                .menu(&menu)
                .show_menu_on_left_click(false)
                .tooltip("monitor4me")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "show" => show_window(app),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("main") {
                            if win.is_visible().unwrap_or(false) {
                                let _ = win.hide();
                            } else {
                                show_window(app);
                            }
                        }
                    }
                })
                .build(app)?;

            // Vérifie les mises à jour 10s après le démarrage
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(10));
                tauri::async_runtime::block_on(async move {
                    use tauri_plugin_updater::UpdaterExt;
                    if let Ok(updater) = handle.updater() {
                        if let Ok(Some(update)) = updater.check().await {
                            let _ = handle.emit("update-available", serde_json::json!({
                                "version": update.version,
                                "notes": update.body.unwrap_or_default()
                            }));
                        }
                    }
                });
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn show_window(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.show();
        let _ = win.unminimize();
        let _ = win.set_focus();
    }
}
