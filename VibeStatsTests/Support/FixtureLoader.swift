import Foundation
@testable import VibeStats

/// Anchors the test bundle. The test host is the sandboxed app, so fixtures
/// travel inside the bundle rather than being read from the source tree.
final class FixtureAnchor {}

enum Fixture {
    static let bundle = Bundle(for: FixtureAnchor.self)

    static func data(_ name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json")
        else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// Load a fixture and edit the decoded JSON before re-encoding. Builds the
    /// "the vendor changed something" variants without checking in a dozen
    /// near-identical files.
    static func mutated(_ name: String, _ transform: (inout [String: Any]) -> Void) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any] else {
            throw FixtureError.notAnObject(name)
        }
        transform(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case missing(String)
        case notAnObject(String)

        var description: String {
            switch self {
            case .missing(let name):     return "fixture \(name).json is not in the test bundle"
            case .notAnObject(let name): return "fixture \(name).json is not a JSON object"
            }
        }
    }
}
