// Generates src-tauri/icons/app-source.png (1024x1024) from SVG
// then calls: tauri icon src-tauri/icons/app-source.png
import { execSync } from "child_process"
import { writeFileSync, mkdirSync } from "fs"
import { join } from "path"

// ── Install resvg-js if absent ────────────────────────────────────────────────
try { await import("@resvg/resvg-js") }
catch { execSync("npm install --save-dev @resvg/resvg-js", { stdio: "inherit" }) }

const { Resvg } = await import("@resvg/resvg-js")

// ── SVG design ────────────────────────────────────────────────────────────────
// Dark rounded square · ECG waveform in electric blue · subtle glow
const SIZE = 1024
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0e1f38"/>
      <stop offset="100%" stop-color="#06090e"/>
    </linearGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="14" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <filter id="softglow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="28" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <clipPath id="rounded">
      <rect width="1024" height="1024" rx="200" ry="200"/>
    </clipPath>
  </defs>

  <!-- Background -->
  <rect width="1024" height="1024" rx="200" fill="url(#bg)"/>

  <!-- Subtle inner border -->
  <rect x="2" y="2" width="1020" height="1020" rx="199" fill="none" stroke="#1c3a5c" stroke-width="3" opacity="0.7"/>

  <!-- Grid dots (subtle background texture) -->
  <g clip-path="url(#rounded)" opacity="0.06">
    <pattern id="grid" x="0" y="0" width="64" height="64" patternUnits="userSpaceOnUse">
      <circle cx="32" cy="32" r="2" fill="#38b4f8"/>
    </pattern>
    <rect width="1024" height="1024" fill="url(#grid)"/>
  </g>

  <!-- Flat baseline (dimmed) -->
  <line x1="80" y1="512" x2="944" y2="512"
    stroke="#38b4f8" stroke-width="6" stroke-linecap="round" opacity="0.18"/>

  <!-- Glow layer (wide soft blur under the waveform) -->
  <polyline
    points="80,512  270,512  320,512  355,310  390,715  430,512  470,512  520,400  545,512  944,512"
    fill="none" stroke="#38b4f8" stroke-width="52" stroke-linecap="round" stroke-linejoin="round"
    opacity="0.12" filter="url(#softglow)"/>

  <!-- ECG waveform — main line with tight glow -->
  <polyline
    points="80,512  270,512  320,512  355,310  390,715  430,512  470,512  520,400  545,512  944,512"
    fill="none" stroke="#38b4f8" stroke-width="28" stroke-linecap="round" stroke-linejoin="round"
    filter="url(#glow)"/>

  <!-- ECG waveform — bright core -->
  <polyline
    points="80,512  270,512  320,512  355,310  390,715  430,512  470,512  520,400  545,512  944,512"
    fill="none" stroke="#7dd6fc" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>

  <!-- Accent dot at peak -->
  <circle cx="355" cy="310" r="18" fill="#38b4f8" filter="url(#glow)" opacity="0.9"/>
  <circle cx="355" cy="310" r="8" fill="#ffffff" opacity="0.85"/>
</svg>`

// ── Render to PNG ─────────────────────────────────────────────────────────────
const resvg = new Resvg(svg, { fitTo: { mode: "width", value: SIZE } })
const png   = resvg.render().asPng()

const outDir = "src-tauri/icons"
mkdirSync(outDir, { recursive: true })
const srcPng = join(outDir, "app-source.png")
writeFileSync(srcPng, png)
console.log(`PNG source écrit : ${srcPng}`)

// ── Generate all Tauri icon variants ─────────────────────────────────────────
console.log("Génération des icônes Tauri...")
execSync(`npx tauri icon "${srcPng}"`, { stdio: "inherit", cwd: process.cwd() })
console.log("Icônes générées.")
