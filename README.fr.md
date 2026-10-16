# monitor4me

[English](README.md) | **Français**

![Plateforme : Windows](https://img.shields.io/badge/plateforme-Windows%2010%2F11-blue)
![Tauri 2](https://img.shields.io/badge/Tauri-2-24C8DB)
![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6)
![Licence : source disponible](https://img.shields.io/badge/licence-source--available-lightgrey)

Dashboard de monitoring hardware pour PC Windows : température, consommation électrique, coûts et historique.

![Démo de monitor4me](docs/media/demo.gif)

> La démo utilise des **données synthétiques** (collecteur et InfluxDB simulés, signalé par la mention « DEMO » dans le coin), pas de vraies mesures. Vidéo complète : [docs/media/demo.mp4](docs/media/demo.mp4).

## Fonctionnalités

- **Capteurs en temps réel** : température, puissance et fréquences CPU/GPU, NVMe, rails PSU (+12V / +5V / +3.3V), RPM des ventilateurs.
- **Coût électrique** : coût horaire en direct, total du jour, historique 31 jours avec détail quotidien, projection mensuelle.
- **Périphériques** : écrans auto-détectés via WMI, consommation par appareil configurable.
- **Détection d'anomalies** : alertes z-score pour le throttling thermique, les chutes de clock GPU et l'instabilité des rails.
- **Graphiques historiques** : kWh horaire sur 24h, barres 7 jours, tableau complet 31 jours.

## Architecture

```
LibreHardwareMonitor (:8085, data.json)
        |  lecture toutes les 2 s
        v
   collecteur (Node.js)  --écrit-->  InfluxDB 2 (:8086)
        |                                   ^
        | WebSocket (:8088, temps réel)     | requêtes Flux (historique)
        v                                   |
              Dashboard Tauri 2 (TypeScript, Vite, Chart.js)
```

| Composant | Technologie |
|---|---|
| App bureau | Tauri 2, TypeScript, Vite, Chart.js |
| Collecteur | Node.js, TypeScript |
| Capteurs | Serveur web de [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) |
| Stockage | InfluxDB 2, Flux |
| Détection écrans | WMI via PowerShell |

Un dashboard Grafana est aussi fourni : [`grafana/dashboards/pc-monitor.json`](grafana/dashboards/pc-monitor.json).

## Prérequis

- Windows 10 (build 1903+) ou Windows 11, x64.
- Connexion internet pendant l'installation (les dépendances sont téléchargées).
- Installés par le setup : .NET Desktop Runtime 10 (requis par LibreHardwareMonitor), InfluxDB 2.7 (port 8086), LibreHardwareMonitor (port 8085), Node.js LTS (runtime du collecteur).
- Droits administrateur (UAC) pour installer les services et tâches planifiées.

## Installation

### Option 1 : installeur de la release (recommandé)

1. Téléchargez `monitor4me_x64-setup.exe` depuis la [dernière release](https://github.com/MehdiZen/monitor4me/releases/latest).
2. Lancez-le. Windows peut afficher « Éditeur inconnu » : *Informations complémentaires > Exécuter quand même*.
3. Au premier lancement, le **Setup Wizard** demande votre tarif électrique (€/kWh) ; acceptez l'UAC.
4. Le wizard installe et configure les dépendances ci-dessus et le collecteur, puis démarre les services (aussi lancés à chaque démarrage de Windows). Aucun redémarrage requis.

Pour réparer ou réinstaller, ouvrez les paramètres (icône engrenage) et cliquez **Réparer**.

Si aucune donnée n'apparaît (statut « Reconnecting »), activez le serveur web de LibreHardwareMonitor à la main : **Options > Remote Web Server > Run** (port 8085).

### Option 2 : scripts du dépôt

- `monitor4me-install.bat` (ou `install.ps1`) : installeur Windows Forms, cochez les composants puis *Installer* (il demande l'élévation lui-même).
- `scripts/setup-from-source.ps1` : installation interactive pas à pas depuis un clone des sources (confirmation avant chaque étape).
- `uninstall.ps1` : désinstalle monitor4me et, au choix, ses dépendances.

## Configuration

Variables d'environnement (documentées dans [`.env.example`](.env.example), valeurs factices) :

| Variable | Utilisée par | Description |
|---|---|---|
| `INFLUX_TOKEN` | collecteur, app bureau | Token API InfluxDB. Défini par l'installeur comme variable utilisateur Windows. Il n'y a aucune valeur par défaut : si elle est absente, les requêtes vers InfluxDB sont rejetées. |

> **Note de sécurité.** L'installeur crée le compte admin InfluxDB local avec le mot de passe par défaut `monitor4me-local` (modifiable dans `install.ps1`). Par défaut, InfluxDB écoute sur toutes les interfaces réseau (port 8086) : toute personne de votre réseau pourrait donc s'y connecter avec ce mot de passe. Changez-le après l'installation (interface InfluxDB sur `http://localhost:8086`), ou limitez InfluxDB à `127.0.0.1` / bloquez le port dans votre pare-feu. La base ne contient que des métriques matérielles.

Le fichier `.env` n'est **pas** chargé automatiquement : définissez la variable dans votre environnement. Les autres réglages (tarif, TDP CPU/GPU, seuils de température, périphériques) se modifient dans les paramètres du dashboard ; le collecteur les persiste dans `collector/user-config.json` (ignoré par git). Les valeurs fixes (ports, intervalle de lecture, rendement PSU) sont dans [`collector/src/config.ts`](collector/src/config.ts).

## Développement

Prérequis : Node.js et les [prérequis Tauri 2](https://tauri.app/start/prerequisites/) (Rust, WebView2, outils de build MSVC).

App bureau (`app/`) :

```bash
cd app
npm install
npm run dev            # serveur Vite sur :5173 (front seul)
npm run tauri dev      # app Tauri complète en mode dev
npm run build          # tsc + vite build
npm run tauri:release  # tauri build (installeur)
```

Collecteur (`collector/`) :

```bash
cd collector
npm install
npm run dev            # ts-node src/index.ts
npm run build          # tsc -> dist/
npm start              # node dist/index.js
```

Le projet n'a ni suite de tests automatisés ni linter configuré. Vérification de types : `npx tsc --noEmit` dans `app/` et dans `collector/`.

## Structure du dépôt

```
monitor4me/
├── app/                  App bureau Tauri
│   ├── src/              UI (main.ts, charts.ts, influx.ts, ws-client.ts, store.ts, styles.css)
│   └── src-tauri/        Couche Rust (fenêtre, tray, updater, commandes de setup)
├── collector/            Collecteur Node.js (LHM -> InfluxDB + WebSocket)
│   └── src/              index, lhm, metrics, anomaly, monitors, notify, influx, ws, config
├── grafana/dashboards/   Dashboard Grafana optionnel
├── scripts/              Scripts PowerShell de setup, packaging et release
├── docs/media/           Vidéo et GIF de démo
├── install.ps1, monitor4me-install.bat, uninstall.ps1
└── LICENSE
```

## Notes hardware

- **RX 9070 XT** : support LHM GPU limité ; le collecteur marque `gpu_power_estimated=true` en mode estimation.
- **RAM** : pas de capteur AM5 disponible, estimation fixe de 10 W.
- **CPU RAPL** : sous-estime d'environ 7 %, corrigé par `CPU_RAPL_CORRECTION = 1.07`.

## Licence

Copyright (c) 2026 Mehdi Zenati. monitor4me est **source disponible** sous double licence : gratuit pour un usage personnel non commercial, licence payante pour un usage commercial/professionnel. Voir [LICENSE](LICENSE) pour les termes exacts. Les composants tiers (LibreHardwareMonitor, InfluxDB) conservent leurs propres licences.
