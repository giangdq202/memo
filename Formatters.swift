import AppKit

// MARK: - Presentation Helpers (View Layer)
// Shared value formatting and threshold colors used by the menu bar view,
// dropdown rows, and notifications. Presentation only: no sampling logic here.

public enum AlertLevel: Int {
    case normal = 0
    case warning = 1
    case high = 2
    case critical = 3
}

public func discreteColor(level: AlertLevel, isDark: Bool) -> NSColor {
    switch level {
    case .normal: // Green
        return isDark ? NSColor(calibratedHue: 130.0/360.0, saturation: 0.40, brightness: 0.92, alpha: 1.0)
                      : NSColor(calibratedHue: 130.0/360.0, saturation: 0.85, brightness: 0.32, alpha: 1.0)
    case .warning: // Yellow
        return isDark ? NSColor(calibratedHue: 48.0/360.0, saturation: 0.45, brightness: 0.95, alpha: 1.0)
                      : NSColor(calibratedHue: 48.0/360.0, saturation: 0.85, brightness: 0.38, alpha: 1.0)
    case .high: // Orange
        return isDark ? NSColor(calibratedHue: 28.0/360.0, saturation: 0.50, brightness: 0.95, alpha: 1.0)
                      : NSColor(calibratedHue: 28.0/360.0, saturation: 0.85, brightness: 0.40, alpha: 1.0)
    case .critical: // Red
        return isDark ? NSColor(calibratedHue: 0.0/360.0, saturation: 0.50, brightness: 0.95, alpha: 1.0)
                      : NSColor(calibratedHue: 0.0/360.0, saturation: 0.85, brightness: 0.42, alpha: 1.0)
    }
}

/// Maps a metric value to its alert level using warn/high/critical thresholds.
public func levelForValue(_ value: Double, warn: Double, high: Double, crit: Double) -> AlertLevel {
    if value >= crit { return .critical }
    if value >= high { return .high }
    if value >= warn { return .warning }
    return .normal
}

/// Threshold color for CPU ("cpu") or memory ("mem") percentages. Memory colors
/// escalate early when the kernel reports memory pressure.
public func colorForUsage(_ percent: Double, isDark: Bool, metricPrefix: String, pressureLevel: Int = 0) -> NSColor {
    let warn: Double
    let high: Double
    let crit: Double

    if metricPrefix == "mem" {
        // If system reports high memory pressure, override usage-based color
        if pressureLevel >= 4 { return discreteColor(level: .critical, isDark: isDark) }
        if pressureLevel >= 2 { return discreteColor(level: .warning, isDark: isDark) }

        warn = 65.0; high = 80.0; crit = 90.0
    } else {
        // CPU
        warn = 60.0; high = 75.0; crit = 90.0
    }

    let level = levelForValue(percent, warn: warn, high: high, crit: crit)
    return discreteColor(level: level, isDark: isDark)
}

/// Threshold color for a Celsius temperature reading.
public func colorForTemperature(_ temp: Double, isDark: Bool) -> NSColor {
    let warn = 55.0
    let high = 70.0
    let crit = 85.0
    let level = levelForValue(temp, warn: warn, high: high, crit: crit)
    return discreteColor(level: level, isDark: isDark)
}

/// Converts a Celsius reading to the requested unit.
func convertedTemperature(_ celsius: Double, unit: String) -> Double {
    return unit == "F" ? celsius * 1.8 + 32.0 : celsius
}

/// Returns the full temperature display string (value plus unit) for menu rows.
public func formatTemperature(_ celsius: Double, unit: String) -> String {
    guard celsius > 0 else { return "--" }
    return String(format: "%.0f°%@", convertedTemperature(celsius, unit: unit), unit)
}

/// Returns only the numeric temperature string for the menu bar, which draws
/// the unit separately.
public func formatTemperatureValue(_ celsius: Double, unit: String) -> String {
    guard celsius > 0 else { return "--" }
    return String(format: "%.0f", convertedTemperature(celsius, unit: unit))
}

/// Formats a CPU percentage for menu rows.
public func formatCPU(_ percent: Double) -> String {
    return String(format: "%.0f%%", percent)
}

/// Formats a byte count for menu rows, preferring GB and falling back to MB.
public func formatMemory(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824.0
    if gb >= 1.0 { return String(format: "%.1f GB", gb) }
    return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
}
