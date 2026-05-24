import { WebSocketServer, WebSocket } from "ws"
import { CONFIG } from "./config"
import { LHMSensors } from "./lhm"
import { ComputedMetrics } from "./metrics"
import { Anomaly } from "./anomaly"
import { updateConfig, runtimeConfig } from "./runtime-config"

export interface WSMessage {
  ts: number
  sensors: LHMSensors
  metrics: ComputedMetrics
  anomalies: Anomaly[]
  config: { tarifKwh: number }
}

interface WSConfigMessage {
  type: "config"
  tarifKwh?: number
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
        }
      } catch { /* ignore malformed messages */ }
    })
  })
  console.log(`  WebSocket: ws://localhost:${CONFIG.WS_PORT}`)
}

export function broadcastMetrics(data: Omit<WSMessage, "config">): void {
  if (!wss) return
  const payload = JSON.stringify({ ...data, config: { tarifKwh: runtimeConfig.tarifKwh } })
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
