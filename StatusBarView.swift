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

// Formatting and threshold-color helpers live in Formatters.swift;
// SparklineMetric (a persisted setting value) lives in AppSettings.swift.

// MARK: - Static constants (allocated once for app lifetime)
private let rightAlignStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.alignment = .right
    return style
}()

private let font = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
private let cpuMemUnitFont = NSFont.systemFont(ofSize: 9.0, weight: .bold)
private let tempValFont = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .bold)

private let cpuMemWidth: CGFloat = 38.0
private let temperatureSectionWidth: CGFloat = 21.0

// Single-line layout: fixed section widths measured once from the widest
// possible content, so digit-count changes never shift the item. Values use
// the large font; unit suffixes (%, G, °C) render smaller and dimmer so the
// numbers read first.
private let singleValFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold)
private let singleUnitFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
private let singleSectionGap: CGFloat = 5.0

/// Measures the render width of `text` and adds a pixel of headroom.
private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) + 1.0
}

private let singleCpuSectionWidth = measuredWidth("100%", font: singleValFont)
private let singleRamSectionWidth = measuredWidth("888.8G", font: singleValFont)
private let singleTempSectionWidth = measuredWidth("188°C", font: singleValFont)

// MARK: - Unified Status Bar View with Cached Rendering
public class UnifiedStatsView: BaseStatsView {
    // Raw input values
    private var _cpuPercent: Double = -1
    private var _cpuTemperature: Double = -1
    private var _tempUnit: String = "C"
    private var _memGB: Double = -1
    private var _memPercent: Double = -1
    private var _pressureLevel: Int = 0

    public var showTemperature: Bool = true

    /// Column arrangement; switching it invalidates every cached line.
    public var layoutMode: MenuBarLayout = .single {
        didSet { invalidateRenderCaches() }
    }

    public static func calculateWidth(showTemperature: Bool, layoutMode: MenuBarLayout = .single) -> CGFloat {
        switch layoutMode {
        case .single:
            var w = singleCpuSectionWidth + singleSectionGap + singleRamSectionWidth
            if showTemperature { w += singleSectionGap + singleTempSectionWidth }
            return w
        case .stacked:
            return cpuMemWidth + (showTemperature ? temperatureSectionWidth : 0.0)
        }
    }

    // Cached rendered attributed strings (survive across frames)
    private var cachedCpuLine: NSAttributedString?
    private var cachedMemLine: NSAttributedString?
    private var cachedTempLine: NSAttributedString?
    private var cachedTempUnitLine: NSAttributedString?

    // Single-line layout caches one token per metric, e.g. "12%" / "8.2G" / "45°C".
    private var cachedSingleCpuLine: NSAttributedString?
    private var cachedSingleRamLine: NSAttributedString?
    private var cachedSingleTempLine: NSAttributedString?

    // Cached raw values used as cache invalidation keys (avoid String allocation)
    private var lastCpuPct: Double = -1
    private var lastMemGB: Double = -1
    private var lastMemPct: Double = -1
    private var lastPressure: Int = -1
    private var lastTempC: Double = -1
    private var lastTempUnit: String = ""

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

    public func updateValues(cpuPercent: Double, cpuTemperature: Double, tempUnit: String, memGB: Double, memPercent: Double, pressureLevel: Int) {
        let dispCpu = cpuPercent.rounded()
        let dispTemp = cpuTemperature > 0 ? cpuTemperature.rounded() : -1.0
        let dispMemGB = (memGB * 10.0).rounded() / 10.0
        let dispMemPct = memPercent.rounded()

        var changed = false
        if _cpuPercent != dispCpu { _cpuPercent = dispCpu; changed = true }
        if _cpuTemperature != dispTemp { _cpuTemperature = dispTemp; changed = true }
        if _tempUnit != tempUnit { _tempUnit = tempUnit; changed = true }
        if _memGB != dispMemGB { _memGB = dispMemGB; changed = true }
        if _memPercent != dispMemPct { _memPercent = dispMemPct; changed = true }
        if _pressureLevel != pressureLevel { _pressureLevel = pressureLevel; changed = true }
        if changed {
            // One sentence for VoiceOver; allocated only when a value changed.
            let tempText = dispTemp > 0 ? formatTemperatureValue(dispTemp, unit: tempUnit) + "°" + tempUnit : "unavailable"
            setAccessibilityLabel("CPU \(Int(dispCpu)) percent, memory \(String(format: "%.1f", dispMemGB)) gigabytes, temperature \(tempText)")
            needsDisplay = true
        }
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

    /// Clears every cached attributed string and invalidation key so the next
    /// draw rebuilds from scratch (appearance or layout changed).
    private func invalidateRenderCaches() {
        cachedCpuLine = nil; cachedMemLine = nil; cachedTempLine = nil; cachedTempUnitLine = nil
        cachedSingleCpuLine = nil; cachedSingleRamLine = nil; cachedSingleTempLine = nil
        lastCpuPct = -1; lastMemGB = -1; lastMemPct = -1; lastPressure = -1; lastTempC = -1; lastTempUnit = ""
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark != cachedIsDark {
            cachedIsDark = isDark
            invalidateRenderCaches()
        }

        switch layoutMode {
        case .single: drawSingleLine(isDark: isDark)
        case .stacked: drawStackedLines(isDark: isDark)
        }
    }

    /// One horizontal line: "12% 8.2G 45°C" with per-metric colors.
    private func drawSingleLine(isDark: Bool) {
        let dimAlpha: CGFloat = isDark ? 0.75 : 0.65
        let lineH: CGFloat = 14.0
        let y = (bounds.height - lineH) / 2
        var x: CGFloat = 0.0

        if cachedSingleCpuLine == nil || _cpuPercent != lastCpuPct {
            lastCpuPct = _cpuPercent
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: String(format: "%.0f", _cpuPercent), attributes: [
                .font: singleValFont,
                .foregroundColor: colorForUsage(_cpuPercent, isDark: isDark, metricPrefix: "cpu"),
                .paragraphStyle: rightAlignStyle
            ]))
            s.append(NSAttributedString(string: "%", attributes: [
                .font: singleUnitFont,
                .foregroundColor: colorForUsage(_cpuPercent, isDark: isDark, metricPrefix: "cpu").withAlphaComponent(dimAlpha),
                .paragraphStyle: rightAlignStyle
            ]))
            cachedSingleCpuLine = s
        }
        cachedSingleCpuLine?.draw(in: CGRect(x: x, y: y, width: singleCpuSectionWidth, height: lineH))
        x += singleCpuSectionWidth + singleSectionGap

