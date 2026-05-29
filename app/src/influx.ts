import { invoke } from "@tauri-apps/api/core"

const INFLUX_URL = "http://localhost:8086"
const ORG        = "home"
const BUCKET     = "pc-monitor"
let HOST         = ""

export function setInfluxHost(host: string): void {
  HOST = host
}

// Token fetched once from Tauri env (INFLUX_TOKEN user env var)
const TOKEN_PROMISE: Promise<string> = invoke<string>("get_influx_token")
  .then(t => t || "pc-monitor-token")
  .catch(() => "pc-monitor-token")

async function query(flux: string): Promise<string> {
  const token = await TOKEN_PROMISE
  const res = await fetch(`${INFLUX_URL}/api/v2/query?org=${encodeURIComponent(ORG)}`, {
    method: "POST",
    headers: {
      "Authorization": `Token ${token}`,
      "Content-Type": "application/vnd.flux",
      "Accept": "application/csv",
    },
    body: flux,
    signal: AbortSignal.timeout(8000),
  })
  if (!res.ok) throw new Error(`InfluxDB ${res.status}`)
  return res.text()
}

function parseCSV(csv: string): Record<string, string>[] {
  const lines = csv.trim().split("\n").filter(l => l && !l.startsWith("#"))
  if (lines.length < 2) return []
  const headers = lines[0].split(",")
  return lines.slice(1).map(line => {
    const vals = line.split(",")
    const obj: Record<string, string> = {}
    headers.forEach((h, i) => { obj[h.trim()] = (vals[i] ?? "").trim() })
    return obj
  })
}

export interface HourlyKWh {
  time: Date
  cpuKwh: number
  gpuKwh: number
  otherKwh: number
  totalKwh: number
}

export async function getTodayCost(): Promise<{ costPc: number; costPeriph: number }> {
  // Both cost_per_hour and periph_cost_per_hour are written at the same ticks (PC on).
  // Reading both from DB ensures periph cost only covers hours the PC was actually running.
  const now = new Date()
  const localMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const startISO = localMidnight.toISOString()

  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: ${startISO})
      |> filter(fn: (r) => r._measurement == "hardware"
          and (r._field == "cost_per_hour" or r._field == "periph_cost_per_hour")
          and r.host == "${HOST}")
      |> sum()
      |> map(fn: (r) => ({ r with _value: r._value * 2.0 / 3600.0 }))
      |> pivot(rowKey: ["_start"], columnKey: ["_field"], valueColumn: "_value")
  `)
  const row = parseCSV(csv)[0]
  return {
    costPc:     parseFloat(row?.cost_per_hour      ?? "0") || 0,
    costPeriph: parseFloat(row?.periph_cost_per_hour ?? "0") || 0,
  }
}

export async function getMonthlyProjection(): Promise<number> {
  // Average hourly rate over last 7 days → projected monthly cost
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -7d)
      |> filter(fn: (r) => r._measurement == "hardware" and r._field == "cost_per_hour" and r.host == "${HOST}")
      |> mean()
  `)
  const rows = parseCSV(csv)
  const avgPerHour = parseFloat(rows[0]?._value ?? "0") || 0
  return avgPerHour * 24 * 30
}

export async function get24hHourly(): Promise<HourlyKWh[]> {
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -24h)
      |> filter(fn: (r) => r._measurement == "hardware" and
          (r._field == "cpu_power_w" or r._field == "gpu_power_w" or r._field == "wall_watts")
          and r.host == "${HOST}")
      |> aggregateWindow(every: 1h, fn: mean, createEmpty: true)
      |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  `)
  return parseCSV(csv)
    .filter(row => row._time && row.wall_watts !== undefined && row.wall_watts !== "")
    .map(row => {
      const cpu  = parseFloat(row.cpu_power_w ?? "0") / 1000
      const gpu  = parseFloat(row.gpu_power_w ?? "0") / 1000
      const wall = parseFloat(row.wall_watts  ?? "0") / 1000
      return {
        time:     new Date(row._time),
        cpuKwh:   cpu,
        gpuKwh:   gpu,
        otherKwh: Math.max(0, wall - cpu - gpu),
        totalKwh: wall,
      }
    })
}

export async function get7dDaily(): Promise<{ time: Date; kwh: number }[]> {
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -7d)
      |> filter(fn: (r) => r._measurement == "hardware" and r._field == "wall_watts" and r.host == "${HOST}")
      |> aggregateWindow(every: 1d, fn: mean, createEmpty: true)
      |> map(fn: (r) => ({ r with _value: r._value * 24.0 / 1000.0 }))
  `)
  return parseCSV(csv)
    .filter(row => row._time && row._value !== undefined && row._value !== "")
    .map(row => ({
      time: new Date(row._time),
      kwh:  parseFloat(row._value ?? "0"),
    }))
}

