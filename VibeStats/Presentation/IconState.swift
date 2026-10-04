//  IconState.swift
//  Everything the menu bar glyph needs to draw one frame. A value type so
//  frames can be cached by state, and so a steady app does zero drawing.

import Foundation

struct IconState: Hashable, Sendable {
    var indicator: StatusIndicator = .unknown
    /// Per-service state, used to colour the hub's nodes.
    var services: [ServiceID: StatusIndicator] = [:]
    /// The hub's nodes, in order: the enabled services. Separate from
    /// `services` because a node exists before its first check lands.
    var nodes: [ServiceID] = ServiceRegistry.ids
    var affectedCount: Int = 0
    var isOffline: Bool = false
    var isChecking: Bool = false

    var style: MenuBarIconStyle = .hub
    var renderMode: IconRenderMode = .monochromeWithPip
    var showBadge: Bool = true
    var motion: MotionLevel = .full

    /// Optional compact text beside the glyph.
    var titleText: String? = nil

    /// The badge mirrors the extension exactly: the affected count when
    /// non-zero, `!` for major/critical with no count, `?` for
    /// minor-with-none and for unknown, nothing when everything is healthy.
    var badgeText: String? {
        guard showBadge, !isOffline else { return nil }
        switch indicator {
        case .operational:              return nil
        case .major, .critical:         return affectedCount > 0 ? String(affectedCount) : "!"
        case .minor:                    return affectedCount > 0 ? String(affectedCount) : "?"
        case .unknown:                  return "?"
        }
    }

    /// The pip carries status in monochrome mode. It is suppressed when a badge
    /// is drawn — the badge already carries the colour, and saying it twice
    /// just crowds an 18-point canvas.
    var showsPip: Bool {
        guard renderMode == .monochromeWithPip else { return false }
        guard badgeText == nil else { return false }
        return isOffline || indicator != .operational
    }

    /// Unknown and offline are drawn as an ABSENCE — a hollow ring — not as
    /// another colour. A shape difference survives monochrome, a small canvas,
    /// and colourblindness; a colour difference survives none of them.
    var isHollow: Bool {
        isOffline || indicator == .unknown
    }

    var effectiveColor: StatusIndicator {
        isOffline ? .unknown : indicator
    }

    // MARK: - Animation

    enum Animation: Hashable, Sendable {
        case none
        /// M1 — the app's heartbeat: "still watching", 6 s cycle.
        case breath
        /// M2 — expanding rings, 1.4 s cycle.
        case criticalPulse
        /// M4 — one arc travelling the outer ring per check.
        case refreshSweep
    }

    var animation: Animation {
        guard motion != .off else { return .none }
        if isChecking { return .refreshSweep }
        if indicator == .critical && !isOffline { return .criticalPulse }
        if motion == .full && indicator == .operational && !isOffline { return .breath }
        return .none
    }

    var animationPeriod: Duration {
        switch animation {
        case .none:          return .seconds(0)
        case .breath:        return .seconds(6)
        case .criticalPulse: return motion == .subtle ? .milliseconds(2500) : .milliseconds(1400)
        case .refreshSweep:  return .milliseconds(900)
        }
    }
}

extension IconState {
    /// Per-service states for previews: the second node carries `indicator`,
    /// the rest are healthy, and `spreading` adds a major on the last node so
    /// an outage preview shows more than one node lit.
    static func sample(
        _ indicator: StatusIndicator, spreading: Bool = false
    ) -> [ServiceID: StatusIndicator] {
        let ids = ServiceRegistry.ids
        var services = Dictionary(uniqueKeysWithValues: ids.map { ($0, StatusIndicator.operational) })
        if ids.indices.contains(1) { services[ids[1]] = indicator }
        if spreading, let last = ids.last, ids.count > 2 { services[last] = .major }
        return services
    }
}
