import Foundation
import Combine
import AppKit

/// Hardware Color Temperature modes supported by Huawei MateView GT 2026 (VCP 0x14)
public enum HardwareColorTemp: UInt16, CaseIterable, Identifiable {
    case warm6500K = 0x05
    case standard  = 0x06
    case cool9300K = 0x08
    case customRGB = 0x0B

    public var id: UInt16 { rawValue }

    public var title: String {
        switch self {
        case .warm6500K: return "暖色 6500K"
        case .standard:  return "标准色温"
        case .cool9300K: return "冷色 9300K"
        case .customRGB: return "自定义 RGB"
        }
    }

    public var shortTitle: String {
        switch self {
        case .warm6500K: return "暖色"
        case .standard:  return "标准"
        case .cool9300K: return "冷色"
        case .customRGB: return "自定义"
        }
    }

    public var iconName: String {
        switch self {
        case .warm6500K: return "sun.dust.fill"
        case .standard:  return "circle.lefthalf.filled"
        case .cool9300K: return "snowflake"
        case .customRGB: return "slider.horizontal.3"
        }
    }
}

/// High-frequency Color & Reading Presets for MateView GT 2026
public enum MateViewPresetMode: String, CaseIterable, Identifiable, Codable {
    case p3         = "p3"
    case srgb       = "srgb"
    case ebookBW    = "ebook_bw"
    case ebookColor = "ebook_color"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .p3:         return "P3 广色域"
        case .srgb:       return "sRGB 标准"
        case .ebookBW:    return "电子书 · 黑白"
        case .ebookColor: return "电子书 · 彩墨"
        }
    }

    public var subtitle: String {
        switch self {
        case .p3:         return "原彩 100% · 标准色温"
        case .srgb:       return "网页/设计 · 6500K"
        case .ebookBW:    return "0 饱和纯墨水 · 类纸护眼"
        case .ebookColor: return "柔和彩墨绘本 · 暖纸感"
        }
    }

    public var iconName: String {
        switch self {
        case .p3:         return "paintpalette.fill"
        case .srgb:       return "display"
        case .ebookBW:    return "book.closed.fill"
        case .ebookColor: return "text.book.closed.fill"
        }
    }

    /// Default hardware parameters (Saturation 0..20, Contrast 0..100, Sharpness 0..100, ColorTemp VCP 0x14)
    public var defaultParameters: ModeImageTuning {
        switch self {
        case .p3:
            return ModeImageTuning(saturation: 10, contrast: 50, sharpness: 50, colorTempRaw: HardwareColorTemp.standard.rawValue)
        case .srgb:
            return ModeImageTuning(saturation: 9, contrast: 50, sharpness: 50, colorTempRaw: HardwareColorTemp.warm6500K.rawValue)
        case .ebookBW:
            return ModeImageTuning(saturation: 0, contrast: 42, sharpness: 58, colorTempRaw: HardwareColorTemp.warm6500K.rawValue)
        case .ebookColor:
            return ModeImageTuning(saturation: 6, contrast: 45, sharpness: 55, colorTempRaw: HardwareColorTemp.warm6500K.rawValue)
        }
    }
}

/// Per-mode customizable hardware image tuning (#3 Extension)
public struct ModeImageTuning: Codable, Equatable {
    public var saturation: Int   // Ext 0xF8E157: 0 (B&W) .. 10 (Std) .. 20 (Vivid)
    public var contrast: Int     // Std 0x12: 0 .. 100
    public var sharpness: Int    // Std 0x87: 0 .. 100
    public var colorTempRaw: UInt16
}

/// Quick Nits Preset (#1 Extension)
public struct NitsQuickPreset: Identifiable, Equatable {
    public let id: Int
    public let label: String
    public let icon: String
    public let targetNits: Int
    public let brightnessPercent: Int

    public static let allPresets: [NitsQuickPreset] = [
        NitsQuickPreset(id: 0, label: "夜间", icon: "moon.stars.fill", targetNits: 80,  brightnessPercent: 11),
        NitsQuickPreset(id: 1, label: "阅读", icon: "book.fill",       targetNits: 180, brightnessPercent: 35),
        NitsQuickPreset(id: 2, label: "办公", icon: "laptopcomputer",  targetNits: 280, brightnessPercent: 59),
        NitsQuickPreset(id: 3, label: "峰值", icon: "sun.max.fill",    targetNits: 450, brightnessPercent: 100)
    ]
}

/// Auto Power-Off Timer Options for IPS Backlight Lifespan Protection
public enum AutoPowerOffInterval: Int, CaseIterable, Identifiable {
    case off   = 0
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case min60 = 60

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .off:   return "关"
        case .min15: return "15m"
        case .min30: return "30m"
        case .min45: return "45m"
        case .min60: return "60m"
        }
    }
}

/// Future expansion protocol for MacBook Air internal display & audio fusion
public protocol InternalDisplayControllable {
    var isAvailable: Bool { get }
    func getInternalBrightness() -> Int
    func setInternalBrightness(_ value: Int)
}

/// Main Hardware Controller for Huawei MateView GT 2026 (QSN-CBB)
public final class HuaweiDDCEngine: ObservableObject {
    public static let shared = HuaweiDDCEngine()

    // MARK: - Published Hardware State
    @Published public var isConnected: Bool = true
    @Published public var modelName: String = "QSN-CBB"
    @Published public var usageHours: Int = 7

    /// Brightness 0 - 100 (VCP 0x10)
    @Published public var brightness: Int = 75
    /// Speaker Volume 0 - 100 (VCP 0x62)
    @Published public var volume: Int = 18
    /// Speaker Hardware Mute (VCP 0x8D: 1=Mute, 2=Unmute)
    @Published public var isMuted: Bool = false

