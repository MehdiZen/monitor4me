import { CONFIG } from "./config"
import * as fs from "fs"
import * as path from "path"

export interface UserConfig {
  tarifKwh: number
}

const CONFIG_FILE = path.join(process.cwd(), "user-config.json")

export const runtimeConfig: UserConfig = {
  tarifKwh: CONFIG.TARIF_KWH,
}

// Load persisted config on startup
try {
  const raw = fs.readFileSync(CONFIG_FILE, "utf-8")
  const data = JSON.parse(raw)
  if (typeof data.tarifKwh === "number" && data.tarifKwh > 0) {
    runtimeConfig.tarifKwh = data.tarifKwh
    console.log(`  Tarif kWh : €${runtimeConfig.tarifKwh} (user-config.json)`)
  }
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
