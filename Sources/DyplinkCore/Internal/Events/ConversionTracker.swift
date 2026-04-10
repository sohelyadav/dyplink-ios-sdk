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
        do {
            var body: [String: Any] = [
                "projectId": projectId,
                "eventType": params.eventType,
                "shortCode": (params.shortCode ?? preferences.attributedShortCode) ?? NSNull(),
                "linkId": (params.linkId ?? preferences.attributedLinkId) ?? NSNull(),
            ]
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
