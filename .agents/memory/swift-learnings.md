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
