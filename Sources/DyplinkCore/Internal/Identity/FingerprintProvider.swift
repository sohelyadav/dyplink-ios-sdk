import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Generates and persists a device fingerprint, anonymous id, and
/// identified id using `DyplinkPreferences`.
///
/// Mirrors the Android `FingerprintProvider` but uses `IDFV`
/// (`identifierForVendor`) as the preferred fingerprint source before
/// falling back to a freshly generated UUID. IDFV is Apple's
/// recommended per-vendor device identifier and does not require the
/// AppTrackingTransparency prompt.
internal final class FingerprintProvider {
    private let preferences: DyplinkPreferences
    private let lock = NSLock()

    init(preferences: DyplinkPreferences) {
        self.preferences = preferences
    }

    /// Stable UUID representing this device installation.
    /// Generated once (or derived from IDFV) and persisted.
    var fingerprint: String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = preferences.deviceFingerprint {
            return existing
        }
        let generated = Self.generateFingerprint()
        preferences.deviceFingerprint = generated
        return generated
    }

    /// Anonymous (pre-identify) user id. Generated on first access
    /// and regenerated only by `reset()`.
    var anonymousId: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let existing = preferences.anonymousId {
                return existing
            }
            let generated = UUID().uuidString
            preferences.anonymousId = generated
            return generated
        }
        set {
            lock.lock()
            preferences.anonymousId = newValue
            lock.unlock()
        }
    }

    /// The identified (logged-in) user id. `nil` when the user has
    /// not been identified or after `reset()`.
    var identifiedId: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return preferences.identifiedId
        }
        set {
            lock.lock()
            preferences.identifiedId = newValue
            lock.unlock()
        }
    }

    /// Best-known user identity: `identifiedId` if set, otherwise
    /// `anonymousId`.
    var distinctId: String {
        identifiedId ?? anonymousId
    }

    /// Clears the identified user and generates a fresh anonymous id.
    /// The device `fingerprint` is unaffected.
    func reset() {
        lock.lock()
        preferences.identifiedId = nil
        preferences.anonymousId = UUID().uuidString
        lock.unlock()
    }

    private static func generateFingerprint() -> String {
        #if canImport(UIKit)
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        return UUID().uuidString
    }
}
