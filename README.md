# monitor4me

Dashboard de monitoring hardware PC — température, consommation électrique, coûts, historique.

Construit avec **Tauri 2** · **TypeScript** · **InfluxDB**.

---

## Installation (utilisateurs)

L'installation de **monitor4me** a été entièrement modernisée avec une expérience utilisateur premium (Setup Wizard intégré dans l'interface sans aucune console de commande PowerShell visible).

**1.** Téléchargez le pack de démarrage [`monitor4me-v1.0.1.zip`](https://github.com/MehdiZen/monitor4me/releases/latest/download/monitor4me-v1.0.1.zip) depuis la [dernière release GitHub](https://github.com/MehdiZen/monitor4me/releases/latest).

**2.** Extrayez l'archive ZIP (Clic droit ➜ Extraire tout), puis double-cliquez sur **`monitor4me-install.bat`**.

> [!WARNING]
> **Avertissement SmartScreen** : Windows affichera un écran bleu de protection. C'est le comportement par défaut pour les scripts téléchargés d'Internet. Cliquez sur **Informations complémentaires** puis sur **Exécuter quand même**.
> Le code de l'installateur est auditable en toute transparence ici : [`install.ps1`](install.ps1).

**3.** L'installateur configure silencieusement les dépendances en tâche de fond (Node.js, InfluxDB, LibreHardwareMonitor) et installe les tâches planifiées système pour que le service de télémétrie démarre de manière invisible avec Windows.

**4.** L'application bureau s'ouvre sur un **Setup Wizard** graphique : saisissez le mot de passe de votre choix pour sécuriser votre base de données locale, votre tarif d'électricité, et laissez le dashboard charger vos graphiques en temps réel !

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

### Production & Publication de Release (pour tags GitHub)

Pour livrer une nouvelle version (ex: `1.0.1`) et permettre le téléchargement et les mises à jour automatiques transparentes de l'application :

#### 🔒 1. Compiler et signer l'application de production
Ouvrez votre terminal PowerShell habituel à la racine du projet et lancez :
```powershell
cd app
.\build-signed.ps1
```
*Saisissez le mot de passe de votre clé de signature `minisign` lorsqu'il est demandé.*
Cela compile et signe le binaire de production, générant l'installateur à cet emplacement :
`app\src-tauri\target\release\bundle\nsis\monitor4me_1.0.1_x64-setup.exe` (et son fichier de signature `.exe.sig`).

#### 📦 2. Compiler et packager le collecteur et les scripts
Depuis la racine du projet, lancez dans PowerShell :
```powershell
# Compiler et packager le collecteur pré-compilé
cd collector
npm run build
powershell -NoProfile -ExecutionPolicy Bypass -Command "..\scripts\package-collector.ps1"

# Packager l'installeur autonome de démarrage
cd ..
powershell -NoProfile -ExecutionPolicy Bypass -Command ".\scripts\package-release.ps1 -Version '1.0.1'"
```
Cela produit deux fichiers d'archives à la racine de votre projet :
* **`collector-dist.zip`** : Les dépendances de production pré-compilées du collecteur.
* **`monitor4me-v1.0.1.zip`** : L'installeur de démarrage rapide (`monitor4me-install.bat` + `install.ps1`).

#### 🔄 3. Générer le fichier de mise à jour automatique (`latest.json`)
Pour que le système d'auto-update Tauri propose cette mise à jour aux utilisateurs, générez la signature finale du fichier en exécutant :
```powershell
.\scripts\generate-latest-json.ps1 -Version "1.0.1" -Notes "Setup Wizard premium intégré et rafraîchissement d'historique instantané."
```
Cela met à jour le fichier [`latest.json`](latest.json) à la racine du dépôt.

#### 🚀 4. Créer le Tag de Release sur GitHub
Poussez vos modifications locales de code et le nouveau `latest.json` sur GitHub :
```powershell
git add .
git commit -m "Release v1.0.1: Setup Wizard graphique et correctifs de performance"
git push
```
Créez ensuite une **Release** sur GitHub nommée **`v1.0.1`** associée au tag **`v1.0.1`** et téléversez-y les **4 fichiers d'assets** générés :
1. `monitor4me-v1.0.1.zip` (le pack de démarrage utilisateur)
2. `collector-dist.zip` (le package du collecteur pré-compilé)
3. `monitor4me_1.0.1_x64-setup.exe` (l'installateur Tauri signé, situé dans `app\src-tauri\target\release\bundle\nsis\`)
4. `monitor4me_1.0.1_x64-setup.exe.sig` (le fichier de signature de l'installateur, situé au même endroit)

> [!IMPORTANT]
> **Visibilité du Dépôt** : Pour que les appels d'API anonymes effectués par l'installateur et l'application (téléchargement du collecteur, vérification des versions de LHM, auto-updater) fonctionnent sans erreur `404`, le dépôt GitHub **doit être public**. Configurez cela dans les *Settings* de votre dépôt GitHub.

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
