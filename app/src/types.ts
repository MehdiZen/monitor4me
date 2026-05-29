export interface LHMSensors {
  cpuName: string
  gpuName: string
  cpuPowerW: number
  cpuTempC: number
  cpuClockMhz: number
  gpuPowerW: number
  gpuTempC: number
  gpuHotspotTempC: number
  gpuMemTempC: number
  gpuFanRpm: number
  gpuFanPct: number
  gpuClockMhz: number
  nvmePowerW: number | null
  nvmeTempC: number
  rail12V: number
  rail5V: number
  rail3v3: number
  fan1Rpm: number
  fan2Rpm: number
  fan5Rpm: number
  gpuPowerEstimated: boolean
}

export interface ComputedMetrics {
  ramPowerW: number
  moboPowerW: number
  nvmePowerW: number
  totalDcW: number
  wallWatts: number
  costPerHour: number
}

export type Severity = "INFO" | "WARNING" | "CRITICAL"

export interface Anomaly {
  type: string
  severity: Severity
  component: string
  measuredValue: number
  threshold: number
  message: string
}

export interface MonitorInfo {
  id: string
  name: string
  active: boolean
}

export interface WSMessage {
  ts: number
  sensors: LHMSensors
  metrics: ComputedMetrics
  anomalies: Anomaly[]
  monitors: MonitorInfo[]
  config?: {
    tarifKwh: number
    host: string
  }
}

export interface DataPoint {
  ts: number
  wallWatts: number
  cpuPowerW: number
  cpuTempC: number
  cpuClockMhz: number
  gpuPowerW: number
  gpuTempC: number
  gpuClockMhz: number
  rail12V: number
  rail5V: number
  rail3v3: number
}

export interface AnomalyRecord extends Anomaly {
  ts: number
}
