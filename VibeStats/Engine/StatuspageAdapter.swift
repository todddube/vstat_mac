//  StatuspageAdapter.swift
//  ≙ checkStatuspageService(). Claude, GitHub and OpenAI.

import Foundation

struct StatuspageAdapter: Sendable {
    let client: any StatusAPIClient

    func check(_ definition: ServiceDefinition, base: URL, now: Date) async -> ServiceSnapshot {
        // Three independent fetches. One failing must not blank the other two —
        // this is the Promise.allSettled behaviour the extension relies on.
        async let statusTask = try? client.get(
            Statuspage.StatusPayload.self, from: base.appending(path: "status.json"))
        async let componentsTask = try? client.get(
            Statuspage.ComponentsPayload.self, from: base.appending(path: "components.json"))
        async let incidentsTask = try? client.get(
            Statuspage.IncidentsPayload.self, from: base.appending(path: "incidents.json"))

        let (status, componentsPayload, incidentsPayload) =
            await (statusTask, componentsTask, incidentsTask)

        let pageIndicator = StatusIndicator(pageIndicator: status?.status?.indicator)

        let matchable = (componentsPayload?.components ?? [])
            // Group headers are components in the payload too. Excluding them
            // stops a group named "Copilot" from stealing the real component.
            .filter { $0.group != true }
            .compactMap { component -> MatchableComponent? in
                guard let name = component.name, !name.isEmpty else { return nil }
                return MatchableComponent(
                    name: name, status: component.status, description: component.description)
            }

        let components = resolve(definition, against: matchable)
        let resolvedCount = components.count(where: \.matched)

        let watchedNames = Set(components.compactMap { $0.matchedName?.lowercased() })
        let incidents = IncidentPruner.prune(
            (incidentsPayload?.incidents ?? []).map { normalize($0, watchedNames: watchedNames) },
            now: now
        )

        let rollUp = RollUp(components.map(\.indicator))

        // Fall back to the vendor's page indicator ONLY when we could not
        // resolve a single component — i.e. they changed their API shape.
        // Otherwise the component roll-up is the answer, which is the whole
        // point of this app.
        let indicator = resolvedCount > 0 ? rollUp.indicator : pageIndicator

        return ServiceSnapshot(
            id: definition.id,
            name: definition.name,
            indicator: indicator,
            pageIndicator: pageIndicator,
            componentsResolved: resolvedCount,
            componentsWatched: components.count,
            unresolvedCount: rollUp.unresolved,
            components: components,
            incidents: incidents,
            affectedComponents: components.filter(\.isAffected).map(\.label),
            error: componentsPayload == nil ? APIError.decoding("components.json").summary : nil,
            checkedAt: now
        )
    }

    /// ≙ resolveComponents(). An unmatched component reports `unknown` rather
    /// than silently `operational` — reporting a component we can no longer
    /// find as healthy is the failure mode this whole design guards against.
    private func resolve(
        _ definition: ServiceDefinition,
        against payload: [MatchableComponent]
    ) -> [ComponentState] {
        var claimed = Set<String>()

        return definition.components.map { component in
            let match = ComponentMatcher.match(component, in: payload, claimed: &claimed)
            return ComponentState(
                id: component.id,
                label: component.label,
                isPrimary: component.isPrimary,
                matched: match != nil,
                matchedName: match?.name,
                rawStatus: match?.status,
                indicator: match.map { StatusIndicator(componentStatus: $0.status) } ?? .unknown,
                detail: match?.description,
                provenance: .reported
            )
        }
    }

    /// ≙ normalizeStatuspageIncident().
    private func normalize(
        _ incident: Statuspage.Incident,
        watchedNames: Set<String>
    ) -> Incident {
        let affected = (incident.components ?? []).compactMap(\.name)

        // With nothing resolved we cannot tell what is relevant, so everything
        // is — better noisy than silently filtered to empty.
        let affectsWatched = watchedNames.isEmpty
            || affected.contains { watchedNames.contains($0.lowercased()) }

        return Incident(
            id: incident.id ?? incident.shortlink ?? UUID().uuidString,
            name: incident.name ?? String(localized: "Untitled incident"),
            status: incident.status ?? "unknown",
            impact: IncidentImpact(vendorValue: incident.impact),
            createdAt: incident.created_at,
            resolvedAt: incident.resolved_at,
            shortlink: incident.shortlink.flatMap(URL.init(string:)),
            affectedComponents: affected,
            affectsWatched: affectsWatched,
            updates: (incident.incident_updates ?? []).prefix(2).map { update in
                IncidentUpdate(
                    body: update.body ?? "",
                    createdAt: update.created_at,
                    status: update.status ?? "update"
                )
            }
        )
    }
}
