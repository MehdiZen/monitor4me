import { invoke } from "@tauri-apps/api/core"
import { listen } from "@tauri-apps/api/event"
import { store } from "./store"
import { startWS, onMessage, sendConfig, type CollectorConfig } from "./ws-client"
import { getTodayCost, getMonthlyProjection, get24hHourly, get7dDaily, getAnomalyHistory, getLast3DaysCost, getLast31DaysCost, setInfluxHost } from "./influx"
import {
  makeCpuPowerChart, makeCpuTempChart, makeCpuClockChart,
  makeGpuPowerChart, makeGpuTempChart, makeGpuClockChart,
  makeRailChart, makeEnergyBarChart, make7dChart,
  makeOverviewPowerChart, makeOverviewTempChart,
  updateLineChart, updateRailChart, updateEnergyBarChart, update7dChart,
  updateOverviewTempChart,
} from "./charts"
import type { Chart } from "chart.js"
import type { WSMessage } from "./types"

// ── Auto-update ───────────────────────────────────────────────────────────────

listen<{ version: string; notes: string }>("update-available", ({ payload }) => {
  const banner  = document.getElementById("update-banner")
  const msg     = document.getElementById("update-msg")
  const btn     = document.getElementById("update-btn")
  const dismiss = document.getElementById("update-dismiss")
  if (!banner || !msg || !btn || !dismiss) return

  msg.textContent = `Nouvelle version disponible : v${payload.version}`
  banner.style.display = "flex"

  btn.onclick = async () => {
    btn.textContent = "Téléchargement…"
    btn.setAttribute("disabled", "true")
    try {
      await invoke("install_update")
    } catch (e) {
      btn.textContent = "Erreur — réessayer"
      btn.removeAttribute("disabled")
      console.error("Update failed:", e)
    }
  }

  dismiss.onclick = () => { banner.style.display = "none" }
})

// ── DOM helpers ───────────────────────────────────────────────────────────────

function el<T extends HTMLElement>(id: string): T {
  return document.getElementById(id) as T
}

function set(id: string, val: string): void {
  const e = el(id)
  if (e) e.textContent = val
}

function severity(s: string): string {
  if (s === "CRITICAL") return "crit"
  if (s === "WARNING") return "warn"
  return "info"
}

// ── Tab navigation ────────────────────────────────────────────────────────────

function setupTabs(): void {
  const tabs = document.querySelectorAll<HTMLElement>(".tab-btn")
  const panels = document.querySelectorAll<HTMLElement>(".tab-panel")

  tabs.forEach(tab => {
    tab.addEventListener("click", () => {
      tabs.forEach(t => t.classList.remove("active"))
      panels.forEach(p => p.classList.remove("active"))
      tab.classList.add("active")
      const target = tab.dataset.tab!
      document.getElementById(`tab-${target}`)?.classList.add("active")
    })
  })
}

// ── Live stat updates ─────────────────────────────────────────────────────────

