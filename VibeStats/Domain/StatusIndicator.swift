//  StatusIndicator.swift
//  The five-level scale, ported from src/core/services.js.
//
//  One deliberate change from the extension: `unknown` is NOT ranked below
//  `operational`. In the extension, STATUS_PRIORITY puts unknown at 0 and
//  operational at 1, so rollUpStatus(['unknown', ...]) reduces to
//  'operational' — which is how a total API blackout renders as
//  "All dev tools are vibing!". See docs/REVIEW.md §3.1.
//
//  Here `unknown` is not on the severity scale at all; it is an absence of
//  information, and RollUp carries it separately.

import Foundation

enum StatusIndicator: String, Codable, Sendable, CaseIterable, Hashable {
    case unknown
    case operational
    case minor
    case major
    case critical

    /// Severity ordering for *known* states. `unknown` returns nil — it cannot
    /// win or lose a comparison, because it is not a measurement.
    var severity: Int? {
        switch self {
        case .unknown:     return nil
        case .operational: return 0
        case .minor:       return 1
        case .major:       return 2
        case .critical:    return 3
        }
    }

    var isKnown: Bool { self != .unknown }

    /// ≙ statusLabel()
    var title: String {
        switch self {
        case .operational: return String(localized: "Operational")
        case .minor:       return String(localized: "Degraded")
        case .major:       return String(localized: "Partial Outage")
        case .critical:    return String(localized: "Major Outage")
        case .unknown:     return String(localized: "Unknown")
        }
    }

    /// ≙ componentStatusText() — the compact monospaced badge on component rows.
    var compactTitle: String {
        switch self {
        case .operational: return "OK"
        case .minor:       return "DEGRADED"
        case .major:       return "PARTIAL"
        case .critical:    return "OUTAGE"
        case .unknown:     return "UNKNOWN"
        }
    }

    // MARK: - Mapping

    /// ≙ mapComponentStatus(): the exact Statuspage table first, then keyword
    /// sniffing so a state we have never seen ("degraded_availability") still
    /// registers as a problem rather than silently passing as healthy.
    init(componentStatus raw: String?) {
        guard let key = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { self = .unknown; return }

        switch key {
        case "operational":
            self = .operational
        case "under_maintenance", "degraded_performance":
            // Maintenance is deliberately a minor, not an outage.
            self = .minor
        case "partial_outage":
            self = .major
        case "major_outage":
            self = .critical
        default:
            if key.contains("major") || key.contains("critical") {
                self = .critical
            } else if key.contains("partial") {
                self = .major
            } else if key.contains("degraded") || key.contains("minor")
                        || key.contains("maintenance") {
                self = .minor
            } else if key.contains("operational") || key == "none" {
                self = .operational
            } else {
                self = .unknown
            }
        }
    }

    /// ≙ mapPageIndicator(): the page-level indicator from status.json.
    init(pageIndicator raw: String?) {
        guard let key = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { self = .unknown; return }

        switch key {
        case "none":        self = .operational
        case "maintenance": self = .minor
        case "operational": self = .operational
        case "minor":       self = .minor
        case "major":       self = .major
        case "critical":    self = .critical
        default:            self = .unknown
        }
    }
}
