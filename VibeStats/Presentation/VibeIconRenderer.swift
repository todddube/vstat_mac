//  VibeIconRenderer.swift
//  Draws the menu bar glyph.
//
//  Animation in the menu bar means re-rendering frames, not attaching a SwiftUI
//  animation — NSStatusItem takes an NSImage. Everything here is therefore
//  explicit Core Graphics, parameterised by a `phase` in [0,1).
//
//  Colours are resolved INSIDE the drawing handler, so one image adapts to a
//  light or dark menu bar with no notification observing.

import AppKit

enum VibeIconRenderer {
    static let canvas: CGFloat = 18
    static let badgeCanvas: CGFloat = 29

    /// `scale` draws the same 18-point geometry into a larger canvas rather
    /// than resampling a bitmap, so a settings preview can be big and crisp
    /// without the drawing code learning a second set of sizes.
    static func image(for state: IconState, phase: CGFloat = 0, scale: CGFloat = 1) -> NSImage {
        let width = state.badgeText == nil ? canvas : badgeCanvas
        let base = NSSize(width: width, height: canvas)
        let size = NSSize(width: base.width * scale, height: base.height * scale)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            draw(state, phase: phase, in: CGRect(origin: .zero, size: base))
            context.restoreGState()
            return true
        }

        // A template image is tinted by the system and is the only rendering
        // guaranteed legible against the transparent menu bar over an arbitrary
        // wallpaper — but it forces every pixel to one colour, so it is only
        // usable when nothing on the canvas needs to stay coloured.
        image.isTemplate = state.renderMode == .monochromeWithPip
            && !state.showsPip
            && state.badgeText == nil