function updateOverview(msg: WSMessage): void {
  const { sensors, metrics } = msg
  const periphW  = totalPeriphWatts()
  const totalW   = metrics.wallWatts + periphW
  const tarif    = loadSavedTarif()
  const costH    = (totalW / 1000) * tarif
  const wallLabel = periphW > 0 ? `${totalW.toFixed(1)} W` : `${metrics.wallWatts.toFixed(1)} W`
  set("ov-wall", wallLabel)
  set("ov-cost-h",  `€${costH.toFixed(4)}`)
  set("ov-cost-day", `€${(costH * 24).toFixed(2)}`)
  set("ov-cost-h2",  `€${costH.toFixed(4)}/h`)
  if (sensors.cpuName) set("ov-cpu-name", sensors.cpuName)
  if (sensors.gpuName) set("ov-gpu-name", sensors.gpuName)
  set("ov-cpu", `${sensors.cpuPowerW.toFixed(1)} W`)
  set("ov-cpu-temp", `${sensors.cpuTempC.toFixed(0)}°C`)
  set("ov-gpu", `${sensors.gpuPowerW.toFixed(1)} W${sensors.gpuPowerEstimated ? " *" : ""}`)
  set("ov-gpu-temp", `${sensors.gpuTempC.toFixed(0)}°C`)
  set("ov-nvme-temp", `${sensors.nvmeTempC.toFixed(0)}°C`)
  set("ov-rail12",  sensors.rail12V  > 0.5 ? `${sensors.rail12V.toFixed(3)} V`  : "N/A")
  set("ov-rail5",   sensors.rail5V   > 0.5 ? `${sensors.rail5V.toFixed(3)} V`   : "N/A")
  set("ov-rail3v3", sensors.rail3v3  > 0.5 ? `${sensors.rail3v3.toFixed(3)} V`  : "N/A")
  // GPU extras
  set("ov-gpu-hotspot", sensors.gpuHotspotTempC > 0 ? `${sensors.gpuHotspotTempC.toFixed(0)}°C` : "N/A")
  set("ov-gpu-mem-temp", sensors.gpuMemTempC > 0 ? `${sensors.gpuMemTempC.toFixed(0)}°C` : "N/A")
  set("ov-gpu-fan", sensors.gpuFanRpm > 0 ? `${sensors.gpuFanRpm.toFixed(0)} RPM (${sensors.gpuFanPct.toFixed(0)}%)` : "N/A")
  // CPU fans (mobo headers)
  set("ov-fan1", sensors.fan1Rpm > 0 ? `${sensors.fan1Rpm.toFixed(0)} RPM` : "—")
  set("ov-fan2", sensors.fan2Rpm > 0 ? `${sensors.fan2Rpm.toFixed(0)} RPM` : "—")
  set("ov-fan5", sensors.fan5Rpm > 0 ? `${sensors.fan5Rpm.toFixed(0)} RPM` : "—")

  const topAnomaly = msg.anomalies[0]
  const statusEl = el("ov-status")
  if (topAnomaly) {
    statusEl.className = `status-badge ${severity(topAnomaly.severity)}`
    statusEl.textContent = `${topAnomaly.severity} — ${topAnomaly.component}`
  } else {
    statusEl.className = "status-badge ok"
    statusEl.textContent = "✓ OK"
  }

  set("last-update", new Date().toLocaleTimeString("fr-FR"))
}

function updateCpuStats(msg: WSMessage): void {
  const { sensors } = msg
  set("cpu-power-val", `${sensors.cpuPowerW.toFixed(1)} W`)
  set("cpu-temp-val", `${sensors.cpuTempC.toFixed(0)} °C`)
  set("cpu-clock-val", `${sensors.cpuClockMhz.toFixed(0)} MHz`)
}

function updateGpuStats(msg: WSMessage): void {
  const { sensors } = msg
  set("gpu-power-val", `${sensors.gpuPowerW.toFixed(1)} W${sensors.gpuPowerEstimated ? " *" : ""}`)
  set("gpu-temp-val", `${sensors.gpuTempC.toFixed(0)} °C`)
  set("gpu-hotspot-val", sensors.gpuHotspotTempC > 0 ? `${sensors.gpuHotspotTempC.toFixed(0)} °C` : "—")
  set("gpu-mem-temp-val", sensors.gpuMemTempC > 0 ? `${sensors.gpuMemTempC.toFixed(0)} °C` : "—")
  set("gpu-fan-val", sensors.gpuFanRpm > 0 ? `${sensors.gpuFanRpm.toFixed(0)} RPM` : "—")
  set("gpu-fan-pct-val", sensors.gpuFanPct > 0 ? `${sensors.gpuFanPct.toFixed(0)} %` : "—")
  set("gpu-clock-val", `${sensors.gpuClockMhz.toFixed(0)} MHz`)
  const warning = el("gpu-estimated-warn")
  if (warning) warning.style.display = sensors.gpuPowerEstimated ? "block" : "none"
}

function updateAnomalyTable(): void {
  const tbody = el<HTMLTableSectionElement>("anomaly-tbody")
  if (!tbody) return
  tbody.innerHTML = store.anomalyLog.slice(0, 100).map(a => `
    <tr>
      <td class="mono">${new Date(a.ts).toLocaleTimeString("fr-FR")}</td>
      <td><span class="badge ${severity(a.severity)}">${a.severity}</span></td>
      <td>${a.component}</td>
      <td>${a.message}</td>
      <td class="mono">${a.measuredValue.toFixed(2)}</td>
    </tr>
  `).join("")
}

