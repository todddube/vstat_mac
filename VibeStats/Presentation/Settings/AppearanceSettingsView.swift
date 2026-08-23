//  AppearanceSettingsView.swift
//  Every option previews itself with the real renderer — a picker that names
//  three icon styles without showing them is a guessing game.

import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable private var preferences = AppServices.shared.preferences
    private var coordinator: MonitorCoordinator { AppServices.shared.coordinator }

    var body: some View {
        Form {
            Section("Menu bar icon") {
                Picker("Style", selection: $preferences.iconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Preview") {
                    IconPreviewStrip(
                        style: preferences.iconStyle,
                        renderMode: preferences.iconRenderMode,
                        showBadge: preferences.showBadgeCount
                    )
                }

                Picker("Colour", selection: $preferences.iconRenderMode) {
                    ForEach(IconRenderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Show the affected-component count", isOn: $preferences.showBadgeCount)
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

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                VStack(spacing: 3) {
                    Image(nsImage: image(for: sample.0, affected: sample.1))
                        .frame(height: 18)
                    Text(sample.0.compactTitle)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func image(for indicator: StatusIndicator, affected: Int) -> NSImage {
        var state = IconState()
        state.indicator = indicator
        state.affectedCount = affected
        state.style = style
        state.renderMode = renderMode
        state.showBadge = showBadge
        state.motion = .off
        state.services = [
            .claude: .operational, .github: indicator,
            .openai: .operational, .gemini: .operational
        ]

        let image = VibeIconRenderer.image(for: state)
        // A template image would be tinted black on the settings background;
        // the preview needs to show the icon, not a silhouette.
        image.isTemplate = false
        return image
    }
}
