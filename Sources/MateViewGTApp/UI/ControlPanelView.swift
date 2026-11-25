import SwiftUI
import AppKit

/// Unified macOS Native Control Center Panel for Huawei MateView GT 2026
/// Organized into 4 logical functional groups with consistent Segmented Bars & Full-Width Pill Sliders
public struct ControlPanelView: View {
    @ObservedObject var engine = HuaweiDDCEngine.shared
    @ObservedObject var hidpi = HiDPIManager.shared
    @ObservedObject var mediaKeys = MediaKeyInterceptor.shared
    @ObservedObject var launchAtLogin = LaunchAtLoginManager.shared
    public var onLayoutHeightChange: (() -> Void)?

    public init(onLayoutHeightChange: (() -> Void)? = nil) {
        self.onLayoutHeightChange = onLayoutHeightChange
    }

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            displayAndResolutionGroup
            soundGroup
            colorAndPictureGroup
            powerAndSystemGroup
            footerBar
        }
        .padding(12)
        .frame(width: 324)
        .background(
            LiquidGlassBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - Top Header Bar
    private var headerBar: some View {
        HStack(spacing: 7) {
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let appIcon = NSImage(contentsOf: iconURL) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            }
            Text("MateView GT Control")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    engine.triggerDisplayPowerOffWithGracePeriod()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: engine.isPowerOffCountdown ? "xmark" : "moon.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text(engine.isPowerOffCountdown ? "取消" : "息屏")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(engine.isPowerOffCountdown ? .white : .primary.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(engine.isPowerOffCountdown ? Color.accentColor : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            Button(action: {
                engine.refreshFromHardware()
                hidpi.refreshCurrentMode()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Group 1: Display Brightness & HiDPI Scaling
    private var displayAndResolutionGroup: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 9) {
                // 1. MateView GT Brightness
                HStack(alignment: .firstTextBaseline) {
                    Text("显示器")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(engine.currentNits) nits · \(engine.brightness)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                LiquidGlassSlider(
                    value: $engine.brightness,
                    range: 0...100,
                    iconName: engine.brightness > 50 ? "sun.max.fill" : "sun.min.fill",
                    tooltipText: { val in
                        "\(HuaweiDDCEngine.nits(forBrightness: val)) nits · \(val)"
                    },
                    onChange: { newVal in
                        engine.setBrightness(newVal)
                    }
                )

                // Quick Brightness Scene Bar (Unified Segmented Control)
                let activeQuickPreset = NitsQuickPreset.allPresets.first {
                    abs(engine.brightness - $0.brightnessPercent) <= 2
                }
                NativeSegmentedBar(
                    items: NitsQuickPreset.allPresets,
                    selected: activeQuickPreset,
                    compact: true,
                    label: { $0.label },
                    onSelect: { preset in
                        engine.setBrightness(preset.brightnessPercent)
                    }
                )

                // 2. MacBook Air Built-in Display Brightness
                if engine.hasMacBookDisplay {
                    Divider().opacity(0.35)

                    HStack(alignment: .firstTextBaseline) {
                        Text("内建视网膜屏幕")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(engine.currentMacBookNits) nits · \(engine.macBookBrightness)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    LiquidGlassSlider(
                        value: $engine.macBookBrightness,
                        range: 0...100,
                        iconName: engine.macBookBrightness > 50 ? "sun.max.fill" : "sun.min.fill",
                        tooltipText: { val in
                            "\(HuaweiDDCEngine.macBookNits(forBrightness: val)) nits · \(val)"
                        },
                        onChange: { newVal in
                            engine.setMacBookBrightness(newVal)
                        }
                    )
                }

                Divider().opacity(0.35)

                // 3. HiDPI Resolution Scaling (Integrated cleanly inside Display Card)
                HStack(alignment: .firstTextBaseline) {
                    Text("分辨率缩放")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(hidpi.currentWidth)×\(hidpi.currentHeight) · \(hidpi.currentRefreshRate)Hz")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                let activeHiDPI = HiDPIResolutionPreset.goldenPresets.first {
                    hidpi.currentWidth == $0.width && hidpi.currentHeight == $0.height && hidpi.isCurrentHiDPI == $0.isHiDPI
                }
                NativeSegmentedBar(
                    items: HiDPIResolutionPreset.goldenPresets,
                    selected: activeHiDPI,
                    compact: true,
                    label: { $0.label },
                    onSelect: { preset in
                        hidpi.applyResolution(preset)
                    }
                )
            }
        }
    }

    // MARK: - Group 2: Sound & Speaker Routing
    private var soundGroup: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center) {
                    Text("声音")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Unified Segmented Audio Output Switcher
                    HStack(spacing: 2) {
                        speakerRouteTab(title: "显示器", isSelected: engine.isAudioRoutedToMonitor) {
                            engine.switchAudioOutput(toMonitor: true)
                        }
                        speakerRouteTab(title: "内置", isSelected: !engine.isAudioRoutedToMonitor) {
                            engine.switchAudioOutput(toMonitor: false)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.black.opacity(0.14))
                    )
                    .frame(width: 96)

                    Spacer().frame(width: 6)

                    Text(currentVolumeReadout)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }

                if engine.isAudioRoutedToMonitor {
                    LiquidGlassSlider(
                        value: $engine.volume,
                        range: 0...100,
                        iconName: volumeIconName(vol: engine.volume, muted: engine.isMuted),
                        isMutedOrDimmed: engine.isMuted || engine.volume == 0,
                        tooltipText: { val in "\(val)" },
                        onIconTap: {
                            engine.toggleMute(showHUD: false)
                        },
                        onChange: { newVal in
                            engine.setVolume(newVal)
                        }
                    )
                } else {
                    LiquidGlassSlider(
                        value: $engine.macBookVolume,
                        range: 0...100,
                        iconName: volumeIconName(vol: engine.macBookVolume, muted: engine.isMacBookMuted),
                        isMutedOrDimmed: engine.isMacBookMuted || engine.macBookVolume == 0,
                        tooltipText: { val in "\(val)" },
                        onIconTap: {
                            engine.toggleMute(showHUD: false)
                        },
                        onChange: { newVal in
                            engine.setMacBookVolume(newVal)
                        }
                    )
                }
            }
        }
    }

    private var currentVolumeReadout: String {
        if engine.isAudioRoutedToMonitor {
            return engine.isMuted ? "静音" : "\(engine.volume)"
        } else {
            return engine.isMacBookMuted ? "静音" : "\(engine.macBookVolume)"
        }
    }

    private func speakerRouteTab(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2.5)
                .foregroundColor(isSelected ? .white : .primary.opacity(0.75))
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func volumeIconName(vol: Int, muted: Bool) -> String {
        if muted || vol == 0 {
            return "speaker.slash.fill"
        } else if vol < 34 {
            return "speaker.wave.1.fill"
        } else if vol < 67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    // MARK: - Group 3: Color Mode, Color Temp & Image Tuning (All visual settings unified in ONE card)
    private var colorAndPictureGroup: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 9) {
                // 1. 2x2 Preset Modes
                Text("色彩模式")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                    ForEach(MateViewPresetMode.allCases) { mode in
                        let isSelected = (engine.activePreset == mode)
                        Button(action: {
                            engine.applyPresetMode(mode)
                        }) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
                                }

                                Text(mode.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(0.11) : Color.black.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07),
                                        lineWidth: 0.6
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.35)

                // 2. Hardware Color Temp (Unified Segmented Bar)
                HStack(alignment: .center) {
                    Text("硬件色温")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }

                NativeSegmentedBar(
                    items: HardwareColorTemp.allCases,
                    selected: engine.colorTemp,
                    compact: true,
                    label: { $0.shortTitle },
                    onSelect: { temp in
                        engine.setHardwareColorTemp(temp)
                        onLayoutHeightChange?()
                    }
                )

                if engine.colorTemp == .customRGB {
                    VStack(spacing: 6) {
                        nativeMiniSlider(label: "R", value: $engine.redGain, range: 0...100) {
                            engine.setRGBGain(red: $0)
                        }
                        nativeMiniSlider(label: "G", value: $engine.greenGain, range: 0...100) {
                            engine.setRGBGain(green: $0)
                        }
                        nativeMiniSlider(label: "B", value: $engine.blueGain, range: 0...100) {
                            engine.setRGBGain(blue: $0)
                        }
                    }
                    .padding(.top, 2)
                }

                Divider().opacity(0.35)

                // 3. Collapsible Image Fine-Tuning inside the same Color & Picture Card
                Button(action: {
                    engine.isTuningExpanded.toggle()
                    onLayoutHeightChange?()
                }) {
                    HStack {
                        Text("画质微调")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(engine.isTuningExpanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if engine.isTuningExpanded {
                    VStack(spacing: 7) {
                        nativeMiniSlider(label: "彩墨度", value: $engine.saturation, range: 0...20) {
                            engine.setSaturation($0)
                        }
                        nativeMiniSlider(label: "对比度", value: $engine.contrast, range: 0...100) {
                            engine.setContrast($0)
                        }
                        nativeMiniSlider(label: "锐度", value: $engine.sharpness, range: 0...100) {
                            engine.setSharpness($0)
                        }

                        HStack {
                            Spacer()
                            Button("重置") {
                                engine.resetCurrentModeTuningToDefault()
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Group 4: 护眼、自动化与系统偏好 (Eye Care, Power & System Preferences)
    private var powerAndSystemGroup: some View {
        LiquidGlassCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("开机自启")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 14)
                        .opacity(0.35)

                    HStack(spacing: 6) {
                        Text("跟随深色模式")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: $engine.autoDarkModeSync)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider().opacity(0.35)

                HStack(alignment: .center, spacing: 8) {
                    Text("自动息屏")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    NativeSegmentedBar(
                        items: AutoPowerOffInterval.allCases,
                        selected: engine.autoPowerOffInterval,
                        compact: true,
                        label: { $0.label },
                        onSelect: { interval in
                            engine.autoPowerOffInterval = interval
                        }
                    )
                    .frame(width: 196)
                }
            }
        }
    }

    private func nativeMiniSlider(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { newVal in
                        let intVal = Int(round(newVal))
                        if intVal != value.wrappedValue {
                            value.wrappedValue = intVal
                            onChange(intVal)
                        }
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .controlSize(.small)

            Text("\(value.wrappedValue)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    // MARK: - Bottom Bar
    private var footerBar: some View {
        HStack {
            Toggle("状态栏尼特", isOn: $engine.showNitsInMenuBar)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            if !mediaKeys.isAccessibilityGranted {
                Button("授权快捷键") {
                    mediaKeys.requestAccessibilityPermissionPrompt()
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.accentColor)
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
}
