import AppKit

public class BaseStatsView: NSView {
    public var onClick: (() -> Void)?
    public var onRightClick: (() -> Void)?

    override public func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override public func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

// MARK: - Color Utilities
public enum NetworkUnitMode: Int {
    case auto = 0
    case binary = 1
    case decimal = 2
    case bits = 3
}

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

public func levelForValue(_ value: Double, warn: Double, high: Double, crit: Double) -> AlertLevel {
    if value >= crit { return .critical }
    if value >= high { return .high }
    if value >= warn { return .warning }
    return .normal
}

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

public func colorForTemperature(_ temp: Double, isDark: Bool) -> NSColor {
    let warn = 55.0
    let high = 70.0
    let crit = 85.0
    let level = levelForValue(temp, warn: warn, high: high, crit: crit)
    return discreteColor(level: level, isDark: isDark)
}

public func colorForNetworkSpeed(_ bytesPerSec: Double, isDark: Bool, defaultColor: NSColor) -> NSColor {
    guard bytesPerSec >= 1024.0 else { return defaultColor }
    let logKb = log10(bytesPerSec / 1024.0)
    let normalized = min(max(logKb / 4.5, 0.0), 1.0)
    // Map normalized speed [0, 1] to threshold levels roughly mapping to 40%, 60%, 80% full scale
    let level = levelForValue(normalized * 100.0, warn: 40.0, high: 60.0, crit: 80.0)
    return discreteColor(level: level, isDark: isDark)
}

/// Shared network speed formatter. Returns (value, unit) so callers can
/// compose them with any separator or font combination. Both the menu bar
/// view and the dropdown menu call this single implementation.
///
/// - Parameters:
///   - bytesPerSec: Raw bytes/second from StatsEngine.
///   - shortUnit: When true, returns short units ("B","K","M","G") for the
///     compact menu bar. When false, returns full units ("B/s","K/s","M/s"…).
public func formatNetworkSpeed(_ bytesPerSec: Double, shortUnit: Bool = false) -> (val: String, unit: String) {
    let mode = NetworkUnitMode(rawValue: UserDefaults.standard.integer(forKey: "networkUnitMode")) ?? .auto
    let val: Double
    let tiers: [(threshold: Double, divisor: Double, short: String, full: String)]
    
    switch mode {
    case .auto:
        val = bytesPerSec
        tiers = [
            (1000.0, 1.0, "B", "B/s"),
            (1024.0 * 1000.0, 1024.0, "K", "K/s"),
            (1024.0 * 1000000.0, 1048576.0, "M", "M/s"),
            (Double.infinity, 1073741824.0, "G", "G/s"),
        ]
    case .binary:
        val = bytesPerSec
        tiers = [
            (1024.0, 1.0, "B", "B/s"),
            (1024.0 * 1024.0, 1024.0, "Ki", "KiB/s"),
            (1024.0 * 1048576.0, 1048576.0, "Mi", "MiB/s"),
            (Double.infinity, 1073741824.0, "Gi", "GiB/s"),
        ]
    case .decimal:
        val = bytesPerSec
        tiers = [
            (1000.0, 1.0, "B", "B/s"),
            (1000.0 * 1000.0, 1000.0, "K", "KB/s"),
            (1000.0 * 1000000.0, 1000000.0, "M", "MB/s"),
            (Double.infinity, 1000000000.0, "G", "GB/s"),
        ]
    case .bits:
        val = bytesPerSec * 8.0
        tiers = [
            (1000.0, 1.0, "b", "bps"),
            (1000.0 * 1000.0, 1000.0, "K", "Kbps"),
            (1000.0 * 1000000.0, 1000000.0, "M", "Mbps"),
            (Double.infinity, 1000000000.0, "G", "Gbps"),
        ]
    }
    
    for tier in tiers {
        if val < tier.threshold {
            let scaled = val / tier.divisor
            let numStr: String
            if scaled < 10.0 && tier.divisor > 1.0 {
                numStr = String(format: "%.1f", scaled)
            } else {
                numStr = String(format: "%.0f", scaled)
            }
            return (numStr, shortUnit ? tier.short : tier.full)
        }
    }
    let lastUnit = tiers.last.map { shortUnit ? $0.short : $0.full } ?? "B"
    return (String(format: "%.0f", val), lastUnit)
}

// MARK: - Static constants (allocated once for app lifetime)
private let rightAlignStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.alignment = .right
    return style
}()

private let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
private let unitFont = NSFont.monospacedSystemFont(ofSize: 9.0, weight: .bold)
private let cpuMemUnitFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
private let tempValFont = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)

private let networkSectionWidth: CGFloat = 44.0
private let cpuMemWidthWithNetwork: CGFloat = 40.0
private let cpuMemWidthWithoutNetwork: CGFloat = 38.0
private let temperatureSectionWidth: CGFloat = 21.0

