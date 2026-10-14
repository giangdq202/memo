---
name: swift-menubar-basics
description: Core Swift and AppKit patterns for the MeMo macOS Menu Bar app. Activate when questions arise about NSColor, NSFont, NSMenuItem, UserDefaults, NSView drawing, or any basic AppKit concept.
---

# Skill: Swift Menu Bar App Basics

## 1. Colors (NSColor)

```swift
// System colors — auto-adjust for dark/light mode
NSColor.labelColor           // Primary text
NSColor.secondaryLabelColor  // Secondary text (dimmer)
NSColor.systemRed
NSColor.systemYellow
NSColor.systemGreen

// Custom HSL color (preferred for threshold-based colors)
NSColor(calibratedHue: 0.33,   // 0.0=red, 0.33=green, 0.66=purple
        saturation: 0.8,
        brightness: 0.9,
        alpha: 1.0)

// Check dark mode
let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
```

## 2. UserDefaults (Storing Settings)

```swift
// Write
UserDefaults.standard.set(50.0, forKey: "cpuWarnThreshold")

// Read (safe pattern)
let threshold = UserDefaults.standard.object(forKey: "cpuWarnThreshold") as? Double ?? 50.0

// Bool
let show = UserDefaults.standard.object(forKey: "showNetworkSpeeds") as? Bool ?? true

// Remove
UserDefaults.standard.removeObject(forKey: "cpuWarnThreshold")
```

Note: `UserDefaults.standard.double(forKey:)` returns `0.0` when the key does not exist — not `nil`. Use `object(forKey:) as? Double` to distinguish "not set" from "set to 0".

## 3. NSMenuItem

```swift
// Standard item
let item = NSMenuItem(title: "My Option", action: #selector(myAction(_:)), keyEquivalent: "")
item.target = self
menu.addItem(item)

// Checkmark state
item.state = isEnabled ? .on : .off

// Submenu
let submenu = NSMenu()
let parent = NSMenuItem(title: "Submenu", action: nil, keyEquivalent: "")
parent.submenu = submenu
menu.addItem(parent)

// Separator
menu.addItem(NSMenuItem.separator())

// Section header (disabled, smaller)
let header = NSMenuItem(title: "Section", action: nil, keyEquivalent: "")
header.isEnabled = false
menu.addItem(header)
```

## 4. NSView Drawing

```swift
override public func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw text
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ]
    "Hello".draw(at: CGPoint(x: 5, y: 5), withAttributes: attrs)

    // Draw rectangle
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
}
```

## 5. guard let vs if let

```swift
// guard let — preferred when nil is an exit case
guard let value = optionalValue else { return }
// use value here

// if let — use when both branches are needed
if let value = optionalValue {
    // use value
} else {
    // handle nil
}
```

## 6. Closures and [weak self]

```swift
// [weak self] prevents retain cycle (timer holds app, app holds timer)
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
    self?.updateStats()   // ? because self could be nil
}

// onClick closure in this project
statsView.onClick = { [weak self] in
    self?.showMenu()
}
```

## 7. Timer — RunLoop Mode Gotcha

```swift
// [CORRECT] Unscheduled timer + manual add to .common
let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
    self?.updateStats()
}
RunLoop.current.add(t, forMode: .common)

// [WRONG] scheduledTimer + add .common = fires twice
// scheduledTimer already adds to .default; .common includes .default
```
