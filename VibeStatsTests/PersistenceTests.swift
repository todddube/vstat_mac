import Foundation
import Testing
@testable import VibeStats

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "VibeStatsTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleSnapshot(at date: Date, indicator: StatusIndicator = .operational) -> Snapshot {
    let services = ServiceRegistry.all.map { definition in
        ServiceSnapshot(
            id: definition.id,
            name: definition.name,
            indicator: indicator,
            pageIndicator: indicator,
            componentsResolved: definition.components.count,
            componentsWatched: definition.components.count,
            unresolvedCount: 0,
            components: [],
            incidents: [],
            affectedComponents: [],
            error: nil,
            checkedAt: date
        )
    }
    return Snapshot(services: services, combined: .combine(services), updatedAt: date)
}

@Suite("SnapshotStore")
struct SnapshotStoreTests {

    @Test("A saved snapshot survives a round trip")
    func roundTrip() async {
        let store = SnapshotStore(directory: temporaryDirectory())
        let snapshot = sampleSnapshot(at: Date(timeIntervalSince1970: 1_787_000_000))

        await store.save(snapshot)
        #expect(await store.load() == snapshot)
    }

    @Test("A missing file is first launch, not an error")
    func missingFile() async {
        #expect(await SnapshotStore(directory: temporaryDirectory()).load() == nil)
    }

    @Test("A corrupt snapshot is discarded rather than poisoning every launch")
    func corruptFile() async throws {
        let directory = temporaryDirectory()
        try Data("{ not a snapshot".utf8).write(to: directory.appending(path: "snapshot.json"))

        let store = SnapshotStore(directory: directory)
        #expect(await store.load() == nil)
        // …and the bad file is gone, so the next launch is clean.
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "snapshot.json").path))
    }

    @Test("Saving twice replaces rather than appends")
    func overwrite() async {
        let store = SnapshotStore(directory: temporaryDirectory())
        await store.save(sampleSnapshot(at: Date(timeIntervalSince1970: 1)))
        let second = sampleSnapshot(at: Date(timeIntervalSince1970: 2))
        await store.save(second)

        #expect(await store.load()?.updatedAt == second.updatedAt)
    }
}

@Suite("HistoryLog")
struct HistoryLogTests {

    @Test("One sample is recorded per service per check")
    func recordsPerService() async {
        let log = HistoryLog(directory: temporaryDirectory())
        await log.record(sampleSnapshot(at: .now))

        let samples = await log.samples()
        #expect(samples.count == ServiceID.allCases.count)
        #expect(Set(samples.map(\.service)) == Set(ServiceID.allCases))
    }

    @Test("Appending accumulates instead of replacing")
    func appends() async {
        let log = HistoryLog(directory: temporaryDirectory())
        await log.record(sampleSnapshot(at: .now.addingTimeInterval(-60)))
        await log.record(sampleSnapshot(at: .now))

        #expect(await log.samples().count == ServiceID.allCases.count * 2)
    }

    @Test("Samples can be filtered by service")
    func filterByService() async {
        let log = HistoryLog(directory: temporaryDirectory())
        await log.record(sampleSnapshot(at: .now))

        let claude = await log.samples(for: .claude)
        #expect(claude.count == 1)
        #expect(claude.first?.service == .claude)
    }

    @Test("Pruning drops everything outside the retention window")
    func pruning() async {
        let log = HistoryLog(directory: temporaryDirectory())
        let now = Date(timeIntervalSince1970: 1_787_000_000)

        await log.record(sampleSnapshot(at: now.addingTimeInterval(-9 * 86_400)))
        await log.record(sampleSnapshot(at: now.addingTimeInterval(-1 * 86_400)))
        await log.prune(now: now)

        let remaining = await log.samples(since: .distantPast)
        #expect(remaining.count == ServiceID.allCases.count)
        for sample in remaining {
            #expect(sample.t >= now.addingTimeInterval(-Double(HistoryLog.retentionDays) * 86_400))
        }
    }

    @Test("Reading an absent log is empty, not a crash")
    func absentLog() async {
        #expect(await HistoryLog(directory: temporaryDirectory()).samples().isEmpty)
    }
}
