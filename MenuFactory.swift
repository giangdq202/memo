import AppKit

// MARK: - Menu Factory (Controller Layer — View Assembly)
// Builds the single settings menu shown on left- or right-click. Every item
// is built once and reused; there is nothing dynamic left to update.

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
    func changeMenuBarLayout(_ sender: NSMenuItem)
    func changeRamDisplayMode(_ sender: NSMenuItem)
}

/// Assembles the menu the status item shows on click (left or right).
final class MenuFactory {
    private let settings: AppSettings
    private weak var actions: MenuActions?

    // Menu items are built once and reused across opens.
    private var cachedVersionItem: NSMenuItem?
    private var cachedActivityItem: NSMenuItem?
    private var cachedShowTemperatureItem: NSMenuItem?
    private var cachedLaunchAtLoginItem: NSMenuItem?
    private var cachedIntervalSubmenu: NSMenu?
    private var cachedTempUnitSubmenu: NSMenu?
    private var cachedLayoutSubmenu: NSMenu?
    private var cachedRamDisplaySubmenu: NSMenu?
    private var cachedGitHubItem: NSMenuItem?
    private var cachedQuitItem: NSMenuItem?
    private var cachedSettingsParentItems: [NSMenuItem] = []

    /// - Parameters:
    ///   - settings: source of the values the menu checkmarks reflect.
    ///   - actions: receiver for every menu item action (held weakly).
    init(settings: AppSettings, actions: MenuActions) {
        self.settings = settings
        self.actions = actions
    }

    // MARK: - Item Builders

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

        let layoutSubmenu = NSMenu()
        for (label, layout) in [("Single Line", MenuBarLayout.single.rawValue), ("Two Lines", MenuBarLayout.stacked.rawValue)] {
            let item = NSMenuItem(title: label, action: #selector(MenuActions.changeMenuBarLayout(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = layout
            layoutSubmenu.addItem(item)
        }
        let layoutItem = NSMenuItem(title: "Menu Bar Layout", action: nil, keyEquivalent: "")
        layoutItem.submenu = layoutSubmenu
        cachedLayoutSubmenu = layoutSubmenu

        let ramSubmenu = NSMenu()
        for (label, mode) in [("Gigabytes (GB)", "gb"), ("Percentage (%)", "percent")] {
            let item = NSMenuItem(title: label, action: #selector(MenuActions.changeRamDisplayMode(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = mode
            ramSubmenu.addItem(item)
        }
        let ramItem = NSMenuItem(title: "RAM Display Mode", action: nil, keyEquivalent: "")
        ramItem.submenu = ramSubmenu
        cachedRamDisplaySubmenu = ramSubmenu

        // Store the parent items in the settings order they appear in the menu.
        cachedSettingsParentItems = [showTempItem, autoStartItem, refreshItem, tempUnitItem, layoutItem, ramItem]
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
        if let submenu = cachedLayoutSubmenu {
            for item in submenu.items {
                if let raw = item.representedObject as? String {
                    item.state = (settings.menuBarLayout.rawValue == raw) ? .on : .off
                }
            }
        }
        if let submenu = cachedRamDisplaySubmenu {
            for item in submenu.items {
                if let mode = item.representedObject as? String {
                    item.state = (settings.ramDisplayMode == mode) ? .on : .off
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

    // MARK: - Menu

    /// Builds the one menu the app shows: version header, telemetry summary,
    /// settings, Activity Monitor, GitHub, and Quit.
    func buildMenu(cpuStats: CPUStats? = nil, memStats: MemoryStats? = nil) -> NSMenu {
        refreshSettingsStates()

        let menu = NSMenu()
        menu.autoenablesItems = false

        reuse(cachedVersionItem, in: menu)

        // Telemetry summary rows (clean, disabled items displaying live metrics)
        if let cpu = cpuStats, let mem = memStats {
            menu.addItem(NSMenuItem.separator())

            let summaryFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: summaryFont
            ]

            let cpuLine = "CPU: \(Int(cpu.usagePercent.rounded()))% · User: \(Int(cpu.userPercent.rounded()))% · System: \(Int(cpu.systemPercent.rounded()))%"
            let cpuItem = NSMenuItem(title: cpuLine, action: nil, keyEquivalent: "")
            cpuItem.isEnabled = false
            cpuItem.attributedTitle = NSAttributedString(string: cpuLine, attributes: attrs)
            menu.addItem(cpuItem)

            let memLine = "RAM: \(String(format: "%.1f", mem.usedGB)) / \(String(format: "%.1f", mem.totalGB)) GB (\(Int(mem.usedPercent.rounded()))%)"
            let memItem = NSMenuItem(title: memLine, action: nil, keyEquivalent: "")
            memItem.isEnabled = false
            memItem.attributedTitle = NSAttributedString(string: memLine, attributes: attrs)
            menu.addItem(memItem)

            let thermalLine: String
            if cpu.temperature > 0 {
                let tempStr = formatTemperatureValue(cpu.temperature, unit: settings.tempUnit) + "°" + settings.tempUnit
                thermalLine = "Temp: \(tempStr) · Thermal: \(cpu.thermalStateDescription)"
            } else {
                thermalLine = "Thermal Pressure: \(cpu.thermalStateDescription)"
            }
            let thermalItem = NSMenuItem(title: thermalLine, action: nil, keyEquivalent: "")
            thermalItem.isEnabled = false
            thermalItem.attributedTitle = NSAttributedString(string: thermalLine, attributes: attrs)
            menu.addItem(thermalItem)
        }

        menu.addItem(NSMenuItem.separator())

        for item in cachedSettingsParentItems {
            reuse(item, in: menu)
        }
        menu.addItem(NSMenuItem.separator())

        reuse(cachedActivityItem, in: menu)
        reuse(cachedGitHubItem, in: menu)
        menu.addItem(NSMenuItem.separator())

        reuse(cachedQuitItem, in: menu)
        return menu
    }
}
