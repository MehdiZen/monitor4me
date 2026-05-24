# PC Monitor — Notes d'installation & problèmes connus

## Dépendances installées

### Outils système (installés depuis zéro)
| Outil | Version | Installé via | Chemin |
|-------|---------|-------------|--------|
| Node.js | 20 LTS | winget / nodejs.org | `C:\Program Files\nodejs\` |
| Rust + Cargo | stable | rustup.rs | `%USERPROFILE%\.cargo\` |
| VS Build Tools | 2022 | winget | `C:\Program Files (x86)\Microsoft Visual Studio\` |

### Outils extraits (zips)
| Outil | Chemin | Usage |
|-------|--------|-------|
| LibreHardwareMonitor | `C:\Tools\LibreHardwareMonitor\` | Lecture capteurs hardware (port 8085) |
| InfluxDB 2.x | `C:\Tools\influxdb\` | Base de données métriques (port 8086) |

### Données InfluxDB
- Données : `%USERPROFILE%\.influxdbv2\`
- Token : variable d'environnement utilisateur `INFLUX_TOKEN`

### Fichiers générés par l'app
- Config tarif kWh : `%LOCALAPPDATA%\pc-monitor-app\` (localStorage Tauri / WebView2)
- Config runtime collector : `C:\Dev\pc-monitor\collector\user-config.json`

### Tâches planifiées (Task Scheduler)
| Nom | Processus | Déclencheur |
|-----|-----------|-------------|
| `PC-Monitor-InfluxDB` | `influxd.exe` | Logon (SYSTEM) |
| `PC-Monitor-LHM` | `LibreHardwareMonitor.exe` | Logon (user) |
| `PC-Monitor-Collector` | `node dist/index.js` | Logon (user, +25s) |

### Autostart Tauri
- Entrée registre : `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\pc-monitor-app`
- Géré automatiquement par `tauri-plugin-autostart` au premier lancement

---

## Problèmes connus & solutions

### Le raccourci bureau ouvre l'ancienne version après un rebuild
**Cause** : le raccourci pointe vers un exe qui n'est pas mis à jour en place — Tauri rebuild écrase l'exe existant dans `target\release\` mais si le raccourci pointe ailleurs il reste figé.  
**Solution** : recréer le raccourci une fois après le premier build :
```powershell
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:USERPROFILE\Desktop\PC Monitor.lnk")
$sc.TargetPath = "C:\Dev\pc-monitor\app\src-tauri\target\release\pc-monitor-app.exe"
$sc.Save()
```
Après ça, tous les builds suivants mettent à jour automatiquement le même exe.

### PowerShell 5.1 : opérateur `?.` non reconnu
**Cause** : `powershell.exe` = PS 5.1, l'opérateur null-conditionnel `?.` n'existe qu'en PS 7+.  
**Solution** : utiliser `(Get-Command x -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)` à la place.

### `npx` / `cargo` non reconnus après installation
**Cause** : PATH de la session PowerShell pas rechargé.  
**Solution** :
```powershell
$env:PATH = "C:\Program Files\nodejs;$env:USERPROFILE\.cargo\bin;$env:PATH"
```

### LHM ne remonte pas les rails 12V/5V/3.3V
**Cause** : puce ITE IT8689E sur la Gigabyte B650E Aorus Elite AX ne expose pas les rails ATX nommés via LHM. Seules des tensions numérotées (#1-#7) sont accessibles, non mappées aux rails.  
**Status** : limitation hardware, pas de workaround.

### LHM : `SensorType` vs `Type` dans le JSON
**Cause** : le champ dans le JSON de LHM s'appelle `Type`, pas `SensorType`.  
**Impacte** : `lhm.ts` et `test-lhm.ps1`.  
**Statut** : corrigé.

### InfluxDB non disponible via winget
**Cause** : `winget install InfluxData.InfluxDB` échoue — paquet absent ou cassé.  
**Solution** : télécharger le zip depuis influxdata.com, extraire dans `C:\Tools\influxdb\`.

### InfluxDB : pas de CLI `influx.exe` dans le zip
**Cause** : le zip Windows ne contient que `influxd.exe`, pas le CLI séparé.  
**Solution** : utiliser l'API REST directement pour setup (voir `scripts/setup-influx.ps1`).

### Task Scheduler : intervalle de restart minimum 1 minute
**Cause** : `New-TimeSpan -Seconds 10` comme `RestartInterval` est refusé.  
**Solution** : `New-TimeSpan -Minutes 1` minimum obligatoire.

### LHM démarre avec l'interface visible
**Cause** : LHM est une app WinForms, Task Scheduler la lance dans la session utilisateur.  
**Solution** : le script `setup-task.ps1` utilise `Start-Process -WindowStyle Minimized` via PowerShell. LHM se minimise dans le tray.

---

## Architecture résumée

```
LibreHardwareMonitor (:8085 REST)
        ↓  poll toutes les 2s
  collector/src/index.ts (Node.js)
        ↓  write
  InfluxDB (:8086)
        ↓  WebSocket broadcast (:8088)
  app/ (Tauri + WebView2)
```

## Chemins importants

| Quoi | Chemin |
|------|--------|
| Source app | `C:\Dev\pc-monitor\` |
| Exe buildé | `C:\Dev\pc-monitor\app\src-tauri\target\release\pc-monitor-app.exe` |
| Collector build | `C:\Dev\pc-monitor\collector\dist\index.js` |
| LHM | `C:\Tools\LibreHardwareMonitor\LibreHardwareMonitor.exe` |
| InfluxDB | `C:\Tools\influxdb\influxd.exe` |
| Données InfluxDB | `%USERPROFILE%\.influxdbv2\` |
| Config collector | `C:\Dev\pc-monitor\collector\user-config.json` |
