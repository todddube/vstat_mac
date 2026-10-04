import Foundation
import Testing
@testable import VibeStats

@Suite("ServiceRegistry integrity")
struct RegistryTests {

    @Test("Services.json loads, in the documented order, with every id tests rely on")
    func coverage() {
        #expect(ServiceRegistry.ids == ServiceID.known)
        for id in ServiceRegistry.ids {
            #expect(ServiceRegistry.definition(for: id)?.id == id)
        }
        #expect(ServiceRegistry.definition(for: "not-a-service") == nil)
    }

    @Test("The registry matches the extension's shape", arguments: [
        (ServiceID.claude, "Claude AI", "Anthropic", 5, 4),
        (.github, "GitHub Copilot", "GitHub", 5, 4),
        (.openai, "OpenAI", "OpenAI", 6, 4),
        (.gemini, "Gemini", "Google", 3, 3),
        (.grok, "Grok", "xAI", 6, 4)
    ])
    func shape(id: ServiceID, name: String, vendor: String, components: Int, primary: Int) {
        let definition = ServiceRegistry.definition(id)
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

    @Test("Statuspage services carry an api/v2 base; the rest carry their feeds")
    func endpoints() {
        for service in ServiceRegistry.all {
            switch service.api {
            case .statuspage(let base):
                #expect(base.absoluteString.hasSuffix("/api/v2"))
                #expect(base.scheme == "https")
            case .googleCloud(let incidents, let keywords):
                #expect(service.id == .gemini)
                #expect(incidents.absoluteString.hasSuffix("incidents.json"))
                #expect(!keywords.isEmpty)
            case .rssFeed(let feed):
                #expect(service.id == .grok)
                #expect(feed.scheme == "https")
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

    @Test("Every service has its own accent")
    func distinctAccents() {
        let accents = ServiceRegistry.all.map(\.accent)
        #expect(Set(accents).count == accents.count)
    }

    @Test("A malformed registry fails with a sentence, not a crash", arguments: [
        // Unknown api type.
        ##"{"services":[{"id":"x","name":"X","vendor":"X","statusURL":"https://x.test","accent":{"dark":"#000000","light":"#FFFFFF"},"api":{"type":"carrierPigeon"},"components":[{"id":"a","label":"A"}]}]}"##,
        // Bad hex.
        ##"{"services":[{"id":"x","name":"X","vendor":"X","statusURL":"https://x.test","accent":{"dark":"black","light":"#FFFFFF"},"api":{"type":"rssFeed","feed":"https://x.test/feed.xml"},"components":[{"id":"a","label":"A"}]}]}"##,
        // Uncompilable pattern.
        ##"{"services":[{"id":"x","name":"X","vendor":"X","statusURL":"https://x.test","accent":{"dark":"#000000","light":"#FFFFFF"},"api":{"type":"rssFeed","feed":"https://x.test/feed.xml"},"components":[{"id":"a","label":"A","patterns":["("]}]}]}"##,
        // No components.
        ##"{"services":[{"id":"x","name":"X","vendor":"X","statusURL":"https://x.test","accent":{"dark":"#000000","light":"#FFFFFF"},"api":{"type":"rssFeed","feed":"https://x.test/feed.xml"},"components":[]}]}"##
    ])
    func rejectsMalformed(json: String) {
        #expect(throws: ServiceRegistry.RegistryError.self) {
            try ServiceRegistry.decode(Data(json.utf8))
        }
    }

    @Test("A minimal new service is just JSON")
    func addingAServiceIsJustJSON() throws {
        let json = ##"{"services":[{"id":"acme","name":"Acme AI","vendor":"Acme","statusURL":"https://status.acme.test","accent":{"dark":"#112233","light":"#445566"},"api":{"type":"statuspage","base":"https://status.acme.test/api/v2"},"components":[{"id":"acme-api","label":"API","exactMatches":["Acme API"],"isPrimary":true}]}]}"##
        let services = try ServiceRegistry.decode(Data(json.utf8))
        #expect(services.map(\.id) == ["acme"])
        #expect(services[0].accent == AccentColor(dark: 0x112233, light: 0x445566))
        #expect(services[0].components[0].exactMatches == ["acme api"])
    }
}
