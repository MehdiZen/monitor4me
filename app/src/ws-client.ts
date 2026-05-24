import { store } from "./store"
import type { WSMessage } from "./types"

const WS_URL = "ws://localhost:8088"
let ws: WebSocket | null = null
let reconnectTimer: ReturnType<typeof setTimeout> | null = null
let pendingConfig: number | null = null

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
    if (pendingConfig !== null) ws!.send(JSON.stringify({ type: "config", tarifKwh: pendingConfig }))
  })

  ws.addEventListener("message", (event) => {
    try {
      const msg: WSMessage = JSON.parse(event.data as string)
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

export function sendConfig(tarifKwh: number): void {
  pendingConfig = tarifKwh
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "config", tarifKwh }))
  }
}

export function startWS(): void {
  connect()
}
