# monitor4me

Dashboard de monitoring hardware PC — température, consommation électrique, coûts, historique.

Construit avec **Tauri 2** · **TypeScript** · **InfluxDB**.

---

## Installation (utilisateurs)

**1.** Télécharger [`monitor4me-install.bat`](https://github.com/MehdiZen/monitor4me/releases/latest/download/monitor4me-install.bat) depuis la [dernière release](https://github.com/MehdiZen/monitor4me/releases/latest)

**2.** Double-cliquer sur le fichier

> **⚠️ Windows affichera un avertissement de sécurité** — c'est normal pour tout fichier téléchargé depuis internet.
> Cliquer sur **Exécuter quand même** (ou "Run" si Windows est en anglais).
> Le code source de l'installeur est consultable ici : [`install.ps1`](install.ps1)

**3.** L'installeur prend en charge tout le reste : Node.js, InfluxDB, LibreHardwareMonitor, l'app et le collector qui démarre automatiquement au boot.

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

### Build de production (signé)

```powershell
cd app
.\build-signed.ps1
# Puis pour générer latest.json (auto-updater) :
cd ..
.\scripts\generate-latest-json.ps1 -Version "X.Y.Z" -Notes "Description"
```

La clé privée de signature doit être à `$env:USERPROFILE\.monitor4me-signing-key` (hors repo).

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
