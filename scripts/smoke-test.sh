#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

public let isDebugMode = false

let engine = StatsEngine()
let cpu = engine.fetchCPUStats()
let mem = engine.fetchMemoryStats()

guard cpu.coreCount > 0 else { fatalError("coreCount is zero") }
guard cpu.usagePercent >= 0 && cpu.usagePercent <= 100 else { fatalError("usagePercent out of range") }
guard mem.totalBytes > 0 else { fatalError("totalBytes is zero") }
guard mem.usedBytes > 0 else { fatalError("usedBytes is zero") }

precondition(formatTemperatureValue(100.0, unit: "C") == "100")
precondition(formatTemperatureValue(100.0, unit: "F") == "212")

print("Smoke tests passed: cores=\(cpu.coreCount), mem=\(String(format: "%.1f", mem.totalGB)) GB")
SWIFT

SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -O -sdk "$SDK_PATH" -module-name MeMoSmoke \
  -framework AppKit -framework IOKit -framework Foundation \
  "$ROOT/SMC.swift" "$ROOT/StatsEngine.swift" "$ROOT/Formatters.swift" "$ROOT/StatusBarView.swift" "$ROOT/AppSettings.swift" \
  "$TMP_DIR/main.swift" -o "$TMP_DIR/smoke"
"$TMP_DIR/smoke"
