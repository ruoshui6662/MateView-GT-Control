import SwiftUI
import AppKit

/// Native AppKit NSVisualEffectView wrapper for macOS Control Center translucent glass
public struct LiquidGlassBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Unified macOS Control Center module card
public struct LiquidGlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(
        cornerRadius: CGFloat = 13,
        padding: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// Unified macOS Control Center Segmented Pill Selector (Inset groove + raised active pill)
public struct NativeSegmentedBar<T: Identifiable & Equatable>: View {
    public let items: [T]
    public let selected: T?
    public let label: (T) -> String
    public var compact: Bool
    public let onSelect: (T) -> Void

    public init(
        items: [T],
        selected: T?,
        compact: Bool = false,
        label: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) {
        self.items = items
        self.selected = selected
        self.compact = compact
        self.label = label
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = (selected == item)
                Button(action: {
                    onSelect(item)
                }) {
                    Text(label(item))
                        .font(.system(size: compact ? 10.5 : 11, weight: isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 4 : 5)
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.78))
                        .background(
                            RoundedRectangle(cornerRadius: compact ? 5.5 : 6.5, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                                .shadow(color: isSelected ? Color.black.opacity(0.14) : .clear, radius: 2, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: compact ? 7.5 : 8.5, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 7.5 : 8.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// Authentic macOS Control Center Full-Width White Pill Slider
/// - Symmetrical [-] and [+] buttons on left and right ends
/// - Center track supports both instant click-to-jump (minimumDistance: 0) and smooth drag
public struct LiquidGlassSlider: View {
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    public let iconName: String
    public let isMutedOrDimmed: Bool
    public let tooltipText: (Int) -> String
    public let onIconTap: (() -> Void)?
    public let onChange: (Int) -> Void

    @State private var isDragging: Bool = false

    public init(
        value: Binding<Int>,
        range: ClosedRange<Int> = 0...100,
        iconName: String,
        isMutedOrDimmed: Bool = false,
        tooltipText: @escaping (Int) -> String,
        onIconTap: (() -> Void)? = nil,
        onChange: @escaping (Int) -> Void
    ) {
        self._value = value
        self.range = range
        self.iconName = iconName
        self.isMutedOrDimmed = isMutedOrDimmed
        self.tooltipText = tooltipText
        self.onIconTap = onIconTap
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Left end: Minus (-1) button
            Button(action: {
                let next = max(range.lowerBound, value - 1)
                value = next
                onChange(next)
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Center: Click-anywhere & Drag White Pill Slider Track
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let totalSpan = CGFloat(max(1, range.upperBound - range.lowerBound))
                let normalized = CGFloat(value - range.lowerBound) / totalSpan
                let fillWidth = max(0, min(width, width * normalized))

                ZStack(alignment: .leading) {
                    // Recessed dark glass track
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.20))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                        )

                    // Pure white translucent pill fill
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isMutedOrDimmed ? 0.35 : 0.92))
                        .frame(width: max(26, fillWidth))
                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 0.5)

                    // Left icon inside track
                    HStack(spacing: 0) {
                        if let onIconTap = onIconTap {
                            Button(action: onIconTap) {
                                Image(systemName: iconName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.75))
                                    .frame(width: 26, height: 26)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: iconName)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.75))
                                .frame(width: 26, height: 26)
                                .allowsHitTesting(false)
                        }
                        Spacer()
                            .allowsHitTesting(false)
                    }
                    .padding(.leading, 2)

                    // Minimalist floating value badge while clicking/dragging
                    if isDragging {
                        Text(tooltipText(value))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                            .offset(x: max(2, min(width - 90, fillWidth - 42)), y: -25)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if !isDragging {
                                isDragging = true
                            }
                            let ratio = max(0, min(1, drag.location.x / width))
                            let computed = range.lowerBound + Int(round(ratio * totalSpan))
                            if computed != value {
                                value = computed
                                onChange(computed)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 26)

            // Right end: Plus (+1) button
            Button(action: {
                let next = min(range.upperBound, value + 1)
                value = next
                onChange(next)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
