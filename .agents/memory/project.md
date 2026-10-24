# Project Memory - MeMo Fork

## Product Philosophy (owner-confirmed 2026-10-24)

- **Purpose**: a personal, minimal menu bar monitor built as a Swift learning vehicle. Not a product; not a feature race.
- **Why not an existing app**: owner rejects all four — bloat/unnecessary features, UI that does not fit, closed source/privacy, opaque numbers with no way to verify where they come from.
- **Design identity (2026-10-24, PR #36)**: owner follows minimalism + monochrome. The menu bar item renders ONLY in system `labelColor`/`secondaryLabelColor` like the native clock; the threshold color machinery (calibratedHue palette) was deleted outright. Do not reintroduce hue-based status colors.
- **Values**: tinkering, portfolio, full control over what runs on the machine.
- **Scope rule ("đủ dùng là dừng")**: once the feature set is enough, stop. When considering a new feature, it must serve the owner's daily use AND teach something new; otherwise decline.
- Precedent: network monitoring was removed (2026-10-17) exactly because it exceeded personal need.

## Architectural Decisions

### 2026-10-24: Separator Rhythm (PR #37)
- **Problem (from owner's screenshot)**: at 11pt the three right-aligned metrics blurred into one digit run.
- **Fix**: Swiss-style mid-dot separators (`·`, tertiaryLabelColor, 9pt, centered in fixed slots) between metrics — `13% · 17.9G · 43°`; constant rhythm regardless of digit counts. Celsius renders bare `°`; Fahrenheit keeps `°F`.
- **Verified visually** via screencapture + vision analysis (distinct groups, dots dimmer than values, native fit).

### 2026-10-24: Monochrome Design
- **All rendering now system monochrome**: values in `labelColor`, units (%, G, °C) in `secondaryLabelColor`, both layouts (single-line and stacked). Semantic NSColors adapt to Dark/Light automatically.
- **Deleted the color machinery**: AlertLevel, discreteColor, levelForValue, colorForUsage, colorForTemperature - Formatters.swift is now Foundation-only with just convertedTemperature + formatTemperatureValue.
- `updateValues` dropped memPercent/pressureLevel (they existed only to pick colors); the RAM token cache now invalidates on GB change alone.

### 2026-10-24: Single-Line Typography Polish (PR #34)
- **11pt values** (was 10pt) for legibility on non-Retina displays; unit suffixes (%, G, °C) uniformly smaller + dimmer so numbers read first (previously only °C was dimmed).
- **Accessibility label** updated per value change for VoiceOver.
- Deliberately NOT done: CPU smoothing (would fake the data, violating the owner's "real numbers" value) and palette changes (green-normal is the app's identity from upstream).

### 2026-10-24: Menu Bar First Simplification
- **Applied the Product Philosophy**: owner confirmed they never use the left-click dropdown, so the menu bar numbers are now the entire UI.
- **Removed**: threshold alerts (AlertCoordinator deleted), history sparkline (view, ring buffers, submenu), top-processes sampling (no more /bin/ps subprocess), the hover tooltip (NSViewToolTipOwner), and the whole dropdown with its live-row updaters and menu width-swap hack (MenuViews.swift deleted).
- **Unified Menu**: left- and right-click open the same settings menu (version header, settings, Activity Monitor, GitHub, Quit); MenuFactory is static-only.
- **Added `menuBarLayout`**: "single" (default, `12% 8.2G 45°C` one line, per-metric threshold colors, fixed section widths measured from worst-case strings so digits never shift the item) or "stacked" (classic two-line).
- **UserDefaults keys removed**: `cpuAlertThreshold`, `ramAlertThreshold`, `tempAlertThreshold`, `sparklineMetric`; added `menuBarLayout`. SMC idle skip now keys off `showCPUTemperature` alone.

### 2026-10-24: MVC / Clean Architecture Layering
- **AppDelegate Split**: The 1048-line god class became a 280-line controller plus five focused files. Dependency rule: Model knows nobody, Controller reads Model and drives View, View renders plain values only.
- **New Files**: `Formatters.swift` (presentation helpers), `AppSettings.swift` (cached write-through settings store, single owner of all UserDefaults keys except `LaunchAtLogin`), `LoginItemService.swift` (SMAppService + plist fallback), `MenuViews.swift` (row components behind `MenuRowFactory`), `AlertCoordinator.swift` (threshold notifications), `MenuFactory.swift` (menu assembly, static item cache, live-row updaters).
- **MenuActions Protocol**: `MenuFactory` dispatches item actions through an `@objc protocol MenuActions` implemented by `AppDelegate`, so view assembly never depends on the concrete controller. Selector reference: `#selector(MenuActions.changeInterval(_:))`.
- **Live Rows Push Model**: The factory stores `latestCpu/latestMem/latestHistories`; the controller pushes fresh values each tick via `refreshLiveRows(cpu:mem:histories:)`. `hasLiveMenu` replaces the old `activeMenuUpdaters` check for the idle SMC skip.
- **Side Effects Moved Out of Setters**: Settings setters persist only; the action handlers own UI side effects (restart timer, re-render, on-demand SMC sample).
- **Pure Refactor**: No behavior change intended; SMC.swift, Info.plist, and build flags untouched (build.sh only gained source entries).

### 2026-10-18: Skip Idle SMC Temperature Polling
- **Idle SMC Skip**: When `showCPUTemperature` is off and no temp alerts or temp sparkline are active, `StatsEngine.fetchCPUStats(includeTemperature: false)` skips all IOKit reads and 30s `#KEY` rescans, reducing context switches by ~78% and Mach syscalls by ~41%.
- **Separated Sampling**: `sampleTemperatures(fullSample:)` is decoupled from CPU delta sampling. Opening the dropdown menu on-demand samples temperatures immediately without touching `prevCpuInfo`, eliminating CPU measurement jitter.
- **Zero-Flicker Toggle**: Re-enabling temperature via Quick Settings samples sensors on-demand in `updateUIForSettingsChange()` and renders immediately, avoiding the transient `--` display.

### 2026-10-18: Lazy Menu Bar Tooltip
- **On-Demand Generation**: Conformed `UnifiedStatsView` to `NSViewToolTipOwner` and registered `bounds` via `addToolTip(_:owner:userData:)`.
- **Zero-Allocation Hot Path**: String formatting only happens when the cursor hovers over the menu bar item, avoiding unnecessary per-tick allocations.
- **Dynamic Content**: Displays `CPU % | RAM GB | Temp` if temperature is enabled and non-zero, or `CPU % | RAM GB` otherwise.

### 2026-10-17: History Sparkline
- **Ring Buffers**: `cpuHistory`, `ramHistory`, and `tempHistory` keep the last 60 samples and are appended on every tick in `updateStats()`.
- **Metric Selection**: `sparklineMetric` stores `""` (off), `"cpu"`, `"ram"`, or `"temp"`; the History Graph submenu exposes those choices.
- **Dropdown Rendering**: When enabled, the full menu inserts a `SparklineView` custom view whose updater redraws from the current history on every tick.
- **Shared Drawing**: `SparklineView` auto-scales to the sample range, draws a faint baseline, and takes its stroke color from the existing metric color helpers.

### 2026-10-17: Configurable Threshold Alerts
- **User-Configurable Thresholds**: `cpuAlertThreshold`, `ramAlertThreshold`, and `tempAlertThreshold` are stored in `UserDefaults`; `0` disables that alert. Preset levels are exposed through submenus, so nothing is hardcoded in the alert logic.
- **Permission on Demand**: `UNUserNotificationCenter` authorization is requested only when the user selects a non-zero threshold, keeping first-run silent.
- **Cooldown**: Each metric has a 60-second cooldown (`lastCpuAlert`, `lastRamAlert`, `lastTempAlert`) to prevent notification spam while a value stays high.
- **Menu Integration**: Alert submenus are cached with the other settings items, so they appear in both the full menu and the right-click quick settings menu.

### 2026-10-17: Ops Hardening & Smoke Tests
- **Release Versioning**: Replaced the fragile `sed` replacement in `release.yml` with `plutil -replace CFBundleShortVersionString` plus a `plutil -lint` check.
- **Smoke Tests**: Added `scripts/smoke-test.sh`, which compiles a temporary harness from `SMC.swift`, `StatsEngine.swift`, and `StatusBarView.swift`, then verifies CPU/memory sampling, top-process sampling, and the shared formatters.
- **CI**: `.github/workflows/ci.yml` now runs the smoke test after verifying the signed app bundle.

### 2026-10-17: Network Monitoring Removed
- **Scope**: MeMo is now a resource monitor only (CPU, memory, temperature, processes). All network sampling, display, settings, and formatting were removed.
- **StatsEngine**: Deleted `NetworkStats`, `fetchNetworkStats()`, `getPrimaryInterface()`, the `SCDynamicStore` reference, and all network delta state.
- **StatusBarView**: Removed `NetworkUnitMode`, `formatNetworkSpeed`, `colorForNetworkSpeed`, the network column, and the network-specific width constants.
- **AppDelegate**: Removed `currentNetStats`, the network summary row, `Show Network Speeds`, the Network Unit submenu, and the related action handlers.
- **Docs**: Updated `README.md`, `AGENTS.md`, and `GEMINI.md` to drop network keys and known issues.

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
- [x] Optimizations: SMC keyInfo cache, draw() cache, codesign cleanup
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
- [x] Notification alerts
- [x] History sparkline chart

---

## Known Issues

| Issue | Status | Workaround |
|---|---|---|
| SDK version mismatch | Fixed | Hardcoded SDK path in build.sh |
| Top Processes: subprocess overhead | Open | Acceptable - only on menu open |
| Timer fired 2x per interval | Fixed | Timer now uses unscheduled Timer() + RunLoop.add(.common) |
| CPU delta integer overflow | Fixed | Cast Int32->Int64 before subtraction, clamp to 0 |
| SMC conn=0 wasted syscalls | Fixed | guard conn != 0 in getValue() |
| updateInterval not persisted | Fixed | Now stored in UserDefaults |
| Fahrenheit in menu shows Celsius value | Fixed | PR 8 - added C->F conversion |
| RAM color stale when % crosses threshold | Fixed | PR 9 - added memPercent to cache key |
| Menu values freeze while open | Fixed | PR 10 - defer cleanup to menuDidClose |
| sp78 signed parse incorrect | Fixed | PR 12 - use Int16 big-endian |
| SMC fallback float false positive | Fixed | PR 12 - removed unsafe default case |
| Duplicated format logic | Fixed | PR 13 - shared formatting helpers |

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
