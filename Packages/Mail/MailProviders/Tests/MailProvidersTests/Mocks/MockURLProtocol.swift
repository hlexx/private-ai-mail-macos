import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [(URLRequest) -> (Data, HTTPURLResponse)?] = []
    nonisolated(unsafe) static var requestLog: [URLRequest] = []
    private static let logLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.logLock.lock()
        Self.requestLog.append(request)
        Self.logLock.unlock()
        for handler in Self.handlers {
            if let (data, response) = handler(request) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        handlers = []
        logLock.lock()
        requestLog = []
        logLock.unlock()
    }

    static func stub(
        path: String,
        statusCode: Int = 200,
        json: String,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) {
        handlers.append { request in
            guard let url = request.url, url.path.contains(path) else { return nil }
            let data = json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers
            )!
            return (data, response)
        }
    }

    static func stubSequence(
        path: String,
        responses: [(statusCode: Int, json: String, headers: [String: String])]
    ) {
        var index = 0
        let lock = NSLock()
        handlers.append { request in
            guard let url = request.url, url.path.contains(path) else { return nil }
            lock.lock()
            let i = index
            index += 1
            lock.unlock()
            guard i < responses.count else { return nil }
            let r = responses[i]
            let data = r.json.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: r.statusCode, httpVersion: nil, headerFields: r.headers
            )!
            return (data, response)
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }
}
