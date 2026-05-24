import { CONFIG } from "./config"
import { runtimeConfig } from "./runtime-config"
import { LHMSensors } from "./lhm"

export interface ComputedMetrics {
  ramPowerW: number
  moboPowerW: number
  nvmePowerW: number
  totalDcW: number
  wallWatts: number
  costPerHour: number
}

export function computeMetrics(sensors: LHMSensors): ComputedMetrics {
  const ramPowerW = CONFIG.RAM_WATTS
  const moboPowerW = CONFIG.MOBO_WATTS
  const nvmePowerW = sensors.nvmePowerW ?? CONFIG.NVME_WATTS_FALLBACK

  const totalDcW = sensors.cpuPowerW + sensors.gpuPowerW + ramPowerW + moboPowerW + nvmePowerW
  const wallWatts = totalDcW / CONFIG.PSU_EFFICIENCY
  const costPerHour = (wallWatts / 1000) * runtimeConfig.tarifKwh

  return { ramPowerW, moboPowerW, nvmePowerW, totalDcW, wallWatts, costPerHour }
}
