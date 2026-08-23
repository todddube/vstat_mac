//  ServicesSettingsView.swift
//  The registry as a debugging surface: each component shows the vendor's own
//  name and raw status beside it, so a rename shows up here as UNRESOLVED
//  before it shows up as a wrong answer in the popover.

import SwiftUI

struct ServicesSettingsView: View {
    @Bindable private var preferences = AppServices.shared.preferences
    private var coordinator: MonitorCoordinator { AppServices.shared.coordinator }

    @State private var expanded: Set<ServiceID> = []

    var body: some View {
        Form {
            Section {
                ForEach(ServiceRegistry.all) { definition in
                    row(for: definition)
                }
            } header: {
                Text("Monitored services")
            } footer: {
                Text("A disabled service is not fetched at all and does not contribute to the combined status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 430)
    }

    @ViewBuilder
    private func row(for definition: ServiceDefinition) -> some View {
        let snapshot = coordinator.snapshot?[definition.id]
        let isEnabled = preferences.isEnabled(definition.id)

        DisclosureGroup(
            isExpanded: Binding(
                get: { expanded.contains(definition.id) },
                set: { isExpanded in
                    if isExpanded { expanded.insert(definition.id) }
                    else { expanded.remove(definition.id) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(definition.components) { component in
                    componentRow(component, state: snapshot?.component(id: component.id))
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 9) {
                Text(String(definition.name.prefix(1)))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accent(definition.id))
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accent(definition.id).opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(definition.name)
                    Text(resolutionSummary(definition, snapshot))
                        .font(.caption)
                        .foregroundStyle(summaryColor(snapshot))
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        preferences.setEnabled(newValue, for: definition.id)
                        coordinator.settingsChanged()
                    }
                ))
                .labelsHidden()
                .accessibilityLabel(String(localized: "Monitor \(definition.name)"))
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func componentRow(_ definition: ComponentDefinition, state: ComponentState?) -> some View {
        HStack(spacing: 8) {
            StatusDot(indicator: state?.indicator ?? .unknown, size: 6)

            Text(definition.label)
                .font(.system(size: 11))
                .frame(width: 96, alignment: .leading)

            if definition.isPrimary {
                Text("PRIMARY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            // The vendor's own name for it — the thing that actually drifts.
            Text(state?.matchedName ?? String(localized: "unresolved"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(state?.matched == true ? .secondary : Color.status(.unknown))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(state?.rawStatus.map { "Vendor status: \($0)" } ?? String(localized: "Not found on the status page"))
    }

    private func resolutionSummary(_ definition: ServiceDefinition, _ snapshot: ServiceSnapshot?) -> String {
        guard let snapshot else {
            return String(localized: "\(definition.components.count) components · not checked yet")
        }
        if snapshot.isFullyResolved {
            return String(localized: "\(snapshot.componentsWatched) components · all resolved")
        }
        return String(localized: "\(snapshot.componentsResolved) of \(snapshot.componentsWatched) components resolved")
    }

    private func summaryColor(_ snapshot: ServiceSnapshot?) -> Color {
        guard let snapshot else { return .secondary }
        return snapshot.isFullyResolved ? .secondary : Color.status(.unknown)
    }
}
