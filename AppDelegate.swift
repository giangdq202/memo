import AppKit
import ServiceManagement

public class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statsView: UnifiedStatsView!
    
    private let statsEngine = StatsEngine()
    private var timer: Timer?
    
    private var currentCpuStats = CPUStats()
    private var currentMemStats = MemoryStats()
    private var currentNetStats = NetworkStats()
    
    private var activeMenuUpdaters: [() -> Void] = []

    // Static menu items are built once and reused across menu opens.
    private var cachedVersionItem: NSMenuItem?
    private var cachedActivityItem: NSMenuItem?
    private var cachedShowNetworkItem: NSMenuItem?
    private var cachedShowTemperatureItem: NSMenuItem?
    private var cachedLaunchAtLoginItem: NSMenuItem?
    private var cachedIntervalSubmenu: NSMenu?
    private var cachedTempUnitSubmenu: NSMenu?
    private var cachedNetworkUnitSubmenu: NSMenu?
    private var cachedGitHubItem: NSMenuItem?
    private var cachedQuitItem: NSMenuItem?
    private var cachedSettingsParentItems: [NSMenuItem] = []

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
        
        setupStatusItem()
        startTimer()
        updateStats()
    }


    
    private func setupStatusItem() {
        let statusBar = NSStatusBar.system
        
        let initialWidth = UnifiedStatsView.calculateWidth(showNetwork: showNetworkSpeeds, showTemperature: showCPUTemperature)
        statusItem = statusBar.statusItem(withLength: initialWidth)
        statsView = UnifiedStatsView(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 22))
        statsView.onClick = { [weak self] in self?.showMenu() }
        statsView.onRightClick = { [weak self] in self?.showMenu() }
        
        statsView.showNetwork = showNetworkSpeeds
        statsView.showTemperature = showCPUTemperature
        statsView.networkUnitMode = networkUnitMode
        updateStatusItemWidth()
        
        if let button = statusItem.button {
            button.addSubview(statsView)
            statsView.frame = button.bounds
            statsView.autoresizingMask = [.width, .height]
        }
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
        currentCpuStats = statsEngine.fetchCPUStats()
        currentMemStats = statsEngine.fetchMemoryStats()
        currentNetStats = statsEngine.fetchNetworkStats()
        
        renderCurrentStats()
    }
    
    private func renderCurrentStats() {
        statsView.updateValues(
            cpuPercent: currentCpuStats.usagePercent,
            cpuTemperature: currentCpuStats.temperature,
            tempUnit: tempUnit,
            memGB: currentMemStats.usedGB,
            memPercent: currentMemStats.usedPercent,
            pressureLevel: currentMemStats.pressureLevel,
            uploadBytesPerSec: currentNetStats.uploadBytesPerSec,
            downloadBytesPerSec: currentNetStats.downloadBytesPerSec
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
        let showNetItem = NSMenuItem(title: "Show Network Speeds", action: #selector(toggleShowNetwork(_:)), keyEquivalent: "")
        showNetItem.target = self
        cachedShowNetworkItem = showNetItem

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

        let netUnitSubmenu = NSMenu()
        let netUnits: [(String, NetworkUnitMode)] = [
            ("Auto (B, K, M, G)", .auto),
            ("Binary (B, KiB, MiB, GiB)", .binary),
            ("Decimal (B, KB, MB, GB)", .decimal),
            ("Bits (bps, Kbps, Mbps)", .bits)
        ]
        for (label, mode) in netUnits {
            let item = NSMenuItem(title: label, action: #selector(changeNetworkUnit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            netUnitSubmenu.addItem(item)
        }
        let netUnitItem = NSMenuItem(title: "Network Unit", action: nil, keyEquivalent: "")
        netUnitItem.submenu = netUnitSubmenu
        cachedNetworkUnitSubmenu = netUnitSubmenu

        // Store the parent items in the settings order they appear in the menu.
        cachedSettingsParentItems = [showNetItem, showTempItem, autoStartItem, refreshItem, tempUnitItem, netUnitItem]
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
        cachedShowNetworkItem?.state = showNetworkSpeeds ? .on : .off
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
        if let submenu = cachedNetworkUnitSubmenu {
            for item in submenu.items {
                if let raw = item.representedObject as? Int, let mode = NetworkUnitMode(rawValue: raw) {
                    item.state = (networkUnitMode == mode) ? .on : .off
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

    private func showMenu() {
        buildStaticMenuItems()
        updateStaticMenuStates()

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
            let (view, updateBlock) = Self.progressBarRow(label: "CPU", percent: self.currentCpuStats.usagePercent, valueText: Self.formatCPU(self.currentCpuStats.usagePercent), prefix: "cpu", width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let pct = self.currentCpuStats.usagePercent
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                updateBlock(pct, Self.formatCPU(pct), colorForUsage(pct, isDark: isDark, metricPrefix: "cpu"))
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
            let displayTemp = (t > 0 && self.tempUnit == "F") ? t * 1.8 + 32.0 : t
            let valStr = t > 0 ? String(format: "%.0f°%@", displayTemp, self.tempUnit) : "--"
            let (view, updateBlock) = Self.inlineRow(label: "Temp", valueText: valStr, isTemp: true, tempVal: t, width: width)
            let updater = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                let tNew = self.currentCpuStats.temperature
                let displayTNew = (tNew > 0 && self.tempUnit == "F") ? tNew * 1.8 + 32.0 : tNew
                let newStr = tNew > 0 ? String(format: "%.0f°%@", displayTNew, self.tempUnit) : "--"
                let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let color = (tNew > 0) ? colorForTemperature(tNew, isDark: isDark) : .secondaryLabelColor
                updateBlock(newStr, color)
            }
            return (view, updater)
        }))
        menu.addItem(NSMenuItem.separator())

        // --- Network Summary Section ---
        let netItem = NSMenuItem(title: "en0      ↑ 100.0 MB/s  ↓ 100.0 MB/s", action: nil, keyEquivalent: "")
        netItem.isEnabled = false
        menu.addItem(netItem)
        customViews.append((netItem, { [weak self] width in 
            guard let self = self else { return (NSView(), {}) }
            let (view, updateBlock) = Self.networkRow(interface: self.currentNetStats.activeInterface, upBps: self.currentNetStats.uploadBytesPerSec, downBps: self.currentNetStats.downloadBytesPerSec, width: width, mode: self.networkUnitMode)
            let updater = { [weak self] in
                guard let self = self else { return }
                updateBlock(self.currentNetStats.activeInterface, self.currentNetStats.uploadBytesPerSec, self.currentNetStats.downloadBytesPerSec)
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
                    let displayTemp = (t > 0 && self.tempUnit == "F") ? t * 1.8 + 32.0 : t
                    let valStr = t > 0 ? String(format: "%.0f°%@", displayTemp, self.tempUnit) : "--"
                    
                    let (view, updateBlock) = Self.tempClusterRow(name: cluster.name, valueText: valStr, tempVal: t, width: width)
                    let updater = { [weak self, weak view] in
                        guard let self = self, let view = view else { return }
                        // Find this cluster's updated temperature
                        let newT = self.currentCpuStats.tempClusters.first(where: { $0.name == cluster.name })?.temperature ?? 0.0
                        let displayTNew = (newT > 0 && self.tempUnit == "F") ? newT * 1.8 + 32.0 : newT
                        let newStr = newT > 0 ? String(format: "%.0f°%@", displayTNew, self.tempUnit) : "--"
                        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        let color = (newT > 0) ? colorForTemperature(newT, isDark: isDark) : .secondaryLabelColor
                        updateBlock(newStr, color)
                    }
                    return (view, updater)
                }))
            }
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
                let value = Self.formatCPU(p.cpuPercent)
                let item = Self.provisionalUsageItem(name: p.name, value: value)
                menu.addItem(item)
                customViews.append((item, { w in (Self.usageRowView(name: p.name, value: value, width: w), {}) }))
            }
            menu.addItem(NSMenuItem.separator())
        }
        if !top.byMemory.isEmpty {
            menu.addItem(Self.sectionHeader("Top Memory"))
            for p in top.byMemory {
                let value = Self.formatMemory(p.memoryBytes)
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
    
    private var showNetworkSpeeds: Bool {
        get { UserDefaults.standard.object(forKey: "showNetworkSpeeds") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showNetworkSpeeds"); updateUIForSettingsChange() }
    }
    
    private var showCPUTemperature: Bool {
        get { UserDefaults.standard.object(forKey: "showCPUTemperature") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showCPUTemperature"); updateUIForSettingsChange() }
    }
    
    private var networkUnitMode: NetworkUnitMode {
        get { NetworkUnitMode(rawValue: UserDefaults.standard.integer(forKey: "networkUnitMode")) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "networkUnitMode"); updateUIForSettingsChange() }
    }
    
    @objc private func toggleShowNetwork(_ sender: NSMenuItem) {
        showNetworkSpeeds.toggle()
    }
    
    @objc private func toggleShowTemperature(_ sender: NSMenuItem) {
        showCPUTemperature.toggle()
    }
    
    private func updateUIForSettingsChange() {
        statsView.showNetwork = showNetworkSpeeds
        statsView.showTemperature = showCPUTemperature
        statsView.networkUnitMode = networkUnitMode
        updateStatusItemWidth()
        statsView.needsDisplay = true
    }

    private func updateStatusItemWidth() {
        let width = UnifiedStatsView.calculateWidth(showNetwork: showNetworkSpeeds, showTemperature: showCPUTemperature)
        statusItem.length = width
        statsView.frame.size.width = width
    }
    
    @objc private func changeTempUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? String {
            tempUnit = unit
        }
    }
    
    @objc private func changeNetworkUnit(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? Int, let mode = NetworkUnitMode(rawValue: raw) {
            networkUnitMode = mode
        }
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

    private static func networkRow(interface: String, upBps: Double, downBps: Double, width: CGFloat, mode: NetworkUnitMode) -> (NSView, (String, Double, Double) -> Void) {
        let leftInset: CGFloat = 21
        let rightInset: CGFloat = 21
        let font = NSFont.menuFont(ofSize: 0)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))

        let nameLabel = NSTextField(labelWithString: interface)
        nameLabel.font = font
        nameLabel.textColor = .labelColor
        nameLabel.frame = NSRect(x: leftInset, y: 2, width: 35, height: 16)
        container.addSubview(nameLabel)

        let upParts = formatNetworkSpeed(upBps, mode: mode)
        let upStr = "↑ \(upParts.val) \(upParts.unit)"
        let downParts = formatNetworkSpeed(downBps, mode: mode)
        let downStr = "↓ \(downParts.val) \(downParts.unit)"
        let speedsStr = "\(upStr)   \(downStr)"

        let maxLabelWidth: CGFloat = 160
        let valueLabel = NSTextField(labelWithString: speedsStr)
        valueLabel.font = font
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - rightInset - maxLabelWidth, y: 2, width: maxLabelWidth, height: 16)
        valueLabel.autoresizingMask = [.minXMargin]
        container.addSubview(valueLabel)

        let updater: (String, Double, Double) -> Void = { newIf, newUp, newDown in
            nameLabel.stringValue = newIf
            let newUpParts = formatNetworkSpeed(newUp, mode: mode)
            let newUpStr = "↑ \(newUpParts.val) \(newUpParts.unit)"
            let newDownParts = formatNetworkSpeed(newDown, mode: mode)
            let newDownStr = "↓ \(newDownParts.val) \(newDownParts.unit)"
            valueLabel.stringValue = "\(newUpStr)   \(newDownStr)"
        }
        
        return (container, updater)
    }



    private static func formatCPU(_ percent: Double) -> String {
        return String(format: "%.0f%%", percent)
    }

    private static func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
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
