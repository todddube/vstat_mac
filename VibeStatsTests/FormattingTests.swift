import Foundation
import Testing
@testable import VibeStats

/// Statuspage emits `2026-08-20T19:16:24.932Z`; Google Cloud emits
/// `2026-08-20T15:40:00+00:00`. Both are ISO 8601, but a single decoding
/// strategy rejects whichever it was not configured for — and a rejected date
/// is a failed decode, which blanks a whole card.
@Suite("Vendor date parsing")
struct VendorDateTests {

    @Test("Statuspage's fractional-seconds form parses")
    func fractionalSeconds() throws {
        let date = try #require(VendorDate.parse("2026-08-20T19:16:24.932Z"))
        #expect(abs(date.timeIntervalSince1970 - 1_787_253_384.932) < 0.01)
    }

    @Test("Google Cloud's offset form, without fractional seconds, parses")
    func plainWithOffset() throws {
        let date = try #require(VendorDate.parse("2026-08-20T15:40:00+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1_787_240_400) < 0.01)
    }

    @Test("Both vendors' forms round-trip through the shared decoder")
    func decoderHandlesBoth() throws {
        struct Pair: Decodable { let a: Date; let b: Date }
        let json = """
        {"a": "2026-08-20T19:16:24.932Z", "b": "2026-08-20T15:40:00+00:00"}
        """
        let pair = try JSONDecoder.vendor().decode(Pair.self, from: Data(json.utf8))
        #expect(pair.a > pair.b)
    }

    @Test("Nil, empty and nonsense are nil rather than a wrong date")
    func rejects() {
        #expect(VendorDate.parse(nil) == nil)
        #expect(VendorDate.parse("") == nil)
        #expect(VendorDate.parse("last Tuesday") == nil)
        #expect(VendorDate.parse("2026-08-20") == nil)
    }

    @Test("An unparseable date fails that field's decode, not the process")
    func decoderThrows() {
        struct Wrapper: Decodable { let when: Date }
        let json = #"{"when": "last Tuesday"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder.vendor().decode(Wrapper.self, from: Data(json.utf8))
        }
    }
}

@Suite("Relative formatting")
struct FormatTests {

    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    @Test("Never checked reads as never, not as a very old date")
    func never() {
        #expect(Format.relative(nil, now: now) == String(localized: "never"))
    }

    @Test("Anything inside the last minute is 'just now'")
    func justNow() {
        let expected = String(localized: "just now")
        #expect(Format.relative(now, now: now) == expected)
        #expect(Format.relative(now.addingTimeInterval(-59), now: now) == expected)
    }

    @Test("Past a minute it becomes a relative phrase, not 'just now'")
    func older() {
        for elapsed in [61.0, 3600, 86_400] {
            let text = Format.relative(now.addingTimeInterval(-elapsed), now: now)
            #expect(text != String(localized: "just now"))
            #expect(!text.isEmpty)
        }
    }

    @Test("Truncation leaves short text alone and ellipsises long text")
    func truncation() {
        #expect(Format.truncate("short", to: 10) == "short")
        #expect(Format.truncate("exactlyten", to: 10) == "exactlyten")

        let truncated = Format.truncate("a much longer sentence than the limit", to: 10)
        #expect(truncated.hasSuffix("…"))
        #expect(truncated.count <= 11)
    }

    @Test("Truncation does not leave a space stranded before the ellipsis")
    func truncationTrimsWhitespace() {
        #expect(Format.truncate("abcde fghij", to: 6) == "abcde…")
    }
}
