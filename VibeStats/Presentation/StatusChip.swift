//  StatusChip.swift
//  Status is never carried by colour alone: every chip pairs a coloured dot
//  with its label, and unknown gets a hollow dot so the state survives
//  monochrome and colour-blindness both.

import SwiftUI

struct StatusDot: View {
    let indicator: StatusIndicator
    var size: CGFloat = 8

    var body: some View {
        Group {
            if indicator == .unknown {
                Circle()
                    .strokeBorder(Color.status(indicator), lineWidth: max(1, size * 0.28))
            } else {
                Circle().fill(Color.status(indicator))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusChip: View {
    let indicator: StatusIndicator
    var label: String?

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(indicator: indicator, size: 7)
            Text(label ?? indicator.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.status(indicator))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.status(indicator).opacity(0.16))
        )
        .overlay(
            Capsule().strokeBorder(Color.status(indicator).opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? indicator.title)
    }
}

/// Shown only when the vendor's own page-level verdict disagrees with our
/// component roll-up. That disagreement is the entire reason this app exists,
/// so it gets a visible chip rather than the extension's tooltip.
struct DivergenceChip: View {
    let pageIndicator: StatusIndicator
    let ourIndicator: StatusIndicator

    private var isPageWorse: Bool {
        (pageIndicator.severity ?? -1) > (ourIndicator.severity ?? -1)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isPageWorse ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 7, weight: .bold))
            // The compact vocabulary (OK / PARTIAL / OUTAGE) keeps this inside
            // a 195 pt card next to a full-width status chip. The long form is
            // in the tooltip.
            Text("page: \(pageIndicator.compactTitle)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(.quaternary.opacity(0.5)))
        .help(String(localized: """
            Watched components: \(ourIndicator.title)
            Whole status page: \(pageIndicator.title)
            """))
    }
}
