import Foundation

/// Thin wrapper around `UserDefaults` that stores small SDK state
/// values (IDs, flags, timestamps).
///
/// Uses a dedicated suite name so SDK prefs don't pollute the host
/// app's `UserDefaults.standard`.
internal final class DyplinkPreferences {
    private let defaults: UserDefaults

    init(suiteName: String = "com.dyplink.sdk.prefs") {
        // `UserDefaults(suiteName:)` returns nil when the suite name is
        // reserved. Fall back to `.standard` in that edge case so the
        // SDK still functions — values will just live alongside host
        // app values under our keys.
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    // ── Anonymous / Device / Identified IDs ────────────────────────────

    var anonymousId: String? {
        get { defaults.string(forKey: Keys.anonymousId) }
        set { defaults.set(newValue, forKey: Keys.anonymousId) }
    }

    var deviceFingerprint: String? {
        get { defaults.string(forKey: Keys.deviceFingerprint) }
        set { defaults.set(newValue, forKey: Keys.deviceFingerprint) }
    }

    var identifiedId: String? {
        get { defaults.string(forKey: Keys.identifiedId) }
        set { defaults.set(newValue, forKey: Keys.identifiedId) }
    }

    // ── Deferred deep-link matching ────────────────────────────────────

    var deferredMatchAttempted: Bool {
        get { defaults.bool(forKey: Keys.deferredMatchAttempted) }
        set { defaults.set(newValue, forKey: Keys.deferredMatchAttempted) }
    }

    var deferredMatchResult: String? {
        get { defaults.string(forKey: Keys.deferredMatchResult) }
        set { defaults.set(newValue, forKey: Keys.deferredMatchResult) }
    }

    // ── Attribution ────────────────────────────────────────────────────

    var attributedShortCode: String? {
        get { defaults.string(forKey: Keys.attributedShortCode) }
        set { defaults.set(newValue, forKey: Keys.attributedShortCode) }
    }

    var attributedLinkId: String? {
        get { defaults.string(forKey: Keys.attributedLinkId) }
        set { defaults.set(newValue, forKey: Keys.attributedLinkId) }
    }

    // ── Session ────────────────────────────────────────────────────────

    /// Millis-since-1970 (matches Android's `System.currentTimeMillis()`).
    var lastSessionTimestamp: Int64 {
        get {
            let v = defaults.object(forKey: Keys.lastSessionTimestamp) as? NSNumber
            return v?.int64Value ?? 0
        }
        set {
            defaults.set(NSNumber(value: newValue), forKey: Keys.lastSessionTimestamp)
        }
    }

    // ── Housekeeping ───────────────────────────────────────────────────

    func clear() {
        for key in [
            Keys.anonymousId, Keys.deviceFingerprint, Keys.identifiedId,
            Keys.deferredMatchAttempted, Keys.deferredMatchResult,
            Keys.attributedShortCode, Keys.attributedLinkId,
            Keys.lastSessionTimestamp,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // ── Keys ───────────────────────────────────────────────────────────

    private enum Keys {
        static let anonymousId = "dyplink_anonymous_id"
        static let deviceFingerprint = "dyplink_device_fingerprint"
        static let identifiedId = "dyplink_identified_id"
        static let deferredMatchAttempted = "dyplink_deferred_match_attempted"
        static let deferredMatchResult = "dyplink_deferred_match_result"
        static let attributedShortCode = "dyplink_attributed_short_code"
        static let attributedLinkId = "dyplink_attributed_link_id"
        static let lastSessionTimestamp = "dyplink_last_session_timestamp"
    }
}
