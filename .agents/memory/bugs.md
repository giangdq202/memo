# Bug Log - MeMo Project

> AI updates this file after every bug is found and fixed.
> Standard format helps learn from past mistakes.

---

## Template

```markdown
## [YYYY-MM-DD] Bug: <short name>

**Symptom**: [Describe what went wrong]
**Root cause**: [Root cause]
**Fix**: [How it was fixed]
**File & Line**: [`filename.swift` line X]
**Lesson**: [What to learn for next time]
```

---

## 2026-08-07: SDK Version Mismatch

**Symptom**: `bash build.sh` reports error:
```
error: failed to build module 'Swift'; this SDK is not supported by the compiler
```

**Root cause**: Swift 6.2.4 (new compiler) but `xcode-select` points to an older SDK.
The SDK symlink (`MacOSX.sdk`) points to a version that doesn't match the compiler.

**Fix**: Hardcode SDK path in `build.sh`:
```bash
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
COMMON_FLAGS=(-Osize -wmo -module-name MeMo -sdk "$SDK_PATH" ...)
```

**File**: `build.sh` lines 21-22

**Lesson**: 
- When updating Command Line Tools, always check `swift --version` vs SDK version.
- `xcrun --show-sdk-path --sdk macosx` -> view active SDK
- `ls /Library/Developer/CommandLineTools/SDKs/` -> view available SDKs

---

## 2026-08-07: Timer Double-Fire

**Symptom**: `updateStats()` runs twice as often as intended -> CPU waste, battery drain.
**Root cause**: `scheduledTimer` auto-adds the timer to the `.default` RunLoop mode. The code then calls `RunLoop.current.add(timer!, forMode: .common)` -> timer registered in both modes. Since `.common` includes `.default`, timer fires 2x.
**Fix**: Use `Timer(timeInterval:...)` (unscheduled) then `RunLoop.current.add(t, forMode: .common)` - only once.
**File**: `AppDelegate.swift` lines 56-66
**Lesson**: `scheduledTimer` = create + add RunLoop. If a custom mode is needed, use `Timer()` constructor + manual add.

---

## 2026-08-07: CPU Delta Integer Overflow

**Symptom**: CPU shows fake 100% or garbage value when counter wraps around.
**Root cause**: `cpuInfo[x] - prevCpuInfo[x]` is an `Int32` subtraction. When counter overflows, result is negative, cast to `UInt64` -> huge value (~2^63).
**Fix**: Cast each operand to `Int64` before subtraction, then `max(0, delta)` to clamp.
**File**: `StatsEngine.swift` lines 168-174
**Lesson**: When subtracting unsigned/signed integers then casting types, always widen the type before subtraction.

---

## 2026-08-07: SMC Connection Not Guarded

**Symptom**: When SMC init fails (conn=0), 100+ useless syscalls to the kernel happen every 2 seconds.
**Root cause**: `SMC.init()` fails silently (returns early, conn remains 0). `getValue()` does not check conn before calling `IOConnectCallStructMethod`.
**Fix**: Add `guard conn != 0 else { return nil }` at the top of `getValue()`.
**File**: `SMC.swift` line 149
**Lesson**: When init can fail, all public methods must guard state validity.

---

## 2026-08-07: ~~Float Byte-Order in SMC~~ (REVERTED - This was an incorrect fix)

**Initial Symptom**: Assumed SMC returns big-endian bytes for `"flt "` type.
**Initial Fix**: Swapped bytes [3,2,1,0] before `load(as: Float.self)`.
**Consequence**: Temperature shows `--` because swap creates garbage values -> falls outside 15-110C range -> filtered out.
**Actual Root Cause**: SMC returns `flt ` type in **host byte order** (little-endian), NOT big-endian. Original code was correct.
**Lesson**: DO NOT assume byte order without actual testing. `sp78` uses big-endian (manual parse), but `flt ` uses host-endian. Each data type has its own convention.

---

## 2026-10-14: Network Spike on Interface Transition

**Symptom**: Giant download/upload throughput spike (e.g. GB/s) whenever network interface switches (Wi-Fi <-> Ethernet).
**Root cause**: Delta calculation subtracted byte counter of new interface from byte counter of previous interface without verifying if the interface had just changed.
**Fix**: Added `let interfaceChanged = (primaryInterface != cachedActiveInterface)`. If `interfaceChanged` is true, skip delta calculation for that single cycle and set speeds to 0.
**File**: `StatsEngine.swift` lines 315, 343
**Lesson**: Network interface cumulative counters cannot be compared across different interface names.

---

## 2026-10-14: Duplicate Launch at Login on macOS 13+

**Symptom**: App launched twice on system reboot on macOS Ventura and newer.
**Root cause**: `setLaunchAtLogin(enabled: true)` registered with `SMAppService.mainApp`, but did not return, continuing to create a user `LaunchAgent` plist as well.
**Fix**: Return immediately when `SMAppService.mainApp.register()` succeeds, and proactively remove any legacy `LaunchAgent` plist.
**File**: `AppDelegate.swift` lines 404-414
**Lesson**: Modern macOS background services must maintain a single source of truth; use `SMAppService` exclusively on macOS 13+ and reserve `LaunchAgents` solely for older systems.

---

## 2026-10-14: Temperature Average Distorted by Ambient Sensors

**Symptom**: CPU temperature displayed in Menu Bar was significantly lower than actual core heat under heavy load.
**Root cause**: Sensor grouping lumped all unrecognized `T` sensors into the average alongside actual P-Cores and E-Cores.
**Fix**: Explicitly calculate menu bar average solely from `P-Cores` and `E-Cores`, only falling back to `Other CPU` if no core sensors are available.
**File**: `StatsEngine.swift` lines 186-224
**Lesson**: Keep primary indicators focused strictly on relevant component metrics rather than broad system-wide sensor averages.

---

## 2026-10-17: NULL ifa_addr and CPU Buffer Leak

**Symptom**: Potential crash during network sampling when an interface disappears, plus a leaked processor-info buffer when `host_processor_info` returns an error after allocating it.
**Root cause**: `ifa_addr` was dereferenced before the optional check, and the error path returned without calling `vm_deallocate`.
**Fix**: Bind `ifa_addr` with `let` before reading `sa_family`; free any non-nil `cpuInfo` buffer before returning on `KERN_SUCCESS` failure.
**File**: `StatsEngine.swift` network and CPU sampling paths
**Lesson**: Check every C pointer before dereferencing it, and free resources on every early-return path.

---

## 2026-10-17: Sleeping Temperature Sensors Never Reappeared

**Symptom**: A temperature sensor that was inactive at app launch stayed missing even after it became active later.
**Root cause**: `scanActiveTempKeys()` ran only in `init`, so keys filtered out at that moment were never reconsidered.
**Fix**: Re-scan every 30 seconds and merge newly active keys into the existing groups without removing known keys.
**File**: `StatsEngine.swift` temperature sampling path
**Lesson**: Discovery scans that depend on transient device state must be repeatable, not one-shot.
