# monitor4me

Dashboard de monitoring hardware PC — température, consommation électrique, coûts, historique.

Construit avec **Tauri 2** · **TypeScript** · **InfluxDB**.

---

## Installation

### Prérequis

- [**.NET Desktop Runtime 8**](https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe) — requis par LibreHardwareMonitor

### Étapes

**1.** Installez **.NET Desktop Runtime 8** via le lien ci-dessus si ce n'est pas déjà fait.

**2.** Téléchargez **[`monitor4me_x64-setup.exe`](https://github.com/MehdiZen/monitor4me/releases/latest)** depuis la dernière release.

**3.** Double-cliquez sur le fichier. Windows peut afficher un avertissement "Éditeur inconnu" — cliquez **Informations complémentaires → Exécuter quand même**.

**4.** L'app s'installe en 30 secondes. Au premier lancement, un **Setup Wizard** s'ouvre automatiquement :
   - Entrez votre tarif électrique (€/kWh)
   - Cliquez **Lancer l'installation**
   - Acceptez la demande d'élévation (UAC)
   - Node.js, InfluxDB, LibreHardwareMonitor et le collecteur s'installent et démarrent automatiquement

**5.** Le dashboard s'ouvre. Les métriques apparaissent en temps réel.

> **Réparer / Réinstaller** : ouvrez les paramètres (⚙) et cliquez **Réparer**.

---

## Fonctionnalités

- **Capteurs en temps réel** — CPU/GPU température · puissance · clocks · NVMe · rails PSU (+12V/+5V/+3.3V) · RPM ventilateurs
- **Coût électrique** — €/h en direct · total du jour · historique 31 jours avec détail quotidien
- **Suivi périphériques** — écrans auto-détectés via WMI, consommation par écran configurable
- **Détection d'anomalies** — alertes z-score pour throttling thermique, chutes de clock GPU, instabilité rails
- **Graphiques historiques** — kWh horaire 24h · barres 7 jours · tableau complet 31 jours

---

## Stack

| | |
|---|---|
| App bureau | Tauri 2 · TypeScript · Vite |
| Graphiques | Chart.js |
| Collecteur | Node.js · TypeScript |
| Capteurs | [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) REST API |
| Stockage | InfluxDB 2 · Flux |
| Détection écrans | WMI via PowerShell (`Get-PnpDevice`) |

---

## Développement (depuis le repo)

### Prérequis

- Windows 10/11
- Node.js 20+
- Rust (build Tauri uniquement)
- LibreHardwareMonitor avec web server activé sur `:8085`
- InfluxDB 2 sur `:8086`

### Setup

```powershell
# Depuis la racine du repo
.\scripts\setup-from-source.ps1
```

### Publier une release

```powershell
# 1. Build signé (clé privée dans ~/.monitor4me-signing-key)
cd app
.\build-signed.ps1          # Entrée au prompt password = vide

# 2. Générer latest.json pour l'auto-updater
cd ..
.\scripts\generate-latest-json.ps1 -Version "X.Y.Z" -Notes "Description"

# 3. Release GitHub
gh release create vX.Y.Z `
    "app\src-tauri\target\release\bundle\nsis\monitor4me_X.Y.Z_x64-setup.exe" `
    "app\src-tauri\target\release\bundle\nsis\monitor4me_X.Y.Z_x64-setup.exe.sig" `
    "latest.json" `
    --title "monitor4me vX.Y.Z" --notes "..."

git push origin master
```

> Le repo doit être **public** pour que l'auto-updater et les téléchargements fonctionnent sans authentification.

---

## Structure

```
monitor4me/
├── app/                    App Tauri (bureau)
│   ├── src/
│   │   ├── main.ts         Logique UI + graphiques
│   │   ├── influx.ts       Requêtes Flux vers InfluxDB
│   │   └── styles.css
│   └── src-tauri/          Couche Rust (fenêtre, tray, updater)
├── collector/              Collecteur Node.js
│   └── src/
│       ├── index.ts        Boucle principale (toutes les 5s)
│       ├── lhm.ts          Parsing capteurs LHM
│       ├── anomaly.ts      Détection anomalies (z-score)
│       ├── notify.ts       Notifications Windows
│       └── monitors.ts     Détection écrans WMI
├── scripts/                Scripts setup/build/release
├── install.ps1             Installeur autonome (utilisateurs finaux)
└── uninstall.ps1           Désinstalleur complet
```

---

## Notes hardware

- **RX 9070 XT** : support LHM GPU limité — le collecteur marque `gpu_power_estimated=true` en mode estimation.
- **RAM** : pas de capteur AM5 disponible, estimation fixe 10W.
- **CPU RAPL** : sous-estime ~7%, corrigé par `CPU_RAPL_CORRECTION = 1.07`.

---

MIT
