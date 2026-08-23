//  NotificationSettingsView.swift

import SwiftUI

struct NotificationSettingsView: View {
    @Bindable private var preferences = AppServices.shared.preferences

    var body: some View {
        Form {
            Section {
                Toggle("When something degrades", isOn: $preferences.notifyOnDegradation)
                Toggle("When something recovers", isOn: $preferences.notifyOnRecovery)

                Picker("Only at or above", selection: $preferences.notifyMinimumSeverity) {
                    ForEach(NotificationSeverity.allCases) { severity in
                        Text(severity.threshold.title).tag(severity)
                    }
                }

                Toggle("Only for components shown on the cards", isOn: $preferences.notifyPrimaryOnly)
                Toggle("Play a sound", isOn: $preferences.notifySound)
            } header: {
                Text("Notify me")
            } footer: {
                Text("A component that stops being measurable is never announced as an outage — “we can no longer see this” is not the same as “this is broken”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Wait between alerts about the same component", selection: cooldownBinding) {
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                }
            } header: {
                Text("Frequency")
            } footer: {
                Text("A service losing several components at once arrives as one notification rather than a burst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quiet hours") {
                Toggle("Stay silent between", isOn: $preferences.quietHoursEnabled)

                HStack {
                    DatePicker("From", selection: quietStart, displayedComponents: .hourAndMinute)
                    DatePicker("to", selection: quietEnd, displayedComponents: .hourAndMinute)
                }
                .disabled(!preferences.quietHoursEnabled)
                .opacity(preferences.quietHoursEnabled ? 1 : 0.5)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 430)
    }

    private var cooldownBinding: Binding<Int> {
        Binding(
            get: { Int(preferences.notifyCooldown.components.seconds / 60) },
            set: { preferences.notifyCooldown = .seconds($0 * 60) }
        )
    }

    private var quietStart: Binding<Date> { minutesBinding(\.quietHoursStart) }
    private var quietEnd: Binding<Date> { minutesBinding(\.quietHoursEnd) }

    /// Quiet hours are stored as minutes past midnight; DatePicker wants a Date.
    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = preferences[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
