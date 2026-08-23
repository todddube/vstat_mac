//  ComponentRowView.swift

import SwiftUI

struct ComponentRowView: View {
    let component: ComponentState

    var body: some View {
        HStack(spacing: 8) {
            Text(component.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            StatusDot(indicator: component.indicator, size: 6)

            // Monospaced so the rows do not jitter as states change width, and
            // so the readout feels measured rather than marketed.
            Text(component.indicator.compactTitle)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(Color.status(component.indicator))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.28)))
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.label), \(component.indicator.title)")
    }

    private var tooltip: String {
        if !component.matched {
            return String(localized: "No component named “\(component.label)” was found on the status page")
        }
        if component.provenance == .derivedFromIncidents {
            return String(localized: """
                \(component.matchedName ?? component.label) — inferred from incidents.
                Google publishes no per-component health, so this is the absence of a \
                matching incident rather than a reported status.
                """)
        }
        return "\(component.matchedName ?? component.label) — \(component.rawStatus ?? "unknown")"
    }
}