// ── Chart instances ───────────────────────────────────────────────────────────

let cpuPowerChart: Chart, cpuTempChart: Chart, cpuClockChart: Chart
let gpuPowerChart: Chart, gpuTempChart: Chart, gpuClockChart: Chart
let rail12vChart: Chart, rail5vChart: Chart, rail3v3Chart: Chart
let energyBarChart: Chart, sevenDayChart: Chart
let ovPowerChart: Chart, ovTempChart: Chart

function initCharts(): void {
  cpuPowerChart = makeCpuPowerChart(el<HTMLCanvasElement>("chart-cpu-power"))
  cpuTempChart = makeCpuTempChart(el<HTMLCanvasElement>("chart-cpu-temp"))
  cpuClockChart = makeCpuClockChart(el<HTMLCanvasElement>("chart-cpu-clock"))
  gpuPowerChart = makeGpuPowerChart(el<HTMLCanvasElement>("chart-gpu-power"))
  gpuTempChart = makeGpuTempChart(el<HTMLCanvasElement>("chart-gpu-temp"))
  gpuClockChart = makeGpuClockChart(el<HTMLCanvasElement>("chart-gpu-clock"))
  rail12vChart = makeRailChart(el<HTMLCanvasElement>("chart-12v"), "12V Rail", "#f0e040", 11.0, 13.0, 11.4, 12.6)
  rail5vChart = makeRailChart(el<HTMLCanvasElement>("chart-5v"), "5V Rail", "#3fb950", 4.5, 5.5, 4.75, 5.25)
  rail3v3Chart = makeRailChart(el<HTMLCanvasElement>("chart-3v3"), "3.3V Rail", "#58a6ff", 2.8, 3.8, 3.14, 3.47)
  energyBarChart = makeEnergyBarChart(el<HTMLCanvasElement>("chart-energy-24h"))
  sevenDayChart = make7dChart(el<HTMLCanvasElement>("chart-7d"))
  ovPowerChart = makeOverviewPowerChart(el<HTMLCanvasElement>("chart-ov-power"))
  ovTempChart  = makeOverviewTempChart(el<HTMLCanvasElement>("chart-ov-temp"))
}

// Reduce to max N points for rendering (keeps performance + avoids overflow)
function downsample(buf: typeof store.buffer, maxPts = 600) {
  if (buf.length <= maxPts) return buf
  const step = Math.ceil(buf.length / maxPts)
  return buf.filter((_, i) => i % step === 0)
}

function updateCharts(): void {
  const buf = store.buffer
  if (buf.length === 0) return
  const s = downsample(buf)
  updateLineChart(cpuPowerChart, s, "cpuPowerW")
  updateLineChart(cpuTempChart, s, "cpuTempC")
  updateLineChart(cpuClockChart, s, "cpuClockMhz")
  updateLineChart(gpuPowerChart, s, "gpuPowerW")
  updateLineChart(gpuTempChart, s, "gpuTempC")
  updateLineChart(gpuClockChart, s, "gpuClockMhz")
  updateRailChart(rail12vChart, s, "rail12V", 11.4, 12.6)
  updateRailChart(rail5vChart, s, "rail5V", 4.75, 5.25)
  updateRailChart(rail3v3Chart, s, "rail3v3", 3.14, 3.47)
  updateLineChart(ovPowerChart, s, "wallWatts")
  updateOverviewTempChart(ovTempChart, s)
}

// ── 3-day cost table ─────────────────────────────────────────────────────────

function periphCostForHours(periphWatts: number, tarif: number, hours: number): number {
  return (periphWatts / 1000) * tarif * hours
}

