//  PopoverSession.swift
//  The lifetime of one popover appearance: how long it has left, whether the
//  user has pinned it, and the outgoing animation.
//
//  Auto-dismiss is only tolerable if it is VISIBLE and INTERRUPTIBLE. A panel
//  that vanishes mid-sentence with no warning is a bug the user cannot report.
//  So: a hairline that visibly depletes, a pause the moment the pointer enters,
//  and a pin button to stop it entirely.

import Observation
import SwiftUI

@MainActor @Observable
final class PopoverSession {
    /// Seconds left before auto-dismiss. `nil` means no auto-dismiss at all.
    private(set) var remaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    private(set) var isPaused = false
    /// True while the exit animation plays, so the view can shrink and fade.
    private(set) var isDismissing = false

    /// Set by the pin button. Survives for the session, not the preference.
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            if isPinned {
                // Clear `remaining`, not just the ticker: leaving it set would
                // freeze the depleting rail on screen at whatever fraction it
                // had reached, which reads as a stuck progress bar.
                stop()
                remaining = nil
            } else {
                restart()
            }
        }
    }

    /// Seconds, or nil for "no auto-close". Taking an interval rather than the
    /// preference enum keeps this testable at 0.2 s instead of 15.
    private var configuredInterval: TimeInterval?
    private var ticker: Task<Void, Never>?
    private var onExpiry: (@MainActor () -> Void)?

    private static let tick: Duration = .milliseconds(50)

    /// The last stretch turns amber — the warning is what makes the dismissal
    /// feel intentional rather than sudden.
    static let warningThreshold: TimeInterval = 4

    var progress: Double {
        guard let remaining, total > 0 else { return 1 }
        return max(0, min(1, remaining / total))
    }

    var isWarning: Bool {
        guard let remaining, !isPaused else { return false }
        return remaining <= Self.warningThreshold
    }

    var isCountingDown: Bool { remaining != nil && !isPaused && !isPinned }

    // MARK: - Lifecycle

    func begin(_ autoClose: PopoverAutoClose, onExpiry: @escaping @MainActor () -> Void) {
        begin(interval: autoClose.isEnabled ? autoClose.interval : nil, onExpiry: onExpiry)
    }

    func begin(interval: TimeInterval?, onExpiry: @escaping @MainActor () -> Void) {
        configuredInterval = interval
        self.onExpiry = onExpiry
        isPinned = false
        isDismissing = false
        restart()
    }

    func restart() {
        stop()
        guard let interval = configuredInterval, interval > 0, !isPinned else {
            remaining = nil
            return
        }
        total = interval
        remaining = interval
        isPaused = false

        // Driven by a deadline, not by subtracting a fixed amount per tick.
        // Task.sleep only guarantees a MINIMUM duration, so decrementing by
        // 0.05 every "50 ms" makes the countdown run slow under load — the
        // popover would then outstay the interval the user configured.
        let deadline = ContinuousClock.now.advanced(by: .seconds(interval))

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard let self, !Task.isCancelled else { return }
                guard !self.isPaused else { continue }

                let left = Self.seconds(from: ContinuousClock.now, to: deadline)
                if left <= 0 {
                    self.remaining = 0
                    self.expire()
                    return
                }
                self.remaining = left
            }
        }
    }

    private static func seconds(from now: ContinuousClock.Instant, to deadline: ContinuousClock.Instant) -> TimeInterval {
        let duration = now.duration(to: deadline)
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) * 1e-18
    }

    /// The pointer entering is the clearest possible signal that the user is
    /// still reading. Pause rather than close.
    func pause() {
        isPaused = true
    }

    /// Leaving restarts from full rather than resuming: after reading a card,
    /// two seconds of grace would feel like a snatch.
    func resume() {
        guard !isPinned else { return }
        restart()
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    func end() {
        stop()
        remaining = nil
        isDismissing = false
    }

    private func expire() {
        stop()
        isDismissing = true
        onExpiry?()
    }
}
