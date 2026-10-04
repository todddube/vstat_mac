//  IconDemo.swift
//  "Test in menu bar": plays every status through the REAL status item for ten
//  seconds, in whatever style, colour and motion are selected, then hands the
//  glyph back to live data.
//
//  The settings previews draw each state too, but a preview in a window is not
//  the menu bar: it has no menu bar tint, no neighbouring icons and no
//  animation. This is the only way to judge a style where it will actually
//  live without waiting for an outage.
//
//  The demo only overrides what the glyph DRAWS. The coordinator, the
//  snapshot and notifications are untouched, so a real check landing mid-demo
//  is simply shown once the demo ends.

import Foundation
import Observation

@MainActor @Observable
final class IconDemo {
    static let shared = IconDemo()
    static let duration: Duration = .seconds(10)

    struct Step: Equatable, Sendable {
        let title: String
        let indicator: StatusIndicator
        let services: [ServiceID: StatusIndicator]
        let affectedCount: Int
        var isOffline = false
        var isChecking = false
    }

    private(set) var current: Step?
    var isRunning: Bool { current != nil }

    /// Called on every step change, including the final hand-back to live.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts from the top; pressing Test again mid-run restarts rather than
    /// stacking a second timeline on the first.
    func start() {
        task?.cancel()
        let steps = Self.steps(for: ServiceRegistry.ids)
        let each = Self.duration / steps.count
        task = Task {
            for step in steps {
                guard !Task.isCancelled else { return }
                set(step)
                try? await Task.sleep(for: each)
            }
            guard !Task.isCancelled else { return }
            set(nil)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        set(nil)
    }

    private func set(_ step: Step?) {
        current = step
        onChange?()
    }

    /// Calm → checking → worsening → the two states that are not on the
    /// severity scale. Ordered so each step is visibly different from the last.
    static func steps(for ids: [ServiceID]) -> [Step] {
        func states(_ assign: (Int) -> StatusIndicator) -> [ServiceID: StatusIndicator] {
            Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, assign($0)) })
        }
        return [
            Step(title: String(localized: "Operational"), indicator: .operational,
                 services: states { _ in .operational }, affectedCount: 0),
            Step(title: String(localized: "Checking"), indicator: .operational,
                 services: states { _ in .operational }, affectedCount: 0, isChecking: true),
            Step(title: String(localized: "Minor issue"), indicator: .minor,
                 services: states { $0 == 1 ? .minor : .operational }, affectedCount: 1),
            Step(title: String(localized: "Major outage"), indicator: .major,
                 services: states { $0 == 0 ? .major : ($0 == 2 ? .minor : .operational) },
                 affectedCount: 3),
            Step(title: String(localized: "Critical outage"), indicator: .critical,
                 services: states { $0 == 0 ? .critical : ($0 == 1 ? .major : .minor) },
                 affectedCount: 5),
            Step(title: String(localized: "Unknown — can't reach status pages"), indicator: .unknown,
                 services: states { _ in .unknown }, affectedCount: 0),
            Step(title: String(localized: "Offline"), indicator: .unknown,
                 services: states { _ in .unknown }, affectedCount: 0, isOffline: true)
        ]
    }
}
