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
let top = engine.fetchTopProcesses(limit: 3)

guard cpu.coreCount > 0 else { fatalError("coreCount is zero") }
guard mem.totalBytes > 0 else { fatalError("totalBytes is zero") }
guard !top.byCPU.isEmpty else { fatalError("top CPU list is empty") }
guard !top.byMemory.isEmpty else { fatalError("top memory list is empty") }

precondition(formatCPU(42.0) == "42%")
precondition(formatMemory(2 * 1024 * 1024 * 1024) == "2.0 GB")
precondition(formatTemperature(100.0, unit: "C") == "100°C")
precondition(formatTemperature(100.0, unit: "F") == "212°F")

print("Smoke tests passed: cores=\(cpu.coreCount), mem=\(String(format: "%.1f", mem.totalGB)) GB, top=\(top.byCPU.count)")
SWIFT

SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -O -sdk "$SDK_PATH" -module-name MeMoSmoke \
  -framework AppKit -framework IOKit -framework Foundation \
  "$ROOT/SMC.swift" "$ROOT/StatsEngine.swift" "$ROOT/StatusBarView.swift" \
  "$TMP_DIR/main.swift" -o "$TMP_DIR/smoke"
"$TMP_DIR/smoke"
