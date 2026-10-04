@testable import VibeStats

/// The app has no compile-time list of services — they come from
/// Services.json — but tests name specific ones constantly. These spell the
/// ids once, and `RegistryTests` asserts each one really is in the registry.
extension ServiceID {
    static let claude: ServiceID = "claude"
    static let github: ServiceID = "github"
    static let openai: ServiceID = "openai"
    static let gemini: ServiceID = "gemini"
    static let grok: ServiceID = "grok"

    static let known: [ServiceID] = [.claude, .github, .openai, .gemini, .grok]
}

extension ServiceRegistry {
    /// Non-optional lookup for tests, where a missing id is a test failure.
    static func definition(_ id: ServiceID) -> ServiceDefinition {
        guard let definition = definition(for: id) else {
            fatalError("\(id) is not in Services.json")
        }
        return definition
    }

    static var claude: ServiceDefinition { definition(.claude) }
    static var gemini: ServiceDefinition { definition(.gemini) }
    static var grok: ServiceDefinition { definition(.grok) }
}
