//  JSONDecoding.swift
//  Decoding is lenient by design: unknown keys are ignored, and vendors are
//  inconsistent about date formats even within one payload. A vendor adding a
//  field, or dropping fractional seconds, must never blank a card.

import Foundation

extension JSONDecoder {
    static func vendor() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = VendorDate.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "unrecognised date \"\(raw)\"")
                )
            }
            return date
        }
        return decoder
    }
}

/// Statuspage emits `2026-08-20T19:16:24.932Z`; Google Cloud emits
/// `2026-08-20T15:40:00+00:00`. Both are ISO 8601, but only one has fractional
/// seconds, and a single strategy rejects whichever it was not configured for.
///
/// `Date.ISO8601FormatStyle` is a Sendable value type, so unlike
/// `ISO8601DateFormatter` these can be shared safely across concurrent parses.
enum VendorDate {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return (try? fractional.parse(raw)) ?? (try? plain.parse(raw))
    }
}