        if cachedSingleRamLine == nil || _memGB != lastMemGB || _memPercent != lastMemPct || _pressureLevel != lastPressure {
            lastMemGB = _memGB
            lastMemPct = _memPercent
            lastPressure = _pressureLevel
            let memColor = colorForUsage(_memPercent, isDark: isDark, metricPrefix: "mem", pressureLevel: _pressureLevel)
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: String(format: "%.1f", _memGB), attributes: [
                .font: singleValFont,
                .foregroundColor: memColor,
                .paragraphStyle: rightAlignStyle
            ]))
            s.append(NSAttributedString(string: "G", attributes: [
                .font: singleUnitFont,
                .foregroundColor: memColor.withAlphaComponent(dimAlpha),
                .paragraphStyle: rightAlignStyle
            ]))
            cachedSingleRamLine = s
        }
        cachedSingleRamLine?.draw(in: CGRect(x: x, y: y, width: singleRamSectionWidth, height: lineH))
        x += singleRamSectionWidth + singleSectionGap

        if showTemperature {
            if cachedSingleTempLine == nil || _cpuTemperature != lastTempC || _tempUnit != lastTempUnit {
                lastTempC = _cpuTemperature
                lastTempUnit = _tempUnit
                let textColor = isDark ? NSColor.white : NSColor.black
                let tempColor = _cpuTemperature > 0 ? colorForTemperature(_cpuTemperature, isDark: isDark) : textColor
                let s = NSMutableAttributedString()
                s.append(NSAttributedString(string: formatTemperatureValue(_cpuTemperature, unit: _tempUnit), attributes: [
                    .font: singleValFont, .foregroundColor: tempColor, .paragraphStyle: rightAlignStyle
                ]))
                if _cpuTemperature > 0 {
                    s.append(NSAttributedString(string: "°\(_tempUnit)", attributes: [
                        .font: singleUnitFont, .foregroundColor: tempColor.withAlphaComponent(dimAlpha), .paragraphStyle: rightAlignStyle
                    ]))
                }
                cachedSingleTempLine = s
            }
            cachedSingleTempLine?.draw(in: CGRect(x: x, y: y, width: singleTempSectionWidth, height: lineH))
        }
    }

    /// Two stacked lines: CPU over RAM on the left, temperature on the right.
    private func drawStackedLines(isDark: Bool) {
        let textColor = isDark ? NSColor.white : NSColor.black
        let dimAlpha: CGFloat = isDark ? 0.75 : 0.65

        let line1Y: CGFloat = 11.0
        let line2Y: CGFloat = 1.0
        let lineH: CGFloat = 11.0
        let cpuMemW: CGFloat = cpuMemWidth
        let tempW: CGFloat = showTemperature ? temperatureSectionWidth : 0.0

        var currentX: CGFloat = 0.0

        // CPU
        if cachedCpuLine == nil || _cpuPercent != lastCpuPct {
            lastCpuPct = _cpuPercent
            let cpuVal = String(format: "%.0f", _cpuPercent)
            let cpuColor = colorForUsage(_cpuPercent, isDark: isDark, metricPrefix: "cpu")
            cachedCpuLine = buildLine(val: cpuVal, unit: "%", color: cpuColor, dimAlpha: dimAlpha,
                                       valFont: font, uFont: cpuMemUnitFont)
        }
        cachedCpuLine?.draw(in: CGRect(x: currentX, y: line1Y, width: cpuMemW, height: lineH))

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
        cachedMemLine?.draw(in: CGRect(x: currentX, y: line2Y, width: cpuMemW, height: lineH))
        
        currentX += cpuMemW

        if showTemperature {
            // Temperature
            if cachedTempLine == nil || _cpuTemperature != lastTempC || _tempUnit != lastTempUnit {
                lastTempC = _cpuTemperature
                lastTempUnit = _tempUnit
                let tempVal = formatTemperatureValue(_cpuTemperature, unit: _tempUnit)
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
            cachedTempLine?.draw(in: CGRect(x: currentX, y: line1Y, width: tempW, height: lineH))
            cachedTempUnitLine?.draw(in: CGRect(x: currentX, y: line2Y, width: tempW, height: lineH))
        }
    }
}
