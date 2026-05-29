import { CONFIG } from "./config"
import * as fs from "fs"
import * as path from "path"

export interface UserConfig {
  tarifKwh: number
  periphWatts: number
  cpuTdpW: number
  gpuTdpW: number
  cpuThrottleTempC: number
  gpuTempCriticalC: number
  nvmeTempCriticalC: number
}

const CONFIG_FILE = path.join(process.cwd(), "user-config.json")

export const runtimeConfig: UserConfig = {
  tarifKwh:          CONFIG.TARIF_KWH,
  periphWatts:       0,
  cpuTdpW:           CONFIG.CPU_TDP_W,
  gpuTdpW:           CONFIG.GPU_TDP_W,
  cpuThrottleTempC:  CONFIG.CPU_THROTTLE_TEMP_C,
  gpuTempCriticalC:  CONFIG.GPU_TEMP_CRITICAL_C,
  nvmeTempCriticalC: CONFIG.NVME_TEMP_CRITICAL_C,
}

// Load persisted config on startup
try {
  const raw = fs.readFileSync(CONFIG_FILE, "utf-8")
  const data = JSON.parse(raw)
  if (typeof data.tarifKwh === "number" && data.tarifKwh > 0) {
    runtimeConfig.tarifKwh = data.tarifKwh
    console.log(`  Tarif kWh : €${runtimeConfig.tarifKwh} (user-config.json)`)
  }
  if (typeof data.periphWatts === "number" && data.periphWatts >= 0) {
    runtimeConfig.periphWatts = data.periphWatts
    console.log(`  Periph watts : ${runtimeConfig.periphWatts} W (user-config.json)`)
  }
  if (typeof data.cpuTdpW           === "number" && data.cpuTdpW > 0)           runtimeConfig.cpuTdpW           = data.cpuTdpW
  if (typeof data.gpuTdpW           === "number" && data.gpuTdpW > 0)           runtimeConfig.gpuTdpW           = data.gpuTdpW
  if (typeof data.cpuThrottleTempC  === "number" && data.cpuThrottleTempC > 0)  runtimeConfig.cpuThrottleTempC  = data.cpuThrottleTempC
  if (typeof data.gpuTempCriticalC  === "number" && data.gpuTempCriticalC > 0)  runtimeConfig.gpuTempCriticalC  = data.gpuTempCriticalC
  if (typeof data.nvmeTempCriticalC === "number" && data.nvmeTempCriticalC > 0) runtimeConfig.nvmeTempCriticalC = data.nvmeTempCriticalC
} catch {
  // No config file yet, use default
}

export function updateConfig(updates: Partial<UserConfig>): void {
  Object.assign(runtimeConfig, updates)
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(runtimeConfig, null, 2))
  } catch (err) {
    console.error("[Config] Failed to persist:", err)
  }
}
