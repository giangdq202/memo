# Swift Learnings - MeMo Project

> Record the Swift concepts learned through each feature.
> AI updates this file after every commit.

---

## Session 1 - 2026-08-07: Project Setup

### Concepts Learned

**App Architecture**
- macOS Menu Bar app has no Window - only `NSStatusItem` on the menu bar.
- `NSApp.setActivationPolicy(.accessory)` -> hides the icon from Dock and Command-Tab.
- `LSUIElement = true` in `Info.plist` -> app runs as a background accessory.

**Entry Point**
- `NSApplicationMain` is skipped -> use `NSApplication.shared` manually to avoid loading NIB.
- `app.delegate = delegate; app.run()` -> starts the event loop.

**Timer**
- `Timer.scheduledTimer(withTimeInterval:repeats:)` -> calls a function periodically.
- `timer.tolerance = 0.25 * interval` -> allows macOS to coalesce with other timers (saves battery).
- `[weak self]` in closure -> prevents memory retain cycle.

**UserDefaults**
- Save simple settings with `UserDefaults.standard.set(value, forKey: "key")`.
- Read with type-safety: `object(forKey:) as? Bool ?? defaultValue`.
- Changes persist after quitting and reopening the app.

**Build System**
- `swiftc` compiles directly without an Xcode project.
- `lipo -create arm64 x86_64 -output universal` -> universal binary.
- `-Osize -wmo -dead_strip` -> optimize size, compile as whole module.

**SDK Fix**
- Swift 6.2.4 needs a matching SDK version.
- Fix: hardcoded `-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk` in `build.sh`.

---

## Session 2 - 2026-08-07: Critical Bugs & Optimizations

### Concepts Learned

**Timer RunLoop Modes**
- `scheduledTimer` = creates Timer + adds to `.default` RunLoop automatically.
- `.common` mode includes `.default` + `.eventTracking` -> timer fires even when the user is dragging.
- To use `.common`: create the timer using `Timer(timeInterval:...)` then `RunLoop.current.add(t, forMode: .common)`.
- DO NOT use `scheduledTimer` + `add(.common)` -> fires twice!

**Integer Overflow Safety**
- `Int32` subtraction when counter wraps -> negative result -> casting to `UInt64` -> garbage value.
- Solution: widen to `Int64` before subtraction, then `max(0, delta)`.
- Similarly for network: `UInt32` overflows when exceeding 4GB -> detect wrap-around.

**SMC / IOKit**
- `IOConnectCallStructMethod` is a syscall into the kernel - heavy, needs to be minimized.
- `keyInfo` (dataSize, dataType) does not change for the same key -> can be cached.
- SMC returns bytes in big-endian, host is little-endian -> must be swapped (or manual parse).

**UserDefaults Computed Property**
- Use computed property `get/set` instead of stored property -> auto-persist.
- `UserDefaults.standard.double(forKey:)` returns 0.0 if the key does not exist -> needs guard.

**NSAttributedString Cache**
- Comparing raw `Double` is faster than formatting a String and then comparing the String.
- Only call `String(format:)` when the value actually changes -> reduces allocation.

---

## Session 3 - 2026-08-17: Dynamic SMC, Memory Pressure & Network Refinements

### Concepts Learned

**Dynamic SMC Key Discovery**
- Using `SMCKeys.readIndex` and `SMCKeys.kernelIndex` to iterate over all SMC keys using key index.
- Read `#KEY` to discover total count, dynamically matching prefix `T` (temperature) rather than maintaining static tables per Apple Silicon generation.

**System Memory Pressure via Sysctl**
- `sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0)` returns macOS system memory pressure (1: Normal, 2: Warning, 4: Critical).
- App memory calculation: `active + speculative - purgeable` better aligns with Activity Monitor than raw active memory.

**Dynamic Primary Network Interface**
- Querying `SCDynamicStore` at `State:/Network/Global/IPv4` to resolve `PrimaryInterface` (e.g. `en0`, `en1`).
- Filtering traffic by primary interface avoids counting inactive interfaces or local bridges.

**CLI Argument Parsing**
- `CommandLine.arguments.contains("--debug")` provides lightweight runtime flag handling without extra dependencies.

---

## Session 4 - 2026-10-14: Core Optimizations & Logic Fixes

### Concepts Learned

**Zero-Allocation in Tight Loops**
- In `getifaddrs` traversal (~20 interfaces sampled every 250ms), avoid `String(cString: namePtr)` heap allocation; use C function `strcmp(namePtr, primaryInterface) == 0`.
- Cache `SCDynamicStore` reference once on class initialization instead of creating/destroying an IPC connection on every cycle.

**Interface Transition Spike Elimination**
- When `PrimaryInterface` switches (e.g. Wi-Fi `en0` to Ethernet `en5`), network cumulative counters differ completely. Suppressing delta calculation for that single cycle prevents massive false throughput spikes.

**Process Execution Locale Consistency**
- When parsing numeric CLI output from `/bin/ps` (`pcpu`, `rss`), system decimal separator can change in non-English locales (e.g., `,` vs `.`). Setting `task.environment = ["LC_ALL": "C"]` guarantees standard POSIX formatting.

**Safe Dictionary Mutation & Optional Chaining**
- Avoid `byName[name]!` force unwrap; use `if var existing = byName[name] { ... byName[name] = existing }`.
- In custom AppKit view drawing, avoid `cachedLine!.draw(...)` force unwrap in favor of safe optional chaining `cachedLine?.draw(...)`.

**SMAppService vs LaunchAgent Single Source of Truth**
- On macOS 13+, `SMAppService.mainApp.register()` handles startup items. Returning immediately upon success and cleaning up any legacy `~/Library/LaunchAgents/*.plist` prevents dual registration and duplicate instance launches.

