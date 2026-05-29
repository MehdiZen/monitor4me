import { CONFIG } from "./config"
import { runtimeConfig } from "./runtime-config"
import { LHMSensors } from "./lhm"

export type Severity = "INFO" | "WARNING" | "CRITICAL"

export interface Anomaly {
  type: string
  severity: Severity
  component: string
  measuredValue: number
  threshold: number
  message: string
}

// Rolling window for Z-score and std-dev calculations
class RollingWindow {
  private values: number[] = []
  private maxSize: number

  constructor(size: number) {
    this.maxSize = size
  }

  push(v: number) {
    this.values.push(v)
    if (this.values.length > this.maxSize) this.values.shift()
  }

  mean(): number {
    if (this.values.length === 0) return 0
    return this.values.reduce((a, b) => a + b, 0) / this.values.length
  }

  stddev(): number {
    if (this.values.length < 2) return 0
    const m = this.mean()
    const variance = this.values.reduce((acc, v) => acc + (v - m) ** 2, 0) / this.values.length
    return Math.sqrt(variance)
  }

  zscore(v: number): number {
    const sd = this.stddev()
    if (sd === 0) return 0
    return (v - this.mean()) / sd
  }

  full(): boolean {
    return this.values.length >= this.maxSize
  }

  last(): number {
    return this.values[this.values.length - 1] ?? 0
  }

  prev(offset = 1): number {
    return this.values[this.values.length - 1 - offset] ?? 0
  }
}

// State shared across ticks
const cpuPowerWindow = new RollingWindow(CONFIG.ZSCORE_WINDOW)
const rail12vWindow = new RollingWindow(CONFIG.RAIL_12V_WINDOW)

// Track previous CPU clock for throttle detection
let prevCpuClockMhz = 0
let prevCpuPowerW = 0
let prevGpuClockMhz = 0
// Track timestamps for power drop window
const cpuPowerHistory: { ts: number; w: number }[] = []

