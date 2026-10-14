---
name: critical-change-guard
description: Defines which changes require the AI to stop and ask the developer for explicit confirmation before proceeding.
trigger: always_on
---

# Critical Change Guard — MeMo

Before performing any action in the categories below, the AI **must stop and ask the developer for confirmation**. No exceptions.

---

## [CRITICAL] — Stop, Explain Risk, Wait For Confirmation

1. **Modifying `SMC.swift`**
   * Low-level IOKit code. One wrong byte can crash the app or trigger a kernel panic.
   * Response: "I do not recommend modifying this file because..."

2. **Modifying `Info.plist`**
   * Especially: `LSUIElement` (controls Dock icon visibility)
   * Especially: `CFBundleIdentifier` (affects UserDefaults domain, LaunchAgent binding)

3. **Deleting or restructuring the `.app` bundle**
   * Includes: `Contents/MacOS/`, `Contents/Resources/`

4. **Replacing AppKit with SwiftUI**
   * This is a major architecture change requiring a separate plan.

5. **Adding any external dependency** (CocoaPods, Swift Package Manager)
   * Project must remain zero-dependency.

---

## [WARN] — Ask Before Doing

6. **Lowering the deployment target** (below macOS 11.0)
   * Will break multiple APIs currently in use.

7. **Changing the SDK path in `build.sh`**
   * SDK mismatch was already fixed once — regression risk is high.

8. **Modifying `build.sh` compiler flags** (`-Osize`, `-wmo`, `-dead_strip`)
   * Directly affects binary size and runtime performance.

9. **Deleting or renaming UserDefaults key names**
   * Will silently lose user settings for existing installs.

---

## [INFO] — Remind Before Doing

10. **Actions touching the filesystem outside the project folder**
    * Writing to `~/Library/`, `/Applications/`, `/tmp/`

11. **Running `install.sh` or `uninstall.sh`**
    * These affect `/Applications/` and system LaunchAgents on the live machine.

---

## Confirmation Template

```
[CRITICAL CHANGE DETECTED]

Action required  : <describe the action>
File / location  : <path>
Reason needed    : <short explanation>
Risk if wrong    : <describe the risk>

Do you want to proceed?
```