        image.accessibilityDescription = state.indicator.title
        return image
    }

    // MARK: - Drawing

    private static func draw(_ state: IconState, phase: CGFloat, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // The glyph occupies a square at the leading edge; a badge, when
        // present, lives in the extra width to its trailing side.
        //
        // A pip sits in the bottom-right corner, which is exactly where the
        // lower-right node lives — so when one is shown the mark shrinks and
        // shifts up-left to clear it. Without this the pip's knock-out halo
        // eats a node and the glyph reads as broken.
        var glyph = CGRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 1, dy: 1)
        if state.showsPip {
            glyph = glyph.insetBy(dx: 1.6, dy: 1.6).offsetBy(dx: -1.4, dy: 1.4)
        }

        switch state.style {
        case .hub:     drawHub(state, phase: phase, in: glyph, context: context)
        case .pulse:   drawPulse(state, phase: phase, in: glyph, context: context)
        case .minimal: drawMinimal(state, phase: phase, in: glyph, context: context)
        }

        if state.showsPip {
            drawPip(state, in: glyph, context: context)
        }

        if let badge = state.badgeText {
            let area = CGRect(x: canvas - 4, y: 0, width: rect.width - canvas + 4, height: canvas)
            drawBadge(badge, state: state, in: area, context: context)
        }
    }

    // MARK: Hub

    private static func drawHub(
        _ state: IconState, phase: CGFloat, in rect: CGRect, context: CGContext
    ) {
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let ink = inkColor(state)

        // M2 — expanding rings from the core, drawn under everything.
        if state.animation == .criticalPulse {
            drawPulseRings(phase: phase, centre: centre, side: side,
                           color: ink, context: context, count: state.motion == .subtle ? 1 : 2)
        }

        // M4 — one bright arc travelling the outer ring per check.
        if state.animation == .refreshSweep {
            drawSweep(phase: phase, centre: centre, side: side, color: ink, context: context)
        }

        // Spokes.
        context.setLineCap(.round)
        context.setLineWidth(VibeHubGeometry.spokeWidth * side)
        context.setStrokeColor(ink.withAlphaComponent(state.isOffline ? 0.4 : 1).cgColor)

        let nodes = state.nodes
        for index in nodes.indices {
            let node = VibeHubGeometry.node(index, of: nodes.count, in: rect)
            let vector = CGVector(dx: node.x - centre.x, dy: node.y - centre.y)
            let length = max(hypot(vector.dx, vector.dy), 0.0001)
            let unit = CGVector(dx: vector.dx / length, dy: vector.dy / length)

            let inner = (VibeHubGeometry.coreRadius + VibeHubGeometry.gap) * side
            let outer = (VibeHubGeometry.nodeRadius + VibeHubGeometry.gap) * side

            context.move(to: CGPoint(x: centre.x + unit.dx * inner, y: centre.y + unit.dy * inner))
            context.addLine(to: CGPoint(x: node.x - unit.dx * outer, y: node.y - unit.dy * outer))
        }
        context.strokePath()

        // Nodes, in fixed service order.
        let nodeRadius = VibeHubGeometry.nodeRadius * side
        for (index, service) in nodes.enumerated() {
            let point = VibeHubGeometry.node(index, of: nodes.count, in: rect)
            let color = nodeColor(state, service: service, fallback: ink)
            // Nodes are ~3 pt across, far too small to hollow out legibly, so
            // an unmeasured node fades instead. The hollow CORE carries the
            // shape difference; the faded nodes reinforce it.
            disc(at: point, radius: nodeRadius,
                 color: state.isHollow ? color.withAlphaComponent(0.4) : color,
                 hollow: false, context: context)
        }

        // Core: the combined verdict, breathing at Full motion.
        let breath: CGFloat = state.animation == .breath
            ? 1 + 0.06 * CGFloat(sin(Double(phase) * 2 * .pi))
            : 1
        disc(at: centre, radius: VibeHubGeometry.coreRadius * side * breath,
             color: coreColor(state, fallback: ink), hollow: state.isHollow, context: context)
    }

    // MARK: Pulse style

    private static func drawPulse(
        _ state: IconState, phase: CGFloat, in rect: CGRect, context: CGContext
    ) {
        let ink = coreColor(state, fallback: inkColor(state))

        // Amplitude by severity: dead flat when healthy, so a calm menu bar
        // stays calm and any deflection at all means something.
        let amplitude: CGFloat = switch state.effectiveColor {
        case .operational: 0.00
        case .minor:       0.20
        case .major:       0.34
        case .critical:    0.46
        case .unknown:     0.08
        }

        let midY = rect.midY
        let steps = 60
        var points: [CGPoint] = []

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = rect.minX + t * rect.width

            // A single QRS-shaped complex travelling left to right: down a
            // little, sharply up, down past the baseline, back. Reads as an
            // instrument trace rather than a sine wave.
            var offset = ((t - phase).truncatingRemainder(dividingBy: 1) + 1)
                .truncatingRemainder(dividingBy: 1)
            if offset > 0.5 { offset -= 1 }

            let y: CGFloat = switch offset {
            case -0.12 ..< -0.06:  -0.18
            case -0.06 ..< -0.01:   1.00
            case -0.01 ..<  0.04:  -0.30
            case  0.04 ..<  0.09:   0.08
            default:                0.00
            }
            points.append(CGPoint(x: x, y: midY + y * amplitude * rect.height))
        }

        context.setLineWidth(1.3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(ink.withAlphaComponent(state.isOffline ? 0.45 : 1).cgColor)
        context.addLines(between: points)
        context.strokePath()
    }

    // MARK: Minimal style

    private static func drawMinimal(
        _ state: IconState, phase: CGFloat, in rect: CGRect, context: CGContext
    ) {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let ink = coreColor(state, fallback: inkColor(state))
        let radius = min(rect.width, rect.height) * 0.22

        if state.animation == .criticalPulse {
            drawPulseRings(phase: phase, centre: centre, side: rect.width,
                           color: ink, context: context, count: 1)
        }

        switch state.effectiveColor {
        case .operational:
            disc(at: centre, radius: radius, color: ink, hollow: false, context: context)
        case .unknown:
            disc(at: centre, radius: radius, color: ink, hollow: true, context: context)
        case .minor, .major, .critical:
            // Ring thickness carries severity, so the state survives monochrome.
            let thickness: CGFloat = state.effectiveColor == .minor ? 1 : (state.effectiveColor == .major ? 1.6 : 2.2)
            disc(at: centre, radius: radius * 0.55, color: ink, hollow: false, context: context)
            context.setLineWidth(thickness)
            context.setStrokeColor(ink.cgColor)
            context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                             width: radius * 2, height: radius * 2))
        }
    }

    // MARK: Decorations

    private static func drawPip(_ state: IconState, in rect: CGRect, context: CGContext) {
        let radius: CGFloat = 2.6
        // Anchored to the canvas corner, not to the (shrunken) glyph box.
        let centre = CGPoint(x: canvas - radius - 0.6, y: radius + 0.6)
        let color = state.isOffline ? Palette.offline : Palette.color(for: state.indicator)

        // Knock a hole in whatever is behind the pip so it reads as a separate
        // object rather than a smudge on the glyph.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: centre.x - radius - 0.7, y: centre.y - radius - 0.7,
                                       width: (radius + 0.7) * 2, height: (radius + 0.7) * 2))
        context.setBlendMode(.normal)

        disc(at: centre, radius: radius, color: color,
             hollow: state.isOffline || state.indicator == .unknown, context: context)
    }

    private static func drawBadge(
        _ text: String, state: IconState, in rect: CGRect, context: CGContext
    ) {
        let color = state.isOffline ? Palette.offline : Palette.color(for: state.indicator)
        let radius: CGFloat = 5
        let centre = CGPoint(x: rect.maxX - radius - 0.5, y: rect.midY)

        // Separate the badge from the glyph with a knocked-out halo, so the two
        // read as distinct objects on a busy wallpaper.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: centre.x - radius - 1, y: centre.y - radius - 1,
                                       width: (radius + 1) * 2, height: (radius + 1) * 2))
        context.setBlendMode(.normal)

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor(hex: 0x0A0F18)
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2))
    }

    private static func drawPulseRings(
        phase: CGFloat, centre: CGPoint, side: CGFloat,
        color: NSColor, context: CGContext, count: Int
    ) {
        for ring in 0..<count {
            // Offset the second ring so they chase rather than overlap.
            let offset = CGFloat(ring) * 0.4
            let t = (phase + offset).truncatingRemainder(dividingBy: 1)
            let radius = VibeHubGeometry.coreRadius * side * (1 + t * 0.8) * 2.2
            let alpha = max(0, 0.45 * (1 - t))

            context.setLineWidth(0.8)
            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                             width: radius * 2, height: radius * 2))
        }
    }

    private static func drawSweep(
        phase: CGFloat, centre: CGPoint, side: CGFloat,
        color: NSColor, context: CGContext
    ) {
        let radius = VibeHubGeometry.nodeRingRadius * side
        let start = phase * 2 * .pi
        let path = CGMutablePath()
        path.addArc(center: centre, radius: radius,
                    startAngle: start, endAngle: start + .pi / 2, clockwise: false)

        context.setLineWidth(1.1)
        context.setLineCap(.round)
        context.setStrokeColor(color.withAlphaComponent(0.55).cgColor)
        context.addPath(path)
        context.strokePath()
    }

    private static func disc(
        at point: CGPoint, radius: CGFloat, color: NSColor, hollow: Bool, context: CGContext
    ) {
        let box = CGRect(x: point.x - radius, y: point.y - radius,
                         width: radius * 2, height: radius * 2)
        if hollow {
            context.setLineWidth(max(0.8, radius * 0.55))
            context.setStrokeColor(color.cgColor)
            context.strokeEllipse(in: box.insetBy(dx: radius * 0.2, dy: radius * 0.2))
        } else {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: box)
        }
    }

    // MARK: Colour resolution

    /// In monochrome mode everything is drawn in the label colour, which
    /// resolves against whatever appearance is drawing — so one image is
    /// correct in both a light and a dark menu bar.
    private static func inkColor(_ state: IconState) -> NSColor {
        state.renderMode == .monochromeWithPip
            ? .labelColor
            : Palette.color(for: state.effectiveColor)
    }

    private static func coreColor(_ state: IconState, fallback: NSColor) -> NSColor {
        state.renderMode == .colour ? Palette.color(for: state.effectiveColor) : fallback
    }

    private static func nodeColor(
        _ state: IconState, service: ServiceID, fallback: NSColor
    ) -> NSColor {
        guard state.renderMode == .colour, !state.isOffline else { return fallback }
        let indicator = state.services[service] ?? .unknown
        // A healthy node stays quiet; only a degraded one takes a colour, so
        // the eye goes straight to the corner that matters.
        return indicator == .operational
            ? Palette.color(for: .operational)
            : Palette.color(for: indicator)
    }
}