    // MARK: - MacBook Air Built-in Display & Audio Output Detection
    @Published public var hasMacBookDisplay: Bool = true
    /// MacBook Air built-in display brightness 0 - 100 (DisplayServices)
    @Published public var macBookBrightness: Int = 63
    /// True if default macOS audio output is MateView GT (QSN-CBB), false if MacBook Air speaker / headphones
    @Published public var isAudioRoutedToMonitor: Bool = true
    @Published public var activeAudioDeviceName: String = "MateView GT"
    /// MacBook Air / System Audio Volume 0 - 100 (CoreAudio)
    @Published public var macBookVolume: Int = 44
    @Published public var isMacBookMuted: Bool = false

    /// Current Active Color / eBook Mode
    @Published public var activePreset: MateViewPresetMode = .p3

    /// Hardware Color Temperature (VCP 0x14)
    @Published public var colorTemp: HardwareColorTemp = .standard
    /// Custom RGB Gains 0 - 100 (VCP 0x16, 0x18, 0x1A)
    @Published public var redGain: Int = 100
    @Published public var greenGain: Int = 100
    @Published public var blueGain: Int = 100

    /// Image Tuning (#3 Extension: Saturation 0-20, Contrast 0-100, Sharpness 0-100)
    @Published public var saturation: Int = 10
    @Published public var contrast: Int = 50
    @Published public var sharpness: Int = 50

    /// (#1 Extension) Auto sync brightness & warm temp with macOS Dark Mode
    @Published public var autoDarkModeSync: Bool = false {
        didSet {
            UserDefaults.standard.set(autoDarkModeSync, forKey: "MateView_AutoDarkModeSync")
        }
    }
    @Published public var nightTargetBrightness: Int = 18 // ~110 nits
    @Published public var dayTargetBrightness: Int = 65   // ~305 nits

    /// (#4 Extension) Display Power Off countdown & standby state
    @Published public var isPowerOffCountdown: Bool = false
    @Published public var isDisplayPoweredOff: Bool = false

    /// Auto Power-Off Timer (Off / 15m / 30m / 45m / 60m) with Two-Stage IPS Backlight Protection
    @Published public var autoPowerOffInterval: AutoPowerOffInterval = .off {
        didSet {
            UserDefaults.standard.set(autoPowerOffInterval.rawValue, forKey: "MateView_AutoPowerOffMinutes")
            if autoPowerOffInterval == .off && isIdleDimmed {
                restoreFromIdleDim()
            }
        }
    }
    @Published public var isIdleDimmed: Bool = false
    private var preIdleBrightness: Int = 75
    private var preIdleMacBookBrightness: Int = 63

    /// UI expansion state for Fine-Tuning drawer
    @Published public var isTuningExpanded: Bool = false {
        didSet {
            UserDefaults.standard.set(isTuningExpanded, forKey: "MateView_IsTuningExpanded")
        }
    }

    /// Always retain and restore historical display & audio settings on app launch / display wake (内置默认永久开启)
    public let retainHistorySettings: Bool = true

    /// Menu bar display option: show real-time nits next to icon
    @Published public var showNitsInMenuBar: Bool = true {
        didSet {
            UserDefaults.standard.set(showNitsInMenuBar, forKey: "MateView_ShowNitsInMenuBar")
            onMenuBarTitleUpdate?()
        }
    }

    public var onMenuBarTitleUpdate: (() -> Void)?

    // MARK: - Nits Conversion (MateView GT 2026 QSN-CBB: 35 nits min .. 450 nits peak)
    public static func nits(forBrightness percent: Int) -> Int {
        let clamped = max(0, min(100, percent))
        return Int(round(35.0 + 4.15 * Double(clamped)))
    }

    public static func macBookNits(forBrightness percent: Int) -> Int {
        let clamped = max(0, min(100, percent))
        return Int(round(5.0 + 4.95 * Double(clamped))) // MacBook Air 500 nits Liquid Retina
    }

    public var currentNits: Int {
        Self.nits(forBrightness: brightness)
    }

    public var currentMacBookNits: Int {
        Self.macBookNits(forBrightness: macBookBrightness)
    }

    // MARK: - Internal Serial DDC Queue & Debounce WorkItems
    private let ddcQueue = DispatchQueue(label: "com.mateviewgt.ddc.serial", qos: .userInteractive)
    private var pendingWrites: [String: DispatchWorkItem] = [:]
    private let pendingLock = NSLock()
    private var lastWriteTimestamp: Date = .distantPast
    private var syncTimer: Timer?
    private var powerOffTimer: Timer?
    private var globalWakeMonitor: Any?

    private init() {
        UserDefaults.standard.set(true, forKey: "MateView_RetainHistorySettings")
        self.autoDarkModeSync = UserDefaults.standard.bool(forKey: "MateView_AutoDarkModeSync")
        self.isTuningExpanded = UserDefaults.standard.bool(forKey: "MateView_IsTuningExpanded")
        if UserDefaults.standard.object(forKey: "MateView_ShowNitsInMenuBar") != nil {
            self.showNitsInMenuBar = UserDefaults.standard.bool(forKey: "MateView_ShowNitsInMenuBar")
        }
        if let savedModeRaw = UserDefaults.standard.string(forKey: "MateView_ActivePreset"),
           let savedMode = MateViewPresetMode(rawValue: savedModeRaw) {
            self.activePreset = savedMode
        }
        let savedAutoOff = UserDefaults.standard.integer(forKey: "MateView_AutoPowerOffMinutes")
        if let interval = AutoPowerOffInterval(rawValue: savedAutoOff) {
            self.autoPowerOffInterval = interval
        }

        // Load saved historical hardware parameters into memory before initial hardware sync/restore
        loadSavedHistoryParametersIntoMemory()

        setupDarkModeObserver()
        setupWorkspaceWakeObserver()

        if retainHistorySettings && UserDefaults.standard.bool(forKey: "MateView_HasSavedHistorySnapshot") {
            restoreSavedHistoryToHardware()
        } else {
            refreshFromHardware()
        }
        startHardwareSyncPolling()
    }

