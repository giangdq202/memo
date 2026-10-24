import Foundation

// MARK: - Settings (Model Layer)
// Single owner of every persisted user preference. Values are read from
// UserDefaults once at startup and kept in memory; setters write through.
// Callers apply UI side effects themselves — this type only stores state.

/// Selects which metric the history sparkline displays.
public enum SparklineMetric: String {
    case off = ""
    case cpu = "cpu"
    case ram = "ram"
    case temp = "temp"
}

/// Central, cached access to all persisted user preferences.
/// Keys and defaults are documented in AGENTS.md; do not rename keys
/// (installed copies would silently lose their settings).
public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults: UserDefaults

    // Cached values (loaded once, kept in sync by the setters below).
    private var _updateInterval: TimeInterval
    private var _tempUnit: String
    private var _showCPUTemperature: Bool
    private var _sparklineMetric: SparklineMetric

    /// - Parameter defaults: persistence backend; injectable for tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: "updateInterval")
        self._updateInterval = storedInterval > 0 ? storedInterval : 2.0
        self._tempUnit = defaults.string(forKey: "tempUnit") ?? "C"
        self._showCPUTemperature = defaults.object(forKey: "showCPUTemperature") as? Bool ?? true
        self._sparklineMetric = SparklineMetric(rawValue: defaults.string(forKey: "sparklineMetric") ?? "") ?? .off
    }

    /// Refresh interval in seconds. Preset values: 0.25, 0.5, 1.0, 2.0, 5.0.
    public var updateInterval: TimeInterval {
        get { _updateInterval }
        set {
            _updateInterval = newValue
            defaults.set(newValue, forKey: "updateInterval")
        }
    }

    /// Temperature unit: "C" or "F".
    public var tempUnit: String {
        get { _tempUnit }
        set {
            _tempUnit = newValue
            defaults.set(newValue, forKey: "tempUnit")
        }
    }

    /// Whether the menu bar shows the CPU temperature column.
    public var showCPUTemperature: Bool {
        get { _showCPUTemperature }
        set {
            _showCPUTemperature = newValue
            defaults.set(newValue, forKey: "showCPUTemperature")
        }
    }

    /// Which metric (if any) the dropdown history sparkline displays.
    public var sparklineMetric: SparklineMetric {
        get { _sparklineMetric }
        set {
            _sparklineMetric = newValue
            defaults.set(newValue.rawValue, forKey: "sparklineMetric")
        }
    }
}
