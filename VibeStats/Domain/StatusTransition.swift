//  StatusTransition.swift
//  What changed between two snapshots, at component granularity.
//
//  Pure and testable: no notification framework, no clock, no preferences.

import Foundation

struct StatusTransition: Sendable, Hashable, Identifiable {
    let service: ServiceID
    let serviceName: String
    let componentID: String
    let componentLabel: String
    let isPrimary: Bool
    let from: StatusIndicator
    let to: StatusIndicator

    var id: String { "\(service.rawValue).\(componentID)" }

    var isDegradation: Bool {
        guard let before = from.severity, let after = to.severity else { return false }
        return after > before
    }

    var isRecovery: Bool {
        guard let before = from.severity, let after = to.severity else { return false }
        return after < before && to == .operational
    }

    /// The severity the notification policy is judged against: where it landed
    /// for a degradation, where it came from for a recovery.
    var judgedSeverity: StatusIndicator {
        isRecovery ? from : to
    }
}

enum TransitionDiff {
    /// Component-level transitions between two snapshots.
    ///
    /// Transitions involving `unknown` are deliberately excluded. "We stopped
    /// being able to measure this" is not an outage and must not be announced
    /// as one — the same discipline that stops an unresolved component from
    /// being reported as healthy.
    static func transitions(from previous: Snapshot?, to current: Snapshot) -> [StatusTransition] {
        guard let previous else { return [] }

        return current.services.flatMap { service -> [StatusTransition] in
            guard let before = previous[service.id] else { return [] }

            return service.components.compactMap { component -> StatusTransition? in
                guard let old = before.component(id: component.id) else { return nil }
                guard old.indicator != component.indicator else { return nil }
                guard old.indicator.isKnown, component.indicator.isKnown else { return nil }

                return StatusTransition(
                    service: service.id,
                    serviceName: service.name,
                    componentID: component.id,
                    componentLabel: component.label,
                    isPrimary: component.isPrimary,
                    from: old.indicator,
                    to: component.indicator
                )
            }
        }
    }
}
