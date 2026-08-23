//  HistoryLog.swift
//  A rolling week of per-service samples, appended one line at a time.
//
//  This is what answers "was Claude Code down at 2pm, or was it me?" — a
//  question the extension cannot answer at all, because it keeps nothing beyond
//  the last snapshot.

import Foundation

struct HistorySample: Codable, Sendable, Hashable {
    let t: Date
    let service: ServiceID
    let indicator: StatusIndicator
}

actor HistoryLog {
    static let retentionDays = 7

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let root = directory ?? SnapshotStore.defaultDirectory
        fileURL = root.appending(path: "history.jsonl")

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// One line per service per check. At six lines every five minutes that is
    /// a few hundred KB a week, pruned on launch and daily.
    func record(_ snapshot: Snapshot) {
        let lines = snapshot.services.compactMap { service -> String? in
            let sample = HistorySample(t: snapshot.updatedAt, service: service.id, indicator: service.indicator)
            guard let data = try? encoder.encode(sample) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        guard !lines.isEmpty else { return }
        append(lines.joined(separator: "\n") + "\n")
    }

    func samples(for service: ServiceID? = nil, since: Date? = nil) -> [HistorySample] {
        let cutoff = since ?? Date.now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)

        return readAll().filter { sample in
            sample.t >= cutoff && (service == nil || sample.service == service)
        }
    }

    /// Drop everything outside the retention window by rewriting the file.
    func prune(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let kept = readAll().filter { $0.t >= cutoff }

        let body = kept.compactMap { sample -> String? in
            guard let data = try? encoder.encode(sample) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n")

        try? (body.isEmpty ? "" : body + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: -

    private func readAll() -> [HistorySample] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(HistorySample.self, from: Data(line.utf8))
        }
    }

    private func append(_ text: String) {
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
