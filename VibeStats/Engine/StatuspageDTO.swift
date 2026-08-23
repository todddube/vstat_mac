//  StatuspageDTO.swift
//  Wire types for the Statuspage v2 API (Claude, GitHub, OpenAI).
//  Only the fields we actually read are declared; everything else is ignored.

import Foundation

enum Statuspage {
    struct StatusPayload: Decodable, Sendable {
        struct Status: Decodable, Sendable {
            let indicator: String?
            let description: String?
        }
        let status: Status?
    }

    struct ComponentsPayload: Decodable, Sendable {
        let components: [Component]?
    }

    struct Component: Decodable, Sendable {
        let id: String?
        let name: String?
        let status: String?
        let description: String?
        /// Statuspage group headers are components too. They must not be
        /// matchable, or a group named "Copilot" steals the real component.
        let group: Bool?
    }

    struct IncidentsPayload: Decodable, Sendable {
        let incidents: [Incident]?
    }

    struct Incident: Decodable, Sendable {
        struct AffectedComponent: Decodable, Sendable {
            let name: String?
        }
        struct Update: Decodable, Sendable {
            let body: String?
            let status: String?
            let created_at: Date?
        }

        let id: String?
        let name: String?
        let status: String?
        let impact: String?
        let created_at: Date?
        let resolved_at: Date?
        let shortlink: String?
        let components: [AffectedComponent]?
        let incident_updates: [Update]?
    }
}
