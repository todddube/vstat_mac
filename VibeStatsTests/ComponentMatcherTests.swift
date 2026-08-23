import Testing
@testable import VibeStats

@Suite("ComponentMatcher")
struct ComponentMatcherTests {

    private func component(_ name: String, _ status: String = "operational") -> MatchableComponent {
        MatchableComponent(name: name, status: status)
    }

    @Test("Exact name wins over a regex that would also match")
    func exactBeatsPattern() {
        let definition = ComponentDefinition(
            id: "copilot", label: "Copilot",
            exactMatches: ["copilot"], patterns: [#"copilot"#]
        )
        let payload = [component("Copilot Chat"), component("Copilot")]
        var claimed = Set<String>()

        #expect(ComponentMatcher.match(definition, in: payload, claimed: &claimed)?.name == "Copilot")
    }

    @Test("Exact matching is case- and whitespace-insensitive")
    func exactNormalises() {
        let definition = ComponentDefinition(
            id: "claude-code", label: "Claude Code", exactMatches: ["claude code"]
        )
        var claimed = Set<String>()
        let match = ComponentMatcher.match(definition, in: [component("  Claude Code ")], claimed: &claimed)
        #expect(match != nil)
    }

    @Test("Regex is the fallback when the vendor renames a component")
    func patternFallback() {
        let definition = ComponentDefinition(
            id: "claude-code", label: "Claude Code",
            exactMatches: ["claude code"], patterns: [#"\bclaude code\b"#]
        )
        var claimed = Set<String>()
        let match = ComponentMatcher.match(
            definition, in: [component("Claude Code (beta)")], claimed: &claimed
        )
        #expect(match?.name == "Claude Code (beta)")
    }

    /// The `claimed` set is what stops a loose pattern from stealing a
    /// component an earlier definition already took and reporting the same
    /// status under two labels.
    @Test("A loose pattern cannot steal an already-claimed component")
    func claimedPreventsStealing() {
        let first = ComponentDefinition(
            id: "codex-desktop", label: "Codex Desktop", patterns: [#"chatgpt"#]
        )
        let second = ComponentDefinition(
            id: "chatgpt", label: "ChatGPT", patterns: [#"chatgpt"#]
        )
        let payload = [component("Codex in ChatGPT Desktop")]
        var claimed = Set<String>()

        let firstMatch = ComponentMatcher.match(first, in: payload, claimed: &claimed)
        let secondMatch = ComponentMatcher.match(second, in: payload, claimed: &claimed)

        #expect(firstMatch?.name == "Codex in ChatGPT Desktop")
        #expect(secondMatch == nil, "the second definition must not re-report the same component")
    }

    @Test("No match returns nil so the caller can report UNKNOWN")
    func noMatchIsNil() {
        let definition = ComponentDefinition(
            id: "ghost", label: "Ghost", exactMatches: ["ghost"], patterns: [#"^ghost$"#]
        )
        var claimed = Set<String>()
        #expect(ComponentMatcher.match(definition, in: [component("Something Else")], claimed: &claimed) == nil)
        #expect(ComponentMatcher.match(definition, in: [], claimed: &claimed) == nil)
    }

    @Test("Anchored patterns do not match substrings")
    func anchoring() {
        #expect(ComponentMatcher.matches(pattern: #"^actions$"#, in: "Actions"))
        #expect(!ComponentMatcher.matches(pattern: #"^actions$"#, in: "GitHub Actions"))
        #expect(ComponentMatcher.matches(pattern: #"^cli$"#, in: "CLI"))
        #expect(!ComponentMatcher.matches(pattern: #"^cli$"#, in: "Codex CLI"))
    }

    /// docs/REVIEW.md §3.6 — the extension's bare /\bapi\b/ would bind the
    /// "API" entry to any component containing the word.
    @Test("Claude's tightened API pattern does not bind to unrelated components")
    func claudeAPIPatternIsNotGreedy() {
        let definition = ServiceRegistry.claude.component(id: "claude-api")!
        for name in ["Copilot API", "API Requests", "Vertex AI API", "Public API"] {
            let matched = definition.patterns.contains {
                ComponentMatcher.matches(pattern: $0, in: name)
            }
            #expect(!matched, "\(name) must not match Claude's API fallback")
        }
        #expect(definition.patterns.contains {
            ComponentMatcher.matches(pattern: $0, in: "Claude API (api.anthropic.com)")
        })
    }
}
