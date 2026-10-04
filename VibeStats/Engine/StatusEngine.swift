//  StatusEngine.swift
//  ≙ VStateMonitor, minus everything platform-shaped: no timer, no badge, no
//  storage. Give it a client, get a Snapshot. Fully deterministic under test.

import Foundation

actor StatusEngine {
    private let client: any StatusAPIClient
    private let statuspage: StatuspageAdapter
    private let google: GoogleCloudAdapter
    private let rss: RSSFeedAdapter

    init(client: any StatusAPIClient) {
        self.client = client
        self.statuspage = StatuspageAdapter(client: client)
        self.google = GoogleCloudAdapter(client: client)
        self.rss = RSSFeedAdapter(client: client)
    }

    /// Check every enabled service concurrently and roll the results up.
    ///
    /// The TaskGroup is the Promise.allSettled equivalent: a child that throws
    /// degrades *that* service to `unknown` and touches nothing else. Unlike
    /// the extension, retry lives in the client, so a transient failure has
    /// already been retried by the time it lands here.
    func check(
        services: [ServiceDefinition] = ServiceRegistry.all,
        now: Date = .now
    ) async -> Snapshot {
        var byID: [ServiceID: ServiceSnapshot] = [:]

        await withTaskGroup(of: (ServiceID, ServiceSnapshot).self) { group in
            for definition in services {
                group.addTask {
                    (definition.id, await self.check(definition, now: now))
                }
            }
            for await (id, snapshot) in group {
                byID[id] = snapshot
            }
        }

        // Emit in registry order so the UI never has to sort.
        let ordered = services.compactMap { byID[$0.id] }

        return Snapshot(
            services: ordered,
            combined: .combine(ordered),
            updatedAt: now
        )
    }

    /// Dispatch one service to its adapter. ≙ checkService().
    func check(_ definition: ServiceDefinition, now: Date = .now) async -> ServiceSnapshot {
        do {
            switch definition.api {
            case .statuspage(let base):
                return await statuspage.check(definition, base: base, now: now)
            case .googleCloud(let incidents, let keywords):
                return try await google.check(definition, incidentsURL: incidents, keywords: keywords, now: now)
            case .rssFeed(let feed):
                return try await rss.check(definition, feedURL: feed, now: now)
            }
        } catch let error as APIError {
            Log.engine.error("\(definition.id.rawValue) failed: \(error.summary)")
            return .unknown(definition, error: error.summary, at: now)
        } catch {
            Log.engine.error("\(definition.id.rawValue) failed: \(error.localizedDescription)")
            return .unknown(definition, error: error.localizedDescription, at: now)
        }
    }
}
