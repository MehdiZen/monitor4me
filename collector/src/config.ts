import * as os from "os"

export const CONFIG = {
  // LibreHardwareMonitor
  LHM_URL: "http://localhost:8085/data.json",
  POLL_INTERVAL_MS: 2000,

  // PSU & hardware constants
  PSU_EFFICIENCY: 0.90,
  RAM_WATTS: 10,
  MOBO_WATTS: 15,
  NVME_WATTS_FALLBACK: 6,

  // Pricing (EDF tarif réglementé 2024)
  TARIF_KWH: 0.2516,

  // TDP limits
  CPU_TDP_W: 120,
  CPU_PPT_MAX_W: 162,
  GPU_TDP_W: 220,

  // Anomaly detection
  ZSCORE_WINDOW: 30,          // points (= 60s at 2s poll)
  ZSCORE_THRESHOLD: 3,
  CPU_THROTTLE_FREQ_DROP: 0.20,  // 20% drop
  CPU_THROTTLE_TEMP_C: 85,
  CPU_POWER_DROP_THRESHOLD: 0.30, // 30% drop
  CPU_POWER_DROP_WINDOW_S: 5,
  GPU_CLOCK_DROP: 0.30,
  GPU_TEMP_CRITICAL_C: 100,
  RAIL_12V_MIN: 11.4,
  RAIL_12V_MAX: 12.6,
  RAIL_12V_STDDEV_MAX: 0.1,
  RAIL_12V_WINDOW: 5,         // points for std dev (10s)
  NVME_TEMP_CRITICAL_C: 70,
  IDLE_WALL_WATTS: 10,

  // Notification debounce
  WARNING_DEBOUNCE_MS: 60_000,

  // InfluxDB
  INFLUX_URL: "http://localhost:8086",
  INFLUX_TOKEN: process.env.INFLUX_TOKEN ?? "pc-monitor-token",
  INFLUX_ORG: "home",
  INFLUX_BUCKET: "pc-monitor",
  INFLUX_HOST_TAG: os.hostname(),

  // RAPL correction (CPU power tends to underestimate ~7%)
  CPU_RAPL_CORRECTION: 1.07,

  // WebSocket server (live data for desktop app)
  WS_PORT: 8088,
} as const
