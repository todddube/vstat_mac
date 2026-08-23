//  Palette.swift
//  Semantic colour tokens. No view — and no icon renderer — names a hex value.
//
//  Every token is a dynamic NSColor so it resolves against whatever appearance
//  is current at draw time. That is what lets the menu bar glyph adapt to a
//  light or dark menu bar without re-rendering on a notification.

import AppKit
import SwiftUI

enum Palette {
    // MARK: - Status

    static let operational = dynamic(dark: 0x22D3A5, light: 0x0E9F6E)
    static let minor       = dynamic(dark: 0xF5B23B, light: 0xB45309)
    static let major       = dynamic(dark: 0xFB7A3C, light: 0xC2410C)
    static let critical    = dynamic(dark: 0xF2545B, light: 0xDC2626)
    static let unknown     = dynamic(dark: 0x6B7A8F, light: 0x64748B)
    static let offline     = dynamic(dark: 0x4A5568, light: 0x94A3B8)

    static func color(for indicator: StatusIndicator) -> NSColor {
        switch indicator {
        case .operational: return operational
        case .minor:       return minor
        case .major:       return major
        case .critical:    return critical
        case .unknown:     return unknown
        }
    }

    // MARK: - Brand & surface

    static let vibe      = dynamic(dark: 0x22D3EE, light: 0x0891B2)
    static let vibeDeep  = dynamic(dark: 0x0E7490, light: 0x155E75)

    static let surfaceBase   = dynamic(dark: 0x0E1420, light: 0xF7F9FC)
    static let surfaceRaised = dynamic(dark: 0x161E2E, light: 0xFFFFFF)
    static let surfaceSunken = dynamic(dark: 0x0A0F18, light: 0xEEF2F7)

    // MARK: - Vendor accents
    //
    // Accents mark WHOSE card this is. They never encode status — mixing the
    // two is how a status grid turns into confetti.

    static func accent(for service: ServiceID) -> NSColor {
        switch service {
        case .claude: return dynamic(dark: 0xE08C3C, light: 0xD97706)
        case .github: return dynamic(dark: 0xA78BFA, light: 0x7C3AED)
        case .openai: return dynamic(dark: 0x34D399, light: 0x059669)
        case .gemini: return dynamic(dark: 0x60A5FA, light: 0x2563EB)
        }
    }

    // MARK: -

    static func dynamic(dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    static func status(_ indicator: StatusIndicator) -> Color {
        Color(nsColor: Palette.color(for: indicator))
    }

    static func accent(_ service: ServiceID) -> Color {
        Color(nsColor: Palette.accent(for: service))
    }

    static let vibe = Color(nsColor: Palette.vibe)
    static let surfaceBase = Color(nsColor: Palette.surfaceBase)
    static let surfaceRaised = Color(nsColor: Palette.surfaceRaised)
    static let surfaceSunken = Color(nsColor: Palette.surfaceSunken)
}
