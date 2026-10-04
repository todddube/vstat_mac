import Foundation
@testable import VibeStats

/// A deterministic stand-in for the network, keyed by the last path component
/// of the request URL ("status.json", "components.json", "incidents.json").
///
/// It is an actor so tests can assert on how many times an endpoint was hit —
/// which is how the retry policy gets verified.
actor StubAPIClient: StatusAPIClient {
    enum Reply: Sendable {
        case data(Data)
        case failure(APIError)
        /// Fail `times` times, then succeed. Models a transient blip.
        case flaky(times: Int, then: Data)
    }

    private var replies: [String: Reply]
    private(set) var callCounts: [String: Int] = [:]
    private let decoder = JSONDecoder.vendor()

    init(_ replies: [String: Reply]) {
        self.replies = replies
    }

    /// Every service, all healthy, from the recorded live payloads.
    static func liveFixtures() throws -> StubAPIClient {
        StubAPIClient([
            "claude/status.json":     .data(try Fixture.data("claude-status")),
            "claude/components.json": .data(try Fixture.data("claude-components")),
            "claude/incidents.json":  .data(try Fixture.data("claude-incidents")),
            "github/status.json":     .data(try Fixture.data("github-status")),
            "github/components.json": .data(try Fixture.data("github-components")),
            "github/incidents.json":  .data(try Fixture.data("github-incidents")),
            "openai/status.json":     .data(try Fixture.data("openai-status")),
            "openai/components.json": .data(try Fixture.data("openai-components")),
            "openai/incidents.json":  .data(try Fixture.data("openai-incidents")),
            "gemini/incidents.json":  .data(try Fixture.data("gemini-incidents")),
            "grok/feed.xml":          .data(try Fixture.data("grok-feed", extension: "xml"))
        ])
    }

    func override(_ key: String, with reply: Reply) {
        replies[key] = reply
    }

    func callCount(_ key: String) -> Int { callCounts[key] ?? 0 }

    func get<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        let key = Self.key(for: url)
        callCounts[key, default: 0] += 1

        guard let reply = replies[key] else {
            throw APIError.http(status: 404)
        }

        switch reply {
        case .data(let data):
            return try decode(type, from: data)
        case .failure(let error):
            throw error
        case .flaky(let times, let data):
            if callCounts[key, default: 0] <= times { throw APIError.timeout }
            replies[key] = .data(data)
            return try decode(type, from: data)
        }
    }

    func data(from url: URL) async throws -> Data {
        let key = Self.key(for: url)
        callCounts[key, default: 0] += 1

        guard let reply = replies[key] else {
            throw APIError.http(status: 404)
        }

        switch reply {
        case .data(let data):
            return data
        case .failure(let error):
            throw error
        case .flaky(let times, let data):
            if callCounts[key, default: 0] <= times { throw APIError.timeout }
            replies[key] = .data(data)
            return data
        }
    }

    private func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch { throw APIError.decoding(String(describing: error).prefix(120).description) }
    }

    /// "https://status.claude.com/api/v2/status.json" -> "claude/status.json"
    static func key(for url: URL) -> String {
        let service: String
        switch url.host() ?? "" {
        case let host where host.contains("claude"): service = "claude"
        case let host where host.contains("github"): service = "github"
        case let host where host.contains("openai"): service = "openai"
        case let host where host.hasSuffix("x.ai"):  service = "grok"
        default:                                     service = "gemini"
        }
        return "\(service)/\(url.lastPathComponent)"
    }
}
