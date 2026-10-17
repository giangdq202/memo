# Project Memory - MeMo Fork

## Architectural Decisions

### 2026-10-17: Correctness Hardening & Per-Tick Efficiency
- **Interface Enumeration Safety**: Guarded `ifa_addr` before dereferencing it in `getifaddrs` traversal, eliminating a possible crash when an interface disappears between enumeration and inspection.
- **Mach Resource Hygiene**: Deallocated the `mach_host_self()` send right in `StatsEngine.deinit` and freed `host_processor_info` buffers on partial failure.
- **Interface Cache**: Cached the primary IPv4 interface for five seconds, reducing `SCDynamicStoreCopyValue` calls from every tick to at most one every five seconds.
- **Temperature Sampling Rotation**: Sample one SMC temperature cluster per tick and reuse cached sensor values for the others, bounding IOKit calls while keeping all clusters visible.
- **UI Settings Cache**: Cached `networkUnitMode` inside `UnifiedStatsView` and passed it to menu rows, removing repeated `UserDefaults` reads from draw and menu update paths.
- **Debug Log Handle**: Reused a single `/tmp/memo_debug.log` file handle and recreates it when the file is removed externally, avoiding open/close pairs for every log line.
- **Auto Unit Thresholds**: Aligned Auto network-unit thresholds to a consistent 1024 base, avoiding the transient "1000 K" display.

### 2026-10-17: Follow-up Rescan & Menu Caching
- **Periodic Temperature Rescan**: Re-scan SMC temperature keys every 30 seconds and merge newly active sensors into the existing groups. Sensors that were asleep at launch can now appear later without removing stable keys.
- **Top-Process Cleanup**: Removed the redundant `waitUntilExit()` after `readDataToEndOfFile()`; EOF already means `ps` has finished, and the local `Process` value is released when the function returns.
- **Static Menu Skeleton**: Cached About, Activity Monitor, Settings, GitHub, and Quit menu items plus their submenus. Each open reuses those items and rebuilds only the dynamic summary, temperature, and process rows.
- **Menu State Refresh**: Centralized on/off state updates for cached settings items in `updateStaticMenuStates()`, keeping submenu checkmarks in sync without rebuilding them.

### 2026-10-17: Deprecation Cleanup & Shared Helpers
- **UserDefaults**: Removed the deprecated `UserDefaults.standard.synchronize()` call; modern Foundation writes are persisted automatically.
- **FileHandle APIs**: Replaced `readDataToEndOfFile()` with `try? readToEnd()` and `closeFile()` with `try? close()`.
- **Temperature Helper**: Extracted shared `formatTemperature` / `formatTemperatureValue` helpers so Celsius-to-Fahrenheit conversion lives in one place.
- **Draw Path**: Temperature strings are formatted only when the cached line is invalidated, not on every draw pass.
- **Network Unit Mode**: `formatNetworkSpeed` now requires an explicit `NetworkUnitMode`, removing the last `UserDefaults` read from the draw path.
- **Top-Process Cache**: Cached `fetchTopProcesses(limit:)` for two seconds, avoiding repeated `/bin/ps` spawns when the menu is reopened quickly.
- **CI Verification**: Added `codesign --verify --deep --strict` and an executable check after the CI build.

### 2026-10-17: Optional AppKit References
- **Safe Optionals**: Changed `AppDelegate.statusItem` and `AppDelegate.statsView` from implicitly unwrapped optionals to real optionals.
- **Setup Locals**: `setupStatusItem()` builds local `item` and `view` values, wires them up, then publishes them to the properties.
- **Guarded Access**: `showMenu()` and `updateStatusItemWidth()` guard-unwrap their dependencies; other call sites use optional chaining (`statsView?.…`) so a missing view cannot crash rendering.

### 2026-10-17: Quick Settings & Startup Polish
- **Duplicate Instance Wait**: Reduced the old-instance termination window from 2.0s to 0.5s with a 0.05s poll, keeping `forceTerminate()` as the final fallback.
- **Right-Click Quick Settings**: Right-clicking the menu bar item now opens a compact settings-only menu (toggles, submenus, Quit) while left-click still opens the full dashboard menu.
- **Shared CPU/Memory Formatting**: Moved `formatCPU` and `formatMemory` out of `AppDelegate` into the shared formatting section of `StatusBarView.swift`.

