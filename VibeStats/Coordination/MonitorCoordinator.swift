//  MonitorCoordinator.swift
//  What background.js would have been if MV3 had let it hold state.
//
//  Owns the schedule, the offline state machine, and the current snapshot.
//  It never parses a payload itself — that is StatusEngine's job — and it never
//  draws anything.

import AppKit
import Observation

@MainActor @Observable
final class MonitorCoordinator {
    enum Phase: Equatable, Sendable {
        case idle
        case checking
        case offline
        case failed(String)
    }

    enum RefreshReason: String, Sendable {
        case launch, scheduled, manual, wake, networkRestored, popoverOpened, settingsChanged
    }

    private(set) var snapshot: Snapshot?
    private(set) var phase: Phase = .idle
    /// True until the first check completes, so the UI can distinguish
    /// "nothing yet" from "nothing wrong".
    private(set) var hasCompletedFirstCheck = false

    /// Data older than this is refreshed when the popover opens.
    static let staleAfter: TimeInterval = 30

    private let engine: StatusEngine
    private let store: SnapshotStore
    private let history: HistoryLog
    private let preferences: Preferences

    private let wakeObserver = WakeObserver()
    private let networkObserver = NetworkObserver()

    private var pollTask: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?

    /// Called after every successful check with (previous, current) so Phase 6
    /// can diff for notifications without the coordinator knowing about them.
    var onSnapshotChange: (@MainActor (Snapshot?, Snapshot) -> Void)?

    init(
        engine: StatusEngine = StatusEngine(client: LiveStatusAPIClient()),
        store: SnapshotStore = SnapshotStore(),
        history: HistoryLog = HistoryLog(),
        preferences: Preferences = .shared
    ) {
        self.engine = engine
        self.store = store
        self.history = history
        self.preferences = preferences
    }

    // MARK: - Lifecycle

    func start() {
        // `[self]` is explicit: the coordinator is owned by the AppDelegate for
        // the whole process lifetime, and stop() cancels every task it owns.
        Task { [self] in
            // Show the last known state immediately; a stale reading with a
            // timestamp beats an empty window.
            snapshot = await store.load()
            await history.pruneIfNeeded()

            wakeObserver.start { [weak self] reason in
                guard let self, self.preferences.checkOnWake else { return }
                Log.app.info("woke (\(reason == .systemWake ? "system" : "screens")) — rechecking")
                self.restartPolling(refreshing: .wake)
            }

            networkObserver.start { [weak self] online in
                guard let self else { return }
                if online {
                    self.phase = .idle
                    self.restartPolling(refreshing: .networkRestored)
                } else {
                    // Offline is its own presentation, not a cascade of
                    // unknowns, and it must not burn retries (specs FR-7).
                    self.phase = .offline
                    self.pollTask?.cancel()
                }
            }

            restartPolling(refreshing: .launch)
        }
    }

    func stop() {
        pollTask?.cancel()
        inFlight?.cancel()
        wakeObserver.stop()
        networkObserver.stop()
    }

    /// Re-arm the schedule from now, optionally checking immediately.
    func restartPolling(refreshing reason: RefreshReason?) {
        pollTask?.cancel()

        pollTask = Task { [weak self] in
            guard let self else { return }

            if let reason {
                await self.refresh(reason: reason)
            }

            while !Task.isCancelled {
                let interval = self.preferences.refreshInterval
                do {
                    // Tolerance lets the system coalesce our wake-ups with
                    // others — the difference between a timer and a battery
                    // complaint.
                    try await Task.sleep(for: interval.duration, tolerance: interval.tolerance)
                } catch {
                    return          // cancelled
                }
                await self.refresh(reason: .scheduled)
            }
        }
    }

    // MARK: - Checking

    /// Whether a refresh for this reason should be attempted at all.
    ///
    /// Extracted as a pure rule so the offline policy is testable without
    /// having to convince NWPathMonitor that the network is down.
    ///
    /// A manual refresh is ALWAYS attempted: the user pressing Refresh and
    /// getting nothing — no attempt, no error — is worse than one wasted
    /// request, and NWPathMonitor can lag a network that is already back.
    static func allows(_ reason: RefreshReason, in phase: Phase) -> Bool {
        guard phase == .offline else { return true }
        return reason == .networkRestored || reason == .manual
    }

    func refresh(reason: RefreshReason) async {
        guard Self.allows(reason, in: phase) else {
            Log.app.debug("skipping \(reason.rawValue) refresh while offline")
            return
        }
        // Never run two checks at once; join the one already running instead.
        if let inFlight {
            await inFlight.value
            return
        }

        let task = Task { @MainActor in
            phase = .checking
            let previous = snapshot
            let fresh = await engine.check(services: preferences.enabledServices)

            snapshot = fresh
            hasCompletedFirstCheck = true
            phase = fresh.combined.indicator == .unknown
                ? .failed(String(localized: "Unable to check status"))
                : .idle

            await store.save(fresh)
            await history.record(fresh)
            // Launch AND daily. pruneIfNeeded is a no-op inside its interval,
            // so calling it after every check costs nothing and means a machine
            // left running for a week — exactly the machine whose log grows —
            // still prunes.
            await history.pruneIfNeeded()

            onSnapshotChange?(previous, fresh)
            Log.app.info("check (\(reason.rawValue)): \(fresh.combined.description)")
        }

        inFlight = task
        await task.value
        inFlight = nil
    }

    /// ≙ the popup's visibility stale-check.
    func refreshIfStale(reason: RefreshReason = .popoverOpened) async {
        guard let updatedAt = snapshot?.updatedAt else {
            await refresh(reason: reason)
            return
        }
        if Date.now.timeIntervalSince(updatedAt) > Self.staleAfter {
            await refresh(reason: reason)
        }
    }

    /// Called when the refresh interval or the enabled-service set changes.
    func settingsChanged() {
        restartPolling(refreshing: .settingsChanged)
    }

    /// A week of samples per service, for the card sparklines.
    func recentHistory() async -> [ServiceID: [HistorySample]] {
        let samples = await history.samples()
        return Dictionary(grouping: samples, by: \.service)
    }

    // MARK: - Derived state

    var combined: CombinedStatus {
        snapshot?.combined ?? .empty
    }

    var isOffline: Bool { phase == .offline }

    var isChecking: Bool { phase == .checking }
}
