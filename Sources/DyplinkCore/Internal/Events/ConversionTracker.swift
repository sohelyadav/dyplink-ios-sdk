import Foundation

/// Tracks conversion events by enqueuing them through `EventQueueManager`.
/// Mirrors Android `ConversionTracker`.
internal final class ConversionTracker {
    private let queueManager: EventQueueManager
    private let preferences: DyplinkPreferences
    private let projectId: String

    init(
        queueManager: EventQueueManager,
        preferences: DyplinkPreferences,
        projectId: String
    ) {
        self.queueManager = queueManager
        self.preferences = preferences
        self.projectId = projectId
    }

    /// Enqueue a conversion event. `shortCode` and `linkId` fall back to
    /// the attributed values stored from a prior deferred match when
    /// not explicitly provided. Fire-and-forget.
    func trackConversion(_ params: TrackConversionParams) {
        let shortCode = params.shortCode ?? preferences.attributedShortCode
        let linkId = params.linkId ?? preferences.attributedLinkId

        // A conversion with neither is one the server cannot join to a link,
        // and it answers `400 Either shortCode or linkId must be provided`.
        // Queueing it anyway loses it twice over: `EventQueueManager` treats
        // a 4xx as final and deletes the event, so the host app is told
        // nothing and the conversion simply never appears in the funnel.
        // Refuse it here, while there is still somewhere to say why.
        guard shortCode != nil || linkId != nil else {
            DyplinkLogger.e(
                "Conversion '\(params.eventType)' not tracked: nothing to attribute it to. "
                + "Pass shortCode or linkId to TrackConversionParams, or call "
                + "matchDeferredDeepLink() first so the attributed link is stored."
            )
            return
        }

        do {
            var body: [String: Any] = [
                "projectId": projectId,
                "eventType": params.eventType,
            ]
            // Omitted rather than null. `CreateConversionDto` types these as
            // a string and a UUID, and the API's validation pipe runs with
            // `forbidNonWhitelisted` — a key carrying `null` is a field the
            // SDK supplied, not a field it left out.
            if let v = shortCode { body["shortCode"] = v }
            if let v = linkId { body["linkId"] = v }
            if let v = params.externalUserId { body["externalUserId"] = v }
            if let meta = params.metadata {
                body["metadata"] = meta.asFoundationJSON()
            }
            let data = try JSONUtils.encode(body)
            guard let payload = String(data: data, encoding: .utf8) else { return }
            queueManager.enqueue(
                eventType: "conversion",
                endpoint: "/api/conversions",
                payload: payload
            )
        } catch {
            DyplinkLogger.e("Conversion track failed", error)
        }
    }

    /// Enqueue a revenue event via the `/api/identity/revenue` endpoint.
    /// Fire-and-forget.
    func trackRevenue(amount: Double, currency: String) {
        do {
            let body: [String: Any] = [
                "projectId": projectId,
                "deviceFingerprint": (preferences.deviceFingerprint ?? "") as String,
                "amount": amount,
                "currency": currency,
            ]
            let data = try JSONUtils.encode(body)
            guard let payload = String(data: data, encoding: .utf8) else { return }
            queueManager.enqueue(
                eventType: "revenue",
                endpoint: "/api/identity/revenue",
                payload: payload
            )
        } catch {
            DyplinkLogger.e("Revenue track failed", error)
        }
    }
}
