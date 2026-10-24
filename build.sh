#!/bin/bash
set -e

APP_NAME="MeMo"
APP_BUNDLE="${APP_NAME}.app"

# Minimum macOS version. MUST match LSMinimumSystemVersion in Info.plist.
# This gets baked into the binary's LC_BUILD_VERSION (minos), which is what
# Launch Services actually checks. Without an explicit -target, swiftc stamps
# minos to the *build machine's* OS version, so the app fails to launch on any
# older Mac with error -10825 (kLSIncompatibleSystemVersionErr).
DEPLOYMENT_TARGET="11.0"

echo "=== Building ${APP_NAME} (Optimized, arm64) ==="

# 1. Generate icon
echo "[1/4] Generating AppIcon.icns..."
python3 generate_icon.py || echo "Warning: Icon generation failed, continuing..."

# Generate Version.swift with current build time
BUILD_TIME=$(date "+%y%m%d.%H%M")
echo "let BUILD_VERSION = \"1.0.0 (${BUILD_TIME})\"" > Version.swift

SOURCES=(SMC.swift StatsEngine.swift Formatters.swift StatusBarView.swift AppSettings.swift LoginItemService.swift MenuFactory.swift AppDelegate.swift main.swift Version.swift)
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
else
    SDK_PATH=$(xcrun --show-sdk-path)
fi
COMMON_FLAGS=(-Osize -wmo -module-name MeMo -sdk "$SDK_PATH" -Xlinker -dead_strip \
    -framework AppKit -framework IOKit -framework Foundation)

# 2. Compile an arm64 Swift executable, pinning the
#    deployment target so it runs on macOS ${DEPLOYMENT_TARGET} and newer,
#    on Apple Silicon Macs.
echo "[2/4] Compiling arm64 binary, min macOS ${DEPLOYMENT_TARGET}..."
swiftc "${COMMON_FLAGS[@]}" -target "arm64-apple-macosx${DEPLOYMENT_TARGET}" \
    "${SOURCES[@]}" -o "${APP_NAME}_bin"

# Strip debug symbols and local symbols to minimize binary
strip -x "${APP_NAME}_bin" || true

# 3. Create .app bundle structure
echo "[3/4] Packaging ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

mv "${APP_NAME}_bin" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"
fi

# 4. Sign binary locally
echo "[4/4] Signing app bundle locally..."
codesign --force --sign - "${APP_BUNDLE}"

echo "=== Build Complete! ==="
echo "App created at: $(pwd)/${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}"
