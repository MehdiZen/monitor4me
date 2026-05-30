# monitor4me

Dashboard de monitoring hardware PC — température, consommation électrique, coûts, historique.

Construit avec **Tauri 2** · **TypeScript** · **InfluxDB**.

<img width="1098" height="758" alt="image" src="https://github.com/user-attachments/assets/91628a6b-c901-4043-9db6-fc61890f9ffd" />

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

### Activation manuelle du web server LibreHardwareMonitor

Le wizard configure automatiquement le web server de LHM. Si les données n'apparaissent pas (statut "Reconnecting"), activez-le manuellement :

**Options → Remote Web Server → Run** (port 8085)

<img width="455" height="444" alt="image" src="https://github.com/user-attachments/assets/fdceba3b-64b5-41e1-aac7-29b3dc7145de" />

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
