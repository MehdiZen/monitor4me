# PC Power Monitor

Real-time power consumption monitoring for Windows — AMD Ryzen 7 7800X3D + RX 9070 XT.

## Quick Start

### 1. Prerequisites

```powershell
winget install InfluxData.InfluxDB
winget install GrafanaLabs.Grafana
# Node.js 20 LTS: https://nodejs.org
# LHM: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases
```

### 2. Start services

```powershell
net start influxdb
net start grafana
# Start LHM.exe as administrator (or use setup-task.ps1)
```

### 3. Configure InfluxDB

```powershell
# Elevated PowerShell
powershell -ExecutionPolicy Bypass -File scripts\setup-influx.ps1
```

### 4. Validate LHM sensors (critical for RX 9070 XT)

```powershell
powershell -File scripts\test-lhm.ps1
```

If GPU power shows 0 → LHM doesn't yet support the RX 9070 XT. The collector will log `(estimated)` and write `gpu_power_estimated=true` to InfluxDB.

### 5. Build & run the collector

```bash
cd collector
npm install
npm run build
INFLUX_TOKEN=<your-token> npm start
```

### 6. Import Grafana dashboard

1. Open http://localhost:3000
2. Dashboards → Import → Upload JSON → `grafana/dashboards/pc-monitor.json`
3. Select your InfluxDB datasource

### 7. Autostart at boot (optional)

```powershell
# Elevated PowerShell — registers LHM + collector as Windows scheduled tasks
powershell -ExecutionPolicy Bypass -File scripts\setup-task.ps1
```

## Architecture

```
LHM.exe (REST :8085) → collector/src/index.ts → InfluxDB :8086 → Grafana :3000
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `INFLUX_TOKEN` | `pc-monitor-token` | InfluxDB API token |

## Known limitations

- **RX 9070 XT**: GPU power via LHM is approximate / may be 0. Collector marks it `gpu_power_estimated=true`.
- **RAM power**: No sensor available on AM5. Fixed 10W estimate.
- **CPU RAPL**: Underestimates ~7%. Corrected by `CPU_RAPL_CORRECTION=1.07` in `config.ts`.
