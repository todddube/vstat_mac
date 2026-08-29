//  ServiceCardView.swift
//
//  The card is a real button — focusable and ↩-activatable — which the
//  extension's <div>-with-a-click-handler was not (docs/REVIEW.md §3.8).

import SwiftUI

struct ServiceCardView: View {
    let definition: ServiceDefinition
    let snapshot: ServiceSnapshot?
    let history: [HistorySample]
    let motion: MotionLevel
    /// True when the popover was opened from this service's notification.
    var isFocused: Bool = false

    @State private var showsIncidents = false
    @Environment(\.openURL) private var openURL

    private var indicator: StatusIndicator { snapshot?.indicator ?? .unknown }

    /// Primary components always; PLUS any non-primary component that is not
    /// operational. A verdict must never come from a component the user cannot
    /// see (docs/REVIEW.md §3.7).
    private var visibleComponents: [ComponentState] {
        guard let snapshot else {
            return definition.primaryComponents.map { definition in
                ComponentState(
                    id: definition.id, label: definition.label, isPrimary: true,
                    matched: false, matchedName: nil, rawStatus: nil,
                    indicator: .unknown, detail: nil, provenance: .reported
                )
            }
        }
        return snapshot.components.filter { $0.isPrimary || $0.isAlwaysVisible }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.accent(definition.id))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 9) {
                header
                statusRow
                components

                if !history.isEmpty {
                    SparklineView(samples: history)
                }

                incidentsDisclosure
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                // The focus ring uses the vendor accent at full strength, which
                // is 2 pt against a 1 pt hairline — legible without colour
                // alone carrying it, since it is also the card scrolled to.
                .strokeBorder(
                    isFocused ? Color.accent(definition.id) : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(Motion.animation(.transition, level: motion), value: isFocused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(definition.name.prefix(1)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accent(definition.id))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7).fill(Color.accent(definition.id).opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(definition.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)

                // The subtitle flips from the vendor's name to naming what is
                // degraded — the fastest possible answer to "what broke".
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(hasAffected ? Color.status(.major) : Color.secondary)
                    .fontWeight(hasAffected ? .semibold : .regular)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                openURL(definition.statusURL)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open \(definition.name) status page"))
            .accessibilityLabel(String(localized: "Open \(definition.name) status page"))
        }
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            StatusChip(indicator: indicator)

            if let snapshot, snapshot.divergesFromPage {
                DivergenceChip(pageIndicator: snapshot.pageIndicator, ourIndicator: indicator)
            }

            Spacer(minLength: 0)
        }
        // Two chips can exceed a 195 pt card. Scaling beats wrapping: a
        // half-height second line of "Outage" reads as a rendering bug.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var components: some View {
        VStack(spacing: 4) {
            ForEach(visibleComponents) { component in
                ComponentRowView(component: component)
            }

            if let snapshot, snapshot.unresolvedCount > 0 {
                // Never let an unmeasured component vanish into "healthy".
                Text("\(snapshot.unresolvedCount) of \(snapshot.componentsWatched) components unresolved")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.status(.unknown))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
        }
    }

    private var incidentsDisclosure: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(Motion.animation(.disclosure, level: motion)) {
                    showsIncidents.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(incidentLabel)
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(showsIncidents ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.separator.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsIncidents ? "Collapse incidents" : "Expand incidents")

            if showsIncidents {
                IncidentListView(incidents: snapshot?.incidents ?? [])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Derived text

    private var hasAffected: Bool { !(snapshot?.affectedComponents.isEmpty ?? true) }

    private var subtitle: String {
        guard let affected = snapshot?.affectedComponents, !affected.isEmpty else {
            return definition.vendor
        }
        return affected.joined(separator: ", ")
    }

    private var incidentLabel: String {
        let count = snapshot?.incidents.count ?? 0
        return count == 0
            ? String(localized: "Issues")
            : String(localized: "Issues (\(count))")
    }

    private var accessibilitySummary: String {
        guard let snapshot else {
            return String(localized: "\(definition.name), status unknown")
        }
        let affected = snapshot.affectedComponents
        if affected.isEmpty {
            return String(localized: "\(definition.name), \(indicator.title)")
        }
        return String(localized: """
            \(definition.name), \(indicator.title), \
            \(affected.count) of \(snapshot.componentsWatched) components affected: \
            \(affected.formatted(.list(type: .and)))
            """)
    }
}
