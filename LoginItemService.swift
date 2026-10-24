import AppKit
import ServiceManagement

// MARK: - Login Item (Model/Service Layer)
// Owns the Launch at Login feature end to end. macOS 13+ uses SMAppService
// exclusively; older systems fall back to a LaunchAgent plist. Only one
// mechanism is ever active at a time (see .agents/memory/bugs.md, 2026-10-14).

/// Manages registration, queries, and cleanup of the app's login item.
enum LoginItemService {
    private static var plistPath: String {
        NSString(string: "~/Library/LaunchAgents/com.giangdq202.memo.plist").expandingTildeInPath
    }

    /// Whether the app is registered to launch at login. Prefers
    /// `SMAppService` on macOS 13+, then falls back to the legacy plist
    /// file, then the persisted flag.
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        if FileManager.default.fileExists(atPath: plistPath) {
            return true
        }
        return UserDefaults.standard.bool(forKey: "LaunchAtLogin")
    }

    /// Registers or unregisters the login item, keeping a single source of
    /// truth on every supported macOS version.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "LaunchAtLogin")

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

    /// Removes every login-item registration. Runs from the early-exit
    /// `--cleanup-login-item` / `--uninstall` CLI paths before the app
    /// finishes launching.
    static func cleanup() {
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
}
