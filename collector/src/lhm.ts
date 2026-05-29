import { CONFIG } from "./config"

export interface LHMSensors {
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

interface LHMNode {
  Text: string
  Value?: string
  Min?: string
  Max?: string
  Children?: LHMNode[]
  ImageURL?: string
  id?: number
  Type?: string
  SensorType?: string
}

// Recursively find all sensor nodes matching predicate
function findSensors(node: LHMNode, predicate: (n: LHMNode) => boolean): LHMNode[] {
  const results: LHMNode[] = []
  if (predicate(node)) results.push(node)
  for (const child of node.Children ?? []) {
    results.push(...findSensors(child, predicate))
  }
  return results
}

function parseValue(raw: string | undefined): number {
  if (!raw) return 0
  const num = parseFloat(raw.replace(",", ".").replace(/[^\d.-]/g, ""))
  return isNaN(num) ? 0 : num
}

function findFirst(root: LHMNode, textIncludes: string, sensorType?: string): LHMNode | undefined {
  const lower = textIncludes.toLowerCase()
  return findSensors(root, (n) => {
    const textMatch = n.Text.toLowerCase().includes(lower)
    const typeMatch = sensorType ? n.Type?.toLowerCase() === sensorType.toLowerCase() : true
    return textMatch && typeMatch && n.Value !== undefined
  })[0]
}

export async function fetchLHMSensors(): Promise<LHMSensors> {
  const response = await fetch(CONFIG.LHM_URL, { signal: AbortSignal.timeout(3000) })
  if (!response.ok) throw new Error(`LHM HTTP ${response.status}`)
  const root = await response.json() as LHMNode

  // CPU — exact match on "Package" to avoid matching "GPU Package"
  const cpuPowerNode = findSensors(root, n =>
    n.Text.toLowerCase() === "package" &&
    n.Type?.toLowerCase() === "power" &&
    n.Value !== undefined
  )[0]
  const cpuTempNode = findFirst(root, "core (tctl/tdie)", "temperature")
  const cpuClockNode = findFirst(root, "cores (average effective)", "clock")
    ?? findFirst(root, "cores (average)", "clock")

  // GPU (RX 9070 XT — supported via "GPU Package")
  const gpuPowerNode    = findFirst(root, "gpu package", "power")
  const gpuTempNode     = findFirst(root, "gpu core", "temperature")
  const gpuHotspotNode  = findFirst(root, "gpu hot spot", "temperature")
  const gpuMemTempNode  = findFirst(root, "gpu memory", "temperature")
  const gpuFanRpmNode   = findFirst(root, "gpu fan", "fan")
  const gpuFanPctNode   = findFirst(root, "gpu fan", "control")
  const gpuClockNode    = findFirst(root, "gpu core", "clock")

  // NVMe — no power sensor on this board, temp via composite
  const nvmePowerNode = undefined
  const nvmeTempNode = findFirst(root, "composite temperature", "temperature")

  // Voltage rails — B650E does not expose ATX rails (12V/5V/3.3V) via LHM ITE chip
  const rail12vNode = undefined
  const rail5vNode  = undefined
  const rail3v3Node = undefined

  // Mobo fan headers (ITE IT8689E) — Fan #1/2/5 active on this build
  const fan1Node = findSensors(root, n => n.Text === "Fan #1" && n.Type?.toLowerCase() === "fan" && n.Value !== undefined)[0]
  const fan2Node = findSensors(root, n => n.Text === "Fan #2" && n.Type?.toLowerCase() === "fan" && n.Value !== undefined)[0]
  const fan5Node = findSensors(root, n => n.Text === "Fan #5" && n.Type?.toLowerCase() === "fan" && n.Value !== undefined)[0]

  const cpuRaw = parseValue(cpuPowerNode?.Value)
  const gpuPowerW = parseValue(gpuPowerNode?.Value)

  return {
    cpuPowerW: cpuRaw * CONFIG.CPU_RAPL_CORRECTION,
    cpuTempC: parseValue(cpuTempNode?.Value),
    cpuClockMhz: parseValue(cpuClockNode?.Value),
    gpuPowerW,
    gpuTempC: parseValue(gpuTempNode?.Value),
    gpuHotspotTempC: parseValue(gpuHotspotNode?.Value),
    gpuMemTempC: parseValue(gpuMemTempNode?.Value),
    gpuFanRpm: parseValue(gpuFanRpmNode?.Value),
    gpuFanPct: parseValue(gpuFanPctNode?.Value),
    gpuClockMhz: parseValue(gpuClockNode?.Value),
    nvmePowerW: null,
    nvmeTempC: parseValue(nvmeTempNode?.Value),
    rail12V: 0,
    rail5V: 0,
    rail3v3: 0,
    fan1Rpm: parseValue(fan1Node?.Value),
    fan2Rpm: parseValue(fan2Node?.Value),
    fan5Rpm: parseValue(fan5Node?.Value),
    gpuPowerEstimated: false,
  }
}