### 2026-10-14: Core Optimizations & Logic Fixes
- **Thermal Average & Ordering**: Fixed thermal cluster order to `P-Cores → E-Cores → GPU → Other CPU` and calculated menu bar CPU average strictly from genuine CPU core sensors (`P-Cores` + `E-Cores`), falling back to `Other CPU` if core sensors are unavailable.
- **Zero-Allocation Network Traversal**: Cached `SCDynamicStore` reference across life of process; adopted `strcmp` in `getifaddrs` traversal to avoid allocating heap strings for non-primary interfaces.
- **Network Transition Spike Guard**: Suppressed delta throughput calculation when `PrimaryInterface` transitions.
- **Subprocess Locale & Safe Unwrap**: Enforced `LC_ALL=C` on `/bin/ps` subprocess, consolidated debug file logging to `writeDebugLog`, and removed force unwraps (`!`) in `StatsEngine.swift` and `StatusBarView.swift`.
- **Menu Bar Render Optimization**: Cached `NSAttributedString` instances for `↑` and `↓` arrows; rounded values to display precision before triggering `needsDisplay`.
- **Launch at Login Consolidation**: Streamlined `setLaunchAtLogin` on macOS 13+ to return immediately upon successful `SMAppService` registration and clean up legacy plist files.

### 2026-10-14: Audit, Cleanup & Configuration Standardization
- **Agent System**: Migrated `.agent/` configuration to standardized `.agents/` folder with YAML frontmatter rules and no-emoji enforcement.
- **Hook Paths**: Corrected `.agent` -> `.agents` directory references in `pre-build.sh` and `post-build.sh` hooks.
- **Layout Constants**: Standardized width constants in `StatusBarView.swift` (`networkSectionWidth = 44.0`, etc.) eliminating hardcoded values in `calculateWidth()` and `draw()`.
- **Documentation Sync**: Synchronized active `UserDefaults` keys and architecture descriptions across `AGENTS.md`, `GEMINI.md`, and `README.md`.

### 2026-08-17: Dynamic SMC, Memory Pressure & Network Refinements
- **Dynamic SMC Keys**: Read total key count (`#KEY`) and index scan for temperature sensors instead of hardcoding key lists.
- **Memory Pressure**: Track `kern.memorystatus_vm_pressure_level` via sysctl; compute active app memory taking into account speculative & purgeable pages.
- **Primary Interface**: Detect primary route using `SCDynamicStore` to prevent multi-interface summation discrepancies, add spike filter.
- **Build Timestamp**: Auto-generate build timestamp in `Version.swift` during build step.
- **Debug Mode**: Added `--debug` command-line flag logging to `/tmp/memo_debug.log`.

### 2026-08-08: Split CI/CD Pipelines
- **CI Workflow**: Created `ci.yml` to automatically build project on `push` and `pull_request` to `main`.
- **CD Workflow**: Modified `release.yml` to only trigger on `tags` (`v*`) and manual `workflow_dispatch`. Prevents release spam on minor commits.

### 2026-08-08: Rebrand & Customization
- **App Name**: Renamed from MacStats to MeMo (Menu Monitor)
- **Credit**: Credit `openhoangnc/mac-stats`, add modifier `giangdq202`
- **Icon**: Changed to modern speedometer icon
- **Release Scripts**: Fix `install.sh` download zip to point to correct giangdq202 repo and rename build artifacts to `MeMo.zip` in `release.yml`

### 2026-08-07: Fork Setup
- **Origin**: Forked from openhoangnc/mac-stats (MIT License)
- **Goal**: Personalization - custom thresholds, compact display
- **Approach**: Modify source files directly, no Swift Package Manager
- **Build**: Universal binary (arm64 + x86_64) via `build.sh`, later restricted to arm64 only.

---

## Dependencies

| Dependency | Version | Notes |
|---|---|---|
| Swift | 6.2.4 | Installed via Xcode Command Line Tools |
| macOS SDK | 15.5 | Path: `/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk` |
| AppKit | system | UI framework |
| IOKit | system | SMC temperature sensor |
| Foundation | system | Core utilities |

