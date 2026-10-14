#!/bin/bash
# Hook: post-build
# Run AFTER a successful build.
# Reports build results and binary size.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

APP_BUNDLE="MeMo.app"
BINARY="$APP_BUNDLE/Contents/MacOS/MeMo"

if [ ! -f "$BINARY" ]; then
    echo "[ERR] [post-build] Binary not found: $BINARY"
    exit 1
fi

echo ""
echo "[INFO] [post-build] Build Report"
echo "─────────────────────────────"

# Binary size
BINARY_SIZE=$(du -sh "$BINARY" 2>/dev/null | awk '{print $1}')
APP_SIZE=$(du -sh "$APP_BUNDLE" 2>/dev/null | awk '{print $1}')
echo "  Binary size : $BINARY_SIZE"
echo "  App bundle  : $APP_SIZE"

# Architecture check
echo "  Architectures:"
lipo -info "$BINARY" 2>/dev/null | sed 's/^/    /'

# Code signature
echo "  Code sign   :"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Authority|TeamIdentifier|Signature" | sed 's/^/    /' || echo "    (ad-hoc)"

echo "─────────────────────────────"
echo "[OK] Build successful! Run with: open $APP_BUNDLE"
echo ""

# Save build log
LOG_FILE=".agents/memory/build_history.log"
mkdir -p ".agents/memory"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Build OK — binary=$BINARY_SIZE app=$APP_SIZE" >> "$LOG_FILE"
