#!/usr/bin/env swift
//
//  make-appicon.swift
//  Draws the Vibe Stats app icon and writes every size the asset catalogue
//  needs. Run with `make icon`.
//
//  The app icon keeps the SIX-spoke hub of the browser extension's mark, for
//  brand continuity; the menu bar uses a four-spoke reduction where each node
//  is one service. Four of the six nodes carry the vendor accents.
//
//  Sizes at or below 64 px are drawn from a SIMPLIFIED path — no orbit rings,
//  no dot field, no glow, no specular — with thicker spokes to hold the same
//  optical weight. A naive downscale of the full artwork turns to cyan mush.

import AppKit
import Foundation

// MARK: - Palette

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let cyan      = srgb(0x22D3EE)
let cyanLight = srgb(0x67E8F9)
let cyanPale  = srgb(0xA5F3FC)
let cyanDeep  = srgb(0x0E7490)
let bgNear    = srgb(0x1B2740)
let bgMid     = srgb(0x111A2B)
let bgFar     = srgb(0x0A0F18)

/// Vendor accents, in the same order the popover cards use them.
let accents: [NSColor] = [
    srgb(0xE08C3C),   // Claude   — upper-left
    srgb(0xA78BFA),   // GitHub   — upper-right
    srgb(0x34D399),   // OpenAI   — lower-right
    srgb(0x60A5FA)    // Gemini   — lower-left
]

// MARK: - Geometry (fractions of the 1024 canvas)

let inset: CGFloat = 100.0 / 1024        // macOS icon grid: 824 of 1024
let cornerRadius: CGFloat = 185.4 / 1024
let ringRadius: CGFloat = 247.0 / 1024
let nodeRadius: CGFloat = 38.0 / 1024
let coreRadius: CGFloat = 62.0 / 1024
let spokeWidth: CGFloat = 14.0 / 1024
let spokeInner: CGFloat = 78.0 / 1024
let spokeOuter: CGFloat = 193.0 / 1024

/// Six directions. Top and bottom stay cyan; the four diagonals are the
/// vendors, in accent order.
let angles: [CGFloat] = [150, 30, 330, 210, 90, 270]   // degrees, y-up
let nodeColours: [NSColor] = accents + [cyan, cyan]

func point(_ degrees: CGFloat, radius: CGFloat, centre: CGPoint) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(x: centre.x + cos(radians) * radius, y: centre.y + sin(radians) * radius)
}

