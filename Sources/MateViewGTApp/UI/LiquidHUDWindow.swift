import SwiftUI
import AppKit

/// Minimalist macOS native On-Screen Display (HUD) for Brightness (Nits + 1-100) and Volume (1-100)
public final class LiquidHUDManager: ObservableObject {
    public static let shared = LiquidHUDManager()

    @Published public var iconName: String = "sun.max.fill"
    @Published public var title: String = "显示器"
    @Published public var valuePercent: Int = 75
    @Published public var badgeText: String = "346 nits · 75 / 100"

    private var hudPanel: NSPanel?
    private var hideTimer: Timer?

    private init() {}

    public func showBrightnessHUD(title: String = "MateView GT", percent: Int, nits: Int) {
        DispatchQueue.main.async {
            self.iconName = percent > 50 ? "sun.max.fill" : "sun.min.fill"
            self.title = title
            self.valuePercent = percent
            self.badgeText = "\(nits) nits · \(percent)"
            self.presentHUD()
        }
    }

    public func showVolumeHUD(title: String = "声音", percent: Int, isMuted: Bool) {
        DispatchQueue.main.async {
            if isMuted || percent == 0 {
                self.iconName = "speaker.slash.fill"
                self.badgeText = "静音 · \(percent)"
            } else if percent < 34 {
                self.iconName = "speaker.wave.1.fill"
                self.badgeText = "\(percent)"
            } else if percent < 67 {
                self.iconName = "speaker.wave.2.fill"
                self.badgeText = "\(percent)"
            } else {
                self.iconName = "speaker.wave.3.fill"
                self.badgeText = "\(percent)"
            }
            self.title = title
            self.valuePercent = isMuted ? 0 : percent
            self.presentHUD()
        }
    }

    private func presentHUD() {
        if hudPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 62),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: LiquidHUDContentView(manager: self))
            self.hudPanel = panel
        }

        if let panel = hudPanel {
            let mouseLoc = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
            if let screen = activeScreen {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - (panel.frame.width / 2)
                let y = screenFrame.minY + 64
                panel.setFrameOrigin(NSPoint(x: x, y: y))
                panel.alphaValue = 1.0
                panel.orderFrontRegardless()
            }
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
            guard let panel = self?.hudPanel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
    }
}

private struct LiquidHUDContentView: View {
    @ObservedObject var manager: LiquidHUDManager

    var body: some View {
        ZStack {
            LiquidGlassBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                )

            VStack(spacing: 7) {
                HStack {
                    Image(systemName: manager.iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                    Text(manager.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(manager.badgeText)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let fill = max(6, w * CGFloat(manager.valuePercent) / 100.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.22))
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: fill)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
        }
        .frame(width: 280, height: 62)
    }
}
