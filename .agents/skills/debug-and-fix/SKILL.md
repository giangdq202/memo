---
name: debug-and-fix
description: Debug workflow for build errors, runtime crashes, and incorrect UI rendering in MeMo. Activate when there is a build error, app crash, or unexpected behavior.
---

# Skill: Debug & Fix

## 1. Build Errors

### Reading The Error Correctly

```
error: <description>
  --> <file>:<line>:<column>
   |
15 | <the line of code>
   | ^ <pointer to issue>
```

Strategy:
1. Fix the **first** error in the list — subsequent errors are often cascades.
2. Read the file path and line number precisely.
3. Distinguish `error:` (blocks build) from `warning:` (does not block).

### Common Swift Build Errors

```swift
// "Value of type 'X' has no member 'y'"
// → Wrong property/method name, or wrong type
// Fix: Check the name and type

// "Cannot convert value of type 'X' to specified type 'Y'"
// → Type mismatch
// Fix: Add as? / as! or correct the type

// "Use of unresolved identifier 'x'"
// → Variable not declared, or out of scope
// Fix: Check declaration and scope

// "Expression is unused"
// → Computed a value but did not assign or use it
// Fix: Assign to a variable or remove the line
```

---

## 2. SDK / Compiler Errors

### SDK Mismatch (seen before)
```
error: failed to build module 'Swift'; this SDK is not supported by the compiler
```

Fix:
```bash
# Check Swift version
swift --version

# List available SDKs
ls /Library/Developer/CommandLineTools/SDKs/

# Then verify SDK_PATH in build.sh matches the compiler version
```

---

## 3. Runtime Issues

### App Does Not Appear On Menu Bar
```bash
pkill -f MeMo
open MeMo.app

# Stream live console logs
log stream --predicate 'process == "MeMo"' --level debug
```

### SMC Temperature Returns 0 or Shows "--"
* Cause: Sensor key is not active on this machine.
* Resolution: No fix needed — `StatusBarView` already handles this with `"--"` display.
* [CRITICAL] Do NOT modify `SMC.swift`.

### Settings Not Persisting
```swift
// Check the key name for typos
UserDefaults.standard.synchronize()  // Force write — debug only, remove after
```

---

## 4. UI Display Issues

### Colors Not Adapting To Dark/Light Mode
```swift
// Always check effectiveAppearance inside draw()
let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
```

### Menu Bar Width Is Wrong
```swift
// Width must always go through calculateWidth() — never hardcode
let width = UnifiedStatsView.calculateWidth(showNetwork: showNetworkSpeeds, showTemperature: showCPUTemperature)
statusItem.length = width
```

---

## 5. Standard Debug Process

```
1. Read the full error — do not skim
2. Identify the file and line number
3. Explain the error to the developer in plain language
4. Propose 1-2 fix options — do not auto-apply
5. Grill if root cause is unclear
6. Fix → Build → Verify behavior
7. Record in .agents/memory/bugs.md if the bug is non-trivial
```

---

## 6. Bug Log Template

After fixing, append to `.agents/memory/bugs.md`:

```markdown
## [YYYY-MM-DD] Bug: <short name>

**Symptom**: <what went wrong>
**Root cause**: <why it happened>
**Fix**: <what was changed>
**File & Line**: [`filename.swift` line X]
**Lesson**: <what to remember>
```
