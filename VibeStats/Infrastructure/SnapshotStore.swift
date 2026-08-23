//  SnapshotStore.swift
//  The last snapshot, on disk, so the popover is never empty at launch.
//
//  Writes are atomic: a torn file after a crash would otherwise poison every
//  future launch. A snapshot that fails to decode is discarded, not fatal — the
//  app simply starts empty and checks.

import Foundation

actor SnapshotStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let root = directory ?? Self.defaultDirectory
        fileURL = root.appending(path: "snapshot.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// ~/Library/Application Support/VibeStats — inside the sandbox container.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "VibeStats")
    }

    func load() -> Snapshot? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(Snapshot.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil          // first launch
        } catch {
            Log.store.error("discarding unreadable snapshot: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    func save(_ snapshot: Snapshot) {
        do {
            let data = try encoder.encode(snapshot)
            let temporary = fileURL.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } catch {
            Log.store.error("failed to persist snapshot: \(error.localizedDescription)")
        }
    }
}
