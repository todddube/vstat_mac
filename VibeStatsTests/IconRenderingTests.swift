import AppKit
import Testing
@testable import VibeStats

@Suite("Menu bar glyph", .serialized)
@MainActor
struct IconRenderingTests {

    private func state(
        _ indicator: StatusIndicator,
        affected: Int = 0,
        offline: Bool = false,
        checking: Bool = false,
        mode: IconRenderMode = .monochromeWithPip,
        style: MenuBarIconStyle = .hub,
        badge: Bool = true
    ) -> IconState {
        var state = IconState()
        state.indicator = indicator
        state.affectedCount = affected
        state.isOffline = offline
        state.isChecking = checking
        state.renderMode = mode
        state.style = style
        state.showBadge = badge
        state.services = [
            .claude: .operational, .github: indicator,
            .openai: .operational, .gemini: .operational
        ]
        return state
    }

    // MARK: - Badge rules (≙ the extension exactly)

    @Test("Badge text follows the extension's rules", arguments: [
        (StatusIndicator.operational, 0, String?.none),
        (.operational, 3, nil),
        (.minor, 0, "?"),
        (.minor, 2, "2"),
        (.major, 0, "!"),
        (.major, 4, "4"),
        (.critical, 0, "!"),
        (.critical, 1, "1"),
        (.unknown, 0, "?")
    ])
    func badgeRules(indicator: StatusIndicator, affected: Int, expected: String?) {
        #expect(state(indicator, affected: affected).badgeText == expected)
    }

    @Test("Turning the badge off removes it entirely")
    func badgeCanBeDisabled() {
        #expect(state(.critical, affected: 2, badge: false).badgeText == nil)
    }

    @Test("Offline shows no badge — it is not a measurement")
    func offlineHasNoBadge() {
        #expect(state(.unknown, offline: true).badgeText == nil)
    }

    // MARK: - Shape semantics

    @Test("Unknown and offline are drawn hollow, so the state survives monochrome")
    func hollowStates() {
        #expect(state(.unknown).isHollow)
        #expect(state(.operational, offline: true).isHollow)
        #expect(!state(.operational).isHollow)
        #expect(!state(.critical, affected: 1).isHollow)
    }

    @Test("The pip appears only when there is something to say, and never beside a badge")
    func pipRules() {
        #expect(!state(.operational).showsPip, "a healthy glyph is quiet")
        #expect(!state(.critical, affected: 2).showsPip, "the badge already carries the colour")
        #expect(state(.critical, affected: 0, badge: false).showsPip)
        #expect(state(.operational, offline: true).showsPip)
        #expect(!state(.critical, affected: 2, mode: .colour).showsPip, "colour mode needs no pip")
    }