function updateCost3dTable(days: { date: string; costPc: number; costPeriph: number }[], today: { costPc: number; costPeriph: number }): void {
  const tbody = el<HTMLTableSectionElement>("cost-3d-tbody")
  if (!tbody) return

  const tarif      = loadSavedTarif()
  const now        = new Date()
  const todayLabel = now.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" })

  const rows: { date: string; costPc: number; costPeriph: number; isToday: boolean }[] = [
    { date: todayLabel, costPc: today.costPc, costPeriph: today.costPeriph, isToday: true },
    ...days
      .filter(d => d.date !== todayLabel)
      .map(d => ({ date: d.date, costPc: d.costPc, costPeriph: d.costPeriph, isToday: false })),
  ]

  tbody.innerHTML = rows.map(r => {
    const costTotal = r.costPc + r.costPeriph
    const kwh = tarif > 0 ? (r.costPc / tarif).toFixed(3) : "—"
    const cls = r.isToday ? " class=\"today-row\"" : ""
    const dayLabel = r.isToday ? `${r.date} <span style="opacity:.5;font-size:11px;">(en cours)</span>` : r.date
    return `<tr${cls}><td>${dayLabel}</td><td>€${r.costPc.toFixed(3)}</td><td>€${costTotal.toFixed(3)}</td><td>${kwh} kWh</td></tr>`
  }).join("") || `<tr><td colspan="4" class="c-muted" style="text-align:center;padding:10px;">Pas encore de données</td></tr>`
}

function updateCost31dTable(days: { date: string; costPc: number; costPeriph: number; kwh: number }[], today: { costPc: number; costPeriph: number }): void {
  const tbody = el<HTMLTableSectionElement>("cost-31d-tbody")
  if (!tbody) return

  const tarif      = loadSavedTarif()
  const now        = new Date()
  const midnight   = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const hoursToday = (now.getTime() - midnight.getTime()) / 3_600_000
  const todayLabel = now.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric", month: "short" })

  const todayKwh = tarif > 0 ? today.costPc / tarif : 0
  const rows: { date: string; costPc: number; costPeriph: number; kwh: number; isToday: boolean }[] = [
    { date: todayLabel, costPc: today.costPc, costPeriph: today.costPeriph, kwh: todayKwh, isToday: true },
    ...days
      .filter(d => d.date !== todayLabel)
      .map(d => ({ date: d.date, costPc: d.costPc, costPeriph: d.costPeriph, kwh: d.kwh, isToday: false })),
  ]

  const totalPc     = rows.reduce((s, r) => s + r.costPc, 0)
  const totalPeriph = rows.reduce((s, r) => s + r.costPeriph, 0)
  const avgPc = rows.length > 0 ? totalPc / rows.length : 0

  const summaryEl = el("cost-31d-summary")
  if (summaryEl) {
    summaryEl.textContent = `${rows.length} j · PC €${totalPc.toFixed(2)} · total €${(totalPc + totalPeriph).toFixed(2)} · moy €${avgPc.toFixed(3)}/j`
  }

  tbody.innerHTML = rows.map(r => {
    const costTotal = r.costPc + r.costPeriph
    const cls = r.isToday ? " class=\"today-row\"" : ""
    const dayLabel = r.isToday ? `${r.date} <span style="opacity:.5;font-size:11px;">(en cours)</span>` : r.date
    const hours = r.isToday ? hoursToday : 24
    const avgW = r.kwh > 0 && hours > 0 ? (r.kwh * 1000 / hours).toFixed(0) : "—"
    return `<tr${cls}><td>${dayLabel}</td><td>€${r.costPc.toFixed(3)}</td><td>€${costTotal.toFixed(3)}</td><td>${r.kwh.toFixed(3)} kWh</td><td style="color:var(--muted)">${avgW} W moy</td></tr>`
  }).join("") || `<tr><td colspan="5" class="c-muted" style="text-align:center;padding:10px;">Pas encore de données</td></tr>`
}

// ── Historical data refresh (every 60s) ──────────────────────────────────────

