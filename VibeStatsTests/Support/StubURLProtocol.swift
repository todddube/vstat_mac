import Foundation

/// A stubbed transport for exercising LiveStatusAPIClient's retry policy.
///
/// URLProtocol subclasses are instantiated by URLSession, so the script has to
/// live in static storage; an NSLock keeps it safe under concurrent loads.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Step: Sendable {
        let status: Int
        let body: Data

        static func failure(_ status: Int) -> Step { Step(status: status, body: Data("{}".utf8)) }
        static func success(_ json: String) -> Step { Step(status: 200, body: Data(json.utf8)) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var steps: [Step] = []
    nonisolated(unsafe) private static var requestCount = 0

    /// Queue the responses this transport will hand back, in order. The last
    /// step repeats if more requests arrive than steps were queued.
    static func script(_ steps: [Step]) {
        lock.withLock {
            self.steps = steps
            self.requestCount = 0
        }
    }

    static var callCount: Int { lock.withLock { requestCount } }

    private static func next() -> Step {
        lock.withLock {
            let step = steps[min(requestCount, steps.count - 1)]
            requestCount += 1
            return step
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let step = Self.next()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: step.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: step.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
