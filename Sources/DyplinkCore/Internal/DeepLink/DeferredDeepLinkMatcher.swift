import Foundation

/// Performs a server-side deferred deep link match.
///
/// Mirrors the Android `DeferredDeepLinkMatcher`. iOS has no equivalent of
/// Google Play's Install Referrer API, so there is nothing that *always*
/// supplies a `cookieRef` here — but when something has supplied one
/// (`DyplinkPreferences.pendingCookieRef`) it is sent, because the server
/// tries it first and it names the link outright. Without one the match
/// rests on the fingerprint the server correlates against recent clicks:
/// `os`, `osVersion`, `model` and screen size, plus the request's own IP.
///
/// The IP is deliberately not in the body. The server reads it off the
/// request, so a client that sent its own would be claiming an address it
/// was never at — which is attribution theft, not a fingerprint.
internal final class DeferredDeepLinkMatcher {
    private let requestExecutor: RequestExecutor
    private let deviceInfoCollector: DeviceInfoCollector
    private let preferences: DyplinkPreferences

    init(
        requestExecutor: RequestExecutor,
        deviceInfoCollector: DeviceInfoCollector,
        preferences: DyplinkPreferences
    ) {
        self.requestExecutor = requestExecutor
        self.deviceInfoCollector = deviceInfoCollector
        self.preferences = preferences
    }

    /// Attempt a deferred match. Returns the cached result if a match
    /// has already been attempted (successful or not).
    func match() async -> DeferredMatchResult {
        if preferences.deferredMatchAttempted {
            return parseCachedResult()
        }

        do {
            return try await performMatch()
        } catch {
            DyplinkLogger.e("DeferredDeepLinkMatcher: match failed", error)
            preferences.deferredMatchAttempted = true
            return .unmatched
        }
    }

    // ── Private implementation ─────────────────────────────────────────

    private func performMatch() async throws -> DeferredMatchResult {
        let body = Self.requestBody(
            deviceInfo: deviceInfoCollector.collect(),
            cookieRef: preferences.pendingCookieRef
        )
        let data = try JSONUtils.encode(body)
        let response = try await requestExecutor.post("/api/deferred/match", jsonBody: data)

        let json = try JSONUtils.decodeEnvelope(response.data)
        let matched = json["matched"] as? Bool ?? false
        let linkId = (json["linkId"] as? String).nonEmpty
        let shortCode = (json["shortCode"] as? String).nonEmpty
        let params = JSONUtils.toAnyJSONMap(json["params"])

        let result = DeferredMatchResult(
            matched: matched,
            linkId: linkId,
            shortCode: shortCode,
            params: params
        )

        preferences.deferredMatchAttempted = true

        if matched {
            var cache: [String: Any] = [
                "matched": true,
                "linkId": linkId ?? NSNull(),
                "shortCode": shortCode ?? NSNull(),
            ]
            if let p = json["params"] {
                cache["params"] = p
            }
            if let cacheData = try? JSONUtils.encode(cache),
               let cacheString = String(data: cacheData, encoding: .utf8) {
                preferences.deferredMatchResult = cacheString
            }
            preferences.attributedShortCode = shortCode
            preferences.attributedLinkId = linkId
        }

        // The ref has had its one chance, whatever came of it.
        preferences.pendingCookieRef = nil

        return result
    }

    /// Builds the `/api/deferred/match` body.
    ///
    /// Internal so the shape can be tested without a server: everything that
    /// decides whether a match is even possible is decided here, and the
    /// failure mode is a plain `matched: false` that looks exactly like a
    /// device the server has never seen.
    ///
    /// `DeferredMatchDto` takes `fingerprint` and `cookieRef` and nothing
    /// else — the API's validation pipe runs with `forbidNonWhitelisted`, so
    /// one extra top-level key makes the whole request a 400.
    internal static func requestBody(
        deviceInfo: [String: Any],
        cookieRef: String?
    ) -> [String: Any] {
        var body: [String: Any] = [:]

        let os = deviceInfo["os"] as? String ?? "iOS"
        let osVersion = deviceInfo["osVersion"] as? String ?? ""
        let model = deviceInfo["model"] as? String ?? ""
        let screenWidth = deviceInfo["screenWidth"] as? Int ?? 0
        let screenHeight = deviceInfo["screenHeight"] as? Int ?? 0

        if !os.isEmpty || !model.isEmpty {
            body["fingerprint"] = [
                "os": os,
                "osVersion": osVersion,
                "model": model,
                "screenWidth": screenWidth,
                "screenHeight": screenHeight,
            ] as [String: Any]
        }

        // Omitted rather than null when there is none: `@IsString()` on a
        // present key is a 400 for anything that is not a string.
        if let ref = cookieRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            body["cookieRef"] = ref
        }

        return body
    }

    private func parseCachedResult() -> DeferredMatchResult {
        guard let raw = preferences.deferredMatchResult,
              let data = raw.data(using: .utf8),
              let json = try? JSONUtils.decodeObject(data)
        else { return .unmatched }

        return DeferredMatchResult(
            matched: json["matched"] as? Bool ?? false,
            linkId: (json["linkId"] as? String).nonEmpty,
            shortCode: (json["shortCode"] as? String).nonEmpty,
            params: JSONUtils.toAnyJSONMap(json["params"])
        )
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}