async function refreshHistorical(): Promise<void> {
  try {
    const [today, monthlyProj, hourly, daily, days3, days31] = await Promise.all([
      getTodayCost(),
      getMonthlyProjection(),
      get24hHourly(),
      get7dDaily(),
      getLast3DaysCost(),
      getLast31DaysCost(),
    ])
    const noInflux = el("energy-no-influx")
    if (noInflux) noInflux.style.display = "none"
    set("ov-cost-today", `€${today.costPc.toFixed(3)}`)
    set("energy-cost-today", `€${today.costPc.toFixed(3)}`)
    set("energy-proj-month", `~€${monthlyProj.toFixed(2)}`)
    updateEnergyBarChart(energyBarChart, hourly)
    update7dChart(sevenDayChart, daily)
    updateCost3dTable(days3, today)
    updateCost31dTable(days31, today)
  } catch (err) {
    console.warn("[InfluxDB] historical refresh failed:", err)
    const noInflux = el("energy-no-influx")
    if (noInflux) noInflux.style.display = "block"
  }

  try {
    const history = await getAnomalyHistory()
    const tbody = el<HTMLTableSectionElement>("anomaly-history-tbody")
    if (tbody) {
      tbody.innerHTML = history.map(a => `
        <tr>
          <td class="mono">${a.ts.toLocaleString("fr-FR")}</td>
          <td><span class="badge ${severity(a.severity)}">${a.severity}</span></td>
          <td>${a.type}</td>
        </tr>
      `).join("")
    }
  } catch { /* ignore */ }
}

// ── Settings — tarif, périphériques & moniteurs ──────────────────────────────

const TARIF_KEY    = "pc-monitor-tarif-kwh"
const DEVICES_KEY  = "pc-monitor-devices"
const MONITORS_KEY = "pc-monitor-monitors"  // { [id]: watts }
const HW_KEY       = "pc-monitor-hw-limits"
const DEFAULT_TARIF = 0.2516

interface HWLimits {
  cpuTdpW: number
  gpuTdpW: number
  cpuThrottleTempC: number
  gpuTempCriticalC: number
  nvmeTempCriticalC: number
}
const DEFAULT_HW: HWLimits = {
  cpuTdpW: 120, gpuTdpW: 220,
  cpuThrottleTempC: 85, gpuTempCriticalC: 100, nvmeTempCriticalC: 70,
}
function loadHWLimits(): HWLimits {
  try { return { ...DEFAULT_HW, ...JSON.parse(localStorage.getItem(HW_KEY) ?? "{}") } }
  catch { return { ...DEFAULT_HW } }
}
function buildCollectorConfig(): CollectorConfig {
  const hw = loadHWLimits()
  return { tarifKwh: loadSavedTarif(), periphWatts: totalPeriphWatts(), ...hw }
}

interface PeriphDevice { id: string; name: string; watts: number }

function loadSavedTarif(): number {
  return parseFloat(localStorage.getItem(TARIF_KEY) ?? String(DEFAULT_TARIF)) || DEFAULT_TARIF
}

function loadDevices(): PeriphDevice[] {
  try { return JSON.parse(localStorage.getItem(DEVICES_KEY) ?? "[]") } catch { return [] }
}

function loadMonitorWatts(): Record<string, number> {
  try { return JSON.parse(localStorage.getItem(MONITORS_KEY) ?? "{}") } catch { return {} }
}

function saveMonitorWatts(map: Record<string, number>): void {
  localStorage.setItem(MONITORS_KEY, JSON.stringify(map))
}

// Live: only currently active monitors (for today's cost and overview)
function totalPeriphWatts(): number {
  const devices  = loadDevices().reduce((s, d) => s + (d.watts || 0), 0)
  const monitorWatts = loadMonitorWatts()
  const activeMonitorW = (store.latest?.monitors ?? [])
    .filter(m => m.active)
    .reduce((s, m) => s + (monitorWatts[m.id] || 0), 0)
  return devices + activeMonitorW
}


// ── Device list renderer ──────────────────────────────────────────────────────

let draftDevices: PeriphDevice[] = []

function renderDeviceList(): void {
  const list = el("devices-list")
  const totalEl = el("devices-total")
  if (!list) return

  list.innerHTML = draftDevices.map((d, i) => `
    <div class="device-row" data-idx="${i}">
      <input class="device-name" type="text"   value="${d.name.replace(/"/g, '&quot;')}" placeholder="Nom" data-field="name" data-idx="${i}" />
      <input class="device-watts" type="number" value="${d.watts}" min="0" max="2000" placeholder="0" data-field="watts" data-idx="${i}" />
      <span class="device-unit">W</span>
      <button class="device-remove" data-idx="${i}" title="Supprimer">×</button>
    </div>
  `).join("")

  list.querySelectorAll<HTMLInputElement>(".device-name, .device-watts").forEach(inp => {
    inp.addEventListener("input", () => {
      const idx = parseInt(inp.dataset.idx!)
      if (inp.dataset.field === "name")  draftDevices[idx].name  = inp.value
      if (inp.dataset.field === "watts") draftDevices[idx].watts = parseFloat(inp.value) || 0
      updateDeviceTotal()
      refreshPreview()
    })
  })

  list.querySelectorAll<HTMLButtonElement>(".device-remove").forEach(btn => {
    btn.addEventListener("click", () => {
      draftDevices.splice(parseInt(btn.dataset.idx!), 1)
      renderDeviceList()
      refreshPreview()
    })
  })

  updateDeviceTotal()
}

