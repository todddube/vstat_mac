//  GoogleCloudAdapter.swift
//  ≙ checkGoogleCloudService(). Gemini.
//
//  Google publishes no per-component health — only a flat incident feed for the
//  whole cloud. So component states here are INFERRED from the absence of a
//  matching active incident, and carry `.derivedFromIncidents` provenance:
//  "Gemini API: OK" is a weaker claim than "Claude Code: OK" and the UI says so
//  (docs/REVIEW.md §3.10).

import Foundation

struct GoogleCloudAdapter: Sendable {
    let client: any StatusAPIClient

    func check(_ definition: ServiceDefinition, incidentsURL: URL, now: Date) async throws -> ServiceSnapshot {
        let payload = try await client.get([GoogleCloud.Incident].self, from: incidentsURL)

        // Keep the flattened search text alongside each incident while we work;
        // it is an internal index and never reaches the snapshot.
        let relevant = payload.compactMap { incident -> (Incident, String)? in
            let text = searchText(for: incident)
            guard ServiceRegistry.googleAIKeywords.contains(where: text.contains) else { return nil }
            return (normalize(incident, now: now), text)
        }

        let pruned = IncidentPruner.prune(relevant.map(\.0), now: now)
        let prunedIDs = Set(pruned.map(\.id))
        let activeText = relevant
            .filter { prunedIDs.contains($0.0.id) && !$0.0.isResolved }

        let components = definition.components.map { component -> ComponentState in
            let hits = activeText.filter { _, text in
                component.patterns.contains { ComponentMatcher.matches(pattern: $0, in: text) }
            }

            let indicator = hits.isEmpty
                ? StatusIndicator.operational
                : RollUp(hits.map { indicator(for: $0.0.impact) }).indicator

            return ComponentState(
                id: component.id,
                label: component.label,
                isPrimary: component.isPrimary,
                matched: true,
                matchedName: component.label,
                rawStatus: indicator.rawValue,
                indicator: indicator,
                detail: hits.first?.0.name,
                provenance: .derivedFromIncidents
            )
        }

        let rollUp = RollUp(components.map(\.indicator))

        return ServiceSnapshot(
            id: definition.id,
            name: definition.name,
            indicator: rollUp.indicator,
            pageIndicator: rollUp.indicator,
            componentsResolved: components.count,
            componentsWatched: components.count,
            unresolvedCount: rollUp.unresolved,
            components: components,
            incidents: pruned,
            affectedComponents: components.filter(\.isAffected).map(\.label),
            error: nil,
            checkedAt: now
        )
    }

    /// ≙ incidentText(). Every text-bearing field, flattened for keyword search.
    private func searchText(for incident: GoogleCloud.Incident) -> String {
        var parts: [String] = [
            incident.external_desc,
            incident.service_name,
            incident.uri
        ].compactMap { $0 }

        parts.append(contentsOf: (incident.affected_products ?? []).compactMap(\.title))
        parts.append(contentsOf: (incident.updates ?? []).compactMap(\.text))

        return parts.joined(separator: " ").lowercased()
    }

    /// ≙ normalizeGoogleIncident().
    private func normalize(_ incident: GoogleCloud.Incident, now: Date) -> Incident {
        let name = incident.external_desc
            ?? incident.service_name
            ?? String(localized: "Google AI incident")

        return Incident(
            id: incident.id ?? incident.uri ?? UUID().uuidString,
            name: name,
            status: status(for: incident, now: now),
            impact: severity(incident.severity),
            createdAt: incident.begin ?? incident.created ?? incident.modified,
            resolvedAt: incident.end,
            shortlink: incident.uri.flatMap {
                URL(string: "https://status.cloud.google.com/\($0)")
            },
            affectedComponents: (incident.affected_products ?? []).compactMap(\.title),
            affectsWatched: true,
            updates: (incident.updates ?? []).prefix(2).map { update in
                IncidentUpdate(
                    body: update.text ?? "",
                    createdAt: update.when ?? update.created ?? update.modified,
                    status: update.status ?? "update"
                )
            }
        )
    }

    /// ≙ mapGoogleStatus().
    private func status(for incident: GoogleCloud.Incident, now: Date) -> String {
        if let end = incident.end, end < now { return "resolved" }

        let raw = (incident.most_recent_update?.status ?? "").lowercased()
        if raw.contains("resolved") || raw.contains("closed") { return "resolved" }
        if raw.contains("identified") { return "identified" }
        if raw.contains("monitoring") { return "monitoring" }
        return "investigating"
    }

    /// ≙ mapGoogleSeverity().
    private func severity(_ raw: String?) -> IncidentImpact {
        switch (raw ?? "").lowercased() {
        case "high", "critical": return .critical
        case "medium":           return .major
        default:                 return .minor
        }
    }

    /// ≙ googleImpactToIndicator().
    private func indicator(for impact: IncidentImpact) -> StatusIndicator {
        switch impact {
        case .critical: return .critical
        case .major:    return .major
        case .minor, .none: return .minor
        }
    }
}