// MARK: - Unified Status Bar View with Cached Rendering
public class UnifiedStatsView: BaseStatsView {
    // Raw input values
    private var _cpuPercent: Double = -1
    private var _cpuTemperature: Double = -1
    private var _tempUnit: String = "C"
    private var _memGB: Double = -1
    private var _memPercent: Double = -1
    private var _pressureLevel: Int = 0
    private var _uploadBPS: Double = -1
    private var _downloadBPS: Double = -1

    public var showNetwork: Bool = true
    public var showTemperature: Bool = true

    public static func calculateWidth(showNetwork: Bool, showTemperature: Bool) -> CGFloat {
        let netW: CGFloat = showNetwork ? networkSectionWidth : 0.0
        let cpuMemW: CGFloat = showNetwork ? cpuMemWidthWithNetwork : cpuMemWidthWithoutNetwork
        let tempW: CGFloat = showTemperature ? temperatureSectionWidth : 0.0
        
        return netW + cpuMemW + tempW
    }

    // Cached rendered attributed strings (survive across frames)
    private var cachedUpLine: NSAttributedString?
    private var cachedDownLine: NSAttributedString?
    private var cachedCpuLine: NSAttributedString?
    private var cachedMemLine: NSAttributedString?
    private var cachedTempLine: NSAttributedString?
    private var cachedTempUnitLine: NSAttributedString?

    // Cached raw values used as cache invalidation keys (avoid String allocation)
    private var lastUpBPS: Double = -1
    private var lastDownBPS: Double = -1
    private var lastCpuPct: Double = -1
    private var lastMemGB: Double = -1
    private var lastMemPct: Double = -1
    private var lastPressure: Int = -1
    private var lastTempC: Double = -1
    private var lastTempUnit: String = ""
    private var lastMode: NetworkUnitMode = .auto