function updateDeviceTotal(): void {
  const total = draftDevices.reduce((s, d) => s + (d.watts || 0), 0)
  const t = el("devices-total")
  if (t) t.textContent = `Total périphériques : ${total} W`
}

// ── Monitor wattage config ────────────────────────────────────────────────────

function renderMonitorList(): void {
  const container = el("monitors-list")
  if (!container) return

  const monitors = store.latest?.monitors ?? []
  const watts    = loadMonitorWatts()

  if (monitors.length === 0) {
    container.innerHTML = `<div class="monitor-empty">Aucun écran détecté (poll toutes les 5 min)</div>`
    return
  }

  container.innerHTML = monitors.map(m => {
    const w = watts[m.id] ?? 0
    const badge = m.active
      ? `<span class="monitor-badge active">● actif</span>`
      : `<span class="monitor-badge off">○ inactif</span>`
    return `
      <div class="device-row" data-monitor-id="${m.id}">
        <div style="flex:1;min-width:0">
          <div style="font-size:12px;color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${m.name}</div>
          <div style="font-size:10px;color:var(--muted);margin-top:2px">${m.id.split("\\").pop() ?? m.id}</div>
        </div>
        ${badge}
        <input class="device-watts monitor-watts" type="number" value="${w || ""}" min="0" max="1000"
          placeholder="W" data-monitor-id="${m.id}" style="width:64px" />
        <span class="device-unit">W</span>
      </div>`
  }).join("")

  container.querySelectorAll<HTMLInputElement>(".monitor-watts").forEach(inp => {
    inp.addEventListener("input", () => {
      const id  = inp.dataset.monitorId!
      const map = loadMonitorWatts()
      const v   = parseFloat(inp.value) || 0
      if (v > 0) map[id] = v
      else delete map[id]
      saveMonitorWatts(map)
      refreshPreview()
    })
  })
}

// ── Settings modal ────────────────────────────────────────────────────────────

function refreshPreview(): void {
  const preview = el("settings-preview")
  if (!preview) return
  const tarif  = parseFloat(el<HTMLInputElement>("input-tarif")?.value ?? "") || loadSavedTarif()
  const pcW    = store.latest?.metrics.wallWatts ?? 0
  const periphW = draftDevices.reduce((s, d) => s + (d.watts || 0), 0)
  const totalW = pcW + periphW
  if (pcW === 0) { preview.textContent = `Tarif : €${tarif.toFixed(4)}/kWh — en attente de données`; return }
  const costH   = (totalW / 1000) * tarif
  const costDay = costH * 24
  preview.textContent = `PC ${pcW.toFixed(0)} W + périph ${periphW} W = ${totalW.toFixed(0)} W → €${costH.toFixed(4)}/h · €${costDay.toFixed(2)}/j`
}

