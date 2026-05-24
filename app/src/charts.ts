import {
  Chart, LineController, BarController, LineElement, BarElement,
  PointElement, LinearScale, TimeScale, CategoryScale,
  Filler, Legend, Tooltip,
} from "chart.js"
import "chartjs-adapter-date-fns"
import type { DataPoint } from "./types"
import type { HourlyKWh } from "./influx"

Chart.register(
  LineController, BarController, LineElement, BarElement,
  PointElement, LinearScale, TimeScale, CategoryScale,
  Filler, Legend, Tooltip,
)

const FONT_COLOR = "#4b5666"
const GRID_COLOR = "rgba(28,37,48,0.9)"

// Console palette
const C_CPU = "#e6b35a"   // amber
const C_GPU = "#e96f6f"   // coral
const C_PWR = "#9cc6ed"   // light blue
const C_CLK = "#7d8a98"   // dim (clock is neutral)
const C_OK  = "#5ec588"   // green

const BASE_OPTS = {
  animation: false as const,
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: "index" as const, intersect: false },
  plugins: {
    legend: { labels: { color: FONT_COLOR, boxWidth: 10, font: { size: 10.5, family: "'IBM Plex Mono', monospace" } } },
    tooltip: { backgroundColor: "#0e1520", titleColor: "#dfe6ee", bodyColor: FONT_COLOR, borderColor: "#1c2530", borderWidth: 1 },
  },
  scales: {
    x: {
      type: "time" as const,
      ticks: { color: FONT_COLOR, maxTicksLimit: 6, font: { size: 10 } },
      grid: { color: GRID_COLOR },
    },
    y: {
      ticks: { color: FONT_COLOR, font: { size: 10 } },
      grid: { color: GRID_COLOR },
    },
  },
}

function timeLabels(buf: DataPoint[]): Date[] {
  return buf.map(p => new Date(p.ts))
}

// ── CPU charts ───────────────────────────────────────────────────────────────

export function makeCpuPowerChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "CPU Power (W)", data: [], borderColor: C_CPU, backgroundColor: C_CPU + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 0, suggestedMax: 160, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}W` } } } },
  })
}

export function makeCpuTempChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "CPU Temp (°C)", data: [], borderColor: C_CPU, backgroundColor: C_CPU + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 20, suggestedMax: 100, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}°C` } } } },
  })
}

export function makeCpuClockChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "CPU Clock (MHz)", data: [], borderColor: C_CLK, backgroundColor: C_CLK + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 0, suggestedMax: 5500, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}` } } } },
  })
}

// ── GPU charts ───────────────────────────────────────────────────────────────

export function makeGpuPowerChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "GPU Power (W)", data: [], borderColor: C_GPU, backgroundColor: C_GPU + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 0, suggestedMax: 320, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}W` } } } },
  })
}

export function makeGpuTempChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "GPU Temp (°C)", data: [], borderColor: C_GPU, backgroundColor: C_GPU + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 20, suggestedMax: 110, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}°C` } } } },
  })
}

export function makeGpuClockChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "GPU Clock (MHz)", data: [], borderColor: C_CLK, backgroundColor: C_CLK + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 0, suggestedMax: 3000 } } },
  })
}

// ── Rails charts ─────────────────────────────────────────────────────────────

export function makeRailChart(canvas: HTMLCanvasElement, label: string, color: string, yMin: number, yMax: number, atxMin: number, atxMax: number): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label, data: [], borderColor: color, backgroundColor: color + "12", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.2 },
        { label: `ATX min (${atxMin}V)`, data: [], borderColor: "rgba(233,111,111,0.45)", pointRadius: 0, borderWidth: 1, borderDash: [4, 4], fill: false },
        { label: `ATX max (${atxMax}V)`, data: [], borderColor: "rgba(233,111,111,0.45)", pointRadius: 0, borderWidth: 1, borderDash: [4, 4], fill: false },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: yMin, max: yMax, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}V` } } } },
  })
}

// ── Overview charts ───────────────────────────────────────────────────────────

