import UserNotifications

// MARK: - Alerts (Controller Layer)
// Owns threshold notifications end to end: permission requests, cooldown
// tracking, and banner presentation. Reads thresholds from AppSettings and
// is handed plain metric values on each tick.

/// Posts high-usage notifications for CPU, memory, and temperature metrics,
/// each rate-limited by a cooldown so a sustained high value does not spam.
final class AlertCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let settings: AppSettings
    private let notificationCenter = UNUserNotificationCenter.current()

    private var lastCpuAlert: CFAbsoluteTime = 0
    private var lastRamAlert: CFAbsoluteTime = 0
    private var lastTempAlert: CFAbsoluteTime = 0
    private let alertCooldown: CFAbsoluteTime = 60.0

    /// - Parameter settings: source of the alert thresholds (0 disables a metric).
    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        notificationCenter.delegate = self
    }

    /// Checks the latest metric values against their thresholds and posts one
    /// notification per metric that crosses its limit and has exited cooldown.
    /// - Parameters:
    ///   - cpu: CPU usage percent.
    ///   - memory: Memory usage percent.
    ///   - temperature: CPU temperature in Celsius (0 means no sensor value).
    ///   - tempUnit: Display unit ("C" or "F") used in the message body.
    func checkAlerts(cpu: Double, memory: Double, temperature: Double, tempUnit: String) {
        let now = CFAbsoluteTimeGetCurrent()

        let cpuThreshold = settings.cpuAlertThreshold
        if cpuThreshold > 0 && cpu >= cpuThreshold && now - lastCpuAlert >= alertCooldown {
            lastCpuAlert = now
            postAlert(title: "High CPU Usage",
                      body: "CPU is at \(String(format: "%.0f", cpu))% (limit \(String(format: "%.0f", cpuThreshold))%).")
        }

        let ramThreshold = settings.ramAlertThreshold
        if ramThreshold > 0 && memory >= ramThreshold && now - lastRamAlert >= alertCooldown {
            lastRamAlert = now
            postAlert(title: "High Memory Usage",
                      body: "Memory is at \(String(format: "%.0f", memory))% (limit \(String(format: "%.0f", ramThreshold))%).")
        }

        let tempThreshold = settings.tempAlertThreshold
        if tempThreshold > 0 && temperature > 0 && temperature >= tempThreshold && now - lastTempAlert >= alertCooldown {
            lastTempAlert = now
            let display = formatTemperature(temperature, unit: tempUnit)
            postAlert(title: "High CPU Temperature",
                      body: "CPU temperature is \(display) (limit \(String(format: "%.0f", tempThreshold))°C).")
        }
    }

    /// Presents a notification request immediately with the default sound.
    private func postAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter.add(request)
    }

    /// Requests notification permission, invoking `onDenied` on the main
    /// queue when the user declines so the caller can roll back the setting.
    func requestAuthorization(onDenied: @escaping () -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard !granted else { return }
            DispatchQueue.main.async { onDenied() }
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