function setupSettings(): void {
  const backdrop = el("modal-backdrop")
  const input    = el<HTMLInputElement>("input-tarif")

  function open(): void {
    draftDevices = loadDevices().map(d => ({ ...d }))
    input.value  = String(loadSavedTarif())
    const hw = loadHWLimits()
    const setVal = (id: string, v: number) => { const e = el<HTMLInputElement>(id); if (e) e.value = String(v) }
    setVal("input-cpu-tdp",   hw.cpuTdpW)
    setVal("input-gpu-tdp",   hw.gpuTdpW)
    setVal("input-cpu-temp",  hw.cpuThrottleTempC)
    setVal("input-gpu-temp",  hw.gpuTempCriticalC)
    setVal("input-nvme-temp", hw.nvmeTempCriticalC)
    renderDeviceList()
    renderMonitorList()
    refreshPreview()
    backdrop.classList.add("open")
  }

  function close(): void {
    backdrop.classList.remove("open")
  }

  el("btn-settings")?.addEventListener("click", open)
  el("modal-close")?.addEventListener("click", close)
  el("modal-cancel")?.addEventListener("click", close)
  backdrop.addEventListener("click", (e) => { if (e.target === backdrop) close() })

  input.addEventListener("input", refreshPreview)

  el("btn-add-device")?.addEventListener("click", () => {
    draftDevices.push({ id: String(Date.now()), name: "", watts: 0 })
    renderDeviceList()
    refreshPreview()
    // focus le dernier champ nom ajouté
    const inputs = el("devices-list").querySelectorAll<HTMLInputElement>(".device-name")
    inputs[inputs.length - 1]?.focus()
  })

  el("modal-save")?.addEventListener("click", () => {
    const v = parseFloat(input.value)
    if (isNaN(v) || v <= 0) { input.style.borderColor = "var(--red)"; return }
    input.style.borderColor = ""
    localStorage.setItem(TARIF_KEY, String(v))
    localStorage.setItem(DEVICES_KEY, JSON.stringify(draftDevices.filter(d => d.watts > 0 || d.name)))
    // Save hardware limits
    const hw: HWLimits = {
      cpuTdpW:           parseFloat((el<HTMLInputElement>("input-cpu-tdp"))?.value)     || DEFAULT_HW.cpuTdpW,
      gpuTdpW:           parseFloat((el<HTMLInputElement>("input-gpu-tdp"))?.value)     || DEFAULT_HW.gpuTdpW,
      cpuThrottleTempC:  parseFloat((el<HTMLInputElement>("input-cpu-temp"))?.value)    || DEFAULT_HW.cpuThrottleTempC,
      gpuTempCriticalC:  parseFloat((el<HTMLInputElement>("input-gpu-temp"))?.value)    || DEFAULT_HW.gpuTempCriticalC,
      nvmeTempCriticalC: parseFloat((el<HTMLInputElement>("input-nvme-temp"))?.value)   || DEFAULT_HW.nvmeTempCriticalC,
    }
    localStorage.setItem(HW_KEY, JSON.stringify(hw))
    sendConfig(buildCollectorConfig())
    close()
  })
}

// ── Window controls (Tauri) ───────────────────────────────────────────────────

function setupWindowControls(): void {
  el("btn-min")?.addEventListener("click",   () => invoke("minimize_win"))
  el("btn-max")?.addEventListener("click",   () => invoke("maximize_win"))
  el("btn-close")?.addEventListener("click", () => invoke("hide_win"))
}

// ── Setup Wizard ──────────────────────────────────────────────────────────────

