import AppKit

// MARK: - Dropdown Row Views (View Layer)
// Reusable NSMenu row components: section headers, value rows, progress-bar
// rows, and the width-measuring placeholder items. Pure presentation — they
// receive plain values and never sample or store anything.

/// A horizontal progress bar track drawn inside a menu row.
final class ProgressBarView: NSView {
    var percent: Double = 0
    var fillColor: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.2).setFill()
        trackPath.fill()

        let p = min(max(percent, 0.0), 100.0) / 100.0
        if p > 0 {
            let w = max(bounds.height, bounds.width * CGFloat(p))
            let fillRect = NSRect(x: 0, y: 0, width: w, height: bounds.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4)
            fillColor.setFill()
            fillPath.fill()
        }
    }
}

/// Builds the custom NSView rows used inside the dropdown menu.
enum MenuRowFactory {
    /// A small-caps, non-interactive section title row (e.g. "Top CPU").
    static func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        return item
    }

    /// A placeholder row used only so the menu can size itself to fit the widest
    /// "name  value" pair before we swap in the final width-filling view.
    static func provisionalUsageItem(name: String, value: String) -> NSMenuItem {
        let display = name.count > 28 ? String(name.prefix(27)) + "…" : name
        let item = NSMenuItem(title: "\(display)    \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A non-interactive row that fills the menu's full `width`: app name on the
    /// left (truncated to fit), value flush to the right edge. Filling the width
    /// is what removes the trailing empty space a fixed tab stop would leave.
    static func usageRowView(name: String, value: String, width: CGFloat) -> NSView {
        let leftInset: CGFloat = 21
        let rightInset: CGFloat = 21
        let font = NSFont.menuFont(ofSize: 0)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))

        let valueWidth = NSAttributedString(string: value, attributes: [.font: font]).size().width
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = font
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - rightInset - valueWidth, y: 2, width: valueWidth + 1, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]
        container.addSubview(valueLabel)

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = font
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.frame = NSRect(x: leftInset, y: 2,
                                 width: max(0, valueLabel.frame.minX - 8 - leftInset), height: 16)
        nameLabel.autoresizingMask = [.width]
        container.addSubview(nameLabel)

        return container
    }

    /// A "name …… temperature" row whose value text and color update live.
    /// - Returns: The row view plus an updater closure invoked on each tick.
    static func tempClusterRow(name: String, valueText: String, tempVal: Double, width: CGFloat) -> (NSView, (String, NSColor) -> Void) {
        let leftInset: CGFloat = 21
        let rightInset: CGFloat = 21
        let font = NSFont.menuFont(ofSize: 0)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))

        let maxLabelWidth: CGFloat = 60
        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.font = font
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - rightInset - maxLabelWidth, y: 2, width: maxLabelWidth, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]

        let isDark = container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if tempVal > 0 {
            valueLabel.textColor = colorForTemperature(tempVal, isDark: isDark)
        } else {
            valueLabel.textColor = .secondaryLabelColor
        }

        container.addSubview(valueLabel)

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = font
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.frame = NSRect(x: leftInset, y: 2,
                                 width: max(0, valueLabel.frame.minX - 8 - leftInset), height: 16)
        nameLabel.autoresizingMask = [.width]
        container.addSubview(nameLabel)

        let updater: (String, NSColor) -> Void = { newStr, newColor in
            valueLabel.stringValue = newStr
            valueLabel.textColor = newColor
        }

        return (container, updater)
    }

    /// A "label [====   ] value" row with a progress bar. The updater closure
    /// receives (percent, value text, bar color) on each tick.
    static func progressBarRow(label: String, percent: Double, valueText: String, prefix: String, width: CGFloat, pressureLevel: Int = 0) -> (NSView, (Double, String, NSColor) -> Void) {
        let leftInset: CGFloat = 21
        let rightInset: CGFloat = 21
        let font = NSFont.menuFont(ofSize: 0)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))

        let maxLabelWidth: CGFloat = 100
        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.font = font
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - rightInset - maxLabelWidth, y: 2, width: maxLabelWidth, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]
        container.addSubview(valueLabel)

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = font
        nameLabel.textColor = .labelColor
        nameLabel.frame = NSRect(x: leftInset, y: 2, width: 35, height: 16)
        container.addSubview(nameLabel)

        let barX = leftInset + 40
        let barW = max(0, valueLabel.frame.minX - 8 - barX)
        let barView = ProgressBarView(frame: NSRect(x: barX, y: 6, width: barW, height: 8))
        barView.percent = percent
        barView.autoresizingMask = [.width]

        let isDark = container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        barView.fillColor = colorForUsage(percent, isDark: isDark, metricPrefix: prefix, pressureLevel: pressureLevel)

        container.addSubview(barView)

        let updater: (Double, String, NSColor) -> Void = { newPercent, newStr, newColor in
            valueLabel.stringValue = newStr
            barView.percent = newPercent
            barView.fillColor = newColor
            barView.needsDisplay = true
        }

        return (container, updater)
    }

    /// A "label …… value" row without a bar (e.g. the Temp summary). The updater
    /// closure receives (value text, color) on each tick.
    static func inlineRow(label: String, valueText: String, isTemp: Bool, tempVal: Double, width: CGFloat) -> (NSView, (String, NSColor) -> Void) {
        let leftInset: CGFloat = 21
        let rightInset: CGFloat = 21
        let font = NSFont.menuFont(ofSize: 0)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))

        let maxLabelWidth: CGFloat = 100
        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.font = font
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - rightInset - maxLabelWidth, y: 2, width: maxLabelWidth, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]

        let isDark = container.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isTemp && tempVal > 0 {
            valueLabel.textColor = colorForTemperature(tempVal, isDark: isDark)
        } else {
            valueLabel.textColor = .secondaryLabelColor
        }

        container.addSubview(valueLabel)

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = font
        nameLabel.textColor = .labelColor
        nameLabel.frame = NSRect(x: leftInset, y: 2, width: 35, height: 16)
        container.addSubview(nameLabel)

        let updater: (String, NSColor) -> Void = { newStr, newColor in
            valueLabel.stringValue = newStr
            valueLabel.textColor = newColor
        }

        return (container, updater)
    }
}
