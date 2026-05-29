import { CONFIG } from "./config"
import { fetchLHMSensors } from "./lhm"
import { computeMetrics } from "./metrics"
import { detectAnomalies } from "./anomaly"
import { writeMetrics, closeInflux } from "./influx"
import { notifyAnomalies } from "./notify"
import { startWSServer, broadcastMetrics, closeWSServer } from "./ws"
import { detectMonitors, getCachedMonitors } from "./monitors"

const MONITOR_POLL_MS = 5 * 60 * 1000 // 5 minutes

let running = true

async function tick(): Promise<void> {
  let sensors
  try {
    sensors = await fetchLHMSensors()
  } catch (err) {
    console.error(`[LHM] fetch failed: ${(err as Error).message}`)
    return
  }

  const metrics = computeMetrics(sensors)
  const anomalies = detectAnomalies(sensors, metrics.wallWatts)

  const gpuTag = sensors.gpuPowerEstimated ? " (estimated)" : ""
  console.log(
    `[${new Date().toISOString()}] ` +
    `Wall: ${metrics.wallWatts.toFixed(1)}W | ` +
    `CPU: ${sensors.cpuPowerW.toFixed(1)}W ${sensors.cpuTempC.toFixed(0)}°C | ` +
    `GPU: ${sensors.gpuPowerW.toFixed(1)}W${gpuTag} ${sensors.gpuTempC.toFixed(0)}°C | ` +
    `Cost: €${metrics.costPerHour.toFixed(4)}/h` +
    (anomalies.length > 0 ? ` | ANOMALY: ${anomalies.map((a) => a.type).join(", ")}` : "")
  )

  for (const a of anomalies) console.warn(`  [${a.severity}] ${a.message}`)

  broadcastMetrics({ ts: Date.now(), sensors, metrics, anomalies, monitors: getCachedMonitors() })

  try {
    await writeMetrics(sensors, metrics, anomalies)
  } catch (err) {
    console.error(`[InfluxDB] write failed: ${(err as Error).message}`)
  }

  notifyAnomalies(anomalies)
}

async function main(): Promise<void> {
  console.log("PC Monitor collector starting...")
  console.log(`  Poll interval: ${CONFIG.POLL_INTERVAL_MS}ms`)
  console.log(`  LHM: ${CONFIG.LHM_URL}`)
  console.log(`  InfluxDB: ${CONFIG.INFLUX_URL} / bucket: ${CONFIG.INFLUX_BUCKET}`)
  console.log(`  Host tag: ${CONFIG.INFLUX_HOST_TAG}`)

  startWSServer()

  // Initial monitor detection + refresh every 5 min
  detectMonitors().then(m => console.log(`  Monitors detected: ${m.map(x => x.name).join(", ") || "none"}`))
  setInterval(() => detectMonitors(), MONITOR_POLL_MS)

  const shutdown = async () => {
    running = false
    console.log("\nShutting down...")
    await Promise.all([closeInflux(), closeWSServer()])
    process.exit(0)
  }

  process.on("SIGINT", shutdown)
  process.on("SIGTERM", shutdown)

  while (running) {
    const start = Date.now()
    await tick()
    const elapsed = Date.now() - start
    const delay = Math.max(0, CONFIG.POLL_INTERVAL_MS - elapsed)
    await new Promise((resolve) => setTimeout(resolve, delay))
  }
}

main().catch((err) => {
  console.error("Fatal:", err)
  process.exit(1)
})
