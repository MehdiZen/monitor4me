import { InfluxDB, Point, WriteApi } from "@influxdata/influxdb-client"
import { CONFIG } from "./config"
import { LHMSensors } from "./lhm"
import { ComputedMetrics } from "./metrics"
import { Anomaly } from "./anomaly"
import { runtimeConfig } from "./runtime-config"

let writeApi: WriteApi | null = null

function getWriteApi(): WriteApi {
  if (!writeApi) {
    const client = new InfluxDB({ url: CONFIG.INFLUX_URL, token: CONFIG.INFLUX_TOKEN })
    writeApi = client.getWriteApi(CONFIG.INFLUX_ORG, CONFIG.INFLUX_BUCKET, "ms")
    writeApi.useDefaultTags({ host: CONFIG.INFLUX_HOST_TAG })
  }
  return writeApi
}

export async function writeMetrics(
  sensors: LHMSensors,
  metrics: ComputedMetrics,
  anomalies: Anomaly[],
): Promise<void> {
  const api = getWriteApi()

  const topAnomaly = anomalies[0]

  const point = new Point("hardware")
    .floatField("cpu_power_w", sensors.cpuPowerW)
    .floatField("cpu_temp_c", sensors.cpuTempC)
    .floatField("cpu_clock_mhz", sensors.cpuClockMhz)
    .floatField("gpu_power_w", sensors.gpuPowerW)
    .floatField("gpu_temp_c", sensors.gpuTempC)
    .floatField("gpu_clock_mhz", sensors.gpuClockMhz)
    .floatField("nvme_power_w", sensors.nvmePowerW ?? metrics.nvmePowerW)
    .floatField("nvme_temp_c", sensors.nvmeTempC)
    .floatField("rail_12v", sensors.rail12V)
    .floatField("rail_5v", sensors.rail5V)
    .floatField("rail_3v3", sensors.rail3v3)
    .floatField("ram_power_w", metrics.ramPowerW)
    .floatField("mobo_power_w", metrics.moboPowerW)
    .floatField("wall_watts", metrics.wallWatts)
    .floatField("cost_per_hour", metrics.costPerHour)
    .floatField("periph_watts", runtimeConfig.periphWatts)
    .floatField("periph_cost_per_hour", (runtimeConfig.periphWatts / 1000) * runtimeConfig.tarifKwh)
    .stringField("anomaly_type", topAnomaly?.type ?? "")
    .stringField("anomaly_severity", topAnomaly?.severity ?? "")
    .booleanField("gpu_power_estimated", sensors.gpuPowerEstimated)

  api.writePoint(point)
  await api.flush()
}

export async function closeInflux(): Promise<void> {
  if (writeApi) {
    await writeApi.close()
    writeApi = null
  }
}
