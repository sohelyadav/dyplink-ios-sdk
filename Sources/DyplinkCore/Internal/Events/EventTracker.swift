import Foundation

/// Tracks custom events by enqueuing them through `EventQueueManager`
/// for reliable offline-first delivery. Mirrors Android `EventTracker`.
internal final class EventTracker {
    private let queueManager: EventQueueManager
    private let fingerprintProvider: FingerprintProvider
    private let projectId: String

    init(
        queueManager: EventQueueManager,
        fingerprintProvider: FingerprintProvider,
        projectId: String
    ) {
        self.queueManager = queueManager
        self.fingerprintProvider = fingerprintProvider
        self.projectId = projectId
    }

    /// Enqueue a custom event. Fire-and-forget — errors are logged.
    func track(_ eventName: String, properties: [String: Any]? = nil) {
        do {
            var body: [String: Any] = [
                "projectId": projectId,
                "eventName": eventName,
                "distinctId": fingerprintProvider.distinctId,
                "deviceFingerprint": fingerprintProvider.fingerprint,
                "timestamp": Self.iso8601Now(),
            ]
            if let properties = properties {
                body["properties"] = properties
            }
            let data = try JSONUtils.encode(body)
            guard let payload = String(data: data, encoding: .utf8) else { return }
            queueManager.enqueue(
                eventType: "track",
                endpoint: "/api/events/track",
                payload: payload
            )
        } catch {
            DyplinkLogger.e("Event track failed", error)
        }
    }

    static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
