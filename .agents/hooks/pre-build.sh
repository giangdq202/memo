#!/bin/bash
# Run before `bash build.sh`. Advisory only; hard policy lives in scripts/policy-check.sh.
set -e
cd "$(cd "$(dirname "$0")/../.." && pwd)"

echo "[INFO] [pre-build] Checking Swift files..."

COUNT=$(grep -n " as! " AppDelegate.swift StatusBarView.swift StatsEngine.swift 2>/dev/null | grep -vc "//.*as!" || true)
if [ "${COUNT:-0}" -gt 0 ]; then
    echo "[WARN] Found $COUNT forced cast(s). Prefer 'as?' with guard."
fi

# SDK selection is build.sh's job (it falls back to xcrun), so it is not checked here.
scripts/policy-check.sh
echo "[OK] [pre-build] Checks passed."
