import AppKit
import ServiceManagement
import UserNotifications

public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var statsView: UnifiedStatsView?
    
    private let statsEngine = StatsEngine()
    private var timer: Timer?
    
    private var currentCpuStats = CPUStats()
    private var currentMemStats = MemoryStats()
    
    private var activeMenuUpdaters: [() -> Void] = []

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

    // Alert submenus and cooldown state
    private var cachedCpuAlertSubmenu: NSMenu?
    private var cachedRamAlertSubmenu: NSMenu?
    private var cachedTempAlertSubmenu: NSMenu?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var lastCpuAlert: CFAbsoluteTime = 0
    private var lastRamAlert: CFAbsoluteTime = 0
    private var lastTempAlert: CFAbsoluteTime = 0
    private let alertCooldown: CFAbsoluteTime = 60.0

    // History buffers for the dropdown sparkline
    private var cpuHistory: [Double] = []
    private var ramHistory: [Double] = []
    private var tempHistory: [Double] = []
    private let historyCapacity = 60
    private var cachedSparklineSubmenu: NSMenu?

    // MARK: - Persisted Settings Helpers

    private var updateInterval: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "updateInterval")
            return val > 0 ? val : 2.0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "updateInterval")
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from appearing in Dock or Command-Tab switcher
        NSApp.setActivationPolicy(.accessory)
        notificationCenter.delegate = self
        
        setupStatusItem()
        startTimer()
        updateStats()
    }


    
    private func setupStatusItem() {
        let statusBar = NSStatusBar.system
        
        let initialWidth = UnifiedStatsView.calculateWidth(showTemperature: showCPUTemperature)
        let item = statusBar.statusItem(withLength: initialWidth)
        let view = UnifiedStatsView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 22))
        view.onClick = { [weak self] in self?.showMenu() }
        view.onRightClick = { [weak self] in self?.showQuickSettingsMenu() }
        
        view.showTemperature = showCPUTemperature
        
        statusItem = item
        statsView = view
        
        if let button = item.button {
            button.addSubview(view)
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
        }
        
        updateStatusItemWidth()
    }
    
    private func startTimer() {
        timer?.invalidate()
        let interval = updateInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            autoreleasepool {
                self?.updateStats()
            }
        }
        t.tolerance = interval * 0.25
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }
    
    private func updateStats() {
        let needsTemp = showCPUTemperature
            || tempAlertThreshold > 0
            || sparklineMetric == .temp
            || !activeMenuUpdaters.isEmpty

        currentCpuStats = statsEngine.fetchCPUStats(includeTemperature: needsTemp)
        currentMemStats = statsEngine.fetchMemoryStats()
        
        appendHistory()
        renderCurrentStats()
        checkAlerts()
    }
    
    private func appendHistory() {
        append(currentCpuStats.usagePercent, to: &cpuHistory)
        append(currentMemStats.usedPercent, to: &ramHistory)
        if currentCpuStats.temperature > 0 {
            append(currentCpuStats.temperature, to: &tempHistory)
        }
    }

    private func append(_ value: Double, to buffer: inout [Double]) {
        buffer.append(value)
        if buffer.count > historyCapacity {
            buffer.removeFirst(buffer.count - historyCapacity)
        }
    }
    
    private func renderCurrentStats() {
        statsView?.updateValues(
            cpuPercent: currentCpuStats.usagePercent,
            cpuTemperature: currentCpuStats.temperature,
            tempUnit: tempUnit,
            memGB: currentMemStats.usedGB,
            memPercent: currentMemStats.usedPercent,
            pressureLevel: currentMemStats.pressureLevel
        )
        
        for updater in activeMenuUpdaters {
            updater()
        }
    }
    
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
        let item = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        item.target = self
        cachedActivityItem = item
    }

    private func buildSettingsItems() {
        let showTempItem = NSMenuItem(title: "Show CPU Temperature", action: #selector(toggleShowTemperature(_:)), keyEquivalent: "")
        showTempItem.target = self
        cachedShowTemperatureItem = showTempItem

        let autoStartItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        autoStartItem.target = self
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
            let item = NSMenuItem(title: label, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sec
            intervalSubmenu.addItem(item)
        }
        let refreshItem = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        refreshItem.submenu = intervalSubmenu
        cachedIntervalSubmenu = intervalSubmenu

        let tempUnitSubmenu = NSMenu()
        for (label, key) in [("Celsius (°C)", "C"), ("Fahrenheit (°F)", "F")] {
            let item = NSMenuItem(title: label, action: #selector(changeTempUnit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            tempUnitSubmenu.addItem(item)
        }
        let tempUnitItem = NSMenuItem(title: "Temperature Unit", action: nil, keyEquivalent: "")
        tempUnitItem.submenu = tempUnitSubmenu
        cachedTempUnitSubmenu = tempUnitSubmenu

        let cpuAlert = makeAlertSubmenu(
            title: "CPU Alerts",
            levels: [("Off", 0.0), ("60%", 60.0), ("70%", 70.0), ("80%", 80.0), ("90%", 90.0), ("95%", 95.0)],
            action: #selector(changeCpuAlert(_:)))
        cachedCpuAlertSubmenu = cpuAlert.submenu

        let ramAlert = makeAlertSubmenu(
            title: "RAM Alerts",
            levels: [("Off", 0.0), ("70%", 70.0), ("80%", 80.0), ("85%", 85.0), ("90%", 90.0), ("95%", 95.0)],
            action: #selector(changeRamAlert(_:)))
        cachedRamAlertSubmenu = ramAlert.submenu

        let tempAlert = makeAlertSubmenu(
            title: "Temperature Alerts",
            levels: [("Off", 0.0), ("70°C", 70.0), ("80°C", 80.0), ("90°C", 90.0), ("100°C", 100.0)],
            action: #selector(changeTempAlert(_:)))
        cachedTempAlertSubmenu = tempAlert.submenu

        let sparklineSubmenu = NSMenu()
        let sparklineOptions: [(String, SparklineMetric)] = [
            ("Off", .off), ("CPU", .cpu), ("RAM", .ram), ("Temperature", .temp)
        ]
        for (label, metric) in sparklineOptions {
            let item = NSMenuItem(title: label, action: #selector(changeSparklineMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            sparklineSubmenu.addItem(item)
        }
        let sparklineItem = NSMenuItem(title: "History Graph", action: nil, keyEquivalent: "")
        sparklineItem.submenu = sparklineSubmenu
        cachedSparklineSubmenu = sparklineSubmenu

        // Store the parent items in the settings order they appear in the menu.
        cachedSettingsParentItems = [showTempItem, autoStartItem, refreshItem, tempUnitItem,
                                     cpuAlert.parent, ramAlert.parent, tempAlert.parent, sparklineItem]
    }

    /// Builds a submenu of alert threshold choices. A level of `0.0` means off.
    private func makeAlertSubmenu(title: String, levels: [(String, Double)], action: Selector) -> (parent: NSMenuItem, submenu: NSMenu) {
        let submenu = NSMenu()
        for (label, level) in levels {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = level
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return (parent, submenu)
    }

    private func buildFooterItems() {
        let githubItem = NSMenuItem(title: "GitHub Repository", action: #selector(openGitHubPage), keyEquivalent: "")
        githubItem.target = self
        cachedGitHubItem = githubItem

        let quitItem = NSMenuItem(title: "Quit MeMo", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        cachedQuitItem = quitItem
    }

    private func buildStaticMenuItems() {
        guard cachedVersionItem == nil else { return }
        buildAboutItem()
        buildActivityItem()
        buildSettingsItems()
        buildFooterItems()
    }

    private func updateStaticMenuStates() {
        cachedShowTemperatureItem?.state = showCPUTemperature ? .on : .off
        cachedLaunchAtLoginItem?.state = isLaunchAtLoginEnabled ? .on : .off

        if let submenu = cachedIntervalSubmenu {
            for item in submenu.items {
                if let sec = item.representedObject as? TimeInterval {
                    item.state = (updateInterval == sec) ? .on : .off
                }
            }
        }
        if let submenu = cachedTempUnitSubmenu {
            for item in submenu.items {
                if let key = item.representedObject as? String {
                    item.state = (tempUnit == key) ? .on : .off
                }
            }
        }

        updateAlertSubmenuState(cachedCpuAlertSubmenu, selectedLevel: cpuAlertThreshold)
        updateAlertSubmenuState(cachedRamAlertSubmenu, selectedLevel: ramAlertThreshold)
        updateAlertSubmenuState(cachedTempAlertSubmenu, selectedLevel: tempAlertThreshold)

        let selectedSparkline = sparklineMetric
        if let submenu = cachedSparklineSubmenu {
            for item in submenu.items {
                if let raw = item.representedObject as? String {
                    item.state = (selectedSparkline.rawValue == raw) ? .on : .off
                }
            }
        }
    }

    private func updateAlertSubmenuState(_ submenu: NSMenu?, selectedLevel: Double) {
        guard let submenu = submenu else { return }
        for item in submenu.items {
            if let level = item.representedObject as? Double {
                item.state = (selectedLevel == level) ? .on : .off
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

    private func showMenu() {
        guard let statusItem = statusItem else { return }
        buildStaticMenuItems()
        updateStaticMenuStates()

        if currentCpuStats.tempClusters.isEmpty {
            let temp = statsEngine.sampleTemperatures(fullSample: true)
            currentCpuStats.temperature = temp.temperature
            currentCpuStats.tempClusters = temp.clusters
        }

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
            let (view, updateBlock) = Self.progressBarRow(label: "CPU", percent: self.currentCpuStats.usagePercent, valueText: formatCPU(self.currentCpuStats.usagePercent), prefix: "cpu", width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let pct = self.currentCpuStats.usagePercent
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
            let valStr = String(format: "%.1f/%.0f GB", self.currentMemStats.usedGB, self.currentMemStats.totalGB)
            let (view, updateBlock) = Self.progressBarRow(label: "RAM", percent: self.currentMemStats.usedPercent, valueText: valStr, prefix: "mem", width: width, pressureLevel: self.currentMemStats.pressureLevel)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let pct = self.currentMemStats.usedPercent
                let pressure = self.currentMemStats.pressureLevel
                let newStr = String(format: "%.1f/%.0f GB", self.currentMemStats.usedGB, self.currentMemStats.totalGB)
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
            let t = self.currentCpuStats.temperature
            let valStr = formatTemperature(t, unit: self.tempUnit)
            let (view, updateBlock) = Self.inlineRow(label: "Temp", valueText: valStr, isTemp: true, tempVal: t, width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let tNew = self.currentCpuStats.temperature
                let newStr = formatTemperature(tNew, unit: self.tempUnit)
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let color = (tNew > 0) ? colorForTemperature(tNew, isDark: isDark) : .secondaryLabelColor
                updateBlock(newStr, color)
            }
            return (view, updater)
        }))
        menu.addItem(NSMenuItem.separator())

        // --- Temperatures Section ---
        if !self.currentCpuStats.tempClusters.isEmpty {
            menu.addItem(Self.sectionHeader("Temperatures"))
            for cluster in self.currentCpuStats.tempClusters {
                let item = NSMenuItem(title: "\(cluster.name)    \(String(format: "%.0f°C", cluster.temperature))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
                
                customViews.append((item, { [weak self] width in
                    guard let self = self else { return (NSView(), {}) }
                    let t = cluster.temperature
                    let valStr = formatTemperature(t, unit: self.tempUnit)
                    
                    let (view, updateBlock) = Self.tempClusterRow(name: cluster.name, valueText: valStr, tempVal: t, width: width)
                    let updater = { [weak self, weak view] in
                        guard let self = self, let view = view else { return }
                        // Find this cluster's updated temperature
                        let newT = self.currentCpuStats.tempClusters.first(where: { $0.name == cluster.name })?.temperature ?? 0.0
                        let newStr = formatTemperature(newT, unit: self.tempUnit)
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
        let sparkline = sparklineMetric
        if sparkline != .off {
            menu.addItem(Self.sectionHeader("History"))
            let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
            historyItem.isEnabled = false
            menu.addItem(historyItem)
            customViews.append((historyItem, { [weak self] width in
                guard let self = self else { return (NSView(), {}) }
                let view = SparklineView(frame: NSRect(x: 0, y: 0, width: width, height: 40))
                let values = self.historyValues(for: sparkline)
                view.values = values
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                view.lineColor = self.sparklineColor(for: sparkline, value: values.last ?? 0.0, isDark: isDark)
                let updater = { [weak self, weak view] in
                    guard let self = self, let view = view else { return }
                    let newValues = self.historyValues(for: sparkline)
                    view.values = newValues
                    let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    view.lineColor = self.sparklineColor(for: sparkline, value: newValues.last ?? 0.0, isDark: dark)
                    view.needsDisplay = true
                }
                return (view, updater)
            }))
            menu.addItem(NSMenuItem.separator())
        }

        // --- Top Processes Section ---
        // Fetched fresh on open; excludes system daemons and rolls helpers into their app.
        // Rows start as plain items so the menu can compute its natural width; below
        // we swap in width-filling views that right-align the value flush to that width.
        let top = statsEngine.fetchTopProcesses(limit: 3)
        if !top.byCPU.isEmpty {
            menu.addItem(Self.sectionHeader("Top CPU"))
            for p in top.byCPU {
                let value = formatCPU(p.cpuPercent)
                let item = Self.provisionalUsageItem(name: p.name, value: value)
                menu.addItem(item)
                customViews.append((item, { w in (Self.usageRowView(name: p.name, value: value, width: w), {}) }))
            }
            menu.addItem(NSMenuItem.separator())
        }
        if !top.byMemory.isEmpty {
            menu.addItem(Self.sectionHeader("Top Memory"))
            for p in top.byMemory {
                let value = formatMemory(p.memoryBytes)
                let item = Self.provisionalUsageItem(name: p.name, value: value)
                menu.addItem(item)
                customViews.append((item, { w in (Self.usageRowView(name: p.name, value: value, width: w), {}) }))
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
        activeMenuUpdaters.removeAll()
        if !customViews.isEmpty {
            let width = menu.size.width
            for cv in customViews {
                cv.item.title = ""
                let (view, updater) = cv.builder(width)
                cv.item.view = view
                activeMenuUpdaters.append(updater)
            }
        }

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Right-click opens a compact settings-only menu that reuses the cached
    /// settings items and the Quit item.
    private func showQuickSettingsMenu() {
        guard let statusItem = statusItem else { return }
        buildStaticMenuItems()
        updateStaticMenuStates()

        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in cachedSettingsParentItems {
            reuse(item, in: menu)
        }
        menu.addItem(NSMenuItem.separator())
        reuse(cachedQuitItem, in: menu)

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    public func menuDidClose(_ menu: NSMenu) {
        activeMenuUpdaters.removeAll()
    }
    
    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled { return true }
        }
        
        let plistPath = NSString(string: "~/Library/LaunchAgents/com.giangdq202.memo.plist").expandingTildeInPath
        if FileManager.default.fileExists(atPath: plistPath) {
            return true
        }
        
        return UserDefaults.standard.bool(forKey: "LaunchAtLogin")
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = !isLaunchAtLoginEnabled
        setLaunchAtLogin(enabled: enable)
        sender.state = enable ? .on : .off
    }
    
    public static func cleanupLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("--> Unregistered SMAppService mainApp login item.")
                }
            } catch {
                print("--> Failed to unregister SMAppService mainApp: \(error)")
            }
        }
        
        let plistPath = NSString(string: "~/Library/LaunchAgents/com.giangdq202.memo.plist").expandingTildeInPath
        let uid = getuid()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(uid)", plistPath]
        try? process.run()
        process.waitUntilExit()
        
        if FileManager.default.fileExists(atPath: plistPath) {
            try? FileManager.default.removeItem(atPath: plistPath)
            print("--> Removed LaunchAgent plist: \(plistPath)")
        }
        
        UserDefaults.standard.removeObject(forKey: "LaunchAtLogin")
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "LaunchAtLogin")
        let plistPath = NSString(string: "~/Library/LaunchAgents/com.giangdq202.memo.plist").expandingTildeInPath
        
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                    // Clean up legacy LaunchAgent plist if present to avoid duplicate launch
                    if FileManager.default.fileExists(atPath: plistPath) {
                        try? FileManager.default.removeItem(atPath: plistPath)
                    }
                    return
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("SMAppService toggle failed, using LaunchAgent fallback: \(error)")
            }
        }
        if enabled {
            let execPath = Bundle.main.bundlePath.hasSuffix(".app")
                ? "\(Bundle.main.bundlePath)/Contents/MacOS/MeMo"
                : "/Applications/MeMo.app/Contents/MacOS/MeMo"
            
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.giangdq202.memo</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            
            do {
                let launchAgentsDir = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
                try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
                try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write LaunchAgent plist: \(error)")
            }
        } else {
            let uid = getuid()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(uid)", plistPath]
            try? process.run()
            process.waitUntilExit()
            
            if FileManager.default.fileExists(atPath: plistPath) {
                try? FileManager.default.removeItem(atPath: plistPath)
            }
        }
    }
    
    @objc private func changeInterval(_ sender: NSMenuItem) {
        if let sec = sender.representedObject as? TimeInterval {
            updateInterval = sec
            startTimer()
        }
    }
    
    private var tempUnit: String {
        get {
            return UserDefaults.standard.string(forKey: "tempUnit") ?? "C"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "tempUnit")
            renderCurrentStats()
        }
    }
    
    private var showCPUTemperature: Bool {
        get { UserDefaults.standard.object(forKey: "showCPUTemperature") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showCPUTemperature"); updateUIForSettingsChange() }
    }
    
    @objc private func toggleShowTemperature(_ sender: NSMenuItem) {
        showCPUTemperature.toggle()
    }
    
    private func updateUIForSettingsChange() {
        if showCPUTemperature && currentCpuStats.temperature <= 0 {
            let temp = statsEngine.sampleTemperatures(fullSample: true)
            currentCpuStats.temperature = temp.temperature
            currentCpuStats.tempClusters = temp.clusters
        }
        statsView?.showTemperature = showCPUTemperature
        updateStatusItemWidth()
        renderCurrentStats()
        statsView?.needsDisplay = true
    }

    private func updateStatusItemWidth() {
        guard let statusItem = statusItem, let statsView = statsView else { return }
        let width = UnifiedStatsView.calculateWidth(showTemperature: showCPUTemperature)
        statusItem.length = width
        statsView.frame.size.width = width
    }
    
    @objc private func changeTempUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? String {
            tempUnit = unit
        }
    }
    
    // MARK: - Alert Settings

    private var cpuAlertThreshold: Double {
        get { UserDefaults.standard.double(forKey: "cpuAlertThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "cpuAlertThreshold") }
    }

    private var ramAlertThreshold: Double {
        get { UserDefaults.standard.double(forKey: "ramAlertThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "ramAlertThreshold") }
    }

    private var tempAlertThreshold: Double {
        get { UserDefaults.standard.double(forKey: "tempAlertThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "tempAlertThreshold") }
    }

    private var sparklineMetric: SparklineMetric {
        get {
            let raw = UserDefaults.standard.string(forKey: "sparklineMetric") ?? SparklineMetric.off.rawValue
            return SparklineMetric(rawValue: raw) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "sparklineMetric") }
    }

    private func historyValues(for metric: SparklineMetric) -> [Double] {
        switch metric {
        case .cpu: return cpuHistory
        case .ram: return ramHistory
        case .temp: return tempHistory
        case .off: return []
        }
    }

    private func sparklineColor(for metric: SparklineMetric, value: Double, isDark: Bool) -> NSColor {
        switch metric {
        case .cpu: return colorForUsage(value, isDark: isDark, metricPrefix: "cpu")
        case .ram: return colorForUsage(value, isDark: isDark, metricPrefix: "mem")
        case .temp: return colorForTemperature(value, isDark: isDark)
        case .off: return .secondaryLabelColor
        }
    }

    @objc private func changeSparklineMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let metric = SparklineMetric(rawValue: raw) else { return }
        sparklineMetric = metric
    }

    @objc private func changeCpuAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        cpuAlertThreshold = level
        if level > 0 {
            requestNotificationPermission { [weak self] in
                self?.cpuAlertThreshold = 0
                self?.updateStaticMenuStates()
            }
        }
    }

    @objc private func changeRamAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        ramAlertThreshold = level
        if level > 0 {
            requestNotificationPermission { [weak self] in
                self?.ramAlertThreshold = 0
                self?.updateStaticMenuStates()
            }
        }
    }

    @objc private func changeTempAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        tempAlertThreshold = level
        if level > 0 {
            requestNotificationPermission { [weak self] in
                self?.tempAlertThreshold = 0
                self?.updateStaticMenuStates()
            }
        }
    }

    private func checkAlerts() {
        let now = CFAbsoluteTimeGetCurrent()

        let cpu = currentCpuStats.usagePercent
        let cpuThreshold = cpuAlertThreshold
        if cpuThreshold > 0 && cpu >= cpuThreshold && now - lastCpuAlert >= alertCooldown {
            lastCpuAlert = now
            postAlert(title: "High CPU Usage",
                      body: "CPU is at \(String(format: "%.0f", cpu))% (limit \(String(format: "%.0f", cpuThreshold))%).")
        }

        let ram = currentMemStats.usedPercent
        let ramThreshold = ramAlertThreshold
        if ramThreshold > 0 && ram >= ramThreshold && now - lastRamAlert >= alertCooldown {
            lastRamAlert = now
            postAlert(title: "High Memory Usage",
                      body: "Memory is at \(String(format: "%.0f", ram))% (limit \(String(format: "%.0f", ramThreshold))%).")
        }

        let temp = currentCpuStats.temperature
        let tempThreshold = tempAlertThreshold
        if tempThreshold > 0 && temp > 0 && temp >= tempThreshold && now - lastTempAlert >= alertCooldown {
            lastTempAlert = now
            let display = formatTemperature(temp, unit: tempUnit)
            postAlert(title: "High CPU Temperature",
                      body: "CPU temperature is \(display) (limit \(String(format: "%.0f", tempThreshold))°C).")
        }
    }

    private func postAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter.add(request)
    }

    private func requestNotificationPermission(onDenied rollback: @escaping () -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard !granted else { return }
            DispatchQueue.main.async { rollback() }
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    @objc private func openGitHubPage() {
        if let url = URL(string: "https://github.com/giangdq202/memo") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openActivityMonitor() {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // Fallback to the canonical location on macOS 11+.
            workspace.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Top Processes menu rendering

    private static func sectionHeader(_ title: String) -> NSMenuItem {
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
    private static func provisionalUsageItem(name: String, value: String) -> NSMenuItem {
        let display = name.count > 28 ? String(name.prefix(27)) + "…" : name
        let item = NSMenuItem(title: "\(display)    \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A non-interactive row that fills the menu's full `width`: app name on the
    /// left (truncated to fit), value flush to the right edge. Filling the width
    /// is what removes the trailing empty space a fixed tab stop would leave.
    private static func usageRowView(name: String, value: String, width: CGFloat) -> NSView {
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

    private static func tempClusterRow(name: String, valueText: String, tempVal: Double, width: CGFloat) -> (NSView, (String, NSColor) -> Void) {
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

    private static func progressBarRow(label: String, percent: Double, valueText: String, prefix: String, width: CGFloat, pressureLevel: Int = 0) -> (NSView, (Double, String, NSColor) -> Void) {
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

    private static func inlineRow(label: String, valueText: String, isTemp: Bool, tempVal: Double, width: CGFloat) -> (NSView, (String, NSColor) -> Void) {
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

class ProgressBarView: NSView {
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