export function detectAnomalies(sensors: LHMSensors, wallWatts: number): Anomaly[] {
  const anomalies: Anomaly[] = []
  const now = Date.now()

  // Update windows
  cpuPowerWindow.push(sensors.cpuPowerW)
  rail12vWindow.push(sensors.rail12V)

  // Keep 5s history for CPU power drop detection
  cpuPowerHistory.push({ ts: now, w: sensors.cpuPowerW })
  const cutoff = now - CONFIG.CPU_POWER_DROP_WINDOW_S * 1000
  while (cpuPowerHistory.length > 0 && cpuPowerHistory[0].ts < cutoff) cpuPowerHistory.shift()

  // --- CPU thermal throttle ---
  if (prevCpuClockMhz > 0 && sensors.cpuTempC > runtimeConfig.cpuThrottleTempC) {
    const freqDrop = (prevCpuClockMhz - sensors.cpuClockMhz) / prevCpuClockMhz
    if (freqDrop > CONFIG.CPU_THROTTLE_FREQ_DROP) {
      anomalies.push({
        type: "cpu_thermal_throttle",
        severity: "WARNING",
        component: "CPU",
        measuredValue: sensors.cpuTempC,
        threshold: runtimeConfig.cpuThrottleTempC,
        message: `CPU throttling: temp ${sensors.cpuTempC.toFixed(1)}°C, freq dropped ${(freqDrop * 100).toFixed(0)}%`,
      })
    }
  }

  // --- CPU power spike (Z-score) ---
  if (cpuPowerWindow.full()) {
    const z = cpuPowerWindow.zscore(sensors.cpuPowerW)
    if (z > CONFIG.ZSCORE_THRESHOLD) {
      anomalies.push({
        type: "cpu_power_spike",
        severity: "INFO",
        component: "CPU",
        measuredValue: sensors.cpuPowerW,
        threshold: cpuPowerWindow.mean() + CONFIG.ZSCORE_THRESHOLD * cpuPowerWindow.stddev(),
        message: `CPU power spike: ${sensors.cpuPowerW.toFixed(1)}W (Z=${z.toFixed(2)})`,
      })
    }
  }

  // --- CPU power drop brutal (>30% in <5s, sans chute de fréquence) ---
  // Si la fréquence chute aussi → transition idle normale (fin de jeu, rendu…), pas une anomalie.
  // Si la puissance chute mais la fréquence reste haute → problème d'alim potentiel.
  if (cpuPowerHistory.length >= 2) {
    const oldest = cpuPowerHistory[0].w
    if (oldest > 20) {
      const drop = (oldest - sensors.cpuPowerW) / oldest
      const clockAlsoDropped = prevCpuClockMhz > 0 && sensors.cpuClockMhz < prevCpuClockMhz * 0.8
      if (drop > CONFIG.CPU_POWER_DROP_THRESHOLD && !clockAlsoDropped) {
        anomalies.push({
          type: "cpu_power_drop",
          severity: "WARNING",
          component: "CPU",
          measuredValue: sensors.cpuPowerW,
          threshold: oldest * (1 - CONFIG.CPU_POWER_DROP_THRESHOLD),
          message: `CPU power dropped ${(drop * 100).toFixed(0)}% in ${CONFIG.CPU_POWER_DROP_WINDOW_S}s (${oldest.toFixed(0)}W → ${sensors.cpuPowerW.toFixed(0)}W)`,
        })
      }
    }
  }

  // --- GPU power > TDP ---
  if (sensors.gpuPowerW > runtimeConfig.gpuTdpW * 1.1) {
    anomalies.push({
      type: "gpu_power_over_tdp",
      severity: "WARNING",
      component: "GPU",
      measuredValue: sensors.gpuPowerW,
      threshold: runtimeConfig.gpuTdpW * 1.1,
      message: `GPU power ${sensors.gpuPowerW.toFixed(1)}W exceeds TDP+10% (${(runtimeConfig.gpuTdpW * 1.1).toFixed(0)}W)`,
    })
  }

  // --- GPU clock drop ---
  if (prevGpuClockMhz > 100) {
    const gpuDrop = (prevGpuClockMhz - sensors.gpuClockMhz) / prevGpuClockMhz
    if (gpuDrop > CONFIG.GPU_CLOCK_DROP && sensors.gpuTempC < runtimeConfig.gpuTempCriticalC - 10) {
      anomalies.push({
        type: "gpu_clock_drop",
        severity: "WARNING",
        component: "GPU",
        measuredValue: sensors.gpuClockMhz,
        threshold: prevGpuClockMhz * (1 - CONFIG.GPU_CLOCK_DROP),
        message: `GPU clock dropped ${(gpuDrop * 100).toFixed(0)}% (${prevGpuClockMhz.toFixed(0)} → ${sensors.gpuClockMhz.toFixed(0)} MHz)`,
      })
    }
  }

  // --- GPU temp critique ---
  if (sensors.gpuTempC >= runtimeConfig.gpuTempCriticalC) {
    anomalies.push({
      type: "gpu_temp_critical",
      severity: "CRITICAL",
      component: "GPU",
      measuredValue: sensors.gpuTempC,
      threshold: runtimeConfig.gpuTempCriticalC,
      message: `GPU temperature critical: ${sensors.gpuTempC.toFixed(1)}°C`,
    })
  }

  // --- Rail 12V hors tolérance ATX ---
  if (sensors.rail12V > 0) {
    if (sensors.rail12V < CONFIG.RAIL_12V_MIN || sensors.rail12V > CONFIG.RAIL_12V_MAX) {
      anomalies.push({
        type: "rail_12v_out_of_spec",
        severity: "CRITICAL",
        component: "PSU",
        measuredValue: sensors.rail12V,
        threshold: CONFIG.RAIL_12V_MIN,
        message: `12V rail out of ATX spec: ${sensors.rail12V.toFixed(3)}V (allowed ${CONFIG.RAIL_12V_MIN}–${CONFIG.RAIL_12V_MAX}V)`,
      })
    }

    // --- Rail 12V instable ---
    if (rail12vWindow.full() && rail12vWindow.stddev() > CONFIG.RAIL_12V_STDDEV_MAX) {
      anomalies.push({
        type: "rail_12v_unstable",
        severity: "WARNING",
        component: "PSU",
        measuredValue: rail12vWindow.stddev(),
        threshold: CONFIG.RAIL_12V_STDDEV_MAX,
        message: `12V rail unstable: std dev ${rail12vWindow.stddev().toFixed(4)}V over last ${CONFIG.RAIL_12V_WINDOW * 2}s`,
      })
    }
  }

  // --- NVMe temp critique ---
  if (sensors.nvmeTempC > 0 && sensors.nvmeTempC >= runtimeConfig.nvmeTempCriticalC) {
    anomalies.push({
      type: "nvme_temp_critical",
      severity: "WARNING",
      component: "NVMe",
      measuredValue: sensors.nvmeTempC,
      threshold: runtimeConfig.nvmeTempCriticalC,
      message: `NVMe temperature critical: ${sensors.nvmeTempC.toFixed(1)}°C`,
    })
  }

  // --- PC inactif ---
  if (wallWatts > 0 && wallWatts < CONFIG.IDLE_WALL_WATTS) {
    anomalies.push({
      type: "pc_idle",
      severity: "INFO",
      component: "SYSTEM",
      measuredValue: wallWatts,
      threshold: CONFIG.IDLE_WALL_WATTS,
      message: `PC idle: wall power ${wallWatts.toFixed(1)}W`,
    })
  }

  // Update prev values
  prevCpuClockMhz = sensors.cpuClockMhz
  prevCpuPowerW = sensors.cpuPowerW
  prevGpuClockMhz = sensors.gpuClockMhz

  return anomalies
}
