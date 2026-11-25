import AppKit
import ApplicationServices
import Carbon
import Foundation
import Combine

/// Intercepts macOS native Brightness (F1/F2, keyCodes 145/144, or NX_KEYTYPE_BRIGHTNESS)
/// and Volume/Mute (F10/F11/F12, keyCodes 74/73/72, or NX_KEYTYPE_SOUND)
public final class MediaKeyInterceptor: ObservableObject {
    public static let shared = MediaKeyInterceptor()

    @Published public var isAccessibilityGranted: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalSystemMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hotKeyHandlerRef: EventHandlerRef?
    private var permissionCheckTimer: Timer?
    private var lastExternalBrightnessTapTime: Date = .distantPast
    public var isEnabled: Bool = true

    // IOKit / NSEvent system defined media key subtypes
    private static let NX_KEYTYPE_SOUND_UP: Int32 = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    private static let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
    private static let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
    private static let NX_KEYTYPE_MUTE: Int32 = 7

    private init() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    public func start() {
        applyHardwareBrightnessKeyRemap(enable: true)
        disableConflictingNativeDisplayBrightnessHotkeys()
        registerCarbonBrightnessHotKeys()
        refreshStatus()

        // 1. Always install fallback NSEvent global & local monitors
        installFallbackGlobalMonitors()

        // 2. Periodically verify Accessibility & EventTap health
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    /// Registers Carbon RegisterEventHotKey for F14 (keyCode 107) and F15 (keyCode 113) with and without Option modifier.
    /// Carbon EventHotKeys work 100% globally across all apps WITHOUT requiring Accessibility / TCC approval!
    private func registerCarbonBrightnessHotKeys() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            // Avoid duplicate trigger if CGEventTap already handled it within 60ms
            guard Date().timeIntervalSince(MediaKeyInterceptor.shared.lastExternalBrightnessTapTime) > 0.06 else {
                return noErr
            }
            MediaKeyInterceptor.shared.lastExternalBrightnessTapTime = Date()

            switch hotKeyID.id {
            case 1: // F14 (Brightness Down -5)
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: -5, showHUD: true)
                }
            case 2: // F15 (Brightness Up +5)
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: 5, showHUD: true)
                }
            case 3: // Option + F14 (Brightness Down -1)
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: -1, showHUD: true)
                }
            case 4: // Option + F15 (Brightness Up +1)
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: 1, showHUD: true)
                }
            default:
                break
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &hotKeyHandlerRef)

        let sig = OSType(0x4D564754) // 'MVGT'
        let bindings: [(UInt32, UInt32, UInt32)] = [
            (1, 107, 0),                 // F14
            (2, 113, 0),                 // F15
            (3, 107, UInt32(optionKey)), // Option + F14
            (4, 113, UInt32(optionKey))  // Option + F15
        ]
        for (id, code, mods) in bindings {
            var ref: EventHotKeyRef? = nil
            let hkID = EventHotKeyID(signature: sig, id: id)
            RegisterEventHotKey(code, mods, hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    /// Remaps physical Consumer Brightness Decrement/Increment (0xC00000070 / 0xC0000006F) and Apple Function Brightness
    /// to neutral F14/F15 (0x700000069 / 0x70000006A) at the IOHID driver level via `/usr/bin/hidutil`.
    /// This completely prevents macOS `corebrightnessd` from ever touching or flickering the MacBook Air built-in screen
    /// when cursor is on the Huawei monitor!
    public func applyHardwareBrightnessKeyRemap(enable: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            if enable {
                let json = """
                {"UserKeyMapping":[
                  {"HIDKeyboardModifierMappingSrc":51539607664,"HIDKeyboardModifierMappingDst":30064771177},
                  {"HIDKeyboardModifierMappingSrc":51539607663,"HIDKeyboardModifierMappingDst":30064771178},
                  {"HIDKeyboardModifierMappingSrc":1099511627796,"HIDKeyboardModifierMappingDst":30064771177},
                  {"HIDKeyboardModifierMappingSrc":1099511627792,"HIDKeyboardModifierMappingDst":30064771178}
                ]}
                """
                // Note:
                // 51539607664   = 0xC00000070 (Consumer Display Brightness Decrement) -> 30064771177 = 0x700000069 (F14 / keyCode 107)
                // 51539607663   = 0xC0000006F (Consumer Display Brightness Increment) -> 30064771178 = 0x70000006A (F15 / keyCode 113)
                // 1099511627796 = 0xFF0100000014 (Apple Vendor Brightness Down)       -> 0x700000069 (F14)
                // 1099511627792 = 0xFF0100000010 (Apple Vendor Brightness Up)         -> 0x70000006A (F15)
                proc.arguments = ["property", "--set", json]
            } else {
                proc.arguments = ["property", "--set", "{\"UserKeyMapping\":[]}"]
            }
            try? proc.run()
        }
    }

    /// Disables macOS built-in symbolic hotkeys 53/54/55/56 ("Decrease/Increase Display Brightness")
    /// so macOS never fights MateView GT Control when cursor is on the external monitor.
    public func disableConflictingNativeDisplayBrightnessHotkeys() {
        DispatchQueue.global(qos: .utility).async {
            guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys") else { return }
            var hotkeys = (domain["AppleSymbolicHotKeys"] as? [String: Any]) ?? [:]
            var changed = false
            for keyID in ["53", "54", "55", "56"] {
                if var entry = hotkeys[keyID] as? [String: Any] {
                    if (entry["enabled"] as? Bool) != false {
                        entry["enabled"] = false
                        hotkeys[keyID] = entry
                        changed = true
                    }
                } else {
                    hotkeys[keyID] = ["enabled": false]
                    changed = true
                }
            }
            if changed {
                var newDomain = domain
                newDomain["AppleSymbolicHotKeys"] = hotkeys
                UserDefaults.standard.setPersistentDomain(newDomain, forName: "com.apple.symbolichotkeys")
                UserDefaults.standard.synchronize()
                let activatePath = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
                if FileManager.default.isExecutableFile(atPath: activatePath) {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: activatePath)
                    proc.arguments = ["-u"]
                    try? proc.run()
                }
            }
        }
    }

    public func refreshStatus() {
        let axTrusted = AXIsProcessTrusted()

        if !axTrusted {
            // If permission was revoked or invalidated after binary rebuild, tear down stale tap
            if eventTap != nil {
                stopEventTap()
            }
            if isAccessibilityGranted {
                isAccessibilityGranted = false
            }
            return
        }

        // Permission is granted; ensure active CGEventTap is alive and enabled
        if eventTap == nil {
            tryInstallCGEventTap()
        } else if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        let isHealthy = (eventTap != nil) && CGEvent.tapIsEnabled(tap: eventTap!)
        if isAccessibilityGranted != isHealthy {
            isAccessibilityGranted = isHealthy
        }
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    public func requestAccessibilityPermissionPrompt() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
        refreshStatus()
        // Also open System Settings -> Accessibility directly so user doesn't have to hunt for it
        if !isAccessibilityGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installFallbackGlobalMonitors() {
        if globalSystemMonitor == nil {
            globalSystemMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] nsEvent in
                guard let self = self, self.eventTap == nil else { return }
                _ = self.handleSystemDefinedNSEvent(nsEvent)
            }
        }
        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] nsEvent in
                guard let self = self, self.eventTap == nil else { return }
                var cleanFlags = nsEvent.modifierFlags
                cleanFlags.remove(.function)
                _ = self.handleKeyDownCode(Int64(nsEvent.keyCode), flags: cleanFlags, isRepeat: nsEvent.isARepeat)
            }
        }
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] nsEvent in
                guard let self = self else { return nsEvent }
                var cleanFlags = nsEvent.modifierFlags
                cleanFlags.remove(.function)
                if self.handleKeyDownCode(Int64(nsEvent.keyCode), flags: cleanFlags, isRepeat: nsEvent.isARepeat) {
                    return nil
                }
                return nsEvent
            }
        }
    }

    private func tryInstallCGEventTap() {
        guard eventTap == nil else { return }

        // Listen for both NX_SYSDEFINED (14) and standard keyDown (10)
        let sysDefinedMask = CGEventMask(1 << 14)
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let keyUpMask = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let combinedMask = sysDefinedMask | keyDownMask | keyUpMask

        let callback: CGEventTapCallBack = { proxy, type, cgEvent, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = MediaKeyInterceptor.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(cgEvent)
            }

            guard MediaKeyInterceptor.shared.isEnabled else {
                return Unmanaged.passUnretained(cgEvent)
            }

            // Case 1: NX_SYSDEFINED media key event (type == 14)
            if type.rawValue == 14 {
                if let nsEvent = NSEvent(cgEvent: cgEvent),
                   MediaKeyInterceptor.shared.handleSystemDefinedNSEvent(nsEvent) {
                    return nil // Swallow event so native blocked OSD doesn't appear
                }
                return Unmanaged.passUnretained(cgEvent)
            }

            // Case 2: Standard keyDown / keyUp (Fast early exit for normal typing keys < 72)
            if type == .keyDown || type == .keyUp {
                let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
                if keyCode != 145 && keyCode != 144 && keyCode != 122 && keyCode != 120 &&
                   keyCode != 107 && keyCode != 113 && keyCode != 109 && keyCode != 103 &&
                   keyCode != 111 && keyCode != 74  && keyCode != 73  && keyCode != 72 {
                    return Unmanaged.passUnretained(cgEvent)
                }

                let cgFlags = cgEvent.flags
                // Pass through to apps/IDEs if Command or Control is held
                // NOTE: Do NOT reject .maskSecondaryFn because macOS sets .maskSecondaryFn automatically on F1..F15!
                if cgFlags.contains(.maskCommand) || cgFlags.contains(.maskControl) {
                    return Unmanaged.passUnretained(cgEvent)
                }

                var nsFlags = NSEvent.ModifierFlags()
                if cgFlags.contains(.maskAlternate) { nsFlags.insert(.option) }
                if cgFlags.contains(.maskShift)     { nsFlags.insert(.shift) }

                if MediaKeyInterceptor.shared.isInterceptedFunctionKeyCode(keyCode, flags: nsFlags) {
                    if type == .keyDown {
                        _ = MediaKeyInterceptor.shared.handleKeyDownCode(keyCode, flags: nsFlags, isRepeat: false)
                    }
                    return nil
                }
            }

            return Unmanaged.passUnretained(cgEvent)
        }

        // Prefer .cghidEventTap (earliest hardware-level interception before WindowServer / OSDUIHelper)
        // with fallback to .cgSessionEventTap
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: combinedMask,
            callback: callback,
            userInfo: nil
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: combinedMask,
            callback: callback,
            userInfo: nil
        )

        if let tap = tap {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.isAccessibilityGranted = true
        }
    }

    private func handleSystemDefinedNSEvent(_ nsEvent: NSEvent) -> Bool {
        guard nsEvent.subtype.rawValue == 8 else { return false }
        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = (data1 & 0x0000FFFF)
        let keyState = ((keyFlags & 0xFF00) >> 8)
        // 0x0A = keyDown, 0x0B = keyUp
        let isKeyDown = (keyState == 0x0A)

        let flags = nsEvent.modifierFlags
        let isFineStep = flags.contains(.option)
        let brightnessStep = isFineStep ? 1 : 5
        let volumeStep = isFineStep ? 1 : 2

        switch keyCode {
        case Self.NX_KEYTYPE_BRIGHTNESS_UP:
            if isKeyDown {
                // Avoid double-stepping if keyDown (144/120) already handled this keystroke within 80ms
                if Date().timeIntervalSince(lastExternalBrightnessTapTime) > 0.08 {
                    lastExternalBrightnessTapTime = Date()
                    DispatchQueue.main.async {
                        HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: brightnessStep, showHUD: true)
                    }
                } else {
                    DispatchQueue.main.async {
                        HuaweiDDCEngine.shared.enforceBuiltInBrightnessLockIfNeeded()
                    }
                }
            }
            return true

        case Self.NX_KEYTYPE_BRIGHTNESS_DOWN:
            if isKeyDown {
                if Date().timeIntervalSince(lastExternalBrightnessTapTime) > 0.08 {
                    lastExternalBrightnessTapTime = Date()
                    DispatchQueue.main.async {
                        HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: -brightnessStep, showHUD: true)
                    }
                } else {
                    DispatchQueue.main.async {
                        HuaweiDDCEngine.shared.enforceBuiltInBrightnessLockIfNeeded()
                    }
                }
            }
            return true

        case Self.NX_KEYTYPE_SOUND_UP:
            if isKeyDown {
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepVolume(by: volumeStep, showHUD: true)
                }
            }
            return true

        case Self.NX_KEYTYPE_SOUND_DOWN:
            if isKeyDown {
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepVolume(by: -volumeStep, showHUD: true)
                }
            }
            return true

        case Self.NX_KEYTYPE_MUTE:
            if isKeyDown {
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.toggleMute(showHUD: true)
                }
            }
            return true

        default:
            return false
        }
    }

    private func isInterceptedFunctionKeyCode(_ keyCode: Int64, flags: NSEvent.ModifierFlags) -> Bool {
        // Don't intercept if Command, Control, or Shift-without-Option is held
        if flags.contains(.command) || flags.contains(.control) {
            return false
        }
        if flags.contains(.shift) && !flags.contains(.option) {
            return false
        }
        switch keyCode {
        case 145, 107, 122: // Brightness Down / F14 / F1
            return true
        case 144, 113, 120: // Brightness Up / F15 / F2
            return true
        case 74, 109:       // Mute / F10
            return true
        case 73, 103:       // Volume Down / F11
            return true
        case 72, 111:       // Volume Up / F12
            return true
        default:
            return false
        }
    }

    private func handleKeyDownCode(_ keyCode: Int64, flags: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard isInterceptedFunctionKeyCode(keyCode, flags: flags) else { return false }
        let isFineStep = flags.contains(.option)
        let brightnessStep = isFineStep ? 1 : 5
        let volumeStep = isFineStep ? 1 : 2

        switch keyCode {
        case 145, 107, 122: // F1 / Brightness Down
            if Date().timeIntervalSince(lastExternalBrightnessTapTime) > 0.08 {
                lastExternalBrightnessTapTime = Date()
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: -brightnessStep, showHUD: true)
                }
            } else {
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.enforceBuiltInBrightnessLockIfNeeded()
                }
            }
            return true

        case 144, 113, 120: // F2 / Brightness Up
            if Date().timeIntervalSince(lastExternalBrightnessTapTime) > 0.08 {
                lastExternalBrightnessTapTime = Date()
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.stepActiveDisplayBrightnessLocked(by: brightnessStep, showHUD: true)
                }
            } else {
                DispatchQueue.main.async {
                    HuaweiDDCEngine.shared.enforceBuiltInBrightnessLockIfNeeded()
                }
            }
            return true

        case 74, 109: // F10 / Mute
            DispatchQueue.main.async {
                HuaweiDDCEngine.shared.toggleMute(showHUD: true)
            }
            return true

        case 73, 103: // F11 / Volume Down
            DispatchQueue.main.async {
                HuaweiDDCEngine.shared.stepVolume(by: -volumeStep, showHUD: true)
            }
            return true

        case 72, 111: // F12 / Volume Up
            DispatchQueue.main.async {
                HuaweiDDCEngine.shared.stepVolume(by: volumeStep, showHUD: true)
            }
            return true

        default:
            return false
        }
    }
}
