---
name: compact-display
description: Step-by-step guide to implement Compact Display mode for MeMo — minimal menu bar pixels, unit label hiding, and layout variants. Activate when the user wants to reduce menu bar footprint or add a Compact Mode toggle.
---

# Skill: Compact Display Mode

## Goal

Add a "Display Mode" toggle that hides unit labels and reduces spacing, keeping only the most essential numbers.

## Width Concept

```
Normal Mode:  [15 up  3.2 K] [23 %  8.1 G] [52 C]   -> ~91px
Compact Mode: [15up 3K] [23% 8G] [52]                -> ~65px
Minimal Mode: [23%] [8G]                             -> ~38px
```

---

## Step 1: Add displayMode Property To AppDelegate.swift

```swift
// Add enum at the top of the file or inside the class
enum DisplayMode: String {
    case normal  = "normal"
    case compact = "compact"
    case minimal = "minimal"
}

// Computed property for persistence
private var displayMode: DisplayMode {
    get {
        let raw = UserDefaults.standard.string(forKey: "displayMode") ?? "normal"
        return DisplayMode(rawValue: raw) ?? .normal
    }
    set {
        UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode")
        updateUIForSettingsChange()
    }
}
```

---

## Step 2: Expose DisplayMode In StatusBarView.swift

```swift
public enum DisplayMode: String {
    case normal, compact, minimal
}

public var displayMode: DisplayMode = .normal {
    didSet { needsDisplay = true }
}

// Update calculateWidth() to account for mode
public static func calculateWidth(showNetwork: Bool, showTemperature: Bool, mode: DisplayMode) -> CGFloat {
    switch mode {
    case .normal:
        let netW: CGFloat  = showNetwork     ? 30.0 : 0.0
        let cpuMemW: CGFloat = showNetwork   ? 40.0 : 38.0
        let tempW: CGFloat = showTemperature ? 21.0 : 0.0
        return netW + cpuMemW + tempW
    case .compact:
        let netW: CGFloat  = showNetwork     ? 22.0 : 0.0
        let cpuMemW: CGFloat = 30.0
        let tempW: CGFloat = showTemperature ? 16.0 : 0.0
        return netW + cpuMemW + tempW
    case .minimal:
        return 38.0  // CPU% and RAM GB only
    }
}
```

---

## Step 3: Modify draw() In StatusBarView.swift

```swift
// Inside draw(), check mode before formatting output:
switch displayMode {
case .normal:
    let (val, unit) = formatSpeed(_uploadBPS)
    // draw val and unit separately
case .compact:
    let (val, unit) = formatSpeed(_uploadBPS)
    let shortUnit = String(unit.prefix(1))  // "K" instead of "KB"
    // draw val and shortUnit
case .minimal:
    break  // Skip network entirely
}
```

---

## Step 4: Add Menu Item To showMenu()

```swift
let displayModeSubmenu = NSMenu()
for (label, mode) in [("Normal",           DisplayMode.normal),
                       ("Compact",          DisplayMode.compact),
                       ("Minimal (CPU+RAM)", DisplayMode.minimal)] {
    let item = NSMenuItem(title: label, action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = mode.rawValue
    item.state = (displayMode == mode) ? .on : .off
    displayModeSubmenu.addItem(item)
}

let displayItem = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
displayItem.submenu = displayModeSubmenu
menu.addItem(displayItem)
```

---

## Step 5: Add The Handler

```swift
@objc private func changeDisplayMode(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
          let mode = DisplayMode(rawValue: raw) else { return }
    displayMode = mode
}
```

---

## Verification Checklist

- [ ] `bash build.sh` passes with no new warnings
- [ ] Menu bar icon click shows "Display Mode" submenu
- [ ] Switching mode changes the menu bar layout immediately
- [ ] Width updates correctly — no clipping, no overflow
- [ ] Selected mode persists after quit and reopen
- [ ] All three modes render correctly in Dark and Light mode
