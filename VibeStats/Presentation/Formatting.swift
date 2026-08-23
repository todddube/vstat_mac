//  Formatting.swift
//  Derived display values, kept out of the views so they can be tested and so
//  no view calls Date.now at render time.

import Foundation

enum Format {
    /// "2m ago" / "3h ago" / "Just now". Locale-aware, unlike the extension's
    /// hardcoded en-US strings.
    static func relative(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return String(localized: "never") }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return String(localized: "just now") }

        var style = Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .narrow)
        style.capitalizationContext = .middleOfSentence
        return date.formatted(style)
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return text.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