**Zero external dependencies** - no CocoaPods, no SPM packages.

---

## Features Roadmap

### Done
- [x] Fork setup & build working
- [x] AGENTS.md + .agent folder structure
- [x] VS Code configurations (tasks, launch, settings)
- [x] Critical bugs fix: timer double-fire, CPU overflow, SMC guard, interval persist
- [x] Optimizations: SMC keyInfo cache, draw() cache, Float endian fix, codesign cleanup
- [x] Custom color thresholds (warn/critical levels)
- [x] Discrete 4-level colors (Green/Yellow/Orange/Red)
- [x] Enhanced Dropdown Menu (system summary, progress bars)
- [x] Network Display Unit Setting
- [x] Optimal Hardcoded Thresholds (Removed UI)
- [x] Removed Display Mode (relying on toggles)
- [x] Network Up/Down Icons
- [x] Dynamic Dropdown Menu & Update Interval (ms)
- [x] Rebrand app to MeMo, add speedometer icon

### Bugfix Backlog (from Deep Inspection 2026-08-08)
- [x] **P1** - Fahrenheit in menu shows Celsius value labeled F -> PR 8
- [x] **P2** - RAM color cache not invalidated when `_memPercent` changes -> PR 9
- [x] **P3** - Menu updaters cleared right after performClick -> PR 10
- [x] **P4** - Fake Network spike when interface disconnects/reconnects -> PR 11
- [x] **P5+P7** - sp78 signed parse + SMC fallback float remove -> PR 12
- [x] **P6** - Deduplicate formatSpeed/formatNetworkSpeed -> PR 13

### In Progress
- [x] Apple Silicon only app (arm64 build)
- [x] Temperature grouped by clusters (P-Cores, E-Cores, GPU) in Dropdown
- [ ] (Future) Notification alerts
- [ ] (Future) History sparkline chart

---

## Known Issues

| Issue | Status | Workaround |
|---|---|---|
| SDK version mismatch | Fixed | Hardcoded SDK path in build.sh |
| Network: ignores VPN/utun | Open | By design - only "en" interfaces |
| Top Processes: subprocess overhead | Open | Acceptable - only on menu open |
| Timer fired 2x per interval | Fixed | Timer now uses unscheduled Timer() + RunLoop.add(.common) |
| CPU delta integer overflow | Fixed | Cast Int32->Int64 before subtraction, clamp to 0 |
| SMC conn=0 wasted syscalls | Fixed | guard conn != 0 in getValue() |
| updateInterval not persisted | Fixed | Now stored in UserDefaults |
| Fahrenheit in menu shows Celsius value | Fixed | PR 8 - added C->F conversion |
| RAM color stale when % crosses threshold | Fixed | PR 9 - added memPercent to cache key |
| Menu values freeze while open | Fixed | PR 10 - defer cleanup to menuDidClose |
| Network spike on interface change | Fixed | PR 11 - clamp delta to 0 |
| sp78 signed parse incorrect | Fixed | PR 12 - use Int16 big-endian |
| SMC fallback float false positive | Fixed | PR 12 - removed unsafe default case |
| Duplicated format logic | Fixed | PR 13 - shared formatNetworkSpeed() |

---

## Learning Notes (Swift Concepts Learned)

*This section records what the owner has learned through each feature*

### Session 1 (2026-08-07)
- App architecture: main.swift -> AppDelegate -> StatsEngine + StatusBarView
- Build using `swiftc` without Xcode
- `UserDefaults` for storing app settings
- `@objc` and `#selector` for AppKit function calls

### Session 2 (2026-08-08)
- `NSMenuDelegate.menuDidClose` - how to detect when dropdown menu closes
- Cache invalidation strategy: all values affecting render must be cache keys
- `sp78` SMC format: signed fixed-point, uses `Int16` big-endian
- Free function vs static method: use free function for shared logic between classes
- Network counter: do not assume wrap-around when summing multiple interfaces

---

## Build History
*(Auto-updated by post-build.sh hook)*
