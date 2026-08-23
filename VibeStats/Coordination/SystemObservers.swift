//  SystemObservers.swift
//  Sleep/wake and network reachability.
//
//  This is the extension's most user-visible gap: a laptop reopened after four
//  hours shows four-hour-old data behind a cheerful green badge, because an
//  MV3 alarm cannot notice that it slept.

import AppKit
import Network

@MainActor
final class WakeObserver {
    private var tokens: [any NSObjectProtocol] = []

    /// Fires on system wake and on displays waking.
    func start(onWake: @escaping @MainActor (WakeReason) -> Void) {
        let center = NSWorkspace.shared.notificationCenter

        tokens.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWake(.systemWake) }
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWake(.screensWake) }
        })
    }

    /// Explicit rather than a deinit: the tokens are main-actor state, and a
    /// nonisolated deinit cannot touch them.
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    enum WakeReason: Sendable {
        case systemWake
        case screensWake
    }
}

@MainActor
final class NetworkObserver {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.todddube.VibeStats.network")
    private(set) var isOnline = true

    /// Called on every *transition*, not on every path update — the monitor is
    /// chatty and we only care about crossing the line.
    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                Log.network.info("network is now \(online ? "online" : "offline")")
                onChange(online)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
