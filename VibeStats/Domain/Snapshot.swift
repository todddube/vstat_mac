//  Snapshot.swift
//  The persisted shape. ≙ the `vstateServices` / `vstateStatus` storage schema,
//  minus the legacy per-service duplicate keys the extension kept for
//  backwards compatibility with older popups.

import Foundation

/// How much a component's state is actually worth.
enum Provenance: String, Codable, Sendable, Hashable {
    /// The vendor publishes this component's health directly (Statuspage).
    case reported
    /// We inferred it from the absence of a matching active incident (Google).
    case derivedFromIncidents
}

enum IncidentImpact: String, Codable, Sendable, Hashable {
    case none, minor, major, critical

    init(vendorValue raw: String?) {
        self = raw.flatMap { IncidentImpact(rawValue: $0.lowercased()) } ?? .none
    }
}

struct IncidentUpdate: Codable, Sendable, Hashable {
    let body: String
    let createdAt: Date?
    let status: String
}

struct Incident: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: IncidentImpact
    let createdAt: Date?
    let resolvedAt: Date?
    let shortlink: URL?
    let affectedComponents: [String]
    /// Whether this incident touches a component we actually watch. This flag
    /// is what lets the UI show "Copilot incidents" instead of "every GitHub
    /// incident".
    let affectsWatched: Bool
    let updates: [IncidentUpdate]

    var isResolved: Bool {
        status.lowercased() == "resolved" || resolvedAt != nil
    }
}

struct ComponentState: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let isPrimary: Bool
    /// False when no component of this name exists on the vendor's page.
    let matched: Bool
    /// The vendor's own name for it, when matched.
    let matchedName: String?
    /// The vendor's own status string, unmapped.
    let rawStatus: String?
    let indicator: StatusIndicator
    let detail: String?
    let provenance: Provenance

    var isAffected: Bool {
        indicator != .operational && indicator != .unknown
    }

    /// Shown on a healthy card only if primary — but always shown when affected
    /// or unresolved, so a verdict can never come from an invisible component.
    var isAlwaysVisible: Bool { isAffected || indicator == .unknown }
}

struct ServiceSnapshot: Codable, Sendable, Hashable, Identifiable {
    let id: ServiceID
    let name: String
    let indicator: StatusIndicator
    /// The vendor's own page-level verdict, kept purely so the UI can show
    /// where it disagrees with our component roll-up. That disagreement is the
    /// entire reason this app exists.
    let pageIndicator: StatusIndicator
    let componentsResolved: Int
    let componentsWatched: Int
    let unresolvedCount: Int
    let components: [ComponentState]
    let incidents: [Incident]
    let affectedComponents: [String]
    let error: String?
    let checkedAt: Date

    var divergesFromPage: Bool {
        pageIndicator.isKnown && indicator.isKnown && pageIndicator != indicator
    }

    var isFullyResolved: Bool { componentsResolved == componentsWatched }

    func component(id: String) -> ComponentState? {
        components.first { $0.id == id }
    }

    /// An entirely unmeasured service. ≙ unknownService().
    static func unknown(_ definition: ServiceDefinition, error: String? = nil, at date: Date) -> ServiceSnapshot {
        ServiceSnapshot(
            id: definition.id,
            name: definition.name,
            indicator: .unknown,
            pageIndicator: .unknown,
            componentsResolved: 0,
            componentsWatched: definition.components.count,
            unresolvedCount: definition.components.count,
            components: definition.components.map { component in
                ComponentState(
                    id: component.id,
                    label: component.label,
                    isPrimary: component.isPrimary,
                    matched: false,
                    matchedName: nil,
                    rawStatus: nil,
                    indicator: .unknown,
                    detail: nil,
                    provenance: .reported
                )
            },
            incidents: [],
            affectedComponents: [],
            error: error,
            checkedAt: date
        )
    }
}

struct CombinedStatus: Codable, Sendable, Hashable {
    let indicator: StatusIndicator
    let description: String
    let affectedServices: [String]
    let affectedComponents: [String]
    let affectedCount: Int
    let unresolvedCount: Int
    let unknownServices: [String]

    /// ≙ combineStatuses() + describeCombined().
    static func combine(_ services: [ServiceSnapshot]) -> CombinedStatus {
        let rollUp = RollUp(services.map(\.indicator))

        let affectedServices = services
            .filter { ($0.indicator.severity ?? -1) > (StatusIndicator.operational.severity ?? 0) }
            .map(\.name)

        let affectedComponents = services.flatMap { service in
            service.affectedComponents.map { "\(service.name): \($0)" }
        }

        let unknownServices = services.filter { $0.indicator == .unknown }.map(\.name)
        let unresolved = services.reduce(0) { $0 + $1.unresolvedCount }

        return CombinedStatus(
            indicator: rollUp.indicator,
            description: describe(
                rollUp.indicator,
                affectedServices: affectedServices,
                unknownServices: unknownServices,
                unresolved: unresolved
            ),
            affectedServices: affectedServices,
            affectedComponents: affectedComponents,
            affectedCount: affectedComponents.count,
            unresolvedCount: unresolved,
            unknownServices: unknownServices
        )
    }

    /// The copy rules from docs/DESIGN.md §8. The one hard rule: the cheerful
    /// string is never shown while anything is unmeasured.
    static func describe(
        _ indicator: StatusIndicator,
        affectedServices: [String],
        unknownServices: [String],
        unresolved: Int
    ) -> String {
        let affected = affectedServices.formatted(.list(type: .and))

        switch indicator {
        case .unknown:
            return String(localized: "Unable to check status")
        case .minor:
            return affectedServices.isEmpty
                ? String(localized: "Minor issues detected")
                : String(localized: "Minor issues with \(affected)")
        case .major:
            return affectedServices.isEmpty
                ? String(localized: "Major issues detected")
                : String(localized: "Major issues affecting \(affected)")
        case .critical:
            return affectedServices.isEmpty
                ? String(localized: "Critical issues detected")
                : String(localized: "Outage: \(affected)")
        case .operational:
            if !unknownServices.isEmpty {
                let list = unknownServices.formatted(.list(type: .and))
                return String(localized: "Status unavailable for \(list)")
            }
            if unresolved > 0 {
                return String(localized: "All watched components OK · \(unresolved) unresolved")
            }
            return String(localized: "All dev tools are vibing")
        }
    }

    static let empty = CombinedStatus(
        indicator: .unknown,
        description: String(localized: "No data yet"),
        affectedServices: [],
        affectedComponents: [],
        affectedCount: 0,
        unresolvedCount: 0,
        unknownServices: []
    )
}

struct Snapshot: Codable, Sendable, Hashable {
    /// In registry order, so the UI does not have to sort.
    let services: [ServiceSnapshot]
    let combined: CombinedStatus
    let updatedAt: Date

    subscript(id: ServiceID) -> ServiceSnapshot? {
        services.first { $0.id == id }
    }
}
