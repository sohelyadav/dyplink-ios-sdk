import Foundation

/// Intercepts requests made through `URLSession.shared` — the session
/// `PushEventReporter` uses — so a fire-and-forget report can be observed
/// without a network. Sessions built from their own configuration, such as
/// the core SDK's `ApiClient`, are unaffected.
final class StubURLProtocol: URLProtocol {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var observer: (@Sendable (URLRequest) -> Void)?

    /// Begin intercepting. `observe` is called with every request, on the
    /// session's own thread.
    static func startIntercepting(_ observe: @escaping @Sendable (URLRequest) -> Void) {
        lock.lock()
        observer = observe
        lock.unlock()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    /// Safe to call when interception was never started.
    static func stopIntercepting() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        lock.lock()
        observer = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let observe = Self.observer
        Self.lock.unlock()
        observe?(request)

        if let url = request.url,
           let response = HTTPURLResponse(
               url: url,
               statusCode: 200,
               httpVersion: "HTTP/1.1",
               headerFields: ["Content-Type": "application/json"]
           ) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
