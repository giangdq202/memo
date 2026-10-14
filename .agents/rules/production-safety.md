---
name: production-safety
description: Safety guardrails for all changes to the MeMo project — prevents accidental system modifications, build artifact commits, and irreversible filesystem actions.
trigger: always_on
---

# Production Safety Rules for MeMo

1. **Filesystem Actions Outside Project Folder**:
   * Never write to `~/Library/`, `/Applications/`, or system paths without explicit user confirmation.
   * Running `install.sh` or `uninstall.sh` affects the live system — always inform the user first.

2. **Destructive File Actions**:
   * Never delete `.app` bundle, `Contents/MacOS/`, or `Contents/Resources/` directories without confirmation.
   * Never `rm -rf` inside the project without confirming with the user step-by-step.

3. **Build Artifacts**:
   * Never commit `MeMo.app`, `MeMo_bin`, `*_arm64`, `*_x86_64`, or `Version.swift` to git.
   * These are auto-generated — `.gitignore` covers them.

4. **Critical File Guard — Stop And Ask First**:
   * `SMC.swift` — low-level IOKit, one wrong byte can kernel panic. Do NOT modify.
   * `Info.plist` — especially `LSUIElement` and `CFBundleIdentifier`.
   * `build.sh` compiler flags (`-Osize`, `-wmo`, `-dead_strip`) — affects binary size and performance.
   * Deployment target — must stay at macOS 11.0 minimum.