    @Test("A template image is only claimed when every pixel may be tinted")
    func templateOnlyWhenSafe() {
        #expect(VibeIconRenderer.image(for: state(.operational)).isTemplate)
        #expect(!VibeIconRenderer.image(for: state(.critical, affected: 2)).isTemplate,
                "a coloured badge cannot survive template tinting")
        #expect(!VibeIconRenderer.image(for: state(.critical, badge: false)).isTemplate,
                "a coloured pip cannot survive template tinting")
        #expect(!VibeIconRenderer.image(for: state(.operational, mode: .colour)).isTemplate)
    }

    // MARK: - Animation gating

    @Test("Motion levels gate the animations they should")
    func animationGating() {
        var healthy = state(.operational)
        healthy.motion = .full
        #expect(healthy.animation == .breath, "the heartbeat only runs at Full")
        healthy.motion = .subtle
        #expect(healthy.animation == .none)
        healthy.motion = .off
        #expect(healthy.animation == .none)

        var critical = state(.critical, affected: 1)
        critical.motion = .subtle
        #expect(critical.animation == .criticalPulse, "an outage still pulses at Subtle")
        critical.motion = .off
        #expect(critical.animation == .none)

        var checking = state(.operational, checking: true)
        checking.motion = .full
        #expect(checking.animation == .refreshSweep, "checking outranks the heartbeat")
    }

    @Test("Offline never animates")
    func offlineIsStill() {
        var offline = state(.critical, offline: true)
        offline.motion = .full
        #expect(offline.animation == .none)
    }

    // MARK: - Rendering

    @Test("Every state renders a non-empty image at the expected size")
    func rendersAllStates() {
        for style in MenuBarIconStyle.allCases {
            for mode in IconRenderMode.allCases {
                for indicator in StatusIndicator.allCases {
                    let state = state(indicator, affected: 2, mode: mode, style: style)
                    let image = VibeIconRenderer.image(for: state, phase: 0.5)

                    #expect(image.size.height == VibeIconRenderer.canvas)
                    #expect(image.size.width >= VibeIconRenderer.canvas)
                    #expect(image.tiffRepresentation != nil,
                            "\(style)/\(mode)/\(indicator) produced no bitmap")
                }
            }
        }
    }

    @Test("Scaling grows the canvas so a settings preview stays crisp")
    func scaledCanvas() {
        let image = VibeIconRenderer.image(for: state(.operational), scale: 2.5)
        #expect(image.size.height == VibeIconRenderer.canvas * 2.5)
        #expect(image.size.width == VibeIconRenderer.canvas * 2.5)
        #expect(image.tiffRepresentation != nil)

        let badged = VibeIconRenderer.image(for: state(.critical, affected: 2), scale: 2)
        #expect(badged.size.width == VibeIconRenderer.badgeCanvas * 2)
    }

    @Test("The badge widens the canvas; a bare glyph stays square")
    func canvasWidth() {
        #expect(VibeIconRenderer.image(for: state(.operational)).size.width == VibeIconRenderer.canvas)
        #expect(VibeIconRenderer.image(for: state(.critical, affected: 2)).size.width
                == VibeIconRenderer.badgeCanvas)
    }

    @Test("Four nodes land exactly on the original diagonal mark")
    func nodePositions() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let original: [CGPoint] = [
            CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: -1)
        ]
        let reach = VibeHubGeometry.nodeRingRadius * 100 * 0.70710678
        for (index, offset) in original.enumerated() {
            let node = VibeHubGeometry.node(index, of: 4, in: rect)
            #expect(abs(node.x - (50 + offset.x * reach)) < 0.001)
            #expect(abs(node.y - (50 + offset.y * reach)) < 0.001)
        }
    }

    @Test("Any node count spaces evenly on one ring, without overlapping nodes",
          arguments: [3, 5, 6])
    func nodeCounts(count: Int) {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let nodes = (0..<count).map { VibeHubGeometry.node($0, of: count, in: rect) }
        let diameter = VibeHubGeometry.nodeRadius * 2 * 100
        for (index, node) in nodes.enumerated() {
            #expect(abs(hypot(node.x - 50, node.y - 50) - VibeHubGeometry.nodeRingRadius * 100) < 0.001)
            let next = nodes[(index + 1) % count]
            #expect(hypot(next.x - node.x, next.y - node.y) > diameter)
        }
        // The first node is always upper-left.
        #expect(nodes[0].x < 50 && nodes[0].y > 50)
    }

    /// Writes a contact sheet so the glyph can be reviewed by eye, not only by
    /// assertion — once per appearance, since a monochrome glyph is drawn in
    /// the label colour and is therefore meaningless outside the appearance it
    /// was rendered for.
    @Test("Contact sheet renders", arguments: [NSAppearance.Name.darkAqua, .aqua])
    func contactSheet(appearanceName: NSAppearance.Name) throws {
        let states: [(String, IconState)] = [
            ("operational", state(.operational)),
            ("minor", state(.minor, affected: 1)),
            ("major", state(.major, affected: 2)),
            ("critical", state(.critical, affected: 3)),
            ("unknown", state(.unknown)),
            ("offline", state(.operational, offline: true)),
            ("checking", state(.operational, checking: true)),
            ("critical-pip", state(.critical, badge: false)),
            ("minor-pip", state(.minor, badge: false)),
            ("colour-ok", state(.operational, mode: .colour)),
            ("colour-major", state(.major, affected: 2, mode: .colour)),
            ("pulse-ok", state(.operational, style: .pulse, badge: false)),
            ("pulse-major", state(.major, style: .pulse, badge: false)),
            ("minimal-ok", state(.operational, style: .minimal, badge: false)),
            ("minimal-major", state(.major, style: .minimal, badge: false))
        ]

        let appearance = try #require(NSAppearance(named: appearanceName))
        let isDark = appearanceName == .darkAqua
        let scale: CGFloat = 4
        let cell = CGSize(width: 34, height: 24)

        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(states.count) * scale,
                                         height: cell.height * scale))
        sheet.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            // Approximate a menu bar of the matching appearance.
            NSColor(hex: isDark ? 0x1B2430 : 0xE9EDF3).setFill()
            NSRect(origin: .zero, size: sheet.size).fill()

            for (index, entry) in states.enumerated() {
                let image = VibeIconRenderer.image(for: entry.1, phase: 0.35)
                // Template images are tinted by the system in the real menu bar;
                // emulate that so the sheet shows what a user would see.
                let drawn: NSImage
                if image.isTemplate {
                    drawn = NSImage(size: image.size, flipped: false) { rect in
                        image.draw(in: rect)
                        (isDark ? NSColor.white : NSColor.black).set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                } else {
                    drawn = image
                }

                let origin = NSPoint(x: (CGFloat(index) * cell.width + 3) * scale, y: 3 * scale)
                drawn.draw(
                    in: NSRect(origin: origin,
                               size: NSSize(width: drawn.size.width * scale,
                                            height: drawn.size.height * scale)),
                    from: .zero, operation: .sourceOver, fraction: 1
                )
            }
        }
        sheet.unlockFocus()

        let url = FileManager.default.temporaryDirectory
            .appending(path: "vibe-icon-sheet-\(isDark ? "dark" : "light").png")
        let bitmap = try #require(sheet.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)

        print("ICON SHEET: \(url.path)")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Test in menu bar")
