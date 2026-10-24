import AppKit

// MARK: - Menu Factory (Controller Layer — View Assembly)
// Builds the dropdown and quick-settings NSMenus, caches static items across
// opens, and refreshes live rows while a menu is open. Decoupled from
// AppDelegate through the MenuActions protocol; never touches StatsEngine.

/// Actions the settings menu dispatches back to the app controller.
/// Implemented by AppDelegate.
@objc protocol MenuActions: NSObjectProtocol {
    func openActivityMonitor()
    func openGitHubPage()
    func quitApp()
    func toggleShowTemperature(_ sender: NSMenuItem)
    func toggleLaunchAtLogin(_ sender: NSMenuItem)
    func changeInterval(_ sender: NSMenuItem)
    func changeTempUnit(_ sender: NSMenuItem)
    func changeSparklineMetric(_ sender: NSMenuItem)
}

/// History samples for the sparkline, handed to the factory on each refresh.
struct HistoryBuffers {
    let cpu: [Double]
    let ram: [Double]
    let temp: [Double]
}

/// Assembles every NSMenu the status item shows and keeps live rows in sync
/// with the latest sampled values while a menu is open.
final class MenuFactory: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private weak var actions: MenuActions?

    // Static menu items are built once and reused across menu opens.
    private var cachedVersionItem: NSMenuItem?
    private var cachedActivityItem: NSMenuItem?
    private var cachedShowTemperatureItem: NSMenuItem?
    private var cachedLaunchAtLoginItem: NSMenuItem?
    private var cachedIntervalSubmenu: NSMenu?
    private var cachedTempUnitSubmenu: NSMenu?
    private var cachedGitHubItem: NSMenuItem?
    private var cachedQuitItem: NSMenuItem?
    private var cachedSettingsParentItems: [NSMenuItem] = []
    private var cachedSparklineSubmenu: NSMenu?

    // Live rows: updaters run on each tick while the menu is open.
    private var liveUpdaters: [() -> Void] = []
    private var latestCpu = CPUStats()
    private var latestMem = MemoryStats()
    private var latestHistories = HistoryBuffers(cpu: [], ram: [], temp: [])

    /// Whether a menu with live rows is currently open.
    var hasLiveMenu: Bool { !liveUpdaters.isEmpty }

    /// - Parameters:
    ///   - settings: source of the values the menu checkmarks reflect.
    ///   - actions: receiver for every menu item action (held weakly).
    init(settings: AppSettings, actions: MenuActions) {
        self.settings = settings
        self.actions = actions
        super.init()
    }

    // MARK: - Static Item Builders

    private func buildAboutItem() {
        let versionStr = BUILD_VERSION
        let item = NSMenuItem(title: "MeMo v\(versionStr)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: "MeMo v\(versionStr)", attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
        cachedVersionItem = item
    }

    private func buildActivityItem() {
        let item = NSMenuItem(title: "Open Activity Monitor", action: #selector(MenuActions.openActivityMonitor), keyEquivalent: "")
        item.target = actions
        cachedActivityItem = item
    }

    private func buildSettingsItems() {
        let showTempItem = NSMenuItem(title: "Show CPU Temperature", action: #selector(MenuActions.toggleShowTemperature(_:)), keyEquivalent: "")
        showTempItem.target = actions
        cachedShowTemperatureItem = showTempItem

        let autoStartItem = NSMenuItem(title: "Launch at Login", action: #selector(MenuActions.toggleLaunchAtLogin(_:)), keyEquivalent: "")
        autoStartItem.target = actions
        cachedLaunchAtLoginItem = autoStartItem

        let intervalSubmenu = NSMenu()
        let intervals: [(String, TimeInterval)] = [
            ("Ultra Fast (250 ms)", 0.25),
            ("Fast (500 ms)", 0.5),
            ("Normal (1 s)", 1.0),
            ("Slow (2 s)", 2.0),
            ("Very Slow (5 s)", 5.0)
        ]
        for (label, sec) in intervals {
            let item = NSMenuItem(title: label, action: #selector(MenuActions.changeInterval(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = sec
            intervalSubmenu.addItem(item)
        }
        let refreshItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        refreshItem.submenu = intervalSubmenu
        cachedIntervalSubmenu = intervalSubmenu

        let tempUnitSubmenu = NSMenu()
        for (label, key) in [("Celsius (°C)", "C"), ("Fahrenheit (°F)", "F")] {
            let item = NSMenuItem(title: label, action: #selector(MenuActions.changeTempUnit(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = key
            tempUnitSubmenu.addItem(item)
        }
        let tempUnitItem = NSMenuItem(title: "Temperature Unit", action: nil, keyEquivalent: "")
        tempUnitItem.submenu = tempUnitSubmenu
        cachedTempUnitSubmenu = tempUnitSubmenu

        let sparklineSubmenu = NSMenu()
        let sparklineOptions: [(String, SparklineMetric)] = [
            ("Off", .off), ("CPU", .cpu), ("RAM", .ram), ("Temperature", .temp)
        ]
        for (label, metric) in sparklineOptions {
            let item = NSMenuItem(title: label, action: #selector(MenuActions.changeSparklineMetric(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = metric.rawValue
            sparklineSubmenu.addItem(item)
        }
        let sparklineItem = NSMenuItem(title: "History Graph", action: nil, keyEquivalent: "")
        sparklineItem.submenu = sparklineSubmenu
        cachedSparklineSubmenu = sparklineSubmenu

        // Store the parent items in the settings order they appear in the menu.
        cachedSettingsParentItems = [showTempItem, autoStartItem, refreshItem, tempUnitItem, sparklineItem]
    }

    private func buildFooterItems() {
        let githubItem = NSMenuItem(title: "GitHub Repository", action: #selector(MenuActions.openGitHubPage), keyEquivalent: "")
        githubItem.target = actions
        cachedGitHubItem = githubItem

        let quitItem = NSMenuItem(title: "Quit MeMo", action: #selector(MenuActions.quitApp), keyEquivalent: "q")
        quitItem.target = actions
        cachedQuitItem = quitItem
    }

    private func buildStaticMenuItems() {
        guard cachedVersionItem == nil else { return }
        buildAboutItem()
        buildActivityItem()
        buildSettingsItems()
        buildFooterItems()
    }

    /// Syncs every cached settings item's checkmark with current state.
    func refreshSettingsStates() {
        buildStaticMenuItems()
        cachedShowTemperatureItem?.state = settings.showCPUTemperature ? .on : .off
        cachedLaunchAtLoginItem?.state = LoginItemService.isEnabled ? .on : .off

        if let submenu = cachedIntervalSubmenu {
            for item in submenu.items {
                if let sec = item.representedObject as? TimeInterval {
                    item.state = (settings.updateInterval == sec) ? .on : .off
                }
            }
        }
        if let submenu = cachedTempUnitSubmenu {
            for item in submenu.items {
                if let key = item.representedObject as? String {
                    item.state = (settings.tempUnit == key) ? .on : .off
                }
            }
        }

        let selectedSparkline = settings.sparklineMetric
        if let submenu = cachedSparklineSubmenu {
            for item in submenu.items {
                if let raw = item.representedObject as? String {
                    item.state = (selectedSparkline.rawValue == raw) ? .on : .off
                }
            }
        }
    }

    /// Detaches a cached item from its previous menu (if any) and adds it to the
    /// new menu. NSMenuItem can only belong to one menu at a time.
    private func reuse(_ item: NSMenuItem?, in menu: NSMenu) {
        guard let item = item else { return }
        item.menu?.removeItem(item)
        menu.addItem(item)
    }

    // MARK: - Dropdown Menu

    /// Builds the full dropdown menu from the latest sampled values.
    /// - Parameters:
    ///   - cpu: CPU stats (usage, temperature, clusters) to display.
    ///   - mem: Memory stats to display.
    ///   - top: Top-process rankings fetched by the controller on open.
    ///   - histories: Ring buffers backing the sparkline.
    /// - Returns: A configured menu with live rows ready for refresh ticks.
    func buildDropdownMenu(cpu: CPUStats, mem: MemoryStats,
                           top: (byCPU: [ProcessUsage], byMemory: [ProcessUsage]),
                           histories: HistoryBuffers) -> NSMenu {
        latestCpu = cpu
        latestMem = mem
        latestHistories = histories

        refreshSettingsStates()

        let menu = NSMenu()
        menu.autoenablesItems = false

        // --- About Header ---
        reuse(cachedVersionItem, in: menu)
        menu.addItem(NSMenuItem.separator())

        var customViews: [(item: NSMenuItem, builder: (CGFloat) -> (NSView, () -> Void))] = []

        // --- System Summary Section ---
        let cpuItem = NSMenuItem(title: "CPU              100%", action: nil, keyEquivalent: "")
        cpuItem.isEnabled = false
        menu.addItem(cpuItem)
        customViews.append((cpuItem, { [weak self] width in
            guard let self = self else { return (NSView(), {}) }
            let (view, updateBlock) = MenuRowFactory.progressBarRow(label: "CPU", percent: self.latestCpu.usagePercent, valueText: formatCPU(self.latestCpu.usagePercent), prefix: "cpu", width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let pct = self.latestCpu.usagePercent
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                updateBlock(pct, formatCPU(pct), colorForUsage(pct, isDark: isDark, metricPrefix: "cpu"))
            }
            return (view, updater)
        }))

        let ramItem = NSMenuItem(title: "RAM              32.0/32.0 GB", action: nil, keyEquivalent: "")
        ramItem.isEnabled = false
        menu.addItem(ramItem)
        customViews.append((ramItem, { [weak self] width in
            guard let self = self else { return (NSView(), {}) }
            let valStr = String(format: "%.1f/%.0f GB", self.latestMem.usedGB, self.latestMem.totalGB)
            let (view, updateBlock) = MenuRowFactory.progressBarRow(label: "RAM", percent: self.latestMem.usedPercent, valueText: valStr, prefix: "mem", width: width, pressureLevel: self.latestMem.pressureLevel)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let pct = self.latestMem.usedPercent
                let pressure = self.latestMem.pressureLevel
                let newStr = String(format: "%.1f/%.0f GB", self.latestMem.usedGB, self.latestMem.totalGB)
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                updateBlock(pct, newStr, colorForUsage(pct, isDark: isDark, metricPrefix: "mem", pressureLevel: pressure))
            }
            return (view, updater)
        }))

        let tempItem = NSMenuItem(title: "Temp              100°C", action: nil, keyEquivalent: "")
        tempItem.isEnabled = false
        menu.addItem(tempItem)
        customViews.append((tempItem, { [weak self] width in
            guard let self = self else { return (NSView(), {}) }
            let t = self.latestCpu.temperature
            let valStr = formatTemperature(t, unit: self.settings.tempUnit)
            let (view, updateBlock) = MenuRowFactory.inlineRow(label: "Temp", valueText: valStr, isTemp: true, tempVal: t, width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let tNew = self.latestCpu.temperature
                let newStr = formatTemperature(tNew, unit: self.settings.tempUnit)
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let color = (tNew > 0) ? colorForTemperature(tNew, isDark: isDark) : .secondaryLabelColor
                updateBlock(newStr, color)
            }
            return (view, updater)
        }))
        menu.addItem(NSMenuItem.separator())

        // --- Temperatures Section ---
        if !latestCpu.tempClusters.isEmpty {
            menu.addItem(MenuRowFactory.sectionHeader("Temperatures"))
            for cluster in latestCpu.tempClusters {
                let item = NSMenuItem(title: "\(cluster.name)    \(String(format: "%.0f°C", cluster.temperature))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)

                customViews.append((item, { [weak self] width in
                    guard let self = self else { return (NSView(), {}) }
                    let t = cluster.temperature
                    let valStr = formatTemperature(t, unit: self.settings.tempUnit)

                    let (view, updateBlock) = MenuRowFactory.tempClusterRow(name: cluster.name, valueText: valStr, tempVal: t, width: width)
                    let updater = { [weak self, weak view] in
                        guard let self = self, let view = view else { return }
                        // Find this cluster's updated temperature
                        let newT = self.latestCpu.tempClusters.first(where: { $0.name == cluster.name })?.temperature ?? 0.0
                        let newStr = formatTemperature(newT, unit: self.settings.tempUnit)
                        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        let color = (newT > 0) ? colorForTemperature(newT, isDark: isDark) : .secondaryLabelColor
                        updateBlock(newStr, color)
                    }
                    return (view, updater)
                }))
            }
            menu.addItem(NSMenuItem.separator())
        }

        // --- History Section ---
        let sparkline = settings.sparklineMetric
        if sparkline != .off {
            menu.addItem(MenuRowFactory.sectionHeader("History"))
            let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            historyItem.isEnabled = false
            menu.addItem(historyItem)
            customViews.append((historyItem, { [weak self] width in
                guard let self = self else { return (NSView(), {}) }
                let view = SparklineView(frame: NSRect(x: 0, y: 0, width: width, height: 40))
                let values = self.historyValues(for: sparkline)
                view.values = values
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                view.lineColor = Self.sparklineColor(for: sparkline, value: values.last ?? 0.0, isDark: isDark)
                let updater = { [weak self, weak view] in
                    guard let self = self, let view = view else { return }
                    let newValues = self.historyValues(for: sparkline)
                    view.values = newValues
                    let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    view.lineColor = Self.sparklineColor(for: sparkline, value: newValues.last ?? 0.0, isDark: dark)
                    view.needsDisplay = true
                }
                return (view, updater)
            }))
            menu.addItem(NSMenuItem.separator())
        }

        // --- Top Processes Section ---
        // Rows start as plain items so the menu can compute its natural width; below
        // we swap in width-filling views that right-align the value flush to that width.
        if !top.byCPU.isEmpty {
            menu.addItem(MenuRowFactory.sectionHeader("Top CPU"))
            for p in top.byCPU {
                let value = formatCPU(p.cpuPercent)
                let item = MenuRowFactory.provisionalUsageItem(name: p.name, value: value)
                menu.addItem(item)
                customViews.append((item, { w in (MenuRowFactory.usageRowView(name: p.name, value: value, width: w), {}) }))
            }
            menu.addItem(NSMenuItem.separator())
        }
        if !top.byMemory.isEmpty {
            menu.addItem(MenuRowFactory.sectionHeader("Top Memory"))
            for p in top.byMemory {
                let value = formatMemory(p.memoryBytes)
                let item = MenuRowFactory.provisionalUsageItem(name: p.name, value: value)
                menu.addItem(item)
                customViews.append((item, { w in (MenuRowFactory.usageRowView(name: p.name, value: value, width: w), {}) }))
            }
            menu.addItem(NSMenuItem.separator())
        }

        // Jump to Activity Monitor for the full, detailed breakdown.
        reuse(cachedActivityItem, in: menu)
        menu.addItem(NSMenuItem.separator())

        // --- Settings Section ---
        for item in cachedSettingsParentItems {
            reuse(item, in: menu)
        }
        menu.addItem(NSMenuItem.separator())

        // GitHub Link
        reuse(cachedGitHubItem, in: menu)
        menu.addItem(NSMenuItem.separator())

        // Quit
        reuse(cachedQuitItem, in: menu)

        // Now that every item is present, the menu's width is final. Replace each
        // provisional item with a custom view that fills that width.
        liveUpdaters.removeAll()
        if !customViews.isEmpty {
            let width = menu.size.width
            for cv in customViews {
                cv.item.title = ""
                let (view, updater) = cv.builder(width)
                cv.item.view = view
                liveUpdaters.append(updater)
            }
        }

        menu.delegate = self
        return menu
    }

    /// Right-click menu: cached settings items plus Quit, nothing dynamic.
    func buildQuickSettingsMenu() -> NSMenu {
        refreshSettingsStates()

        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in cachedSettingsParentItems {
            reuse(item, in: menu)
        }
        menu.addItem(NSMenuItem.separator())
        reuse(cachedQuitItem, in: menu)

        menu.delegate = self
        return menu
    }

    // MARK: - Live Rows

    /// Stores the latest sampled values and reruns every live-row updater.
    /// No-op while no menu is open.
    func refreshLiveRows(cpu: CPUStats, mem: MemoryStats, histories: HistoryBuffers) {
        latestCpu = cpu
        latestMem = mem
        latestHistories = histories
        for updater in liveUpdaters {
            updater()
        }
    }

    public func menuDidClose(_ menu: NSMenu) {
        liveUpdaters.removeAll()
    }

    /// Returns the history buffer backing the selected sparkline metric.
    private func historyValues(for metric: SparklineMetric) -> [Double] {
        switch metric {
        case .cpu: return latestHistories.cpu
        case .ram: return latestHistories.ram
        case .temp: return latestHistories.temp
        case .off: return []
        }
    }

    /// Threshold color for the sparkline's most recent sample.
    private static func sparklineColor(for metric: SparklineMetric, value: Double, isDark: Bool) -> NSColor {
        switch metric {
        case .cpu: return colorForUsage(value, isDark: isDark, metricPrefix: "cpu")
        case .ram: return colorForUsage(value, isDark: isDark, metricPrefix: "mem")
        case .temp: return colorForTemperature(value, isDark: isDark)
        case .off: return .secondaryLabelColor
        }
    }
}
