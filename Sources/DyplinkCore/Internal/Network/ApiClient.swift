import Foundation

/// Minimal view of `DyplinkConfig` required by the network layer.
/// Kept deliberately narrow so the network stack can be instantiated
/// in isolation during tests.
internal protocol ApiClientConfig {
    var baseUrl: String { get }
    var apiKey: String { get }
    var logLevel: DyplinkLogLevel { get }
    var maxRetries: Int { get }
}

extension DyplinkConfig: ApiClientConfig {}

/// Singleton-style holder for the `URLSession` that all SDK network
/// calls share.
///
/// Mirrors the Android `ApiClient`: timeouts, a chain of request
/// adapters (interceptors), and a shared `RequestExecutor`.
///
/// Adapters are applied in order on every request:
///   1. `ApiKeyAdapter` — attaches the `X-API-Key` header
///   2. (retry is handled inside `RequestExecutor`, not as an adapter,
///       because `URLSession` has no equivalent of OkHttp's interceptor chain
///       for response-level retries)
internal final class ApiClient {
    let session: URLSession
    let adapters: [RequestAdapter]

    init(config: ApiClientConfig) {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = Self.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = Self.timeoutSeconds
        sessionConfig.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "User-Agent": Self.userAgent,
        ]
        self.session = URLSession(configuration: sessionConfig)
        self.adapters = [ApiKeyAdapter(apiKey: config.apiKey)]
    }

    static let timeoutSeconds: TimeInterval = 15

    private static var userAgent: String {
        let bundle = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return "DyplinkSDK/0.1.0 (\(bundle)/\(version); iOS)"
    }
}

/// A hook that can mutate a request before it is sent. URLSession
/// doesn't have a chain-of-responsibility interceptor API, so we
/// implement a tiny one ourselves.
internal protocol RequestAdapter {
    func adapt(_ request: inout URLRequest)
}

/// Attaches the configured `X-API-Key` header to every outgoing request.
internal struct ApiKeyAdapter: RequestAdapter {
    let apiKey: String
    func adapt(_ request: inout URLRequest) {
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
    }
}
