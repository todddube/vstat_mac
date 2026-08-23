//  RollUp.swift
//  ≙ rollUpStatus(), with the defect in docs/REVIEW.md §3.1 fixed.

import Foundation

/// The result of reducing many indicators to one.
///
/// The extension returned a bare indicator, which meant unknowns silently
/// vanished into `operational`. Carrying `unresolved` alongside the verdict is
/// what lets the UI say "3 of 5 components unresolved" instead of lying.
struct RollUp: Sendable, Hashable {
    let indicator: StatusIndicator
    let unresolved: Int

    /// Returns `.unknown` only when *every* input is unknown. Otherwise the
    /// worst known state, with the unknown count preserved.
    init(_ indicators: some Sequence<StatusIndicator>) {
        var worst: StatusIndicator?
        var unknownCount = 0

        for indicator in indicators {
            guard let severity = indicator.severity else {
                unknownCount += 1
                continue
            }
            if let current = worst, let currentSeverity = current.severity,
               currentSeverity >= severity {
                continue
            }
            worst = indicator
        }

        self.indicator = worst ?? .unknown
        self.unresolved = unknownCount
    }

    /// True when the verdict is trustworthy: something was actually measured.
    var isConclusive: Bool { indicator.isKnown }
}
