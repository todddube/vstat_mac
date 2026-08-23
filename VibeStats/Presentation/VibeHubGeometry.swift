//  VibeHubGeometry.swift
//  The mark, defined once on a unit square and scaled everywhere.
//
//  The extension's icon is a six-spoke hub. Here it is reduced to FOUR spokes,
//  each permanently assigned to one monitored service, so the glyph stops being
//  decoration and becomes a readout: at a glance you can see not just that
//  something is degraded but which corner of your toolchain it is.
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

    /// Fixed positions, always, regardless of card ordering in the popover.
    /// Order matches `ServiceID.allCases`.
    static let nodeOffsets: [CGPoint] = [
        CGPoint(x: -1, y:  1),   // claude — upper-left
        CGPoint(x:  1, y:  1),   // github — upper-right
        CGPoint(x:  1, y: -1),   // openai — lower-right
        CGPoint(x: -1, y: -1)    // gemini — lower-left
    ]

    private static let diagonal: CGFloat = 0.70710678

    static func node(_ index: Int, in rect: CGRect) -> CGPoint {
        let offset = nodeOffsets[index % nodeOffsets.count]
        let radius = nodeRingRadius * rect.width * diagonal
        return CGPoint(x: rect.midX + offset.x * radius, y: rect.midY + offset.y * radius)
    }
}
