param([string]$LhmUrl = "http://localhost:8085/data.json")
$ErrorActionPreference = "Stop"

Write-Host "Probing LHM at $LhmUrl..." -ForegroundColor Cyan

try {
    $data = Invoke-RestMethod $LhmUrl -TimeoutSec 5
} catch {
    Write-Error "Cannot reach LHM. Is it running with admin rights? Error: $_"
    exit 1
}

Write-Host "LHM reachable OK" -ForegroundColor Green

function Search-Sensors {
    param($Node, [string]$SensorType = "", [int]$Depth = 0)
    $indent = "  " * $Depth
    foreach ($child in $Node.Children) {
        $isMatch = ($SensorType -eq "") -or ($child.Type -eq $SensorType)
        if ($isMatch -and $child.Value) {
            $tag = if ($child.Type) { "[$($child.Type)]" } else { "" }
            Write-Host "$indent$($child.Text) $tag = $($child.Value)"
        }
        Search-Sensors -Node $child -SensorType $SensorType -Depth ($Depth + 1)
    }
}

Write-Host ""
Write-Host "=== POWER SENSORS ===" -ForegroundColor Cyan
Search-Sensors -Node $data -SensorType "Power"

Write-Host ""
Write-Host "=== VOLTAGE SENSORS ===" -ForegroundColor Cyan
Search-Sensors -Node $data -SensorType "Voltage"

Write-Host ""
Write-Host "=== TEMPERATURE SENSORS ===" -ForegroundColor Cyan
Search-Sensors -Node $data -SensorType "Temperature"

Write-Host ""
Write-Host "=== CLOCK SENSORS ===" -ForegroundColor Cyan
Search-Sensors -Node $data -SensorType "Clock"

Write-Host ""
Write-Host "=== GPU POWER CHECK ===" -ForegroundColor Yellow

$found = $false
function Find-GPU {
    param($Node)
    foreach ($child in $Node.Children) {
        if ($child.Text -match "GPU|AMD|Radeon|RX" -and $child.Type -eq "Power" -and $child.Value) {
            Write-Host "  FOUND: $($child.Text) = $($child.Value)" -ForegroundColor Green
            $script:found = $true
        }
        Find-GPU $child
    }
}
Find-GPU $data

if (-not $found) {
    Write-Host "  NO GPU POWER SENSOR FOUND" -ForegroundColor Red
    Write-Host "  RX 9070 XT likely not yet supported by this LHM version." -ForegroundColor Yellow
}
