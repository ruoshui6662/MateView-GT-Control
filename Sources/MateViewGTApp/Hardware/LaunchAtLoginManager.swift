import Foundation
import ServiceManagement
import Combine

/// Manages "Launch at Login" (开机自启) for MateView GT using dual native mechanisms:
/// 1. SMAppService.mainApp (macOS 13+ System Settings -> General -> Login Items)
/// 2. User LaunchAgent plist (`~/Library/LaunchAgents/com.ruoshui.MateViewGT.plist`) so it works reliably
///    even when the app runs from a project directory outside `/Applications`.
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool = false

    private let bundleIdentifier = "com.ruoshui.MateViewGT"
    private let defaultsKey = "MateView_LaunchAtLogin"

    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist", isDirectory: false)
    }

    private var executablePath: String {
        let installedPath = "/Applications/MateView GT Control.app/Contents/MacOS/MateViewGT"
        if FileManager.default.isExecutableFile(atPath: installedPath) {
            return installedPath
        }
        if let execPath = Bundle.main.executablePath,
           FileManager.default.isExecutableFile(atPath: execPath) {
            return execPath
        }
        return "/Users/ruoshui/vibecoding/mateviewGT/MateView GT Control.app/Contents/MacOS/MateViewGT"
    }

    private init() {
        refreshStatus()
        // If user previously enabled Launch at Login, ensure LaunchAgent plist points to current executable path
        if UserDefaults.standard.object(forKey: defaultsKey) != nil {
            let savedPref = UserDefaults.standard.bool(forKey: defaultsKey)
            if savedPref && !isEnabled {
                setEnabled(true)
            }
        }
    }

    public func refreshStatus() {
        let agentExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
        var smEnabled = false
        if #available(macOS 13.0, *) {
            smEnabled = (SMAppService.mainApp.status == .enabled)
        }
        let active = agentExists || smEnabled
        if isEnabled != active {
            isEnabled = active
        }
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)

        if enabled {
            // 1. Write user LaunchAgent plist (guaranteed to work from any folder on macOS)
            do {
                let agentsDir = launchAgentURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

                let plistDict: [String: Any] = [
                    "Label": bundleIdentifier,
                    "ProgramArguments": [executablePath],
                    "RunAtLoad": true,
                    "KeepAlive": false,
                    "ProcessType": "Interactive"
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try data.write(to: launchAgentURL, options: .atomic)
            } catch {
                // Fallback to SMAppService if file write fails
            }

            // 2. Also register with SMAppService if not already enabled and no LaunchAgent conflict
            // Note: To prevent double-launching if both SMAppService and LaunchAgent fire,
            // if LaunchAgent plist succeeded, unregister SMAppService so only one instance launches at login.
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
            } else if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.register()
            }
        } else {
            // Disable both LaunchAgent plist and SMAppService
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try? FileManager.default.removeItem(at: launchAgentURL)
            }
            if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }

        refreshStatus()
    }
}
