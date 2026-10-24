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

    // History ring buffers for the dropdown sparkline
    private var cpuHistory: [Double] = []
    private var ramHistory: [Double] = []
    private var tempHistory: [Double] = []
    private let historyCapacity = 60

    // MARK: - Wired Dependencies

    /// Single source of truth for user preferences (cached, write-through).
    private let settings = AppSettings.shared
    private lazy var alertCoordinator = AlertCoordinator(settings: settings)
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
        // Skip all SMC work when no temperature consumer is active.
        let needsTemp = settings.showCPUTemperature
            || settings.tempAlertThreshold > 0
            || settings.sparklineMetric == .temp
            || menuFactory.hasLiveMenu

        currentCpuStats = statsEngine.fetchCPUStats(includeTemperature: needsTemp)
        currentMemStats = statsEngine.fetchMemoryStats()

        appendHistory()
        renderCurrentStats()
        alertCoordinator.checkAlerts(
            cpu: currentCpuStats.usagePercent,
            memory: currentMemStats.usedPercent,
            temperature: currentCpuStats.temperature,
            tempUnit: tempUnit
        )
    }

    private func appendHistory() {
        append(currentCpuStats.usagePercent, to: &cpuHistory)
        append(currentMemStats.usedPercent, to: &ramHistory)
        if currentCpuStats.temperature > 0 {
            append(currentCpuStats.temperature, to: &tempHistory)
        }
    }

    /// Appends one sample to a ring buffer capped at `historyCapacity`.
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

        menuFactory.refreshLiveRows(
            cpu: currentCpuStats,
            mem: currentMemStats,
            histories: HistoryBuffers(cpu: cpuHistory, ram: ramHistory, temp: tempHistory)
        )
    }

    // MARK: - Menu Presentation

    private func showMenu() {
        guard let statusItem = statusItem else { return }

        // The dropdown shows temperature clusters even when the menu bar
        // column is off; sample them on demand if the ticks have not yet.
        if currentCpuStats.tempClusters.isEmpty {
            let temp = statsEngine.sampleTemperatures(fullSample: true)
            currentCpuStats.temperature = temp.temperature
            currentCpuStats.tempClusters = temp.clusters
        }

        let menu = menuFactory.buildDropdownMenu(
            cpu: currentCpuStats,
            mem: currentMemStats,
            top: statsEngine.fetchTopProcesses(limit: 3),
            histories: HistoryBuffers(cpu: cpuHistory, ram: ramHistory, temp: tempHistory)
        )

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Right-click opens a compact settings-only menu.
    private func showQuickSettingsMenu() {
        guard let statusItem = statusItem else { return }
        let menu = menuFactory.buildQuickSettingsMenu()
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

    @objc func changeSparklineMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let metric = SparklineMetric(rawValue: raw) else { return }
        settings.sparklineMetric = metric
    }

    @objc func changeCpuAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        settings.cpuAlertThreshold = level
        if level > 0 {
            alertCoordinator.requestAuthorization(onDenied: { [weak self] in
                self?.settings.cpuAlertThreshold = 0
                self?.menuFactory.refreshSettingsStates()
            })
        }
    }

    @objc func changeRamAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        settings.ramAlertThreshold = level
        if level > 0 {
            alertCoordinator.requestAuthorization(onDenied: { [weak self] in
                self?.settings.ramAlertThreshold = 0
                self?.menuFactory.refreshSettingsStates()
            })
        }
    }

    @objc func changeTempAlert(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? Double else { return }
        settings.tempAlertThreshold = level
        if level > 0 {
            alertCoordinator.requestAuthorization(onDenied: { [weak self] in
                self?.settings.tempAlertThreshold = 0
                self?.menuFactory.refreshSettingsStates()
            })
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
