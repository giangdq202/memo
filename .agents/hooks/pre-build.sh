#!/bin/bash
# Hook: pre-build
# Run BEFORE the build step to validate code.
# Invoked automatically by the agent before each `bash build.sh`.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "[INFO] [pre-build] Checking Swift files..."

# 1. Warn about force unwraps in UI/delegate files (not in SMC.swift)
FORCE_UNWRAP_COUNT=$(grep -rn " as! " AppDelegate.swift StatusBarView.swift 2>/dev/null | grep -v "//.*as!" | wc -l | tr -d ' ')
if [ "$FORCE_UNWRAP_COUNT" -gt "0" ]; then
    echo "[WARN] Found $FORCE_UNWRAP_COUNT force unwrap(s). Consider using 'as?' with guard/if let."
    grep -rn " as! " AppDelegate.swift StatusBarView.swift 2>/dev/null | grep -v "//.*as!" || true
fi

# 2. Guard SMC.swift against accidental modification (high-risk IOKit code)
SMC_HASH_FILE=".agents/.smc_checksum"
CURRENT_SMC_HASH=$(md5 -q SMC.swift 2>/dev/null || md5sum SMC.swift 2>/dev/null | awk '{print $1}')
if [ -f "$SMC_HASH_FILE" ]; then
    SAVED_HASH=$(cat "$SMC_HASH_FILE")
    if [ "$CURRENT_SMC_HASH" != "$SAVED_HASH" ]; then
        echo "[WARN] SMC.swift has been modified!"
        echo "   SMC.swift is low-level IOKit code — changes are high-risk."
        echo "   If intentional, run: echo '$CURRENT_SMC_HASH' > .agents/.smc_checksum"
    fi
else
    echo "$CURRENT_SMC_HASH" > "$SMC_HASH_FILE"
    echo "[INFO] SMC.swift checksum saved."
fi

# 3. Verify SDK path exists before attempting build
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [ ! -d "$SDK_PATH" ]; then
    echo "[ERR] SDK not found at $SDK_PATH"
    echo "   Available SDKs:"
    ls /Library/Developer/CommandLineTools/SDKs/ 2>/dev/null || echo "   (none found)"
    echo "   Update SDK_PATH in build.sh to match an available SDK."
    exit 1
fi

echo "[OK] [pre-build] All checks passed."