---

## Session 5 - 2026-10-17: Correctness Hardening & Per-Tick Efficiency

### Concepts Learned

**Optional C Pointers**
- `UnsafeMutablePointer` fields coming from C APIs may be `NULL`; bind them with `guard let`/`if let` before dereferencing. A chained optional unwrap in an `if` condition is evaluated left to right, so put the pointer check before `.pointee`.

**Mach Port Lifetime**
- `mach_host_self()` returns a send right. Balance it with `mach_port_deallocate(mach_task_self_, port)` in `deinit`, just like `vm_deallocate` for processor-info buffers.

**Sampling Budget Design**
- Instead of reading every SMC temperature key on every tick, rotate one sensor group per tick and keep last-known values in a dictionary. This bounds IOKit work while preserving a complete cluster display.

**Caching with a Time Budget**
- A short TTL cache for `SCDynamicStore` primary-interface queries removes per-tick IPC overhead. A five-second stale window is acceptable for menu-bar network statistics.

**Reusing File Handles**
- Keep a single `FileHandle` open for append-only debug logging; close it in `deinit`. This avoids syscall and allocation overhead on every log line. If the file may be deleted or rotated externally, check existence before writing and reopen, because writes to an unlinked file succeed silently.

---

## Session 6 - 2026-10-17: Follow-up Rescan & Menu Caching

### Concepts Learned

**Repeatable Discovery**
- A one-shot hardware scan at init is fragile when sensors can sleep or appear later. Re-run the scan on a timer, merge new keys into the existing set, and keep old keys so the UI does not flicker.

**Process EOF Semantics**
- `readDataToEndOfFile()` returns after the child closes its stdout, which for a short-lived tool like `ps` means it has already exited. An explicit `waitUntilExit()` is redundant; the local `Process` value is released at function exit.

**NSMenuItem Reuse**
- `NSMenuItem` can belong to only one `NSMenu` at a time. To reuse a cached item, remove it from its previous menu before adding it to the new one.
- Cache only items whose content does not depend on live data (About, Settings, Quit); keep dynamic rows fresh.
- Centralize state updates for cached checkmark items so submenus stay in sync without a full rebuild.

---

## Session 7 - 2026-10-17: Deprecation Cleanup & Shared Helpers

### Concepts Learned

**Modern FileHandle APIs**
- `readDataToEndOfFile()` and `closeFile()` are deprecated. Use `try? handle.readToEnd()` (falling back to `Data()`) and `try? handle.close()` so errors do not crash the sampling path.

**Shared Formatting Helpers**
- Keep unit conversion in one place. `formatTemperature(_:unit:)` returns the full display string, while `formatTemperatureValue(_:unit:)` returns only the number the menu bar draws next to a separate unit label.

**Cache-Guarded Formatting**
- Compute display strings only inside the cache-invalidation branch. Formatting on every `draw()` wastes work even when the rendered string has not changed.

**Explicit Dependencies**
- Making `mode: NetworkUnitMode` a required parameter removes the hidden `UserDefaults` read from the render path and forces callers to pass the already-cached value.

**Short-Lived Subprocess Caching**
- A two-second TTL around `fetchTopProcesses` avoids re-spawning `/bin/ps` when the menu is reopened quickly, while keeping the data fresh enough for an interactive menu.

**CI as a Gate**
- Adding `codesign --verify --deep --strict` and an executable check after the build catches broken bundles before a release.

---

## Session 8 - 2026-10-17: Optional AppKit References

### Concepts Learned

**Avoiding Implicitly Unwrapped Optionals**
- `NSStatusItem!` and `UnifiedStatsView!` compile but hide the possibility of a nil access. Real optionals plus `guard let` at the point of use keep the lifecycle explicit.
- Build dependent objects locally in `setupStatusItem()` (`let item`, `let view`), then assign them to the properties once fully configured. This avoids partially wired property state.
- For optional UI updates that are safe to skip, optional chaining (`statsView?.updateValues(...)`) is concise; for operations that must not run without the dependency, `guard let` is clearer.

---

## Session 9 - 2026-10-17: Quick Settings & Startup Polish

### Concepts Learned

**Bounded Startup Waits**
- When terminating a previous process, wait for the shortest practical window and poll often. A 0.5s deadline with a 0.05s run-loop tick keeps the status item handoff reliable without blocking launch for two seconds.

**Distinguishing Left and Right Click**
- `NSView.mouseDown` and `rightMouseDown` let one view drive two menus. Reusing the same cached `NSMenuItem` objects for both menus is safe because `reuse(_:in:)` detaches each item from its previous menu first.
- A compact right-click menu can be assembled from the existing cached settings items plus a Quit item, avoiding a second menu definition.

**Shared Formatting Across Files**
- Small formatters like `formatCPU` and `formatMemory` belong next to the other shared formatters (`formatNetworkSpeed`, `formatTemperature`) so any layer of the app can reuse them without duplicating format strings.

---

## Session 10 - 2026-10-17: Removing a Feature Cleanly

### Concepts Learned

**Feature Removal Checklist**
- Remove the full vertical slice: data model (`NetworkStats`), sampling function, cached state, UI properties, drawing code, menu items, settings keys, and helper formatters.
- Re-run `grep` for the feature name after each removal pass to catch leftovers in docs, skills, and config.
- Update `README.md`, `AGENTS.md`, and `GEMINI.md` so the documented feature set matches the binary.

**Simplifying Layout After Removal**
- Deleting a menu bar column let the two remaining sections share a single width constant and drop the `showNetwork` parameter from `calculateWidth`.
- Removing the network column also removed the only consumer of `unitFont`, so the font constant was deleted too.

**Safe Large Refactor**
- Do the removal per file, build after each file, and keep the change on its own branch so it can be reverted independently if needed.