export function makeOverviewPowerChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "Wall Power (W)", data: [], borderColor: C_PWR, backgroundColor: C_PWR + "14", fill: true, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 0, suggestedMax: 600, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}W` } } } },
  })
}

export function makeOverviewTempChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "line",
    data: {
      labels: [],
      datasets: [
        { label: "CPU", data: [], borderColor: C_CPU, backgroundColor: "transparent", fill: false, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
        { label: "GPU", data: [], borderColor: C_GPU, backgroundColor: "transparent", fill: false, pointRadius: 0, borderWidth: 1.5, tension: 0.3 },
      ],
    },
    options: { ...BASE_OPTS, scales: { ...BASE_OPTS.scales, y: { ...BASE_OPTS.scales.y, min: 20, suggestedMax: 100, ticks: { ...BASE_OPTS.scales.y.ticks, callback: (v) => `${v}°C` } } } },
  })
}

export function updateOverviewTempChart(chart: Chart, buf: DataPoint[]): void {
  chart.data.labels = timeLabels(buf)
  chart.data.datasets[0].data = buf.map(p => p.cpuTempC)
  chart.data.datasets[1].data = buf.map(p => p.gpuTempC)
  chart.update("none")
}

// ── Energy charts ─────────────────────────────────────────────────────────────

export function makeEnergyBarChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "bar",
    data: {
      labels: [],
      datasets: [
        { label: "CPU (kWh)", data: [], backgroundColor: C_CPU + "cc", stack: "energy" },
        { label: "GPU (kWh)", data: [], backgroundColor: C_GPU + "cc", stack: "energy" },
        { label: "Reste (kWh)", data: [], backgroundColor: "#4b5666aa", stack: "energy" },
      ],
    },
    options: {
      ...BASE_OPTS,
      datasets: { bar: { maxBarThickness: 40 } },
      scales: {
        x: { stacked: true, type: "category" as const, ticks: { color: FONT_COLOR, font: { size: 10 } }, grid: { color: GRID_COLOR } },
        y: { stacked: true, ticks: { color: FONT_COLOR, font: { size: 10 }, callback: (v) => `${v}kWh` }, grid: { color: GRID_COLOR } },
      },
    },
  })
}

export function make7dChart(canvas: HTMLCanvasElement): Chart {
  return new Chart(canvas, {
    type: "bar",
    data: {
      labels: [],
      datasets: [
        { label: "kWh / jour", data: [], backgroundColor: C_OK + "b3", borderColor: C_OK, borderWidth: 1 },
      ],
    },
    options: {
      ...BASE_OPTS,
      datasets: { bar: { maxBarThickness: 60 } },
      scales: {
        x: { type: "category" as const, ticks: { color: FONT_COLOR, font: { size: 10 } }, grid: { color: GRID_COLOR } },
        y: { ticks: { color: FONT_COLOR, font: { size: 10 }, callback: (v) => `${v}kWh` }, grid: { color: GRID_COLOR } },
      },
    },
  })
}

// ── Update helpers ────────────────────────────────────────────────────────────

export function updateLineChart(chart: Chart, buf: DataPoint[], field: keyof DataPoint): void {
  chart.data.labels = timeLabels(buf)
  chart.data.datasets[0].data = buf.map(p => p[field] as number)
  chart.update("none")
}

export function updateRailChart(chart: Chart, buf: DataPoint[], field: keyof DataPoint, atxMin: number, atxMax: number): void {
  const labels = timeLabels(buf)
  chart.data.labels = labels
  chart.data.datasets[0].data = buf.map(p => p[field] as number)
  chart.data.datasets[1].data = buf.map(() => atxMin)
  chart.data.datasets[2].data = buf.map(() => atxMax)
  chart.update("none")
}

export function updateEnergyBarChart(chart: Chart, data: HourlyKWh[]): void {
  chart.data.labels = data.map(d => d.time.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" }))
  chart.data.datasets[0].data = data.map(d => +d.cpuKwh.toFixed(4))
  chart.data.datasets[1].data = data.map(d => +d.gpuKwh.toFixed(4))
  chart.data.datasets[2].data = data.map(d => +d.otherKwh.toFixed(4))
  chart.update("none")
}

export function update7dChart(chart: Chart, data: { time: Date; kwh: number }[]): void {
  chart.data.labels = data.map(d => d.time.toLocaleDateString("fr-FR", { weekday: "short", day: "numeric" }))
  chart.data.datasets[0].data = data.map(d => +d.kwh.toFixed(3))
  chart.update("none")
}
