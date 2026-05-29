import { WebSocketServer, WebSocket } from "ws"
import { CONFIG } from "./config"
import { LHMSensors } from "./lhm"
import { ComputedMetrics } from "./metrics"
import { Anomaly } from "./anomaly"
import { MonitorInfo } from "./monitors"
import { updateConfig, runtimeConfig } from "./runtime-config"

export interface WSMessage {
  ts: number
  sensors: LHMSensors
  metrics: ComputedMetrics
  anomalies: Anomaly[]
  monitors: MonitorInfo[]
  config: { tarifKwh: number; host: string }
}

interface WSConfigMessage {
  type: "config"
  tarifKwh?: number
  periphWatts?: number
  cpuTdpW?: number
  gpuTdpW?: number
  cpuThrottleTempC?: number
  gpuTempCriticalC?: number
  nvmeTempCriticalC?: number
}

let wss: WebSocketServer | null = null

export function startWSServer(): void {
  wss = new WebSocketServer({ port: CONFIG.WS_PORT })
  wss.on("connection", (ws) => {
    ws.on("error", () => {})
    ws.on("message", (raw) => {
      try {
        const msg: WSConfigMessage = JSON.parse(raw.toString())
        if (msg.type === "config") {
          if (typeof msg.tarifKwh === "number" && msg.tarifKwh > 0) {
            updateConfig({ tarifKwh: msg.tarifKwh })
            console.log(`[Config] Tarif kWh mis a jour : €${msg.tarifKwh}`)
          }
          if (typeof msg.periphWatts      === "number" && msg.periphWatts >= 0)      updateConfig({ periphWatts:       msg.periphWatts })
          if (typeof msg.cpuTdpW          === "number" && msg.cpuTdpW > 0)          updateConfig({ cpuTdpW:           msg.cpuTdpW })
          if (typeof msg.gpuTdpW          === "number" && msg.gpuTdpW > 0)          updateConfig({ gpuTdpW:           msg.gpuTdpW })
          if (typeof msg.cpuThrottleTempC === "number" && msg.cpuThrottleTempC > 0) updateConfig({ cpuThrottleTempC:  msg.cpuThrottleTempC })
          if (typeof msg.gpuTempCriticalC === "number" && msg.gpuTempCriticalC > 0) updateConfig({ gpuTempCriticalC:  msg.gpuTempCriticalC })
          if (typeof msg.nvmeTempCriticalC=== "number" && msg.nvmeTempCriticalC> 0) updateConfig({ nvmeTempCriticalC: msg.nvmeTempCriticalC })
        }
      } catch { /* ignore malformed messages */ }
    })
  })
  console.log(`  WebSocket: ws://localhost:${CONFIG.WS_PORT}`)
}

export function broadcastMetrics(data: Omit<WSMessage, "config">): void {
  if (!wss) return
  const payload = JSON.stringify({ ...data, config: { tarifKwh: runtimeConfig.tarifKwh, host: CONFIG.INFLUX_HOST_TAG } })
  wss.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) client.send(payload)
  })
}

export async function closeWSServer(): Promise<void> {
  return new Promise((resolve) => {
    if (!wss) { resolve(); return }
    wss.close(() => resolve())
  })
}
