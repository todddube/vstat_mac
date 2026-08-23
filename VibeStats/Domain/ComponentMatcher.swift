//  ComponentMatcher.swift
//  ≙ matchComponent(). Exact vendor name first, regex fallback second.

import Foundation

/// The subset of a vendor component we need to match against.
struct MatchableComponent: Sendable, Hashable {
    let name: String
    let status: String?
    let description: String?

    init(name: String, status: String? = nil, description: String? = nil) {
        self.name = name
        self.status = status
        self.description = description
    }

    var normalizedName: String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ComponentMatcher {
    /// Resolve one registry entry against the live payload.
    ///
    /// `claimed` holds the vendor names already taken by earlier definitions.
    /// Without it a loose pattern can steal another entry's component — e.g.
    /// /chatgpt/ matching OpenAI's "Codex in ChatGPT Desktop" for two different
    /// entries and reporting the same status under two labels.
    static func match(
        _ definition: ComponentDefinition,
        in components: [MatchableComponent],
        claimed: inout Set<String>
    ) -> MatchableComponent? {
        guard !components.isEmpty else { return nil }

        let available = components.filter { !claimed.contains($0.normalizedName) }
        guard !available.isEmpty else { return nil }

        if !definition.exactMatches.isEmpty,
           let exact = available.first(where: { definition.exactMatches.contains($0.normalizedName) }) {
            claimed.insert(exact.normalizedName)
            return exact
        }

        if !definition.patterns.isEmpty,
           let fuzzy = available.first(where: { candidate in
               definition.patterns.contains { matches(pattern: $0, in: candidate.name) }
           }) {
            claimed.insert(fuzzy.normalizedName)
            return fuzzy
        }

        return nil
    }

    /// Case-insensitive ICU regex test. Patterns are stored as strings rather
    /// than compiled objects so the registry stays a plain Sendable value.
    static func matches(pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
