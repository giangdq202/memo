import Foundation

// MARK: - Presentation Helpers (View Layer)
// MeMo is monochrome by design: values render in system label colors and
// hierarchy comes from size and brightness, never from hue. Only value
// formatting lives here.

/// Converts a Celsius reading to the requested unit.
func convertedTemperature(_ celsius: Double, unit: String) -> Double {
    return unit == "F" ? celsius * 1.8 + 32.0 : celsius
}

/// Returns only the numeric temperature string for the menu bar, which draws
/// the unit separately.
public func formatTemperatureValue(_ celsius: Double, unit: String) -> String {
    guard celsius > 0 else { return "--" }
    let rounded = Int(convertedTemperature(celsius, unit: unit).rounded())
    return String(rounded)
}
