//  IncidentPruner.swift
//  ≙ pruneIncidents(). Keeps stored incidents recent and bounded so the
//  snapshot cannot grow without limit.

import Foundation

enum IncidentPruner {
    static let maxStored = 10
    static let maxAgeDays = 14

    static func prune(
        _ incidents: [Incident],
        now: Date,
        maxCount: Int = maxStored,
        maxDays: Int = maxAgeDays
    ) -> [Incident] {
        let cutoff = now.addingTimeInterval(-Double(maxDays) * 24 * 60 * 60)

        return incidents
            .filter { incident in
                // An incident with no timestamp cannot be aged, so it is dropped
                // rather than kept forever.
                guard let created = incident.createdAt else { return false }
                return created >= cutoff
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .prefix(maxCount)
            .map { $0 }
    }
}
