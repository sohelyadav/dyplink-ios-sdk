import Foundation

/// Thin async wrapper around `URLSession` for executing JSON HTTP
/// requests against the Dyplink API.
///
/// Mirrors the Android `RequestExecutor` interface: `post`, `get`,
/// `delete`, with optional query params and an exponential-backoff
/// retry policy applied to 5xx responses and transport failures.
internal final class RequestExecutor {
    let apiClient: ApiClient
    let baseUrl: String
    let maxRetries: Int

    init(apiClient: ApiClient, baseUrl: String, maxRetries: Int) {
        self.apiClient = apiClient
        self.baseUrl = baseUrl
        self.maxRetries = maxRetries
    }

    /// POST `jsonBody` to `baseUrl + endpoint`.
    @discardableResult
    func post(_ endpoint: String, jsonBody: Data) async throws -> HTTPResponse {
        var request = URLRequest(url: try buildURL(endpoint))
        request.httpMethod = "POST"
        request.httpBody = jsonBody
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await execute(&request)
    }

    /// GET `baseUrl + endpoint` with optional query parameters.
    @discardableResult
    func get(_ endpoint: String, queryParams: [String: String]? = nil) async throws -> HTTPResponse {
        var request = URLRequest(url: try buildURL(endpoint, query: queryParams))
        request.httpMethod = "GET"
        return try await execute(&request)
    }

    /// DELETE `baseUrl + endpoint` with optional query parameters.
    @discardableResult
    func delete(_ endpoint: String, queryParams: [String: String]? = nil) async throws -> HTTPResponse {
        var request = URLRequest(url: try buildURL(endpoint, query: queryParams))
        request.httpMethod = "DELETE"
        return try await execute(&request)
    }

    // ── Internal execution with retry ──────────────────────────────────

    private func execute(_ request: inout URLRequest) async throws -> HTTPResponse {
        // Apply request adapters.
        for adapter in apiClient.adapters {
            adapter.adapt(&request)
        }

        var attempt = 0
        var lastTransportError: Error?

        while true {
            do {
                let (data, urlResponse) = try await apiClient.session.data(for: request)
                guard let http = urlResponse as? HTTPURLResponse else {
                    throw DyplinkError.networkError(
                        message: "Non-HTTP response from \(request.url?.absoluteString ?? "unknown")"
                    )
                }
                let code = http.statusCode

                // Success or permanent client error → return immediately.
                if (200...299).contains(code) || (400...499).contains(code) {
                    return HTTPResponse(statusCode: code, data: data, headers: http.allHeaderFields)
                }

                // Server error (5xx) → retry if budget remains.
                if attempt >= maxRetries {
                    return HTTPResponse(statusCode: code, data: data, headers: http.allHeaderFields)
                }

                let backoff = backoffNanos(attempt: attempt)
                DyplinkLogger.w(
                    "RequestExecutor: HTTP \(code) on \(request.url?.absoluteString ?? "?"). "
                    + "Retrying in \(backoff / 1_000_000)ms (attempt \(attempt + 1)/\(maxRetries))"
                )
                try? await Task.sleep(nanoseconds: backoff)
                attempt += 1
            } catch {
                lastTransportError = error
                if attempt >= maxRetries {
                    throw DyplinkError.networkError(
                        message: "Network request failed after \(attempt + 1) attempts: \(error.localizedDescription)",
                        underlying: error
                    )
                }
                let backoff = backoffNanos(attempt: attempt)
                DyplinkLogger.w(
                    "RequestExecutor: transport error on \(request.url?.absoluteString ?? "?"): "
                    + "\(error.localizedDescription). Retrying in \(backoff / 1_000_000)ms "
                    + "(attempt \(attempt + 1)/\(maxRetries))"
                )
                try? await Task.sleep(nanoseconds: backoff)
                attempt += 1
            }
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private func buildURL(_ endpoint: String, query: [String: String]? = nil) throws -> URL {
        let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let path = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        guard var components = URLComponents(string: base + path) else {
            throw DyplinkError.invalidConfig("Invalid URL: \(base + path)")
        }
        if let query = query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw DyplinkError.invalidConfig("Failed to build URL for \(endpoint)")
        }
        return url
    }

    /// 2^attempt × 1 second, capped at 30 seconds. Returned in
    /// nanoseconds to match `Task.sleep(nanoseconds:)`.
    private func backoffNanos(attempt: Int) -> UInt64 {
        let raw = min(UInt64(pow(2.0, Double(attempt))) * 1_000, 30_000) // milliseconds
        return raw * 1_000_000
    }
}

/// Thin wrapper around a completed HTTP response. Matches the bits of
/// `okhttp3.Response` the Android SDK actually uses.
internal struct HTTPResponse {
    let statusCode: Int
    let data: Data
    let headers: [AnyHashable: Any]

    var isSuccessful: Bool { (200...299).contains(statusCode) }
    var bodyString: String? { String(data: data, encoding: .utf8) }
}
