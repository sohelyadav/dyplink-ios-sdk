import Foundation

/// Intercepts requests made through `URLSession.shared` — the session
/// `PushEventReporter` and `DyplinkNotificationService` use — so a
/// fire-and-forget report or an image download can be observed without a
/// network. Sessions built from their own configuration, such as the core
/// SDK's `ApiClient`, are unaffected.
final class StubURLProtocol: URLProtocol {

    /// What an intercepted request is answered with, for the tests that
    /// care about the response rather than the request.
    enum StubResponse {
        case success(statusCode: Int, headerFields: [String: String], body: Data)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var observer: (@Sendable (URLRequest) -> Void)?
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> StubResponse?)?

    /// Begin intercepting. `observe` is called with every request, on the
    /// session's own thread.
    static func startIntercepting(_ observe: @escaping @Sendable (URLRequest) -> Void) {
        lock.lock()
        observer = observe
        lock.unlock()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    /// Answer intercepted requests with something other than the default
    /// empty JSON body. Returning `nil` for a request falls back to it.
    static func respond(_ responder: @escaping @Sendable (URLRequest) -> StubResponse?) {
        lock.lock()
        self.responder = responder
        lock.unlock()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    /// Safe to call when interception was never started.
    static func stopIntercepting() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        lock.lock()
        observer = nil
        responder = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let observe = Self.observer
        let responder = Self.responder
        Self.lock.unlock()
        observe?(request)

        switch responder?(request) {
        case .failure(let code)?:
            client?.urlProtocol(self, didFailWithError: URLError(code))

        case .success(let statusCode, let headerFields, let body)?:
            send(statusCode: statusCode, headerFields: headerFields, body: body)

        case nil:
            send(
                statusCode: 200,
                headerFields: ["Content-Type": "application/json"],
                body: Data("{}".utf8)
            )
        }
    }

    override func stopLoading() {}

    private func send(statusCode: Int, headerFields: [String: String], body: Data) {
        if let url = request.url,
           let response = HTTPURLResponse(
               url: url,
               statusCode: statusCode,
               httpVersion: "HTTP/1.1",
               headerFields: headerFields
           ) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

extension URLRequest {
    /// `URLSession` usually moves an outgoing body onto `httpBodyStream`
    /// before a `URLProtocol` ever sees the request, so both have to be read.
    var interceptedBody: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
