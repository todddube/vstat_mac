//  StatusAPIClient.swift
//  The only thing in the app that touches the network.
//
//  Retry lives HERE, at the request level — not wrapped around the whole sweep.
//  The extension wrapped its retry around a Promise.allSettled, which never
//  rejects, so the retry could only ever fire on a storage failure and a
//  transient DNS blip cost a full 5-minute interval (docs/REVIEW.md §3.2).

import Foundation

protocol StatusAPIClient: Sendable {
    func get<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T
}

enum APIError: Error, Sendable, Equatable {
    case http(status: Int)
    case timeout
    case offline
    case decoding(String)
    case transport(String)
    case cancelled

    var isTransient: Bool {
        switch self {
        case .timeout, .transport:      return true
        case .http(let status):         return status >= 500
        case .offline, .decoding, .cancelled: return false
        }
    }

    var summary: String {
        switch self {
        case .http(let status):    return "HTTP \(status)"
        case .timeout:             return "timed out"
        case .offline:             return "offline"
        case .decoding(let detail): return "unexpected response format: \(detail)"
        case .transport(let detail): return detail
        case .cancelled:           return "cancelled"
        }
    }
}

struct LiveStatusAPIClient: StatusAPIClient {
    /// How many *extra* attempts a transient failure earns.
    let maxRetries: Int
    private let session: URLSession
    private let decoder = JSONDecoder.vendor()

    /// `protocolClasses` is a testability seam: it lets the retry policy be
    /// exercised against a stubbed transport instead of the real network.
    init(maxRetries: Int = 2, timeout: TimeInterval = 10, protocolClasses: [AnyClass]? = nil) {
        self.maxRetries = maxRetries

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 3
        // ≙ the extension's `cache: 'no-cache'`.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        // Fail fast; the coordinator owns the offline state machine.
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": Self.userAgent
        ]
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        session = URLSession(configuration: configuration)
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "VibeStats/\(version ?? "dev") (macOS; +https://github.com/todddube/vstat)"
    }()

    func get<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await fetch(type, from: url)
            } catch let error as APIError where error.isTransient && attempt < maxRetries {
                attempt += 1
                // Linear backoff with jitter — enough to clear a blip, bounded
                // well inside the shortest refresh interval.
                let delay = Duration.milliseconds(400 * attempt + Int.random(in: 0...200))
                Log.network.debug("retry \(attempt) for \(url.lastPathComponent): \(error.summary)")
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func fetch<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error).prefix(160).description)
        }
    }

    private static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .cancelled:
            return .cancelled
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .resourceUnavailable:
            return .transport(error.localizedDescription)
        default:
            return .transport(error.localizedDescription)
        }
    }
}
