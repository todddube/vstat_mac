import Foundation
import Testing
@testable import VibeStats

@Suite("ServiceRegistry integrity")
struct RegistryTests {

    @Test("Every ServiceID has exactly one definition, in registry order")
    func coverage() {
        #expect(ServiceRegistry.all.count == ServiceID.allCases.count)
        #expect(ServiceRegistry.all.map(\.id) == ServiceID.allCases)
        for id in ServiceID.allCases {
            #expect(ServiceRegistry.definition(for: id).id == id)
        }
    }

    @Test("The registry matches the extension's shape", arguments: [
        (ServiceID.claude, "Claude AI", "Anthropic", 5, 4),
        (.github, "GitHub Copilot", "GitHub", 5, 4),
        (.openai, "OpenAI", "OpenAI", 6, 4),
        (.gemini, "Gemini", "Google", 3, 3)
    ])
    func shape(id: ServiceID, name: String, vendor: String, components: Int, primary: Int) {
        let definition = ServiceRegistry.definition(for: id)
        #expect(definition.name == name)
        #expect(definition.vendor == vendor)
        #expect(definition.components.count == components)
        #expect(definition.primaryComponents.count == primary)
    }

    @Test("Component ids are unique within a service and across the registry")
    func uniqueIDs() {
        var seen = Set<String>()
        for service in ServiceRegistry.all {
            let ids = service.components.map(\.id)
            #expect(Set(ids).count == ids.count, "duplicate component id in \(service.id)")
            for id in ids {
                #expect(seen.insert(id).inserted, "component id \(id) is reused across services")
            }
        }
    }

    @Test("Every stored pattern is a valid regex")
    func patternsCompile() throws {
        for service in ServiceRegistry.all {
            for component in service.components {
                for pattern in component.patterns {
                    #expect(throws: Never.self) {
                        try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                    }
                }
            }
        }
    }

    @Test("Every component can be matched by its own label or exact name")
    func selfMatching() {
        for service in ServiceRegistry.all {
            for component in service.components {
                let probe = component.exactMatches.first ?? component.label
                var claimed = Set<String>()
                let match = ComponentMatcher.match(
                    component,
                    in: [MatchableComponent(name: probe)],
                    claimed: &claimed
                )
                #expect(match != nil, "\(service.id)/\(component.id) cannot match \"\(probe)\"")
            }
        }
    }

    @Test("No component's fallback patterns match a sibling's exact name")
    func patternsDoNotCollide() {
        for service in ServiceRegistry.all {
            for component in service.components {
                let siblings = service.components.filter { $0.id != component.id }
                for sibling in siblings {
                    for name in sibling.exactMatches {
                        let collides = component.patterns.contains {
                            ComponentMatcher.matches(pattern: $0, in: name)
                        }
                        #expect(
                            !collides,
                            "\(service.id)/\(component.id) pattern matches sibling \(sibling.id) name \"\(name)\""
                        )
                    }
                }
            }
        }
    }

    @Test("Statuspage services carry an api/v2 base; Gemini carries an incident feed")
    func endpoints() {
        for service in ServiceRegistry.all {
            switch service.api {
            case .statuspage(let base):
                #expect(base.absoluteString.hasSuffix("/api/v2"))
                #expect(base.scheme == "https")
            case .googleCloud(let incidents):
                #expect(service.id == .gemini)
                #expect(incidents.absoluteString.hasSuffix("incidents.json"))
            }
            #expect(service.statusURL.scheme == "https")
        }
    }

    @Test("Gemini components are pattern-only — Google publishes no component health")
    func geminiIsIncidentDerived() {
        for component in ServiceRegistry.gemini.components {
            #expect(component.exactMatches.isEmpty)
            #expect(!component.patterns.isEmpty)
        }
    }
}