    // MARK: - Lightweight Background Hardware Sync Polling (Syncs with Monitor OSD Joystick / MacBook Display & CoreAudio)
    public func startHardwareSyncPolling() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollQuickHardwareState()
        }
    }

    public func syncMacBookAndAudioState() {
        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            let bridge = IOAVServiceBridge.shared()
            let hasMB = bridge.hasBuiltInDisplay()
            let mbBright = bridge.getBuiltInDisplayBrightness()
            let isExtAudio = bridge.isDefaultAudioOutputExternalMonitor()
            let audioName = bridge.currentAudioOutputDeviceName()
            let sysVol = bridge.getSystemAudioVolume()
            let sysMute = bridge.getSystemAudioMute()

            DispatchQueue.main.async {
                self.hasMacBookDisplay = hasMB
                if mbBright >= 0 && !self.isIdleDimmed && !self.isDisplayPoweredOff && self.lockedMacBookBrightnessFloat == nil {
                    let pct = Int(round(mbBright * 100.0))
                    if self.macBookBrightness != pct && pct > 0 {
                        self.macBookBrightness = max(0, min(100, pct))
                    }
                }
                self.isAudioRoutedToMonitor = isExtAudio
                self.activeAudioDeviceName = isExtAudio ? "MateView GT" : (audioName.contains("MacBook") ? "MacBook Air" : audioName)
                let volPct = Int(round(sysVol * 100.0))
                if self.macBookVolume != volPct {
                    self.macBookVolume = max(0, min(100, volPct))
                }
                if self.isMacBookMuted != sysMute {
                    self.isMacBookMuted = sysMute
                }
            }
        }
    }

    public func pollQuickHardwareState() {
        syncMacBookAndAudioState()
        checkIdleAutoPowerOff()

        // Skip DDC polling while display is powered off, idle-dimmed, or immediately after user drags a slider (within 1.5s)
        guard !isDisplayPoweredOff,
              !isIdleDimmed,
              Date().timeIntervalSince(lastWriteTimestamp) > 1.5 else { return }

        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            let bridge = IOAVServiceBridge.shared()

            var curB: UInt16 = 0, maxB: UInt16 = 100
            let okB = bridge.readStandardVCP(0x10, currentValue: &curB, maxValue: &maxB)

            var curV: UInt16 = 0, maxV: UInt16 = 100
            let okV = bridge.readStandardVCP(0x62, currentValue: &curV, maxValue: &maxV)

            var curMute: UInt16 = 2, maxMute: UInt16 = 2
            let okM = bridge.readStandardVCP(0x8D, currentValue: &curMute, maxValue: &maxMute)

            var curCT: UInt16 = 0x06, maxCT: UInt16 = 0x0B
            let okCT = bridge.readStandardVCP(0x14, currentValue: &curCT, maxValue: &maxCT)

            DispatchQueue.main.async {
                guard Date().timeIntervalSince(self.lastWriteTimestamp) > 1.5 else { return }
                var brightnessChanged = false
                var stateChangedFromOSD = false
                if okB {
                    let b = Int(max(0, min(100, curB)))
                    if self.brightness != b {
                        self.brightness = b
                        brightnessChanged = true
                        stateChangedFromOSD = true
                    }
                }
                if okV {
                    let v = Int(max(0, min(100, curV)))
                    if self.volume != v {
                        self.volume = v
                        stateChangedFromOSD = true
                    }
                }
                if okM {
                    let m = (curMute == 1)
                    if self.isMuted != m {
                        self.isMuted = m
                        stateChangedFromOSD = true
                    }
                }
                if okCT, let ct = HardwareColorTemp(rawValue: curCT), self.colorTemp != ct {
                    self.colorTemp = ct
                    stateChangedFromOSD = true
                }
                if brightnessChanged {
                    self.onMenuBarTitleUpdate?()
                }
                if stateChangedFromOSD && self.retainHistorySettings {
                    self.saveFullHistorySnapshot()
                }
            }
        }
    }

    // MARK: - Hardware Sync (Read All Registers)
    public func refreshFromHardware() {
        syncMacBookAndAudioState()
        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            let bridge = IOAVServiceBridge.shared()
            let info = bridge.detectExternalDisplay()

            var curB: UInt16 = 75, maxB: UInt16 = 100
            let hasB = bridge.readStandardVCP(0x10, currentValue: &curB, maxValue: &maxB)

            var curV: UInt16 = 18, maxV: UInt16 = 100
            _ = bridge.readStandardVCP(0x62, currentValue: &curV, maxValue: &maxV)

            var curMute: UInt16 = 2, maxMute: UInt16 = 2
            _ = bridge.readStandardVCP(0x8D, currentValue: &curMute, maxValue: &maxMute)

            var curContrast: UInt16 = 50, maxContrast: UInt16 = 100
            _ = bridge.readStandardVCP(0x12, currentValue: &curContrast, maxValue: &maxContrast)

            var curSharp: UInt16 = 50, maxSharp: UInt16 = 100
            _ = bridge.readStandardVCP(0x87, currentValue: &curSharp, maxValue: &maxSharp)

            var curCT: UInt16 = 0x06, maxCT: UInt16 = 0x0B
            _ = bridge.readStandardVCP(0x14, currentValue: &curCT, maxValue: &maxCT)

            var curR: UInt16 = 100, curG: UInt16 = 100, curBl: UInt16 = 100, dummyMax: UInt16 = 100
            _ = bridge.readStandardVCP(0x16, currentValue: &curR, maxValue: &dummyMax)
            _ = bridge.readStandardVCP(0x18, currentValue: &curG, maxValue: &dummyMax)
            _ = bridge.readStandardVCP(0x1A, currentValue: &curBl, maxValue: &dummyMax)

            var curUsage: UInt16 = 7, maxUsage: UInt16 = 0
            _ = bridge.readStandardVCP(0xC0, currentValue: &curUsage, maxValue: &maxUsage)

            var curSat: UInt16 = 10, maxSat: UInt16 = 20
            let hasSat = bridge.readExtendedVCP(0xF8, sub1: 0xE1, sub2: 0x57, currentValue: &curSat, maxValue: &maxSat)

            DispatchQueue.main.async {
                self.isConnected = info.isConnected || hasB
                self.modelName = info.modelName
                if hasB { self.brightness = Int(max(0, min(100, curB))) }
                self.volume = Int(max(0, min(100, curV)))
                self.isMuted = (curMute == 1)
                self.contrast = Int(max(0, min(100, curContrast)))
                self.sharpness = Int(max(0, min(100, curSharp)))
                if let ct = HardwareColorTemp(rawValue: curCT) {
                    self.colorTemp = ct
                }
                self.redGain = Int(max(0, min(100, curR)))
                self.greenGain = Int(max(0, min(100, curG)))
                self.blueGain = Int(max(0, min(100, curBl)))
                if curUsage > 0 { self.usageHours = Int(curUsage) }
                if hasSat {
                    self.saturation = Int(max(0, min(20, curSat)))
                    // Infer preset if saturation is 0
                    if self.saturation == 0 {
                        self.activePreset = .ebookBW
                    } else if self.saturation <= 7 && self.colorTemp == .warm6500K {
                        self.activePreset = .ebookColor
                    }
                }
                if self.retainHistorySettings {
                    self.saveFullHistorySnapshot()
                }
                self.onMenuBarTitleUpdate?()
            }
        }
    }

    // MARK: - Debounced Hardware Writers
    private func scheduleWrite(key: String, delay: TimeInterval = 0.035, block: @escaping () -> Void) {
        lastWriteTimestamp = Date()
        pendingLock.lock()
        pendingWrites[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.lastWriteTimestamp = Date()
            block()
        }
        pendingWrites[key] = item
        pendingLock.unlock()
        ddcQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - 1. Brightness Control (MateView GT 0-100 & MacBook Air 0-100)
    public func isCursorOnBuiltInDisplay() -> Bool {
        guard hasMacBookDisplay else { return false }
        let mouseLoc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLoc, screen.frame, false) {
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return CGDisplayIsBuiltin(num.uint32Value) != 0
                }
            }
        }
        return false
    }

    public func setBrightness(_ newValue: Int, showHUD: Bool = false) {
        let clamped = max(0, min(100, newValue))
        if brightness != clamped {
            brightness = clamped
        }
        saveFullHistorySnapshot()
        onMenuBarTitleUpdate?()
        if showHUD {
            LiquidHUDManager.shared.showBrightnessHUD(title: "MateView GT", percent: clamped, nits: currentNits)
        }
        scheduleWrite(key: "vcp_0x10") {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x10, value: UInt16(clamped))
        }
    }

    public func setMacBookBrightness(_ newValue: Int, showHUD: Bool = false) {
        let clamped = max(0, min(100, newValue))
        if macBookBrightness != clamped {
            macBookBrightness = clamped
        }
        saveFullHistorySnapshot()
        _ = IOAVServiceBridge.shared().setBuiltInDisplayBrightness(Float(clamped) / 100.0)
        if showHUD {
            LiquidHUDManager.shared.showBrightnessHUD(title: "MacBook Air", percent: clamped, nits: currentMacBookNits)
        }
    }

    /// Smart Brightness Stepper: routes to MacBook Air when cursor is on built-in screen, otherwise MateView GT
    /// When cursor is on MateView GT, actively pins MacBook Air's built-in display brightness so macOS corebrightnessd never leaks F1/F2 changes to the built-in screen!
    private var lockedMacBookBrightnessFloat: Float? = nil
    private var builtInLockReleaseTimer: Timer? = nil

    public func stepActiveDisplayBrightnessLocked(by delta: Int, showHUD: Bool = true) {
        if isCursorOnBuiltInDisplay() {
            setMacBookBrightness(macBookBrightness + delta, showHUD: showHUD)
        } else {
            setBrightness(brightness + delta, showHUD: showHUD)
        }
    }

    public func enforceBuiltInBrightnessLockIfNeeded() {
        // No longer needed because hidutil hardware remapping intercepts brightness keys before corebrightnessd!
    }

    public func stepActiveDisplayBrightness(by delta: Int, showHUD: Bool = true) {
        stepActiveDisplayBrightnessLocked(by: delta, showHUD: showHUD)
    }

    public func stepBrightness(by delta: Int, showHUD: Bool = true) {
        stepActiveDisplayBrightness(by: delta, showHUD: showHUD)
    }

    // MARK: - 2. Volume & Speaker Output Detection Control (0 - 100)
    public func switchAudioOutput(toMonitor useMonitor: Bool) {
        if IOAVServiceBridge.shared().setDefaultAudioOutputToExternalMonitor(useMonitor) {
            isAudioRoutedToMonitor = useMonitor
            saveFullHistorySnapshot()
            syncMacBookAndAudioState()
        }
    }

    public func setVolume(_ newValue: Int, showHUD: Bool = false) {
        let clamped = max(0, min(100, newValue))
        volume = clamped
        if clamped > 0 && isMuted {
            isMuted = false
            scheduleWrite(key: "vcp_0x8D") {
                _ = IOAVServiceBridge.shared().writeStandardVCP(0x8D, value: 2)
            }
        }
        saveFullHistorySnapshot()
        if showHUD {
            LiquidHUDManager.shared.showVolumeHUD(title: "MateView GT", percent: clamped, isMuted: isMuted || clamped == 0)
        }
        scheduleWrite(key: "vcp_0x62") {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x62, value: UInt16(clamped))
        }
    }

    public func setMacBookVolume(_ newValue: Int, showHUD: Bool = false) {
        let clamped = max(0, min(100, newValue))
        macBookVolume = clamped
        if clamped > 0 && isMacBookMuted {
            isMacBookMuted = false
            _ = IOAVServiceBridge.shared().setSystemAudioMute(false)
        }
        saveFullHistorySnapshot()
        _ = IOAVServiceBridge.shared().setSystemAudioVolume(Float(clamped) / 100.0)
        if showHUD {
            LiquidHUDManager.shared.showVolumeHUD(title: activeAudioDeviceName, percent: clamped, isMuted: isMacBookMuted || clamped == 0)
        }
    }

    /// Smart Volume Stepper: automatically detects current default audio output speaker and adjusts that device!
    public func stepActiveSpeakerVolume(by delta: Int, showHUD: Bool = true) {
        let isExt = IOAVServiceBridge.shared().isDefaultAudioOutputExternalMonitor()
        isAudioRoutedToMonitor = isExt
        if isExt {
            setVolume(volume + delta, showHUD: showHUD)
        } else {
            let cur = Int(round(IOAVServiceBridge.shared().getSystemAudioVolume() * 100.0))
            setMacBookVolume(cur + delta, showHUD: showHUD)
        }
    }

    public func stepVolume(by delta: Int, showHUD: Bool = true) {
        stepActiveSpeakerVolume(by: delta, showHUD: showHUD)
    }

    public func toggleActiveSpeakerMute(showHUD: Bool = true) {
        let isExt = IOAVServiceBridge.shared().isDefaultAudioOutputExternalMonitor()
        isAudioRoutedToMonitor = isExt
        if isExt {
            isMuted.toggle()
            saveFullHistorySnapshot()
            let targetVal: UInt16 = isMuted ? 1 : 2
            if showHUD {
                LiquidHUDManager.shared.showVolumeHUD(title: "MateView GT", percent: volume, isMuted: isMuted)
            }
            scheduleWrite(key: "vcp_0x8D", delay: 0.01) {
                _ = IOAVServiceBridge.shared().writeStandardVCP(0x8D, value: targetVal)
            }
        } else {
            isMacBookMuted.toggle()
            saveFullHistorySnapshot()
            _ = IOAVServiceBridge.shared().setSystemAudioMute(isMacBookMuted)
            if showHUD {
                LiquidHUDManager.shared.showVolumeHUD(title: activeAudioDeviceName, percent: macBookVolume, isMuted: isMacBookMuted)
            }
        }
    }

    public func toggleMute(showHUD: Bool = true) {
        toggleActiveSpeakerMute(showHUD: showHUD)
    }

    // MARK: - 3. Color & eBook Mode Switching (Hardware Scaler + Saved Per-Mode Tuning)
    public func applyPresetMode(_ mode: MateViewPresetMode) {
        activePreset = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "MateView_ActivePreset")

        let tuning = loadTuning(for: mode)
        saturation = tuning.saturation
        contrast = tuning.contrast
        sharpness = tuning.sharpness
        if let ct = HardwareColorTemp(rawValue: tuning.colorTempRaw) {
            colorTemp = ct
        }
        saveFullHistorySnapshot()

        // Write hardware registers sequentially on serial queue
        scheduleWrite(key: "preset_switch", delay: 0.01) {
            let bridge = IOAVServiceBridge.shared()
            // 1. Hardware Color Temperature (0x14)
            _ = bridge.writeStandardVCP(0x14, value: tuning.colorTempRaw)
            // 2. Hardware Saturation (Ext 0xF8E157: 0 = pure B&W e-ink, 6 = color picture book, 10 = standard P3)
            _ = bridge.writeExtendedVCP(0xF8, sub1: 0xE1, sub2: 0x57, value: UInt16(tuning.saturation))
            // 3. Hardware Contrast (0x12)
            _ = bridge.writeStandardVCP(0x12, value: UInt16(tuning.contrast))
            // 4. Hardware Sharpness (0x87)
            _ = bridge.writeStandardVCP(0x87, value: UInt16(tuning.sharpness))
        }
    }

    // MARK: - 4. Hardware Color Temp & Custom RGB Gains
    public func setHardwareColorTemp(_ temp: HardwareColorTemp) {
        colorTemp = temp
        saveCurrentModeTuning()
        saveFullHistorySnapshot()
        scheduleWrite(key: "vcp_0x14", delay: 0.02) {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x14, value: temp.rawValue)
        }
    }

    public func setRGBGain(red: Int? = nil, green: Int? = nil, blue: Int? = nil) {
        if let r = red {
            redGain = max(0, min(100, r))
            scheduleWrite(key: "vcp_0x16") {
                _ = IOAVServiceBridge.shared().writeStandardVCP(0x16, value: UInt16(self.redGain))
            }
        }
        if let g = green {
            greenGain = max(0, min(100, g))
            scheduleWrite(key: "vcp_0x18") {
                _ = IOAVServiceBridge.shared().writeStandardVCP(0x18, value: UInt16(self.greenGain))
            }
        }
        if let b = blue {
            blueGain = max(0, min(100, b))
            scheduleWrite(key: "vcp_0x1A") {
                _ = IOAVServiceBridge.shared().writeStandardVCP(0x1A, value: UInt16(self.blueGain))
            }
        }
        saveFullHistorySnapshot()
    }

    // MARK: - 5. (#3 Extension) Hardware Contrast, Sharpness & Saturation Fine-Tuning
    public func setSaturation(_ newValue: Int) {
        let clamped = max(0, min(20, newValue))
        saturation = clamped
        saveCurrentModeTuning()
        saveFullHistorySnapshot()
        scheduleWrite(key: "ext_F8E157") {
            _ = IOAVServiceBridge.shared().writeExtendedVCP(0xF8, sub1: 0xE1, sub2: 0x57, value: UInt16(clamped))
        }
    }

    public func setContrast(_ newValue: Int) {
        let clamped = max(0, min(100, newValue))
        contrast = clamped
        saveCurrentModeTuning()
        saveFullHistorySnapshot()
        scheduleWrite(key: "vcp_0x12") {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x12, value: UInt16(clamped))
        }
    }

    public func setSharpness(_ newValue: Int) {
        let clamped = max(0, min(100, newValue))
        sharpness = clamped
        saveCurrentModeTuning()
        saveFullHistorySnapshot()
        scheduleWrite(key: "vcp_0x87") {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x87, value: UInt16(clamped))
        }
    }

    public func resetCurrentModeTuningToDefault() {
        let key = "MateView_Tuning_\(activePreset.rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
        applyPresetMode(activePreset)
    }

    private func loadTuning(for mode: MateViewPresetMode) -> ModeImageTuning {
        let key = "MateView_Tuning_\(mode.rawValue)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ModeImageTuning.self, from: data) {
            return decoded
        }
        return mode.defaultParameters
    }

    private func saveCurrentModeTuning() {
        let tuning = ModeImageTuning(
            saturation: saturation,
            contrast: contrast,
            sharpness: sharpness,
            colorTempRaw: colorTemp.rawValue
        )
        let key = "MateView_Tuning_\(activePreset.rawValue)"
        if let data = try? JSONEncoder().encode(tuning) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - 6. (#1 Extension) Smooth Transition & macOS Dark Mode Auto Sync (Both MateView GT & MacBook Air)
    public func smoothTransitionBrightness(to targetPercent: Int, macBookTargetPercent: Int? = nil) {
        let start = brightness
        let target = max(0, min(100, targetPercent))
        let mbStart = macBookBrightness
        let mbTarget = macBookTargetPercent.map { max(0, min(100, $0)) }

        let steps = 5
        let diff = Double(target - start)
        let mbDiff = mbTarget.map { Double($0 - mbStart) } ?? 0.0

        for step in 1...steps {
            let delay = Double(step) * 0.12
            let ratio = Double(step) / Double(steps)
            let intermediate = start + Int(round(diff * ratio))
            let mbIntermediate = mbStart + Int(round(mbDiff * ratio))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                if start != target {
                    self.setBrightness(intermediate, showHUD: step == steps)
                }
                if let mbT = mbTarget, mbStart != mbT, self.hasMacBookDisplay {
                    self.setMacBookBrightness(mbIntermediate, showHUD: false)
                }
            }
        }
    }

    private func setupDarkModeObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.autoDarkModeSync else { return }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                self.dayTargetBrightness = max(35, self.brightness)
                self.smoothTransitionBrightness(to: self.nightTargetBrightness, macBookTargetPercent: 25)
                self.setHardwareColorTemp(.warm6500K)
            } else {
                self.smoothTransitionBrightness(to: self.dayTargetBrightness, macBookTargetPercent: 65)
                self.setHardwareColorTemp(.standard)
            }
        }
    }

    // MARK: - 7. (#4 Extension) Display Power Off Only (Mac stays awake)
    public func triggerDisplayPowerOffWithGracePeriod() {
        if isPowerOffCountdown {
            cancelPowerOffCountdown()
            return
        }
        isPowerOffCountdown = true
        powerOffTimer?.invalidate()
        powerOffTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.executeHardwarePowerOff()
        }
    }

    public func cancelPowerOffCountdown() {
        powerOffTimer?.invalidate()
        powerOffTimer = nil
        isPowerOffCountdown = false
    }

    private func executeHardwarePowerOff() {
        isPowerOffCountdown = false
        if !isIdleDimmed && !isDisplayPoweredOff {
            preIdleBrightness = max(10, brightness)
            if hasMacBookDisplay && macBookBrightness > 0 {
                preIdleMacBookBrightness = macBookBrightness
            }
        }
        isDisplayPoweredOff = true

        // 1. Cut MacBook Air built-in display backlight completely to 0.0 (True physical LED backlight off!)
        if hasMacBookDisplay {
            _ = IOAVServiceBridge.shared().setBuiltInDisplayBrightness(0.0)
        }

        // 2. Send VCP 0xD6 = 0x04 (DPM Off / Hardware Standby) to MateView GT
        ddcQueue.async {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0xD6, value: 0x04)
        }

        // Install global wake listener after 0.8s so minor mouse release doesn't immediately wake
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.installWakeMonitor()
        }
    }

    private func installWakeMonitor() {
        removeWakeMonitor()
        globalWakeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            self?.wakeDisplayFromStandby()
        }
    }

    public func wakeDisplayFromStandby() {
        if isIdleDimmed {
            restoreFromIdleDim()
        }
        guard isDisplayPoweredOff else { return }
        isDisplayPoweredOff = false
        removeWakeMonitor()

        // 1. Restore MacBook Air built-in display backlight immediately
        if hasMacBookDisplay {
            let targetMB = max(15, preIdleMacBookBrightness)
            macBookBrightness = targetMB
            _ = IOAVServiceBridge.shared().setBuiltInDisplayBrightness(Float(targetMB) / 100.0)
        }

        // 2. Wake MateView GT from hardware standby and restore brightness
        let targetExt = max(10, preIdleBrightness)
        brightness = targetExt
        onMenuBarTitleUpdate?()
        ddcQueue.async {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0xD6, value: 0x01)
            usleep(120000)
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x10, value: UInt16(targetExt))
        }
    }

    // MARK: - 8. Two-Stage Idle Auto Power-Off (Dual-Screen IPS Backlight Lifespan Protection)
    private func checkIdleAutoPowerOff() {
        guard autoPowerOffInterval != .off else { return }
        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            let bridge = IOAVServiceBridge.shared()
            let idleSeconds = bridge.secondsSinceLastUserInput()
            let mediaPreventing = (idleSeconds >= 3.0) ? bridge.isDisplaySleepPreventedByActiveMedia() : false

            DispatchQueue.main.async {
                guard self.autoPowerOffInterval != .off else { return }
                if idleSeconds < 3.0 {
                    if self.isDisplayPoweredOff {
                        self.wakeDisplayFromStandby()
                    } else if self.isIdleDimmed {
                        self.restoreFromIdleDim()
                    }
                    return
                }
                if mediaPreventing {
                    return
                }

                let powerOffThreshold = Double(self.autoPowerOffInterval.rawValue * 60)
                let preDimThreshold = min(900.0, powerOffThreshold / 3.0)

                if idleSeconds >= powerOffThreshold {
                    if !self.isDisplayPoweredOff {
                        self.executeHardwarePowerOff()
                    }
                } else if idleSeconds >= preDimThreshold {
                    if !self.isIdleDimmed && !self.isDisplayPoweredOff {
                        self.preIdleBrightness = max(10, self.brightness)
                        if self.hasMacBookDisplay && self.macBookBrightness > 5 {
                            self.preIdleMacBookBrightness = self.macBookBrightness
                        }
                        self.isIdleDimmed = true

                        let hasMB = self.hasMacBookDisplay
                        self.ddcQueue.async {
                            if hasMB {
                                _ = IOAVServiceBridge.shared().setBuiltInDisplayBrightness(0.04)
                            }
                            _ = IOAVServiceBridge.shared().writeStandardVCP(0x10, value: 0)
                        }
                    }
                }
            }
        }
    }

    private func restoreFromIdleDim() {
        guard isIdleDimmed else { return }
        isIdleDimmed = false

        // Restore MacBook Air built-in display
        if hasMacBookDisplay {
            let targetMB = max(15, preIdleMacBookBrightness)
            macBookBrightness = targetMB
            _ = IOAVServiceBridge.shared().setBuiltInDisplayBrightness(Float(targetMB) / 100.0)
        }

        // Restore MateView GT
        let target = max(10, preIdleBrightness)
        brightness = target
        onMenuBarTitleUpdate?()
        scheduleWrite(key: "vcp_0x10", delay: 0.01) {
            _ = IOAVServiceBridge.shared().writeStandardVCP(0x10, value: UInt16(target))
        }
    }

    private func removeWakeMonitor() {
        if let monitor = globalWakeMonitor {
            NSEvent.removeMonitor(monitor)
            globalWakeMonitor = nil
        }
    }

    // MARK: - 9. Historical Settings Retention & Auto-Restore (历史设置保留)
    public func saveFullHistorySnapshot() {
        guard retainHistorySettings, !isIdleDimmed, !isDisplayPoweredOff else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "MateView_HasSavedHistorySnapshot")
        defaults.set(brightness, forKey: "MateView_SavedBrightness")
        defaults.set(macBookBrightness, forKey: "MateView_SavedMacBookBrightness")
        defaults.set(volume, forKey: "MateView_SavedVolume")
        defaults.set(isMuted, forKey: "MateView_SavedIsMuted")
        defaults.set(macBookVolume, forKey: "MateView_SavedMacBookVolume")
        defaults.set(isMacBookMuted, forKey: "MateView_SavedIsMacBookMuted")
        defaults.set(isAudioRoutedToMonitor, forKey: "MateView_SavedAudioRoutedToMonitor")
        defaults.set(activePreset.rawValue, forKey: "MateView_ActivePreset")
        defaults.set(Int(colorTemp.rawValue), forKey: "MateView_SavedColorTempRaw")
        defaults.set(redGain, forKey: "MateView_SavedRedGain")
        defaults.set(greenGain, forKey: "MateView_SavedGreenGain")
        defaults.set(blueGain, forKey: "MateView_SavedBlueGain")
        defaults.set(saturation, forKey: "MateView_SavedSaturation")
        defaults.set(contrast, forKey: "MateView_SavedContrast")
        defaults.set(sharpness, forKey: "MateView_SavedSharpness")
    }

    private func loadSavedHistoryParametersIntoMemory() {
        let defaults = UserDefaults.standard
        guard retainHistorySettings, defaults.bool(forKey: "MateView_HasSavedHistorySnapshot") else { return }

        if defaults.object(forKey: "MateView_SavedBrightness") != nil {
            // Never restore a 0% pitch-black brightness on startup
            brightness = max(10, min(100, defaults.integer(forKey: "MateView_SavedBrightness")))
        }
        if defaults.object(forKey: "MateView_SavedMacBookBrightness") != nil {
            macBookBrightness = max(15, min(100, defaults.integer(forKey: "MateView_SavedMacBookBrightness")))
        }
        if defaults.object(forKey: "MateView_SavedVolume") != nil {
            volume = max(0, min(100, defaults.integer(forKey: "MateView_SavedVolume")))
        }
        if defaults.object(forKey: "MateView_SavedIsMuted") != nil {
            isMuted = defaults.bool(forKey: "MateView_SavedIsMuted")
        }
        if defaults.object(forKey: "MateView_SavedMacBookVolume") != nil {
            macBookVolume = max(0, min(100, defaults.integer(forKey: "MateView_SavedMacBookVolume")))
        }
        if defaults.object(forKey: "MateView_SavedIsMacBookMuted") != nil {
            isMacBookMuted = defaults.bool(forKey: "MateView_SavedIsMacBookMuted")
        }
        if defaults.object(forKey: "MateView_SavedAudioRoutedToMonitor") != nil {
            isAudioRoutedToMonitor = defaults.bool(forKey: "MateView_SavedAudioRoutedToMonitor")
        }
        if defaults.object(forKey: "MateView_SavedColorTempRaw") != nil,
           let ct = HardwareColorTemp(rawValue: UInt16(defaults.integer(forKey: "MateView_SavedColorTempRaw"))) {
            colorTemp = ct
        }
        if defaults.object(forKey: "MateView_SavedRedGain") != nil {
            redGain = max(0, min(100, defaults.integer(forKey: "MateView_SavedRedGain")))
        }
        if defaults.object(forKey: "MateView_SavedGreenGain") != nil {
            greenGain = max(0, min(100, defaults.integer(forKey: "MateView_SavedGreenGain")))
        }
        if defaults.object(forKey: "MateView_SavedBlueGain") != nil {
            blueGain = max(0, min(100, defaults.integer(forKey: "MateView_SavedBlueGain")))
        }
        if defaults.object(forKey: "MateView_SavedSaturation") != nil {
            saturation = max(0, min(20, defaults.integer(forKey: "MateView_SavedSaturation")))
        }
        if defaults.object(forKey: "MateView_SavedContrast") != nil {
            contrast = max(0, min(100, defaults.integer(forKey: "MateView_SavedContrast")))
        }
        if defaults.object(forKey: "MateView_SavedSharpness") != nil {
            sharpness = max(0, min(100, defaults.integer(forKey: "MateView_SavedSharpness")))
        }
    }

    /// Writes saved historical parameters back to MateView GT & MacBook Air on launch or display wake
    public func restoreSavedHistoryToHardware() {
        guard retainHistorySettings,
              UserDefaults.standard.bool(forKey: "MateView_HasSavedHistorySnapshot") else {
            refreshFromHardware()
            return
        }

        lastWriteTimestamp = Date()
        let targetB = max(10, brightness)
        let targetMBB = max(15, macBookBrightness)
        let targetV = volume
        let targetMute: UInt16 = isMuted ? 1 : 2
        let targetRouteMonitor = isAudioRoutedToMonitor
        let targetCT = colorTemp
        let targetR = redGain
        let targetG = greenGain
        let targetBl = blueGain
        let targetSat = saturation
        let targetCon = contrast
        let targetSharp = sharpness

        // Restore MacBook Air & MateView GT asynchronously on background serial queue (zero main thread block)
        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastWriteTimestamp = Date()
            let hw = IOAVServiceBridge.shared()
            if hw.hasBuiltInDisplay() {
                _ = hw.setBuiltInDisplayBrightness(Float(targetMBB) / 100.0)
            }
            _ = hw.setDefaultAudioOutputToExternalMonitor(targetRouteMonitor)
            let info = hw.detectExternalDisplay()

            _ = hw.writeStandardVCP(0x10, value: UInt16(targetB))
            _ = hw.writeStandardVCP(0x62, value: UInt16(targetV))
            _ = hw.writeStandardVCP(0x8D, value: targetMute)
            _ = hw.writeStandardVCP(0x14, value: targetCT.rawValue)
            if targetCT == .customRGB {
                _ = hw.writeStandardVCP(0x16, value: UInt16(targetR))
                _ = hw.writeStandardVCP(0x18, value: UInt16(targetG))
                _ = hw.writeStandardVCP(0x1A, value: UInt16(targetBl))
            }
            _ = hw.writeExtendedVCP(0xF8, sub1: 0xE1, sub2: 0x57, value: UInt16(targetSat))
            _ = hw.writeStandardVCP(0x12, value: UInt16(targetCon))
            _ = hw.writeStandardVCP(0x87, value: UInt16(targetSharp))

            DispatchQueue.main.async {
                self.isConnected = info.isConnected
                self.modelName = info.modelName
                self.onMenuBarTitleUpdate?()
            }
        }
    }

    private func setupWorkspaceWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if self.retainHistorySettings && UserDefaults.standard.bool(forKey: "MateView_HasSavedHistorySnapshot") {
                    self.restoreSavedHistoryToHardware()
                    HiDPIManager.shared.restoreSavedResolutionIfNeeded()
                } else {
                    self.refreshFromHardware()
                    HiDPIManager.shared.refreshCurrentMode()
                }
            }
        }
    }
}
