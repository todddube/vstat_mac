//  ServiceRegistry.swift
//  The single source of truth for what Vibe Stats watches — loaded from
//  Resources/Services.json, which is the port of the extension's
//  src/core/services.js. Adding a service is an edit to that file alone.
//
//  Component names are matched against the live status API first by exact name
//  (`exactMatches`, lower-cased) and then by regex (`patterns`), so a vendor
//  rename degrades to a fuzzy hit instead of a silent "operational".
//
//  `isPrimary` marks the components shown on a healthy card. EVERY component
//  listed here feeds the service's rolled-up indicator, and any non-operational
//  component is shown regardless of the flag (docs/REVIEW.md §3.7).
//
//  Registry ORDER IS SIGNIFICANT: it decides who claims a contested component.

import Foundation

/// A service's identity. A string rather than a closed enum, so a service can
/// be added from the registry file without touching Swift. Encodes as its bare
/// raw value, which keeps snapshots and history written by the enum readable.
struct ServiceID: RawRepresentable, Codable, Sendable, Hashable, Identifiable,
                  ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var id: String { rawValue }
    var description: String { rawValue }
}

enum ServiceAPI: Sendable, Hashable {
    /// {base}/status.json, {base}/components.json, {base}/incidents.json
    case statuspage(base: URL)
    /// Google Cloud publishes a flat incident feed rather than a Statuspage;
    /// `keywords` pick out the incidents relevant to this service.
    case googleCloud(incidents: URL, keywords: [String])
    /// An RSS incident feed whose item titles open with "[Component name]".
    case rssFeed(feed: URL)
}

/// A vendor accent as hex RGB per appearance. Kept as plain numbers so the
/// Domain layer stays Foundation-only; `Palette` turns it into a colour.
struct AccentColor: Sendable, Hashable {
    let dark: UInt32
    let light: UInt32
}

struct ComponentDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    /// Exact vendor component names, lower-cased. Tried first.
    let exactMatches: [String]
    /// ICU regex fallbacks, matched case-insensitively. Tried second.
    let patterns: [String]
    let isPrimary: Bool

    init(
        id: String,
        label: String,
        exactMatches: [String] = [],
        patterns: [String] = [],
        isPrimary: Bool = false
    ) {
        self.id = id
        self.label = label
        self.exactMatches = exactMatches.map { $0.lowercased() }
        self.patterns = patterns
        self.isPrimary = isPrimary
    }
}

struct ServiceDefinition: Sendable, Hashable, Identifiable {
    let id: ServiceID
    let name: String
    let vendor: String
    let statusURL: URL
    let api: ServiceAPI
    let accent: AccentColor
    let components: [ComponentDefinition]

    var primaryComponents: [ComponentDefinition] { components.filter(\.isPrimary) }

    func component(id: String) -> ComponentDefinition? {
        components.first { $0.id == id }
    }
}

enum ServiceRegistry {
    /// Loaded once. A malformed bundled registry is a build defect, not a
    /// runtime condition: RegistryTests decodes the same file, so it fails
    /// there long before it can fail here.
    static let all: [ServiceDefinition] = {
        do {
            return try load(from: .main)
        } catch {
            preconditionFailure("Services.json is invalid: \(error)")
        }
    }()

    static var ids: [ServiceID] { all.map(\.id) }

    static func definition(for id: ServiceID) -> ServiceDefinition? {
        all.first { $0.id == id }
    }

    static func load(from bundle: Bundle) throws -> [ServiceDefinition] {
        guard let url = bundle.url(forResource: "Services", withExtension: "json") else {
            throw RegistryError.missingFile
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes and validates. Validation lives here rather than only in tests
    /// so a hand-edited registry fails with a sentence, not a force-unwrap.
    static func decode(_ data: Data) throws -> [ServiceDefinition] {
        let file = try JSONDecoder().decode(RegistryFile.self, from: data)
        let services = try file.services.map { try $0.definition() }

        var seen = Set<ServiceID>()
        for service in services {
            guard seen.insert(service.id).inserted else {
                throw RegistryError.invalid("duplicate service id \"\(service.id)\"")
            }
            guard !service.components.isEmpty else {
                throw RegistryError.invalid("\(service.id) watches no components")
            }
            for component in service.components {
                for pattern in component.patterns {
                    do {
                        _ = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                    } catch {
                        throw RegistryError.invalid("\(service.id)/\(component.id): bad pattern \(pattern)")
                    }
                }
            }
        }
        guard !services.isEmpty else { throw RegistryError.invalid("no services") }
        return services
    }

    enum RegistryError: Error, CustomStringConvertible {
        case missingFile
        case invalid(String)

        var description: String {
            switch self {
            case .missingFile:          return "Services.json is not in the app bundle"
            case .invalid(let detail):  return detail
            }
        }
    }
}

// MARK: - File format

/// The on-disk shape of Services.json. Kept separate from the domain types so
/// the file can stay forgiving (optional arrays, hex strings) while the
/// definitions the app uses stay strict.
private struct RegistryFile: Decodable {
    struct Service: Decodable {
        struct Accent: Decodable { let dark: String; let light: String }
        struct API: Decodable {
            let type: String
            let base: URL?
            let incidents: URL?
            let keywords: [String]?
            let feed: URL?
        }
        struct Component: Decodable {
            let id: String
            let label: String
            let exactMatches: [String]?
            let patterns: [String]?
            let isPrimary: Bool?
        }

        let id: String
        let name: String
        let vendor: String
        let statusURL: URL
        let accent: Accent
        let api: API
        let components: [Component]

        func definition() throws -> ServiceDefinition {
            ServiceDefinition(
                id: ServiceID(rawValue: id),
                name: name,
                vendor: vendor,
                statusURL: statusURL,
                api: try resolvedAPI(),
                accent: AccentColor(dark: try hex(accent.dark), light: try hex(accent.light)),
                components: components.map {
                    ComponentDefinition(
                        id: $0.id, label: $0.label,
                        exactMatches: $0.exactMatches ?? [],
                        patterns: $0.patterns ?? [],
                        isPrimary: $0.isPrimary ?? false
                    )
                }
            )
        }

        private func resolvedAPI() throws -> ServiceAPI {
            switch (api.type, api.base, api.incidents, api.feed) {
            case ("statuspage", let base?, _, _):
                return .statuspage(base: base)
            case ("googleCloud", _, let incidents?, _):
                return .googleCloud(incidents: incidents, keywords: (api.keywords ?? []).map { $0.lowercased() })
            case ("rssFeed", _, _, let feed?):
                return .rssFeed(feed: feed)
            default:
                throw ServiceRegistry.RegistryError.invalid(
                    "\(id): api type \"\(api.type)\" is unknown or missing its URL")
            }
        }

        private func hex(_ string: String) throws -> UInt32 {
            let digits = string.hasPrefix("#") ? String(string.dropFirst()) : string
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
                throw ServiceRegistry.RegistryError.invalid("\(id): accent \"\(string)\" is not #RRGGBB")
            }
            return value
        }
    }

    let services: [Service]
}
