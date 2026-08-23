//  IncidentListView.swift
//  Incidents touching a watched component come first — that ordering is what
//  turns "every GitHub incident" into "Copilot incidents".

import SwiftUI

struct IncidentListView: View {
    let incidents: [Incident]
    var limit: Int = 5

    private var ordered: [Incident] {
        incidents
            .sorted {
                if $0.affectsWatched != $1.affectsWatched { return $0.affectsWatched }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ordered.isEmpty {
                Text("No recent incidents")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(ordered) { incident in
                    IncidentRowView(incident: incident)
                }
            }
        }
    }
}

struct IncidentRowView: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(incident.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(incident.status.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tagColor.opacity(0.18))
                    )
                    .foregroundStyle(tagColor)

                if !incident.affectedComponents.isEmpty {
                    Text(incident.affectedComponents.prefix(3).joined(separator: ", "))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                Text(Format.relative(incident.createdAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
            }

            if let body = incident.updates.first?.body, !body.isEmpty {
                // Vendor-supplied text: rendered as a plain string, never as
                // markup. SwiftUI's Text does not interpret it.
                Text(verbatim: Format.truncate(body, to: 140))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.25))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(impactColor)
                .frame(width: 2.5)
                .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var tagColor: Color {
        incident.isResolved ? Color.status(.operational) : Color.status(.minor)
    }

    private var impactColor: Color {
        switch incident.impact {
        case .critical: return Color.status(.critical)
        case .major:    return Color.status(.major)
        case .minor:    return Color.status(.minor)
        case .none:     return Color.secondary.opacity(0.4)
        }
    }
}
