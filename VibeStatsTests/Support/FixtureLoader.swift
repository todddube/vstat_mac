import Foundation
@testable import VibeStats

/// Anchors the test bundle. The test host is the sandboxed app, so fixtures
/// travel inside the bundle rather than being read from the source tree.
final class FixtureAnchor {}

enum Fixture {
    static let bundle = Bundle(for: FixtureAnchor.self)

    static func data(_ name: String, extension ext: String = "json") throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: ext)
        else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// Edit a text fixture (the RSS feed) by string substitution.
    static func text(_ name: String, extension ext: String, _ transform: (String) -> String) throws -> Data {
        Data(transform(String(decoding: try data(name, extension: ext), as: UTF8.self)).utf8)
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
            case .missing(let name):     return "fixture \(name) is not in the test bundle"
            case .notAnObject(let name): return "fixture \(name).json is not a JSON object"
            }
        }
    }
}
