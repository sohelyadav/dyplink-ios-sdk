import Foundation

/// Tracks app sessions based on foreground/background transitions.
/// Mirrors the Android `SessionTracker`.
///
/// A new session is started when the app comes to the foreground AND
/// more than `sessionTimeoutSeconds` has elapsed since the last
/// background transition.
internal final class SessionTracker {
    private let eventTracker: EventTracker
    private let preferences: DyplinkPreferences
    private let sessionTimeoutSeconds: Int
    private let lock = NSLock()

    private(set) var isInSession: Bool = false

    init(
        eventTracker: EventTracker,
        preferences: DyplinkPreferences,
        sessionTimeoutSeconds: Int
    ) {
        self.eventTracker = eventTracker
        self.preferences = preferences
        self.sessionTimeoutSeconds = sessionTimeoutSeconds
    }

    func onAppForegrounded() {
        lock.lock()
        defer { lock.unlock() }

        let now = EventQueueStore.nowMillis()
        let last = preferences.lastSessionTimestamp
        let elapsedSeconds: Int64 = last > 0 ? (now - last) / 1_000 : .max

        if elapsedSeconds >= Int64(sessionTimeoutSeconds) {
            DyplinkLogger.d("SessionTracker: session timeout exceeded — starting new session")
            eventTracker.track("session_start")
        }

        preferences.lastSessionTimestamp = now
        isInSession = true
    }

    func onAppBackgrounded() {
        lock.lock()
        defer { lock.unlock() }
        preferences.lastSessionTimestamp = EventQueueStore.nowMillis()
        isInSession = false
    }
}
