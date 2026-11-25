import Foundation
import ApplicationServices
import Combine

public struct HiDPIResolutionPreset: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let width: Int
    public let height: Int
    public let isHiDPI: Bool

    public static let goldenPresets: [HiDPIResolutionPreset] = [
        HiDPIResolutionPreset(id: "1920x1080_hidpi", label: "1080P",  width: 1920, height: 1080, isHiDPI: true),
        HiDPIResolutionPreset(id: "2304x1296_hidpi", label: "2.3K",   width: 2304, height: 1296, isHiDPI: true),
        HiDPIResolutionPreset(id: "2560x1440_hidpi", label: "2K",     width: 2560, height: 1440, isHiDPI: true),
        HiDPIResolutionPreset(id: "3008x1692_hidpi", label: "3K",     width: 3008, height: 1692, isHiDPI: true),
        HiDPIResolutionPreset(id: "3840x2160_native", label: "4K",    width: 3840, height: 2160, isHiDPI: false)
    ]
}

public final class HiDPIManager: ObservableObject {
    public static let shared = HiDPIManager()

    @Published public var currentWidth: Int = 2560
    @Published public var currentHeight: Int = 1440
    @Published public var currentRefreshRate: Int = 160
    @Published public var isCurrentHiDPI: Bool = true
    @Published public var availableRefreshRates: [Int] = [160, 144, 120, 60]

    private let savedPresetIDKey = "MateView_SavedHiDPIPresetID"
    private let savedRefreshRateKey = "MateView_SavedRefreshRate"

    private init() {
        refreshCurrentMode()
        restoreSavedResolutionIfNeeded()
    }

    /// Restores user's last selected HiDPI resolution & refresh rate automatically on launch / wake
    public func restoreSavedResolutionIfNeeded() {
        guard let savedID = UserDefaults.standard.string(forKey: savedPresetIDKey),
              let preset = HiDPIResolutionPreset.goldenPresets.first(where: { $0.id == savedID }) else {
            return
        }
        let savedHz = UserDefaults.standard.integer(forKey: savedRefreshRateKey)
        let targetHz = savedHz > 0 ? savedHz : currentRefreshRate

        if currentWidth != preset.width || currentHeight != preset.height || isCurrentHiDPI != preset.isHiDPI {
            setDisplayMode(width: preset.width, height: preset.height, hiDPI: preset.isHiDPI, targetHz: targetHz, savePreference: false)
        }
    }

    public func externalDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else {
            return nil
        }
        for i in 0..<Int(displayCount) {
            let dID = displays[i]
            if CGDisplayIsBuiltin(dID) == 0 {
                return dID
            }
        }
        return nil
    }

    public func refreshCurrentMode() {
        guard let dID = externalDisplayID(),
              let mode = CGDisplayCopyDisplayMode(dID) else { return }

        let w = mode.width
        let h = mode.height
        let pw = mode.pixelWidth
        let hz = Int(round(mode.refreshRate))

        DispatchQueue.main.async {
            self.currentWidth = w
            self.currentHeight = h
            self.currentRefreshRate = hz > 0 ? hz : 160
            self.isCurrentHiDPI = (pw > w)
        }
    }

    public func applyResolution(_ preset: HiDPIResolutionPreset, preferredHz: Int? = nil) {
        let targetHz = preferredHz ?? currentRefreshRate
        UserDefaults.standard.set(preset.id, forKey: savedPresetIDKey)
        UserDefaults.standard.set(targetHz, forKey: savedRefreshRateKey)
        setDisplayMode(width: preset.width, height: preset.height, hiDPI: preset.isHiDPI, targetHz: targetHz, savePreference: true)
    }

    public func applyRefreshRate(_ hz: Int) {
        UserDefaults.standard.set(hz, forKey: savedRefreshRateKey)
        setDisplayMode(width: currentWidth, height: currentHeight, hiDPI: isCurrentHiDPI, targetHz: hz, savePreference: true)
    }

    public func setDisplayMode(width: Int, height: Int, hiDPI: Bool, targetHz: Int, savePreference: Bool = true) {
        guard let dID = externalDisplayID() else { return }

        let options: NSDictionary = [kCGDisplayShowDuplicateLowResolutionModes as NSString: NSNumber(value: true)]
        guard let allModes = CGDisplayCopyAllDisplayModes(dID, options as CFDictionary) as? [CGDisplayMode] else {
            return
        }

        // Filter matching width & height & HiDPI status
        let matchingModes = allModes.filter { mode in
            let isModeHiDPI = (mode.pixelWidth > mode.width)
            return mode.width == width && mode.height == height && isModeHiDPI == hiDPI
        }

        // Pick closest refresh rate to targetHz (preferring highest if target not available)
        let bestMode = matchingModes.min { a, b in
            let diffA = abs(Int(round(a.refreshRate)) - targetHz)
            let diffB = abs(Int(round(b.refreshRate)) - targetHz)
            if diffA != diffB {
                return diffA < diffB
            }
            return a.refreshRate > b.refreshRate
        } ?? allModes.first { mode in
            mode.width == width && mode.height == height
        }

        guard let selectedMode = bestMode else { return }

        var configRef: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&configRef) == .success, let config = configRef {
            CGConfigureDisplayWithDisplayMode(config, dID, selectedMode, nil)
            if CGCompleteDisplayConfiguration(config, .forSession) == .success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.refreshCurrentMode()
                }
            } else {
                CGCancelDisplayConfiguration(config)
            }
        }
    }
}
