import type { WSMessage, DataPoint, AnomalyRecord } from "./types"

const BUFFER_SIZE = 21600 // 12 hours at 2s intervals

export const store = {
  latest: null as WSMessage | null,
  connected: false,
  lastUpdate: 0,
  buffer: [] as DataPoint[],
  anomalyLog: [] as AnomalyRecord[],

  push(msg: WSMessage): void {
    this.latest = msg
    this.lastUpdate = Date.now()

    const pt: DataPoint = {
      ts: msg.ts,
      wallWatts: msg.metrics.wallWatts,
      cpuPowerW: msg.sensors.cpuPowerW,
      cpuTempC: msg.sensors.cpuTempC,
      cpuClockMhz: msg.sensors.cpuClockMhz,
      gpuPowerW: msg.sensors.gpuPowerW,
      gpuTempC: msg.sensors.gpuTempC,
      gpuClockMhz: msg.sensors.gpuClockMhz,
      rail12V: msg.sensors.rail12V,
      rail5V: msg.sensors.rail5V,
      rail3v3: msg.sensors.rail3v3,
    }

    this.buffer.push(pt)
    if (this.buffer.length > BUFFER_SIZE) this.buffer.shift()

    for (const a of msg.anomalies) {
      this.anomalyLog.unshift({ ...a, ts: msg.ts })
    }
    if (this.anomalyLog.length > 500) this.anomalyLog.length = 500
  },
}
