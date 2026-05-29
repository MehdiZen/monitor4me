# monitor4me

Real-time PC hardware monitoring dashboard — power draw, temperatures, voltages, fan speeds, and electricity costs with full historical tracking.

Built with **Tauri 2** + **TypeScript** + **InfluxDB**.

---

## Features

- **Live sensors** — CPU/GPU power & temperature, clocks, NVMe, PSU voltage rails (+12V / +5V / +3.3V), fan RPMs
- **Electricity costs** — live €/h, today's total, 31-day history with daily breakdown
- **Peripheral cost tracking** — monitors auto-detected via WMI, per-device wattage config; costs written to InfluxDB alongside PC data so history is immutable and accurate
- **Anomaly detection** — z-score alerts for thermal throttling, GPU clock drops, rail instability
- **Historical charts** — 24h hourly kWh, 7-day bar chart, full 31-day cost table (PC cost + total cost columns)

## Stack

| | |
|---|---|
| Desktop app | Tauri 2 · TypeScript · Vite |
| Charts | Chart.js |
| Collector | Node.js · TypeScript |
| Sensor source | [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) REST API |
| Storage | InfluxDB 2 · Flux |
| Monitor detection | WMI via PowerShell (`Get-PnpDevice`) |

## Prerequisites

- Windows 10/11
- [Node.js](https://nodejs.org) 20+
- [Rust](https://rustup.rs) (Tauri build only)
- **LibreHardwareMonitor** running with web server enabled on `:8085`
- **InfluxDB 2** running locally on `:8086`

## Setup

**1. InfluxDB** — create org `home`, bucket `pc-monitor`, and an API token, then expose it:

```powershell
[System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", "your-token", "User")
```

**2. Collector**

```bash
cd collector
npm install && npm run build
npm start
```

Polls LHM every 2s · writes metrics to InfluxDB · broadcasts live data on WebSocket `:8088`.

**3. App**

```bash
cd app
npm install
npm run build:app
```

Binary: `app/src-tauri/target/release/pc-monitor-app.exe` — a desktop shortcut is created automatically.

## Configuration

Click ⚙ in the app to set:

- **Electricity tariff** (€/kWh) — synced live to the collector
- **Detected monitors** — auto-listed from WMI, set wattage per screen
- **Other peripherals** — amp, NAS, etc.

## Project Structure

```
monitor4me/
├── app/                    Tauri desktop app
│   ├── src/
│   │   ├── main.ts         UI logic & chart updates
│   │   ├── influx.ts       InfluxDB Flux queries
│   │   ├── ws-client.ts    WebSocket client
│   │   └── charts.ts       Chart.js configuration
│   └── src-tauri/          Rust layer (window controls, tray icon, token bridge)
└── collector/              Node.js data collector
    └── src/
        ├── index.ts        Main poll loop
        ├── lhm.ts          LHM sensor parsing
        ├── metrics.ts      Power & cost calculations
        ├── anomaly.ts      Anomaly detection (z-score)
        ├── monitors.ts     WMI monitor detection
        ├── influx.ts       InfluxDB writes
        └── ws.ts           WebSocket broadcast
```

## Notes

- **RX 9070 XT**: LHM GPU power support is limited — collector marks readings `gpu_power_estimated=true` when falling back to an estimate.
- **RAM power**: No AM5 sensor available, fixed 10W estimate.
- **CPU RAPL**: Underestimates ~7%, corrected by `CPU_RAPL_CORRECTION = 1.07` in `config.ts`.

---

MIT
