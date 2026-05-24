import { invoke } from "@tauri-apps/api/core"

const INFLUX_URL = "http://localhost:8086"
const ORG        = "home"
const BUCKET     = "pc-monitor"
const HOST       = "CODEC"

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

export async function getTodayCost(): Promise<number> {
  // cost_per_hour is a rate (€/h). Each sample covers POLL_INTERVAL_S seconds.
  // actual cost = sum(rate_i) * poll_interval_h = sum * (2/3600)
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: today())
      |> filter(fn: (r) => r._measurement == "hardware" and r._field == "cost_per_hour" and r.host == "${HOST}")
      |> sum()
      |> map(fn: (r) => ({ r with _value: r._value * 2.0 / 3600.0 }))
  `)
  const rows = parseCSV(csv)
  return parseFloat(rows[0]?._value ?? "0") || 0
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

export async function getLast3DaysCost(): Promise<{ date: string; cost: number }[]> {
  const csv = await query(`
    from(bucket: "${BUCKET}")
      |> range(start: -3d)
      |> filter(fn: (r) => r._measurement == "hardware" and r._field == "cost_per_hour" and r.host == "${HOST}")
      |> aggregateWindow(every: 1d, fn: sum, createEmpty: true)
      |> map(fn: (r) => ({ r with _value: r._value * 2.0 / 3600.0 }))
  `)
  return parseCSV(csv)
    .filter(row => row._time && row._value !== undefined && row._value !== "")
    .map(row => {
      const d = new Date(row._time)
      // _time marks end of window — subtract 1ms to get the correct day
      d.setMilliseconds(d.getMilliseconds() - 1)
      return {
        date: d.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" }),
        cost: parseFloat(row._value ?? "0") || 0,
      }
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
