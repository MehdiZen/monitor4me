# monitor4me

Dashboard de monitoring hardware PC — température, consommation électrique, coûts, historique.

Construit avec **Tauri 2** · **TypeScript** · **InfluxDB**.

---

## Installation

### Prérequis système

- Windows 10 (build 1903+) ou Windows 11, x64
- Connexion internet (le wizard télécharge les dépendances)

### Étapes

**1.** Téléchargez **[`monitor4me_x64-setup.exe`](https://github.com/MehdiZen/monitor4me/releases/latest)** depuis la dernière release.

**2.** Double-cliquez sur le fichier. Windows peut afficher un avertissement "Éditeur inconnu" — cliquez **Informations complémentaires → Exécuter quand même**.

**3.** Au premier lancement, le **Setup Wizard** s'ouvre automatiquement. Entrez votre tarif électrique (€/kWh) et cliquez **Lancer l'installation**.

**4.** Acceptez la demande d'élévation (UAC) — nécessaire pour installer les services système.

**5.** Le wizard installe et configure automatiquement :
   - **.NET Desktop Runtime 10** — requis par LibreHardwareMonitor
   - **InfluxDB 2.7** — base de données time-series locale (port 8086)
   - **LibreHardwareMonitor** — lecture des capteurs hardware (port 8085)
   - **Node.js LTS** — runtime du collecteur
   - **Collecteur de métriques** — envoie les données dans InfluxDB toutes les 2s

**6.** Les services démarrent automatiquement à la fin du wizard, puis à chaque démarrage Windows.

> Pas de redémarrage requis. Le dashboard est opérationnel immédiatement après le wizard.

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
.\build-signed.ps1

# 2. Générer latest.json pour l'auto-updater
cd ..
.\scripts\generate-latest-json.ps1 -Version "X.Y.Z" -Notes "Description"

# 3. Packager le collecteur
.\scripts\package-collector.ps1

# 4. Release GitHub
gh release create vX.Y.Z `
    "app\src-tauri\target\release\bundle\nsis\monitor4me_X.Y.Z_x64-setup.exe" `
    "app\src-tauri\target\release\bundle\nsis\monitor4me_X.Y.Z_x64-setup.exe.sig" `
    "latest.json" "collector-dist.zip" `
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
│       ├── index.ts        Boucle principale (toutes les 2s)
│       ├── lhm.ts          Parsing capteurs LHM
│       ├── anomaly.ts      Détection anomalies (z-score)
│       ├── notify.ts       Notifications Windows
│       └── monitors.ts     Détection écrans WMI
└── scripts/                Scripts setup/build/release
```

---

## Notes hardware

- **RX 9070 XT** : support LHM GPU limité — le collecteur marque `gpu_power_estimated=true` en mode estimation.
- **RAM** : pas de capteur AM5 disponible, estimation fixe 10W.
- **CPU RAPL** : sous-estime ~7%, corrigé par `CPU_RAPL_CORRECTION = 1.07`.

---

MIT