function windowTimeToDayLabel(isoTime: string): string {
  // aggregateWindow _time = end of window (UTC-aligned).
  // Subtracting 12h lands at mid-window which always falls in the correct local day,
  // regardless of the local UTC offset — unlike -1ms which breaks near UTC midnight boundaries.
  const d = new Date(isoTime)
  d.setHours(d.getHours() - 12)
  return d.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" })
}

export async function getLast3DaysCost(): Promise<{ date: string; costPc: number; costPeriph: number }[]> {
  const now = new Date()
  const localMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const stopISO = localMidnight.toISOString()

  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -2d, stop: ${stopISO})
      |> filter(fn: (r) => r._measurement == "hardware"
          and (r._field == "cost_per_hour" or r._field == "periph_cost_per_hour")
          and r.host == "${HOST}")
      |> aggregateWindow(every: 1d, fn: sum, createEmpty: false)
      |> map(fn: (r) => ({ r with _value: r._value * 2.0 / 3600.0 }))
      |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> sort(columns: ["_time"], desc: true)
  `)
  return parseCSV(csv)
    .filter(row => row._time && row.cost_per_hour !== undefined && row.cost_per_hour !== "")
    .map(row => ({
      date:        windowTimeToDayLabel(row._time),
      costPc:      parseFloat(row.cost_per_hour ?? "0") || 0,
      costPeriph:  parseFloat(row.periph_cost_per_hour ?? "0") || 0,
    }))
}

export async function getLast31DaysCost(): Promise<{ date: string; costPc: number; costPeriph: number; kwh: number }[]> {
  const now = new Date()
  const localMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const stopISO = localMidnight.toISOString()

  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -31d, stop: ${stopISO})
      |> filter(fn: (r) => r._measurement == "hardware"
          and (r._field == "cost_per_hour" or r._field == "periph_cost_per_hour" or r._field == "wall_watts")
          and r.host == "${HOST}")
      |> aggregateWindow(every: 1d, fn: sum, createEmpty: false)
      |> map(fn: (r) => ({ r with _value: r._value * 2.0 / 3600.0 }))
      |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> sort(columns: ["_time"], desc: true)
  `)
  return parseCSV(csv)
    .filter(row => row._time && row.cost_per_hour !== undefined && row.cost_per_hour !== "")
    .map(row => {
      const costPc     = parseFloat(row.cost_per_hour ?? "0") || 0
      const costPeriph = parseFloat(row.periph_cost_per_hour ?? "0") || 0
      // wall_watts sum * 2/3600 = Wh → /1000 pour kWh
      const kwh = (parseFloat(row.wall_watts ?? "0") || 0) / 1000
      return { date: windowTimeToDayLabel(row._time), costPc, costPeriph, kwh }
    })
}

export async function getAnomalyHistory(): Promise<{ ts: Date; severity: string; type: string; message: string; value: number }[]> {
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -30d)
      |> filter(fn: (r) => r._measurement == "hardware" and
          (r._field == "anomaly_type" or r._field == "anomaly_severity")
          and r._value != "" and r.host == "${HOST}")
      |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> filter(fn: (r) => exists r.anomaly_severity and r.anomaly_severity != "")
      |> sort(columns: ["_time"], desc: true)
      |> limit(n: 200)
  `)
  return parseCSV(csv).map(row => ({
    ts:       new Date(row._time),
    severity: row.anomaly_severity ?? "",
    type:     row.anomaly_type ?? "",
    message:  row.anomaly_type ?? "",
    value:    0,
  }))
}
