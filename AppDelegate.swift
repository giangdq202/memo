import AppKit

// MARK: - App Controller
// Owns the model objects (StatsEngine, AppSettings), the status bar view, and
// the update loop. Builds menus through MenuFactory and receives every menu
// action through the MenuActions protocol. No row layout or persistence
// details live here.

public class AppDelegate: NSObject, NSApplicationDelegate, MenuActions {
    private var statusItem: NSStatusItem?
    private var statsView: UnifiedStatsView?

    private let statsEngine = StatsEngine()
    private var timer: Timer?

    private var currentCpuStats = CPUStats()
    private var currentMemStats = MemoryStats()

    // MARK: - Wired Dependencies

    /// Single source of truth for user preferences (cached, write-through).
    private let settings = AppSettings.shared
    private lazy var menuFactory = MenuFactory(settings: settings, actions: self)

    private var tempUnit: String { settings.tempUnit }
    private var showCPUTemperature: Bool { settings.showCPUTemperature }

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from appearing in Dock or Command-Tab switcher
        NSApp.setActivationPolicy(.accessory)

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
        view.onRightClick = { [weak self] in self?.showMenu() }

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
        let interval = settings.updateInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            autoreleasepool {
                self?.updateStats()
            }
        }
        t.tolerance = interval * 0.25
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Update Loop

    private func updateStats() {
        // Skip all SMC work when the temperature column is hidden.
        currentCpuStats = statsEngine.fetchCPUStats(includeTemperature: settings.showCPUTemperature)
        currentMemStats = statsEngine.fetchMemoryStats()

        renderCurrentStats()
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
    }

    // MARK: - Menu Presentation

    /// Left- and right-click both open the same settings menu; the menu bar
    /// numbers are the app's entire dashboard.
    private func showMenu() {
        guard let statusItem = statusItem else { return }
        let menu = menuFactory.buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Re-renders after a display-affecting setting changed (e.g. the
    /// temperature column toggled), sampling sensors on demand so the value
    /// appears immediately instead of showing a transient "--".
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

    // MARK: - Menu Actions (MenuActions)

    private var isLaunchAtLoginEnabled: Bool { LoginItemService.isEnabled }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = !isLaunchAtLoginEnabled
        LoginItemService.setEnabled(enable)
        sender.state = enable ? .on : .off
    }

    @objc func changeInterval(_ sender: NSMenuItem) {
        if let sec = sender.representedObject as? TimeInterval {
            settings.updateInterval = sec
            startTimer()
        }
    }

    @objc func toggleShowTemperature(_ sender: NSMenuItem) {
        settings.showCPUTemperature.toggle()
        updateUIForSettingsChange()
    }

    @objc func changeTempUnit(_ sender: NSMenuItem) {
        if let unit = sender.representedObject as? String {
            settings.tempUnit = unit
            renderCurrentStats()
        }
    }

    @objc func openGitHubPage() {
        if let url = URL(string: "https://github.com/giangdq202/memo") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openActivityMonitor() {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // Fallback to the canonical location on macOS 11+.
            workspace.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