@MainActor
struct IconDemoTests {
    @Test("The demo covers every status, offline and checking, across every service")
    func coversEverything() {
        let steps = IconDemo.steps(for: ServiceRegistry.ids)
        let indicators = Set(steps.filter { !$0.isOffline }.map(\.indicator))
        #expect(indicators == Set(StatusIndicator.allCases))
        #expect(steps.contains { $0.isOffline })
        #expect(steps.contains { $0.isChecking })
        for step in steps {
            #expect(Set(step.services.keys) == Set(ServiceRegistry.ids))
        }
        // Each step must look different from the one before it.
        for (previous, next) in zip(steps, steps.dropFirst()) {
            #expect(previous != next)
        }
    }

    @Test("Start shows a step and notifies; Stop hands the glyph back to live")
    func startStop() {
        let demo = IconDemo()
        var changes = 0
        demo.onChange = { changes += 1 }

        demo.start()
        // The first step is set from inside a Task, so nothing is shown yet…
        #expect(!demo.isRunning || demo.current?.indicator == .operational)

        demo.stop()
        #expect(!demo.isRunning)
        #expect(changes >= 1)
    }

    @Test("A running demo walks through its steps and ends on its own")
    func runsToCompletion() async {
        let demo = IconDemo()
        var seen: [String] = []
        demo.onChange = { seen.append(demo.current?.title ?? "live") }

        demo.start()
        try? await Task.sleep(for: IconDemo.duration + .milliseconds(800))

        #expect(!demo.isRunning)
        #expect(seen.last == "live")
        #expect(seen.count == IconDemo.steps(for: ServiceRegistry.ids).count + 1)
    }
}
