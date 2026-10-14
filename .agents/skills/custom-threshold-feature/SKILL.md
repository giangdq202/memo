---
name: custom-threshold-feature
description: Step-by-step guide to implement custom color thresholds for CPU, RAM, and Temperature in MeMo. Activate when the user wants to add color-coded warnings, configure threshold levels, or switch from gradient to discrete colors.
---

# Skill: Custom Color Threshold Feature

## Goal

Replace the current continuous color gradient with 3 discrete colors (green / yellow / red) at user-configurable thresholds.

## Architecture

```
UserDefaults <-> AppDelegate (settings) -> StatusBarView (rendering)
                      ^
               Menu Settings UI
```

---

## Step 1: Add Threshold Properties To AppDelegate.swift

Add after the `showCPUTemperature` property (~line 341):

```swift
// MARK: - Custom Thresholds

private var cpuWarnThreshold: Double {
    get { UserDefaults.standard.object(forKey: "cpuWarnThreshold") as? Double ?? 50.0 }
    set { UserDefaults.standard.set(newValue, forKey: "cpuWarnThreshold"); updateStats() }
}

private var cpuCriticalThreshold: Double {
    get { UserDefaults.standard.object(forKey: "cpuCriticalThreshold") as? Double ?? 80.0 }
    set { UserDefaults.standard.set(newValue, forKey: "cpuCriticalThreshold"); updateStats() }
}

private var memWarnThreshold: Double {
    get { UserDefaults.standard.object(forKey: "memWarnThreshold") as? Double ?? 70.0 }
    set { UserDefaults.standard.set(newValue, forKey: "memWarnThreshold"); updateStats() }
}

private var memCriticalThreshold: Double {
    get { UserDefaults.standard.object(forKey: "memCriticalThreshold") as? Double ?? 90.0 }
    set { UserDefaults.standard.set(newValue, forKey: "memCriticalThreshold"); updateStats() }
}
```

---

## Step 2: Pass Thresholds To StatusBarView

Modify `updateStats()` in AppDelegate:

```swift
statsView.updateValues(
    cpuPercent: currentCpuStats.usagePercent,
    cpuWarn: cpuWarnThreshold,
    cpuCritical: cpuCriticalThreshold,
    memPercent: currentMemStats.usedPercent,
    memWarn: memWarnThreshold,
    memCritical: memCriticalThreshold,
    ...
)
```

---

## Step 3: Add Color Function To StatusBarView.swift

Add stored properties:
```swift
private var _cpuWarn: Double = 50.0
private var _cpuCritical: Double = 80.0
private var _memWarn: Double = 70.0
private var _memCritical: Double = 90.0
```

Add the color function (replaces `colorForUsage`):
```swift
/// Returns a color based on discrete thresholds — no gradient.
/// Green = normal, Yellow = warning, Red = critical.
/// - Parameters:
///   - value: The usage percentage (0-100)
///   - warn: Warn threshold
///   - critical: Critical threshold
///   - isDark: True if in Dark Mode
private func colorForThreshold(_ value: Double, warn: Double, critical: Double, isDark: Bool) -> NSColor {
    if value >= critical {
        return isDark ? NSColor(calibratedHue: 0.0, saturation: 0.7, brightness: 1.0, alpha: 1.0)
                      : NSColor(calibratedHue: 0.0, saturation: 0.9, brightness: 0.7, alpha: 1.0)
    } else if value >= warn {
        return isDark ? NSColor(calibratedHue: 0.13, saturation: 0.7, brightness: 1.0, alpha: 1.0)
                      : NSColor(calibratedHue: 0.13, saturation: 0.9, brightness: 0.6, alpha: 1.0)
    } else {
        return isDark ? NSColor(calibratedHue: 0.33, saturation: 0.5, brightness: 0.95, alpha: 1.0)
                      : NSColor(calibratedHue: 0.33, saturation: 0.8, brightness: 0.35, alpha: 1.0)
    }
}
```

---

## Step 4: Add Settings Submenu To AppDelegate.showMenu()

```swift
let thresholdSubmenu = NSMenu()

for (label, warn, crit) in [("Conservative (50/80%)", 50.0, 80.0),
                              ("Balanced (60/85%)",     60.0, 85.0),
                              ("Aggressive (70/90%)",   70.0, 90.0)] {
    let item = NSMenuItem(title: label, action: #selector(changeCPUThreshold(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = [warn, crit]
    item.state = (cpuWarnThreshold == warn && cpuCriticalThreshold == crit) ? .on : .off
    thresholdSubmenu.addItem(item)
}

let thresholdItem = NSMenuItem(title: "CPU Alert Levels", action: nil, keyEquivalent: "")
thresholdItem.submenu = thresholdSubmenu
menu.addItem(thresholdItem)
```

---

## Verification Checklist

- [ ] `bash build.sh` passes with no new warnings
- [ ] Click menu bar icon → "CPU Alert Levels" submenu is visible
- [ ] Selecting a preset changes the CPU color immediately
- [ ] Quit and reopen → selected preset is retained
- [ ] Dark mode and Light mode both render correct colors
