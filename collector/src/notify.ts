import notifier from "node-notifier"
import { Anomaly, Severity } from "./anomaly"
import { CONFIG } from "./config"

// Debounce map: anomaly type → last notified timestamp
const lastNotified = new Map<string, number>()

export function notifyAnomalies(anomalies: Anomaly[]): void {
  for (const anomaly of anomalies) {
    if (anomaly.severity === "INFO") continue  // INFO → InfluxDB only

    const now = Date.now()
    const last = lastNotified.get(anomaly.type) ?? 0

    const debounceMs = anomaly.severity === "CRITICAL" ? 15_000 : CONFIG.WARNING_DEBOUNCE_MS
    if (now - last < debounceMs) continue

    lastNotified.set(anomaly.type, now)

    const icon = anomaly.severity === "CRITICAL" ? "❌" : "⚠️"

    notifier.notify({
      title: `${icon} PC Monitor — ${anomaly.component} ${anomaly.severity}`,
      message: anomaly.message,
      sound: anomaly.severity === "CRITICAL",
      wait: false,
      appID: "PC Monitor",
    })
  }
}