    // Cached appearance state
    private var cachedIsDark: Bool? = nil

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    public func updateValues(cpuPercent: Double, cpuTemperature: Double, tempUnit: String, memGB: Double, memPercent: Double, pressureLevel: Int,
                             uploadBytesPerSec: Double, downloadBytesPerSec: Double) {
        var changed = false
        if _cpuPercent != cpuPercent { _cpuPercent = cpuPercent; changed = true }
        if _cpuTemperature != cpuTemperature { _cpuTemperature = cpuTemperature; changed = true }
        if _tempUnit != tempUnit { _tempUnit = tempUnit; changed = true }
        if _memGB != memGB { _memGB = memGB; changed = true }
        if _memPercent != memPercent { _memPercent = memPercent; changed = true }
        if _pressureLevel != pressureLevel { _pressureLevel = pressureLevel; changed = true }
        if _uploadBPS != uploadBytesPerSec { _uploadBPS = uploadBytesPerSec; changed = true }
        if _downloadBPS != downloadBytesPerSec { _downloadBPS = downloadBytesPerSec; changed = true }
        if changed { needsDisplay = true }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> (val: String, unit: String) {
        return formatNetworkSpeed(bytesPerSec, shortUnit: true)
    }

    private func buildLine(val: String, unit: String, color: NSColor, dimAlpha: CGFloat,
                           valFont: NSFont, uFont: NSFont) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: val, attributes: [
            .font: valFont, .foregroundColor: color, .paragraphStyle: rightAlignStyle
        ]))
        s.append(NSAttributedString(string: " " + unit, attributes: [
            .font: uFont, .foregroundColor: color.withAlphaComponent(dimAlpha), .paragraphStyle: rightAlignStyle
        ]))
        return s
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let appearanceChanged = (isDark != cachedIsDark)
        let mode = NetworkUnitMode(rawValue: UserDefaults.standard.integer(forKey: "networkUnitMode")) ?? .auto
        let modeChanged = (mode != lastMode)
        
        if appearanceChanged || modeChanged {
            cachedIsDark = isDark
            lastMode = mode
            cachedUpLine = nil; cachedDownLine = nil; cachedCpuLine = nil; cachedMemLine = nil; cachedTempLine = nil; cachedTempUnitLine = nil
            lastUpBPS = -1; lastDownBPS = -1; lastCpuPct = -1; lastMemGB = -1; lastMemPct = -1; lastPressure = -1; lastTempC = -1; lastTempUnit = ""
        }

        let textColor = isDark ? NSColor.white : NSColor.black
        let dimAlpha: CGFloat = isDark ? 0.75 : 0.65

        let line1Y: CGFloat = 11.0
        let line2Y: CGFloat = 1.0
        let lineH: CGFloat = 11.0
        let netW: CGFloat = showNetwork ? networkSectionWidth : 0.0
        let cpuMemW: CGFloat = showNetwork ? cpuMemWidthWithNetwork : cpuMemWidthWithoutNetwork
        let tempW: CGFloat = showTemperature ? temperatureSectionWidth : 0.0

        var currentX: CGFloat = 0.0

        if showNetwork {
            // Upload
            if cachedUpLine == nil || _uploadBPS != lastUpBPS {
                lastUpBPS = _uploadBPS
                let (upVal, upUnit) = formatSpeed(_uploadBPS)
                let upColor = colorForNetworkSpeed(_uploadBPS, isDark: isDark, defaultColor: textColor)
                cachedUpLine = buildLine(val: upVal, unit: upUnit, color: upColor, dimAlpha: dimAlpha,
                                         valFont: font, uFont: unitFont)
            }
            let upArrow = NSAttributedString(string: "↑", attributes: [.font: unitFont, .foregroundColor: textColor.withAlphaComponent(dimAlpha)])
            upArrow.draw(at: CGPoint(x: currentX, y: line1Y))
            cachedUpLine!.draw(in: CGRect(x: currentX + 8, y: line1Y, width: netW - 8, height: lineH))

            // Download
            if cachedDownLine == nil || _downloadBPS != lastDownBPS {
                lastDownBPS = _downloadBPS
                let (downVal, downUnit) = formatSpeed(_downloadBPS)
                let downColor = colorForNetworkSpeed(_downloadBPS, isDark: isDark, defaultColor: textColor)
                cachedDownLine = buildLine(val: downVal, unit: downUnit, color: downColor, dimAlpha: dimAlpha,
                                           valFont: font, uFont: unitFont)
            }
            let downArrow = NSAttributedString(string: "↓", attributes: [.font: unitFont, .foregroundColor: textColor.withAlphaComponent(dimAlpha)])
            downArrow.draw(at: CGPoint(x: currentX, y: line2Y))
            cachedDownLine!.draw(in: CGRect(x: currentX + 8, y: line2Y, width: netW - 8, height: lineH))
            
            currentX += netW
        }

        // CPU
        if cachedCpuLine == nil || _cpuPercent != lastCpuPct {
            lastCpuPct = _cpuPercent
            let cpuVal = String(format: "%.0f", _cpuPercent)
            let cpuColor = colorForUsage(_cpuPercent, isDark: isDark, metricPrefix: "cpu")
            cachedCpuLine = buildLine(val: cpuVal, unit: "%", color: cpuColor, dimAlpha: dimAlpha,
                                       valFont: font, uFont: cpuMemUnitFont)
        }
        cachedCpuLine!.draw(in: CGRect(x: currentX, y: line1Y, width: cpuMemW, height: lineH))

        // RAM
        if cachedMemLine == nil || _memGB != lastMemGB || _memPercent != lastMemPct || _pressureLevel != lastPressure {
            lastMemGB = _memGB
            lastMemPct = _memPercent
            lastPressure = _pressureLevel
            let memKey = String(format: "%.1f", _memGB)
            let memColor = colorForUsage(_memPercent, isDark: isDark, metricPrefix: "mem", pressureLevel: _pressureLevel)
            cachedMemLine = buildLine(val: memKey, unit: "G", color: memColor, dimAlpha: dimAlpha,
                                       valFont: font, uFont: cpuMemUnitFont)
        }
        cachedMemLine!.draw(in: CGRect(x: currentX, y: line2Y, width: cpuMemW, height: lineH))
        
        currentX += cpuMemW

        if showTemperature {
            // Temperature
            let tempVal: String
            if _cpuTemperature > 0 {
                if _tempUnit == "F" {
                    tempVal = String(format: "%.0f", _cpuTemperature * 1.8 + 32.0)
                } else {
                    tempVal = String(format: "%.0f", _cpuTemperature)
                }
            } else {
                tempVal = "--"
            }
            
            if cachedTempLine == nil || _cpuTemperature != lastTempC || _tempUnit != lastTempUnit {
                lastTempC = _cpuTemperature
                lastTempUnit = _tempUnit
                let tempColor = _cpuTemperature > 0 ? colorForTemperature(_cpuTemperature, isDark: isDark) : textColor
                
                // Value line (Top, bigger font)
                let s1 = NSMutableAttributedString()
                s1.append(NSAttributedString(string: tempVal, attributes: [
                    .font: tempValFont, .foregroundColor: tempColor, .paragraphStyle: rightAlignStyle
                ]))
                cachedTempLine = s1
                
                // Unit line (Bottom, standard font, dimmed)
                let s2 = NSMutableAttributedString()
                s2.append(NSAttributedString(string: _cpuTemperature > 0 ? "°" + _tempUnit : "", attributes: [
                    .font: cpuMemUnitFont, .foregroundColor: tempColor.withAlphaComponent(dimAlpha), .paragraphStyle: rightAlignStyle
                ]))
                cachedTempUnitLine = s2
            }
            cachedTempLine!.draw(in: CGRect(x: currentX, y: line1Y, width: tempW, height: lineH))
            cachedTempUnitLine!.draw(in: CGRect(x: currentX, y: line2Y, width: tempW, height: lineH))
        }
    }
}
