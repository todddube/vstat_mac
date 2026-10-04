//  VibeHubGeometry.swift
//  The mark, defined once on a unit square and scaled everywhere.
//
//  The extension's icon is a six-spoke hub. Here it has ONE spoke per enabled
//  service, each assigned to that service in registry order, so the glyph stops
//  being decoration and becomes a readout: at a glance you can see not just
//  that something is degraded but which corner of your toolchain it is.
//
//  Nodes are spaced evenly, clockwise from upper-left. With four services that
//  lands exactly on the original diagonal mark:
//
//      Claude ◆         ◆ GitHub
//            ╲         ╱
//              ╲     ╱
//                ◉  ←── core: the combined roll-up
//              ╱     ╲
//            ╱         ╲
//     Gemini ◆         ◆ OpenAI

import CoreGraphics
import Foundation

enum VibeHubGeometry {
    /// Fractions of the canvas edge.
    ///
    /// These are tuned for an 18 pt menu bar canvas, where the whole mark is
    /// about 12 pt across. The first pass used the app icon's proportions and
    /// produced 1.8 pt nodes and 0.6 pt spokes — legible at 4× in a contact
    /// sheet, mush in an actual menu bar, and far too small for the hollow
    /// (unknown) treatment to read at all.
    static let nodeRingRadius: CGFloat = 0.300
    static let coreRadius: CGFloat     = 0.115
    static let nodeRadius: CGFloat     = 0.085
    static let spokeWidth: CGFloat     = 0.055
    /// A spoke never touches either disc — that gap is what keeps the mark
    /// crisp at 16 pt.
    static let gap: CGFloat            = 0.022

    /// Evenly spaced, clockwise from the upper-left diagonal (135°), so four
    /// nodes reproduce the original X exactly and a fifth service slots in
    /// without a special case. Positions depend only on the enabled set — card
    /// ordering in the popover never moves them.
    static func node(_ index: Int, of count: Int, in rect: CGRect) -> CGPoint {
        let count = max(count, 1)
        let angle = (135.0 - 360.0 * Double(index) / Double(count)) * .pi / 180
        let radius = nodeRingRadius * rect.width
        return CGPoint(x: rect.midX + radius * CGFloat(cos(angle)),
                       y: rect.midY + radius * CGFloat(sin(angle)))
    }
}