// MARK: - Drawing

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    let simplified = size <= 64
    let centre = CGPoint(x: size / 2, y: size / 2)
    let body = CGRect(
        x: inset * size, y: inset * size,
        width: size - 2 * inset * size, height: size - 2 * inset * size
    )
    let squircle = NSBezierPath(roundedRect: body,
                                xRadius: cornerRadius * size, yRadius: cornerRadius * size)

    // --- substrate
    context.saveGState()
    squircle.addClip()

    if simplified {
        srgb(0x0E1420).setFill()
        body.fill()
    } else {
        let gradient = NSGradient(colorsAndLocations:
            (bgNear, 0.0), (bgMid, 0.55), (bgFar, 1.0)
        )!
        gradient.draw(
            fromCenter: CGPoint(x: body.minX + body.width * 0.35, y: body.maxY - body.height * 0.30),
            radius: 0,
            toCenter: CGPoint(x: body.midX, y: body.midY),
            radius: body.width * 0.85,
            options: []
        )

        // A dot field, masked to the corners so it reads as substrate rather
        // than texture.
        let step = 48.0 / 1024 * size
        var y = body.minY
        while y < body.maxY {
            var x = body.minX
            while x < body.maxX {
                let distance = hypot(x - centre.x, y - centre.y) / (body.width / 2)
                let alpha = max(0, min(0.05, (distance - 0.55) * 0.09))
                if alpha > 0.001 {
                    NSColor.white.withAlphaComponent(alpha).setFill()
                    NSBezierPath(ovalIn: CGRect(x: x, y: y, width: step * 0.09, height: step * 0.09)).fill()
                }
                x += step
            }
            y += step
        }

        // Orbit rings.
        cyan.withAlphaComponent(0.12).setStroke()
        let inner = NSBezierPath(ovalIn: CGRect(
            x: centre.x - 346.0 / 1024 * size, y: centre.y - 346.0 / 1024 * size,
            width: 692.0 / 1024 * size, height: 692.0 / 1024 * size))
        inner.lineWidth = 3.0 / 1024 * size
        inner.stroke()

        cyan.withAlphaComponent(0.06).setStroke()
        let outer = NSBezierPath(ovalIn: CGRect(
            x: centre.x - 387.0 / 1024 * size, y: centre.y - 387.0 / 1024 * size,
            width: 774.0 / 1024 * size, height: 774.0 / 1024 * size))
        outer.lineWidth = 2.5 / 1024 * size
        outer.setLineDash([18.0 / 1024 * size, 26.0 / 1024 * size], count: 2, phase: 0)
        outer.stroke()
    }

    // --- spokes
    let spokes = NSBezierPath()
    for angle in angles {
        spokes.move(to: point(angle, radius: spokeInner * size, centre: centre))
        spokes.line(to: point(angle, radius: spokeOuter * size, centre: centre))
    }
    spokes.lineWidth = (simplified ? spokeWidth * 1.7 : spokeWidth) * size
    spokes.lineCapStyle = .round
    (simplified ? cyan : cyanDeep.blended(withFraction: 0.5, of: cyan) ?? cyan).setStroke()
    spokes.stroke()

    // --- nodes
    for (index, angle) in angles.enumerated() {
        let centrePoint = point(angle, radius: ringRadius * size, centre: centre)
        let radius = nodeRadius * size
        let colour = nodeColours[index]

        if !simplified {
            colour.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: centrePoint.x - radius * 1.7, y: centrePoint.y - radius * 1.7,
                                        width: radius * 3.4, height: radius * 3.4)).fill()
        }
        colour.setFill()
        NSBezierPath(ovalIn: CGRect(x: centrePoint.x - radius, y: centrePoint.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    // --- core
    let core = coreRadius * size
    if !simplified {
        cyan.withAlphaComponent(0.45).setFill()
        NSBezierPath(ovalIn: CGRect(x: centre.x - core * 1.9, y: centre.y - core * 1.9,
                                    width: core * 3.8, height: core * 3.8)).fill()

        let coreGradient = NSGradient(colorsAndLocations:
            (cyanPale, 0.0), (cyanLight, 0.55), (cyan, 1.0)
        )!
        coreGradient.draw(
            fromCenter: CGPoint(x: centre.x - core * 0.25, y: centre.y + core * 0.3), radius: 0,
            toCenter: centre, radius: core, options: []
        )

        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: CGRect(x: centre.x - core * 0.55, y: centre.y + core * 0.03,
                                    width: core * 0.5, height: core * 0.5)).fill()
    } else {
        cyanLight.setFill()
        NSBezierPath(ovalIn: CGRect(x: centre.x - core, y: centre.y - core,
                                    width: core * 2, height: core * 2)).fill()
    }

    context.restoreGState()

    // --- edge lighting
    if !simplified {
        NSColor.white.withAlphaComponent(0.07).setStroke()
        squircle.lineWidth = 2.0 / 1024 * size
        squircle.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <AppIcon.appiconset path>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// (point size, scale) pairs the macOS asset catalogue expects.
let entries: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2)
]

var images: [[String: String]] = []

for entry in entries {
    let pixels = entry.point * entry.scale
    let filename = "icon_\(entry.point)x\(entry.point)\(entry.scale == 2 ? "@2x" : "").png"
    let rep = drawIcon(size: CGFloat(pixels))

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(filename)\n".utf8))
        exit(1)
    }
    try data.write(to: output.appending(path: filename))
    print("  \(filename)  \(pixels)×\(pixels)")

    images.append([
        "idiom": "mac",
        "size": "\(entry.point)x\(entry.point)",
        "scale": "\(entry.scale)x",
        "filename": filename
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "vibe-stats", "version": 1]
]
let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]
)
try json.write(to: output.appending(path: "Contents.json"))

print("Wrote \(entries.count) images to \(output.path)")
