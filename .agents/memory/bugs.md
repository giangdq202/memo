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
