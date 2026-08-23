//  ServiceRegistry.swift
//  The single source of truth for what Vibe Stats watches — the direct port of
//  src/core/services.js, and the contract shared with the browser extension.
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

enum ServiceID: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case claude, github, openai, gemini
    var id: String { rawValue }
}

enum ServiceAPI: Sendable, Hashable {
    /// {base}/status.json, {base}/components.json, {base}/incidents.json
    case statuspage(base: URL)
    /// Google Cloud publishes a flat incident feed rather than a Statuspage.
    case googleCloud(incidents: URL)
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
    let components: [ComponentDefinition]

    var primaryComponents: [ComponentDefinition] { components.filter(\.isPrimary) }

    func component(id: String) -> ComponentDefinition? {
        components.first { $0.id == id }
    }
}

enum ServiceRegistry {
    static let all: [ServiceDefinition] = [claude, github, openai, gemini]

    static func definition(for id: ServiceID) -> ServiceDefinition {
        // Total by construction: `all` covers every case of ServiceID, and a
        // test asserts it.
        all.first { $0.id == id }!
    }

    /// Keywords that mark a Google Cloud incident as AI/Gemini-relevant.
    static let googleAIKeywords = [
        "gemini", "ai studio", "vertex ai", "generative ai", "ai platform", "cloud ai"
    ]

    // MARK: - Claude

    static let claude = ServiceDefinition(
        id: .claude,
        name: "Claude AI",
        vendor: "Anthropic",
        statusURL: URL(string: "https://status.claude.com")!,
        api: .statuspage(base: URL(string: "https://status.claude.com/api/v2")!),
        components: [
            ComponentDefinition(
                id: "claude-code", label: "Claude Code",
                exactMatches: ["claude code"],
                patterns: [#"\bclaude code\b"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "claude-api", label: "API",
                exactMatches: ["claude api (api.anthropic.com)"],
                // The extension used a bare /\bapi\b/, which matches almost any
                // component containing "API" and can bind this entry to an
                // unrelated component — a silent wrong answer, worse than
                // UNKNOWN. Tightened per docs/REVIEW.md §3.6.
                patterns: [#"\bclaude api\b"#, #"\bapi\.anthropic\.com\b"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "claude-web", label: "Claude.ai",
                exactMatches: ["claude.ai"],
                patterns: [#"\bclaude\.ai\b"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "claude-console", label: "Console",
                exactMatches: ["claude console (platform.claude.com)"],
                patterns: [#"\bclaude console\b"#, #"\bplatform\.claude\.com\b"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "claude-cowork", label: "Cowork",
                exactMatches: ["claude cowork"],
                patterns: [#"\bcowork\b"#]
            )
        ]
    )

    // MARK: - GitHub

    static let github = ServiceDefinition(
        id: .github,
        name: "GitHub Copilot",
        vendor: "GitHub",
        statusURL: URL(string: "https://www.githubstatus.com")!,
        api: .statuspage(base: URL(string: "https://www.githubstatus.com/api/v2")!),
        components: [
            ComponentDefinition(
                id: "copilot", label: "Copilot",
                exactMatches: ["copilot"], patterns: [#"^copilot$"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "copilot-models", label: "AI Models",
                exactMatches: ["copilot ai model providers"],
                patterns: [#"copilot.*model"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "codespaces", label: "Codespaces",
                exactMatches: ["codespaces"], patterns: [#"\bcodespaces\b"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "actions", label: "Actions",
                exactMatches: ["actions"], patterns: [#"^actions$"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "github-api", label: "API Requests",
                exactMatches: ["api requests"], patterns: [#"\bapi requests\b"#]
            )
        ]
    )

    // MARK: - OpenAI

    /// OpenAI publishes very granular components; we watch the developer
    /// surfaces rather than the consumer ones (no Sora/Images/Voice here).
    static let openai = ServiceDefinition(
        id: .openai,
        name: "OpenAI",
        vendor: "OpenAI",
        statusURL: URL(string: "https://status.openai.com")!,
        api: .statuspage(base: URL(string: "https://status.openai.com/api/v2")!),
        components: [
            ComponentDefinition(
                id: "codex-api", label: "Codex API",
                exactMatches: ["codex api"], patterns: [#"^codex api$"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "codex-web", label: "Codex Web",
                exactMatches: ["codex web"], patterns: [#"^codex web$"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "vscode-extension", label: "VS Code Ext",
                exactMatches: ["vs code extension"], patterns: [#"vs ?code extension"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "chat-completions", label: "Chat API",
                exactMatches: ["chat completions"], patterns: [#"^chat completions$"#],
                isPrimary: true
            ),
            ComponentDefinition(
                id: "responses", label: "Responses",
                exactMatches: ["responses"], patterns: [#"^responses$"#]
            ),
            ComponentDefinition(
                id: "codex-cli", label: "CLI",
                exactMatches: ["cli"], patterns: [#"^cli$"#]
            )
        ]
    )

    // MARK: - Gemini

    /// No Statuspage. Component states are derived from active incidents, so
    /// they carry `.derivedFromIncidents` provenance — "Gemini API: OK" is a
    /// weaker claim than "Claude Code: OK" and the UI says so.
    static let gemini = ServiceDefinition(
        id: .gemini,
        name: "Gemini",
        vendor: "Google",
        statusURL: URL(string: "https://status.cloud.google.com")!,
        api: .googleCloud(incidents: URL(string: "https://status.cloud.google.com/incidents.json")!),
        components: [
            ComponentDefinition(
                id: "gemini-api", label: "Gemini API",
                patterns: [#"\bgemini\b"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "ai-studio", label: "AI Studio",
                patterns: [#"\bai studio\b"#], isPrimary: true
            ),
            ComponentDefinition(
                id: "vertex-ai", label: "Vertex AI",
                patterns: [#"\bvertex ai\b"#], isPrimary: true
            )
        ]
    )
}
