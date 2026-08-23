//  Motion.swift
//  One gate for every animation in the app.
//
//  A nil SwiftUI.Animation is a valid argument meaning "no animation", so
//  `withAnimation(Motion.animation(...))` honours the Off level by
//  construction rather than by every call site remembering to check.

import AppKit
import SwiftUI

enum Motion {
    /// The system's Reduce Motion setting always wins over the app's.
    static func effectiveLevel(_ preference: MotionLevel) -> MotionLevel {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .off : preference
    }

    enum Spec {
        case transition      // M3/M5 — a state actually changed
        case disclosure      // M7 — incidents panel
        case appear          // M6/M9 — rows and popover
    }

    static func animation(_ spec: Spec, level: MotionLevel) -> Animation? {
        switch effectiveLevel(level) {
        case .off:
            return nil
        case .subtle:
            switch spec {
            case .transition:  return .easeInOut(duration: 0.2)
            case .disclosure:  return .easeInOut(duration: 0.18)
            case .appear:      return .easeOut(duration: 0.15)
            }
        case .full:
            switch spec {
            case .transition:  return .spring(response: 0.35, dampingFraction: 0.7)
            case .disclosure:  return .spring(response: 0.32, dampingFraction: 0.82)
            case .appear:      return .easeOut(duration: 0.22)
            }
        }
    }
}
