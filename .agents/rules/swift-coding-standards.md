---
name: swift-coding-standards
description: Swift coding style and safety rules for the MeMo project. Applies to all .swift source files.
trigger: always_on
---

# Swift Coding Standards — MeMo

## 1. Code Safety

* Every `UnsafeMutablePointer` allocation must have a corresponding `vm_deallocate` or `free`.
* No strong reference cycles — use `[weak self]` in all closures capturing `self`.
* No allocations in hot paths: `draw()` method and timer callbacks must be allocation-free.
* Every new function must have a doc comment explaining what it does, its parameters, and return value.
* `guard let` is preferred over `if let` when `nil` is an exit case.
* Never use force unwrap (`as!`) on user-provided input or `representedObject`. Use `as?` with `guard`.
* Do not use Swift 6 strict concurrency features — project targets Swift 5.x semantics.

## 2. UserDefaults Pattern

Always use computed property with get/set:

```swift
private var cpuWarnThreshold: Double {
    get { UserDefaults.standard.object(forKey: "cpuWarnThreshold") as? Double ?? 50.0 }
    set { UserDefaults.standard.set(newValue, forKey: "cpuWarnThreshold") }
}
```

* Every new UserDefaults key must be documented in the `AGENTS.md` Key Files Reference table.
* Default values must be conservative (warn=50%, critical=80%).
* To remove a key: `UserDefaults.standard.removeObject(forKey:)`.

## 3. Colors

* Never hardcode `NSColor(red:green:blue:alpha:)` for UI elements — it does not adapt to dark/light mode.
* Use `NSColor.labelColor`, `NSColor.secondaryLabelColor` for text.
* For threshold-based colors, use `calibratedHue` with an `isDark` check:

```swift
let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
NSColor(calibratedHue: hue, saturation: sat, brightness: bright, alpha: 1.0)
```

## 4. Code Organization

* Use `// MARK: -` to divide class sections.
* Variable names: `camelCase`. Function names: `verb + Noun` (e.g. `fetchCpuStats`, `updateValues`).
* No code block longer than 50 lines per implementation step.
* Prefer clear `if/else` over nested ternary operators.

## 5. Post-Edit Requirement

After modifying any `.swift` file, run `bash build.sh` to verify compilation before proceeding.
