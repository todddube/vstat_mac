//  GeneralSettingsView.swift

import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable private var preferences = AppServices.shared.preferences
    private var coordinator: MonitorCoordinator { AppServices.shared.coordinator }

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Picker("Check every", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .onChange(of: preferences.refreshInterval) { _, _ in
                    coordinator.settingsChanged()
                }

                Toggle("Check on wake and when the network returns", isOn: $preferences.checkOnWake)
            } header: {
                Text("Monitoring")
            } footer: {
                Text("A laptop that has been closed for hours shows stale data until it checks again. Checking on wake is what keeps the menu bar honest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Close the popover after", selection: $preferences.popoverAutoClose) {
                    ForEach(PopoverAutoClose.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                Text("Popover")
            } footer: {
                Text("A depleting hairline shows the time remaining. Moving the pointer into the popover pauses it, and the pin button stops it for that visit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }

                if LaunchAtLogin.requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.status(.minor))
                        Text("Login items for Vibe Stats are turned off in System Settings.")
                            .font(.caption)
                        Button("Open…") { LaunchAtLogin.openSystemSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }

                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(Color.status(.critical))
                }

                Toggle("Show in the Dock as well as the menu bar", isOn: $preferences.showInDock)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 430)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            // Registration fails for an app running from a build directory, so
            // say why rather than silently snapping the switch back.
            launchAtLogin = LaunchAtLogin.isEnabled
            launchError = String(
                localized: "Could not change the login item: \(error.localizedDescription). Move Vibe Stats to Applications and try again."
            )
        }
    }
}