async function runSetupWizard(): Promise<void> {
  const wizard = el("setup-wizard")
  if (!wizard) return
  wizard.style.display = "flex"

  const step2 = el("setup-step-2")
  const step3 = el("setup-step-3")

  const btnNext2 = el("btn-setup-next-2")
  const btnFinish = el("btn-setup-finish")

  const inputTarif = el<HTMLInputElement>("setup-tarif")

  const progressIcon = el("setup-progress-icon")
  const progressTitle = el("setup-progress-title")
  const progressSubtitle = el("setup-progress-subtitle")
  const progressBar = el("setup-progress-bar")
  const logsContainer = el("setup-logs")

  // Mot de passe fixe — les donnees ne sont pas sensibles, pas besoin de le demander
  const dbPass = "monitor4me-local"
  let tarif = 0.2516

  btnNext2?.addEventListener("click", async () => {
    tarif = parseFloat(inputTarif?.value || "0.2516") || 0.2516
    if (step2) step2.style.display = "none"
    if (step3) step3.style.display = "flex"

    const unlisten = await listen<string>("setup-log", (event) => {
      const line = event.payload
      const div = document.createElement("div")

      if (line.startsWith("STEP: ")) {
        const stepName = line.substring(6)
        if (progressTitle) progressTitle.textContent = stepName
        if (progressSubtitle) progressSubtitle.textContent = "Configuration en cours..."
        
        if (progressBar) {
          const currentWidth = parseFloat(progressBar.style.width) || 0
          progressBar.style.width = Math.min(95, currentWidth + 12) + "%"
        }
        div.style.fontWeight = "bold"
        div.style.color = "var(--accent)"
        div.textContent = `➜ ${stepName}`
      } else if (line.startsWith("OK: ")) {
        div.className = "ok"
        div.textContent = `✓ ${line.substring(4)}`
      } else if (line.startsWith("ERR: ")) {
        div.className = "err"
        div.textContent = `✗ ${line.substring(5)}`
        if (progressIcon) {
          progressIcon.className = "setup-icon"
          progressIcon.textContent = "❌"
        }
        if (progressTitle) progressTitle.textContent = "Échec de l'installation"
        if (progressSubtitle) progressSubtitle.textContent = "Vérifiez les logs ci-dessous."
      } else if (line.startsWith("WARN: ")) {
        div.style.color = "var(--orange)"
        div.textContent = `⚠ ${line.substring(6)}`
      } else {
        div.textContent = line
      }

      if (logsContainer) {
        logsContainer.appendChild(div)
        logsContainer.scrollTop = logsContainer.scrollHeight
      }

      if (line.includes("INSTALLATION_SUCCESS")) {
        if (progressBar) progressBar.style.width = "100%"
        if (progressIcon) {
          progressIcon.className = "setup-icon"
          progressIcon.textContent = "🎉"
        }
        if (progressTitle) progressTitle.textContent = "Installation terminée avec succès !"
        if (progressSubtitle) progressSubtitle.textContent = "monitor4me est prêt à fonctionner."
        if (btnFinish) btnFinish.style.display = "block"
      }
    })

    try {
      await invoke("run_silent_install", { adminPass: dbPass, tarifKwh: tarif })
    } catch (err) {
      const div = document.createElement("div")
      div.className = "err"
      div.textContent = `Erreur critique : ${err}`
      if (logsContainer) {
        logsContainer.appendChild(div)
        logsContainer.scrollTop = logsContainer.scrollHeight
      }
      if (progressIcon) {
        progressIcon.className = "setup-icon"
        progressIcon.textContent = "❌"
      }
      if (progressTitle) progressTitle.textContent = "Échec de l'installation"
      if (progressSubtitle) progressSubtitle.textContent = "Une erreur système est survenue."
    }
  })

  btnFinish?.addEventListener("click", () => {
    localStorage.setItem(TARIF_KEY, String(tarif))
    localStorage.setItem("pc-monitor-setup-completed", "true")
    if (wizard) wizard.style.display = "none"
    window.location.reload()
  })
}

// ── Boot ──────────────────────────────────────────────────────────────────────

async function boot(): Promise<void> {
  const token = await invoke<string>("get_influx_token").catch(() => "")
  
  // Si un token d'accès existe déjà dans l'environnement (installation existante),
  // on valide automatiquement l'étape de configuration pour ne pas déranger l'utilisateur.
  if (token && token.trim() !== "") {
    localStorage.setItem("pc-monitor-setup-completed", "true")
  }

  const setupCompleted = localStorage.getItem("pc-monitor-setup-completed") === "true"

  if (!token || !setupCompleted) {
    setupWindowControls()
    await runSetupWizard()
    return
  }

  setupTabs()
  initCharts()
  setupSettings()
  setupWindowControls()
  sendConfig(buildCollectorConfig())
  startWS()

  let lastPeriphW = -1
  let hostSynced  = false
  onMessage((msg) => {
    updateOverview(msg)
    updateCpuStats(msg)
    updateGpuStats(msg)
    updateCharts()
    updateAnomalyTable()
    // Sync InfluxDB host tag from collector on first message
    if (!hostSynced && msg.config?.host) {
      hostSynced = true
      setInfluxHost(msg.config.host)
      refreshHistorical()
    }
    // Re-sync periphWatts whenever the active monitor set changes
    const pw = totalPeriphWatts()
    if (pw !== lastPeriphW) {
      lastPeriphW = pw
      sendConfig({ ...buildCollectorConfig(), periphWatts: pw })
    }
  })

  // Historical data: immediately + every 60s
  refreshHistorical()
  setInterval(refreshHistorical, 60_000)
}

boot()
