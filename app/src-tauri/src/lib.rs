use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};
use std::process::{Command, Stdio};
use std::os::windows::process::CommandExt;
use std::io::{BufRead, BufReader};

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
async fn run_silent_install(
    admin_pass: String,
    tarif_kwh: f64,
    app: tauri::AppHandle,
) -> Result<(), String> {
    // 1. Localiser silent-install.ps1 (mode dev ou release)
    let mut script_path = std::env::current_dir()
        .unwrap_or_default()
        .join("scripts")
        .join("silent-install.ps1");

    if !script_path.exists() {
        if let Ok(res_dir) = app.path().resource_dir() {
            let candidates = vec![
                res_dir.join("silent-install.ps1"),
                res_dir.join("scripts").join("silent-install.ps1"),
                res_dir.join("resources").join("silent-install.ps1"),
            ];
            for p in candidates {
                if p.exists() {
                    script_path = p;
                    break;
                }
            }
        }
    }

    if !script_path.exists() {
        return Err("silent-install.ps1 introuvable".to_string());
    }

    // 2. Fichier de log temporaire pour IPC avec le processus eleve
    let log_file = std::env::temp_dir().join("monitor4me-setup.log");
    std::fs::write(&log_file, "").map_err(|e| e.to_string())?;

    let script_str = script_path.to_string_lossy().into_owned();
    let log_str    = log_file.to_string_lossy().into_owned();

    // 3. Lancer un PowerShell non-eleve qui demande l'elevation via Start-Process -Verb RunAs
    //    Le processus eleve ecrit dans le fichier de log.
    //    On n'utilise PAS CREATE_NO_WINDOW ici pour que la boite UAC soit visible.
    let ps_cmd = format!(
        "Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait \
         -ArgumentList @('-ExecutionPolicy','Bypass','-File','\"{}\"',\
         '-AdminPass','\"{}\"','-TarifKwh','{}','-LogFile','\"{}\"')",
        script_str.replace('\'', "''"),
        admin_pass.replace('\'', "''"),
        tarif_kwh,
        log_str.replace('\'', "''")
    );

    let mut child = Command::new("powershell")
        .creation_flags(CREATE_NO_WINDOW)
        .args(&["-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", &ps_cmd])
        .spawn()
        .map_err(|e| format!("Echec lancement : {}", e))?;

    // 4. Thread de polling : lit le fichier de log et emet les evenements en temps reel
    let handle     = app.clone();
    let log_path   = log_file.clone();
    std::thread::spawn(move || {
        let mut last_line = 0usize;
        loop {
            std::thread::sleep(std::time::Duration::from_millis(400));
            if let Ok(content) = std::fs::read_to_string(&log_path) {
                let lines: Vec<&str> = content.lines().collect();
                for line in lines.iter().skip(last_line) {
                    let _ = handle.emit("setup-log", line.to_string());
                }
                last_line = lines.len();
                if content.contains("INSTALLATION_SUCCESS") {
                    break;
                }
            }
        }
    });

    // 5. Attendre la fin du processus wrapper (qui attend lui-meme le processus eleve)
    child.wait().map_err(|e| format!("Attente echouee : {}", e))?;

    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_influx_token, minimize_win, maximize_win, hide_win, install_update, run_silent_install
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
