import Foundation
import Testing
@testable import VibeStats

/// docs/REVIEW.md §3.2 — the extension's retry sat around a Promise.allSettled
/// that never rejects, so it could only ever fire on a storage failure. Here
/// retry lives at the request level, and these tests hold it there.
@Suite("Retry policy", .serialized)
struct RetryPolicyTests {

    private struct Payload: Decodable, Sendable, Equatable {
        let ok: Bool
    }

    private let url = URL(string: "https://status.claude.com/api/v2/status.json")!

    private func client(maxRetries: Int = 2) -> LiveStatusAPIClient {
        LiveStatusAPIClient(maxRetries: maxRetries, timeout: 2, protocolClasses: [StubURLProtocol.self])
    }

    @Test("A transient 5xx is retried and then succeeds")
    func retriesTransientFailure() async throws {
        StubURLProtocol.script([.failure(503), .success(#"{"ok":true}"#)])

        let payload = try await client().get(Payload.self, from: url)

        #expect(payload.ok)
        #expect(StubURLProtocol.callCount == 2, "one failure plus one retry")
    }

    @Test("Retries are bounded by maxRetries and then the error surfaces")
    func retriesAreBounded() async throws {
        StubURLProtocol.script([.failure(500)])

        await #expect(throws: APIError.http(status: 500)) {
            try await client(maxRetries: 2).get(Payload.self, from: url)
        }
        #expect(StubURLProtocol.callCount == 3, "initial attempt plus two retries")
    }

    @Test("A 4xx is a real answer and is never retried")
    func doesNotRetryClientErrors() async throws {
        StubURLProtocol.script([.failure(404)])

        await #expect(throws: APIError.http(status: 404)) {
            try await client().get(Payload.self, from: url)
        }
        #expect(StubURLProtocol.callCount == 1)
    }

    @Test("A decode failure is not retried — the payload will not improve")
    func doesNotRetryDecodeFailures() async throws {
        StubURLProtocol.script([.success("{ not json")])

        await #expect(throws: (any Error).self) {
            try await client().get(Payload.self, from: url)
        }
        #expect(StubURLProtocol.callCount == 1)
    }

    @Test("Success on the first attempt costs exactly one request")
    func noRetryWhenHealthy() async throws {
        StubURLProtocol.script([.success(#"{"ok":true}"#)])

        _ = try await client().get(Payload.self, from: url)
        #expect(StubURLProtocol.callCount == 1)
    }

    @Test("Transience classification", arguments: [
        (APIError.timeout, true),
        (.transport("connection lost"), true),
        (.http(status: 500), true),
        (.http(status: 503), true),
        (.http(status: 404), false),
        (.http(status: 429), false),
        (.offline, false),
        (.decoding("bad"), false),
        (.cancelled, false)
    ])
    func transienceTable(error: APIError, isTransient: Bool) {
        #expect(error.isTransient == isTransient)
    }
}
