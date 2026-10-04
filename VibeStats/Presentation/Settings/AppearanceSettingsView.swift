//  AppearanceSettingsView.swift
//  Every option previews itself with the real renderer — a picker that names
//  three icon styles without showing them is a guessing game.

import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable private var preferences = AppServices.shared.preferences
    private var demo: IconDemo { IconDemo.shared }
    private var coordinator: MonitorCoordinator { AppServices.shared.coordinator }

    var body: some View {
        Form {
            Section {
                // A segmented picker of three nouns made the choice look
                // inconsequential and hid the only thing that distinguishes
                // them — the shape. The cards ARE the picker.
                HStack(spacing: 10) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        IconStyleCard(
                            style: style,
                            renderMode: preferences.iconRenderMode,
                            isSelected: preferences.iconStyle == style
                        ) {
                            preferences.iconStyle = style
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Menu bar icon")
            }

            Section {
                IconPreviewStrip(
                    style: preferences.iconStyle,
                    renderMode: preferences.iconRenderMode,
                    showBadge: preferences.showBadgeCount
                )
                .frame(maxWidth: .infinity)

                Picker("Colour", selection: $preferences.iconRenderMode) {
                    ForEach(IconRenderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Show the affected-component count", isOn: $preferences.showBadgeCount)

                Picker("Text beside the icon", selection: $preferences.menuBarTextMode) {
                    Text("None").tag(MenuBarTextMode.none)
                    Text("Status").tag(MenuBarTextMode.shortLabel)
                    Text("Affected count").tag(MenuBarTextMode.affectedCount)
                }
            } header: {
                Text("Every state, as it will appear")
            }

            Section {
                MenuBarDemoRow(demo: demo)
            } header: {
                Text("Try it for real")
            }

            Section {
                Picker("Animations", selection: $preferences.motionLevel) {
                    ForEach(MotionLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .disabled(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            } header: {
                Text("Motion")
            } footer: {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Label(
                        "Reduce Motion is on in System Settings, so animations are off regardless of this setting.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Full adds a slow ambient pulse to a healthy icon. Subtle keeps only the outage pulse. Off disables everything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 430)
        .onChange(of: preferences.iconStyle) { _, _ in refreshIcon() }
        .onChange(of: preferences.iconRenderMode) { _, _ in refreshIcon() }
        .onChange(of: preferences.showBadgeCount) { _, _ in refreshIcon() }
        .onChange(of: preferences.motionLevel) { _, _ in refreshIcon() }
        .onChange(of: preferences.menuBarTextMode) { _, _ in refreshIcon() }
    }

    /// Nudges the coordinator so the status item re-renders immediately rather
    /// than at the next scheduled check.
    private func refreshIcon() {
        NotificationCenter.default.post(name: .vibeStatsAppearanceChanged, object: nil)
    }
}

extension Notification.Name {
    static let vibeStatsAppearanceChanged = Notification.Name("VibeStatsAppearanceChanged")
}

/// The same states the menu bar can show, drawn by the same renderer.
struct IconPreviewStrip: View {
    let style: MenuBarIconStyle
    let renderMode: IconRenderMode
    let showBadge: Bool

    private let samples: [(StatusIndicator, Int)] = [
        (.operational, 0), (.minor, 1), (.major, 2), (.critical, 3), (.unknown, 0)
    ]

    /// Twice menu bar size: at 18 points the difference between the styles is
    /// real but not reviewable.
    private static let scale: CGFloat = 2

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                VStack(spacing: 5) {
                    Image(nsImage: image(for: sample.0, affected: sample.1))
                        .frame(height: VibeIconRenderer.canvas * Self.scale)
                    Text(sample.0.compactTitle)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func image(for indicator: StatusIndicator, affected: Int) -> NSImage {
        var state = IconState()
        state.indicator = indicator
        state.affectedCount = affected
        state.style = style
        state.renderMode = renderMode
        state.showBadge = showBadge
        state.motion = .off
        state.services = IconState.sample(indicator)

        let image = VibeIconRenderer.image(for: state, scale: Self.scale)
        // A template image would be tinted black on the settings background;
        // the preview needs to show the icon, not a silhouette.
        image.isTemplate = false
        return image
    }
}

/// One selectable style, drawn large enough to actually choose by.
struct IconStyleCard: View {
    let style: MenuBarIconStyle
    let renderMode: IconRenderMode
    let isSelected: Bool
    let select: () -> Void

    private static let scale: CGFloat = 2.4

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    glyph(.operational)
                    glyph(.critical)
                }
                .frame(height: VibeIconRenderer.canvas * Self.scale)

                Text(style.title)
                    .font(.callout.weight(.semibold))
                Text(style.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        // Selection is carried by a border AND a checked state, never by the
        // tint alone.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(style.title): \(style.subtitle)")
    }

    /// Healthy beside an outage: one glyph shows the shape, the pair shows what
    /// the style does when something breaks, which is the point of choosing.
    private func glyph(_ indicator: StatusIndicator) -> some View {
        var state = IconState()
        state.indicator = indicator
        state.style = style
        state.renderMode = renderMode
        // The badge is the same digit in every style, so it is left out here —
        // the card is about the mark. The strip below shows it in place.
        state.showBadge = false
        state.motion = .off
        state.services = IconState.sample(indicator, spreading: indicator == .critical)

        // Phase 0.5 puts the Pulse complex in the middle of the card; at phase
        // 0 it sits on the left edge, half of it outside the canvas.
        let image = VibeIconRenderer.image(for: state, phase: 0.5, scale: Self.scale)
        image.isTemplate = false
        return Image(nsImage: image)
    }
}

/// The "Test in menu bar" control. While the demo runs it points at the menu
/// bar and names the state on show, so a glyph you have never seen before
/// arrives with its meaning attached.
struct MenuBarDemoRow: View {
    let demo: IconDemo

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let step = demo.current {
                Image(systemName: "arrow.up")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.vibe)
                    .symbolEffect(.bounce, options: .repeating)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look at your menu bar")
                        .font(.headline)
                    Text("Now showing: \(step.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                Button("Stop") { demo.stop() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Test in menu bar")
                    Text("Plays every status on the real icon for 10 seconds in this style, then returns to live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Test") { demo.start() }
                    .keyboardShortcut("t", modifiers: .command)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: demo.current)
    }
}
