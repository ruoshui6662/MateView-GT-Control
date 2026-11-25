import SwiftUI
import AppKit

/// Custom borderless floating panel (just like macOS Native Control Center - no ugly popover triangle arrow!)
private final class ControlCenterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: ControlCenterPanel?
    private var hostingView: NSHostingView<ControlPanelView>?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon to run as a native macOS menu bar utility
        NSApp.setActivationPolicy(.accessory)

        setupFloatingPanel()
        setupStatusItem()

        // Hook up real-time Nits update in Menu Bar
        HuaweiDDCEngine.shared.onMenuBarTitleUpdate = { [weak self] in
            self?.updateStatusItemAppearance()
        }

        // Start native keyboard Brightness / Volume / Mute media key interception
        MediaKeyInterceptor.shared.start()

        // Close panel when clicking outside
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, let panel = self.panel, panel.isVisible {
                self.closePanel()
            }
        }

        // Close panel on ESC key
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self = self, let panel = self.panel, panel.isVisible {
                self.closePanel()
                return nil
            }
            return event
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Restore default macOS hardware brightness key mapping when app quits
        MediaKeyInterceptor.shared.applyHardwareBrightnessKeyRemap(enable: false)

        // Safety guarantee: if user quits app while screens are idle-dimmed or powered off, restore backlights immediately!
        if HuaweiDDCEngine.shared.isDisplayPoweredOff || HuaweiDDCEngine.shared.isIdleDimmed {
            HuaweiDDCEngine.shared.wakeDisplayFromStandby()
        }
    }

    private func setupFloatingPanel() {
        let rootView = ControlPanelView { [weak self] in
            self?.repositionPanelKeepingTopEdge()
        }
        let hosting = NSHostingView(rootView: rootView)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }
        let fitting = hosting.fittingSize

        let p = ControlCenterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: max(380, fitting.height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.contentView = hosting

        self.hostingView = hosting
        self.panel = p
    }

    private func computeIdealPanelFrame() -> NSRect? {
        guard let hosting = hostingView else { return nil }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        let idealSize = hosting.fittingSize
        guard idealSize.height > 10 else { return nil }

        // Determine the screen where the status item button currently resides (fallback to mouse screen or main screen)
        let buttonWindow = statusItem?.button?.window
        let targetScreen = buttonWindow?.screen
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main

        guard let screen = targetScreen else { return nil }
        let screenFullFrame = screen.frame
        let screenVisibleFrame = screen.visibleFrame

        var x = screenFullFrame.maxX - idealSize.width - 12
        var topY = screenVisibleFrame.maxY - 6

        if let button = statusItem?.button, let btnWin = button.window {
            let btnRect = btnWin.convertToScreen(button.convert(button.bounds, to: nil))
            // Sanity check: only use btnRect.minY if it is actually in the top menu bar zone of the screen
            // (Guards against macOS "Click Wallpaper to Show Desktop" / Expose temporarily shifting status bar window coordinates!)
            if btnRect.minY >= screenFullFrame.maxY - 60 && btnRect.minY <= screenFullFrame.maxY {
                topY = btnRect.minY - 6
            }
            if btnRect.midX >= screenFullFrame.minX && btnRect.midX <= screenFullFrame.maxX {
                x = btnRect.midX - (idealSize.width / 2)
            }
        }

        x = max(screenFullFrame.minX + 8, min(screenFullFrame.maxX - idealSize.width - 8, x))
        let y = topY - idealSize.height

        return NSRect(x: round(x), y: round(y), width: idealSize.width, height: idealSize.height)
    }

    private func repositionPanelKeepingTopEdge() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let panel = self.panel, let newFrame = self.computeIdealPanelFrame() else { return }
            if panel.frame != newFrame {
                panel.setFrame(newFrame, display: true, animate: false)
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        if let button = item.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        updateStatusItemAppearance()
    }

    public func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let engine = HuaweiDDCEngine.shared

        if let resURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let customImg = NSImage(contentsOf: resURL) {
            customImg.size = NSSize(width: 18, height: 18)
            customImg.isTemplate = true
            button.image = customImg
        } else if let img = NSImage(systemSymbolName: "display", accessibilityDescription: "MateView GT") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            button.image = img.withSymbolConfiguration(config)
        }

        if engine.showNitsInMenuBar {
            let titleStr = " \(engine.currentNits) nits"
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            button.attributedTitle = NSAttributedString(
                string: titleStr,
                attributes: [
                    .font: font,
                    .baselineOffset: -0.5
                ]
            )
        } else {
            button.title = ""
        }
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        guard let panel = panel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let panel = panel else { return }
        if HuaweiDDCEngine.shared.isDisplayPoweredOff {
            HuaweiDDCEngine.shared.wakeDisplayFromStandby()
        } else {
            HuaweiDDCEngine.shared.pollQuickHardwareState()
        }
        HiDPIManager.shared.refreshCurrentMode()
        MediaKeyInterceptor.shared.refreshStatus()
        LaunchAtLoginManager.shared.refreshStatus()

        // Set exact frame synchronously BEFORE showing window so Show Desktop / Expose never flashes it at the wrong edge
        if let targetFrame = computeIdealPanelFrame() {
            panel.setFrame(targetFrame, display: true, animate: false)
        }
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        guard let panel = panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

@main
public struct MateViewGTMain {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
