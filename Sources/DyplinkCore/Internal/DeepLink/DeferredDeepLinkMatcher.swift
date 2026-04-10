import Foundation

/// Performs a server-side deferred deep link match.
///
/// Mirrors the Android `DeferredDeepLinkMatcher` with one key
/// difference: iOS has no equivalent of Google Play's Install Referrer
/// API, so the `cookieRef` field is always nil. Matching on iOS relies
/// purely on the device fingerprint (os/osVersion/model/screen) + IP
/// correlation performed by the server.
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
        let deviceInfo = deviceInfoCollector.collect()

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

        let data = try JSONUtils.encode(body)
        let response = try await requestExecutor.post("/api/deferred/match", jsonBody: data)

        let json = try JSONUtils.decodeObject(response.data)
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

        return result
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
