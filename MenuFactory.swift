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

        // Store the parent items in the settings order they appear in the menu.
        cachedSettingsParentItems = [showTempItem, autoStartItem, refreshItem, tempUnitItem]
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
    }

    /// Detaches a cached item from its previous menu (if any) and adds it to the
    /// new menu. NSMenuItem can only belong to one menu at a time.
    private func reuse(_ item: NSMenuItem?, in menu: NSMenu) {
        guard let item = item else { return }
        item.menu?.removeItem(item)
        menu.addItem(item)
    }

    // MARK: - Menu

    /// Builds the one menu the app shows: version header, settings,
    /// Activity Monitor, GitHub, and Quit.
    func buildMenu() -> NSMenu {
        refreshSettingsStates()

        let menu = NSMenu()
        menu.autoenablesItems = false

        reuse(cachedVersionItem, in: menu)
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
