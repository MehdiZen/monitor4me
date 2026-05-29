import { store } from "./store"
import type { WSMessage } from "./types"

const WS_URL = "ws://localhost:8088"
let ws: WebSocket | null = null
let reconnectTimer: ReturnType<typeof setTimeout> | null = null
let pendingConfig: number | null = null
let pendingPeriphWatts: number | null = null

type Listener = (msg: WSMessage) => void
const listeners: Listener[] = []

export function onMessage(fn: Listener): void {
  listeners.push(fn)
}

function connect(): void {
  ws = new WebSocket(WS_URL)

  ws.addEventListener("open", () => {
    store.connected = true
    updateStatus(true)
    if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null }
    if (pendingFullConfig !== null) {
      ws!.send(JSON.stringify({ type: "config", ...pendingFullConfig }))
    } else if (pendingConfig !== null) {
      ws!.send(JSON.stringify({ type: "config", tarifKwh: pendingConfig }))
    }
  })

  ws.addEventListener("message", (event) => {
    try {
      const raw = JSON.parse(event.data as string)
      const msg: WSMessage = { monitors: [], ...raw } // fallback if collector is older build
      store.push(msg)
      for (const fn of listeners) fn(msg)
    } catch { /* ignore malformed frames */ }
  })

  ws.addEventListener("close", () => {
    store.connected = false
    updateStatus(false)
    scheduleReconnect()
  })

  ws.addEventListener("error", () => {
    ws?.close()
  })
}

function scheduleReconnect(): void {
  if (reconnectTimer) return
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    connect()
  }, 3000)
}

function updateStatus(connected: boolean): void {
  const dot = document.getElementById("status-dot")
  const text = document.getElementById("status-text")
  if (!dot || !text) return
  dot.className = "status-dot " + (connected ? "ok" : "error")
  text.textContent = connected ? "Connected" : "Reconnecting…"
}

export interface CollectorConfig {
  tarifKwh: number
  periphWatts?: number
  cpuTdpW?: number
  gpuTdpW?: number
  cpuThrottleTempC?: number
  gpuTempCriticalC?: number
  nvmeTempCriticalC?: number
}

let pendingFullConfig: CollectorConfig | null = null

export function sendConfig(cfg: CollectorConfig): void {
  pendingConfig       = cfg.tarifKwh
  pendingPeriphWatts  = cfg.periphWatts ?? pendingPeriphWatts
  pendingFullConfig   = cfg
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "config", ...cfg }))
  }
}

export function startWS(): void {
  connect()
}
