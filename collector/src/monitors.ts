import { exec } from "child_process"

export interface MonitorInfo {
  id: string        // stable InstanceId
  name: string      // FriendlyName (real model name from EDID)
  active: boolean   // PnpDevice Status == "OK"
}

// Cached result — refreshed every MONITOR_POLL_MS
let cachedMonitors: MonitorInfo[] = []

export function getCachedMonitors(): MonitorInfo[] {
  return cachedMonitors
}

export async function detectMonitors(): Promise<MonitorInfo[]> {
  return new Promise((resolve) => {
    const ps = `Get-PnpDevice -Class Monitor | Select-Object Status,FriendlyName,InstanceId | ConvertTo-Json -Compress`
    exec(
      `powershell -NoProfile -NonInteractive -Command "${ps}"`,
      { timeout: 10000 },
      (err, stdout) => {
        if (err) {
          console.warn("[monitors] PnpDevice query failed:", err.message)
          resolve(cachedMonitors)
          return
        }
        try {
          const raw = stdout.trim()
          if (!raw) { resolve(cachedMonitors); return }

          // ConvertTo-Json returns object (not array) when there's only 1 item
          const parsed = JSON.parse(raw)
          const items: Array<{ Status: string; FriendlyName: string; InstanceId: string }> =
            Array.isArray(parsed) ? parsed : [parsed]

          const all: MonitorInfo[] = items
            .filter(m => m && m.InstanceId)
            .map(m => ({
              id:     m.InstanceId,
              name:   m.FriendlyName || m.InstanceId,
              active: (m.Status ?? "").toLowerCase() === "ok",
            }))

          // Garde uniquement les moniteurs actifs (Status === "OK").
          // Les ports fantômes ont Status != "OK" → filtrés naturellement.
          // Deux moniteurs identiques sur ports différents ont tous deux Status="OK" → conservés.
          const monitors: MonitorInfo[] = all.filter(m => m.active)

          cachedMonitors = monitors
          console.log(`[monitors] detected: ${monitors.map(m => `${m.active ? "●" : "○"} ${m.name}`).join(", ")}`)
          resolve(monitors)
        } catch (e) {
          console.warn("[monitors] JSON parse failed:", e)
          resolve(cachedMonitors)
        }
      }
    )
  })
}
