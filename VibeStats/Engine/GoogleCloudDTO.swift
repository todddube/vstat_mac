//  GoogleCloudDTO.swift
//  Wire types for Google Cloud's flat incident feed. There is no Statuspage
//  and no per-component health here — only incidents.

import Foundation

enum GoogleCloud {
    struct Incident: Decodable, Sendable {
        struct Product: Decodable, Sendable {
            let title: String?
        }
        struct Update: Decodable, Sendable {
            let text: String?
            let status: String?
            let created: Date?
            let modified: Date?
            let when: Date?
        }

        let id: String?
        let external_desc: String?
        let service_name: String?
        let uri: String?
        let severity: String?
        let begin: Date?
        let end: Date?
        let created: Date?
        let modified: Date?
        let affected_products: [Product]?
        let updates: [Update]?
        let most_recent_update: Update?
    }
}
