import Foundation

/// Manages identity-related API calls: identify, merge, link-device,
/// and revenue. Mirrors the Android `IdentityManager`.
internal final class IdentityManager {
    private let requestExecutor: RequestExecutor
    private let fingerprintProvider: FingerprintProvider
    private let deviceInfoCollector: DeviceInfoCollector
    private let projectId: String
    private let enableAutoDeviceInfo: Bool

    init(
        requestExecutor: RequestExecutor,
        fingerprintProvider: FingerprintProvider,
        deviceInfoCollector: DeviceInfoCollector,
        projectId: String,
        enableAutoDeviceInfo: Bool
    ) {
        self.requestExecutor = requestExecutor
        self.fingerprintProvider = fingerprintProvider
        self.deviceInfoCollector = deviceInfoCollector
        self.projectId = projectId
        self.enableAutoDeviceInfo = enableAutoDeviceInfo
    }

    /// Identifies the current user by posting their attributes to
    /// `/api/identity/identify`. Transitions from anonymous to
    /// identified also trigger a fire-and-forget `/api/identity/merge`.
    @discardableResult
    func identify(_ params: IdentifyParams) async throws -> IdentifyResult {
        let previousDistinctId = fingerprintProvider.distinctId

        // Update local identity when the caller provides an explicit id.
        if let ext = params.externalUserId {
            fingerprintProvider.identifiedId = ext
        } else if let d = params.distinctId {
            fingerprintProvider.identifiedId = d
        }

        let body = buildIdentifyBody(params)
        let response = try await requestExecutor.post(
            "/api/identity/identify",
            jsonBody: try JSONUtils.encode(body)
        )

        guard response.isSuccessful else {
            throw DyplinkError.apiError(
                message: "Identify failed with status \(response.statusCode)",
                statusCode: response.statusCode,
                responseBody: response.bodyString
            )
        }

        let json = try JSONUtils.decodeObject(response.data)
        let newDistinctId = fingerprintProvider.distinctId
        if newDistinctId != previousDistinctId {
            Task { await self.merge(anonymousId: previousDistinctId, identifiedId: newDistinctId) }
        }

        return IdentifyResult(
            id: json["id"] as? String ?? "",
            projectId: json["projectId"] as? String ?? projectId,
            distinctId: json["distinctId"] as? String,
            externalUserId: json["externalUserId"] as? String,
            deviceFingerprint: json["deviceFingerprint"] as? String ?? fingerprintProvider.fingerprint,
            platform: json["platform"] as? String ?? "ios"
        )
    }

    /// Fires `/api/identity/merge` when the anonymous/identified IDs
    /// transition. Failures are logged but not thrown.
    func merge(anonymousId: String, identifiedId: String) async {
        do {
            let body: [String: Any] = [
                "projectId": projectId,
                "anonymousId": anonymousId,
                "identifiedId": identifiedId,
            ]
            _ = try await requestExecutor.post(
                "/api/identity/merge",
                jsonBody: try JSONUtils.encode(body)
            )
        } catch {
            DyplinkLogger.e("Identity merge failed", error)
        }
    }

    /// Fires `/api/identity/link-device`. Failures are logged but not thrown.
    func linkDevice(externalUserId: String) async {
        do {
            let body: [String: Any] = [
                "projectId": projectId,
                "deviceFingerprint": fingerprintProvider.fingerprint,
                "externalUserId": externalUserId,
                "platform": "ios",
            ]
            _ = try await requestExecutor.post(
                "/api/identity/link-device",
                jsonBody: try JSONUtils.encode(body)
            )
        } catch {
            DyplinkLogger.e("Link device failed", error)
        }
    }

    /// Fires `/api/identity/revenue`. Failures are logged but not thrown.
    func trackRevenue(amount: Double, currency: String) async {
        do {
            let body: [String: Any] = [
                "projectId": projectId,
                "deviceFingerprint": fingerprintProvider.fingerprint,
                "amount": amount,
                "currency": currency,
            ]
            _ = try await requestExecutor.post(
                "/api/identity/revenue",
                jsonBody: try JSONUtils.encode(body)
            )
        } catch {
            DyplinkLogger.e("Track revenue failed", error)
        }
    }

    // ── Body builder ───────────────────────────────────────────────────

    private func buildIdentifyBody(_ params: IdentifyParams) -> [String: Any] {
        var body: [String: Any] = [
            "projectId": projectId,
            "deviceFingerprint": fingerprintProvider.fingerprint,
            "platform": "ios",
            "distinctId": fingerprintProvider.distinctId,
        ]

        if let v = params.externalUserId { body["externalUserId"] = v }
        if let v = params.firstName { body["firstName"] = v }
        if let v = params.lastName { body["lastName"] = v }
        if let v = params.phone { body["phone"] = v }
        if let v = params.avatar { body["avatar"] = v }
        if let v = params.locale { body["locale"] = v }
        if let v = params.language { body["language"] = v }
        if let v = params.appVersion { body["appVersion"] = v }
        if let v = params.appBuild { body["appBuild"] = v }
        if let v = params.utmSource { body["utmSource"] = v }
        if let v = params.utmMedium { body["utmMedium"] = v }
        if let v = params.utmCampaign { body["utmCampaign"] = v }
        if let v = params.utmContent { body["utmContent"] = v }
        if let v = params.utmTerm { body["utmTerm"] = v }
        if let v = params.installSource { body["installSource"] = v }
        if let v = params.installCampaign { body["installCampaign"] = v }
        if let v = params.emailOptIn { body["emailOptIn"] = v }
        if let v = params.smsOptIn { body["smsOptIn"] = v }
        if let v = params.pushOptIn { body["pushOptIn"] = v }
        if let v = params.gdprConsent { body["gdprConsent"] = v }
        if let v = params.doNotTrack { body["doNotTrack"] = v }

        if let traits = params.traits {
            body["traits"] = traits.asFoundationJSON()
        }

        if enableAutoDeviceInfo {
            let deviceInfo = deviceInfoCollector.collect()
            for (key, value) in deviceInfo where body[key] == nil {
                body[key] = value
            }
        }

        return body
    }
}
