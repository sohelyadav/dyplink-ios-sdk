import Foundation
import DyplinkCore

/// Optional push notification module for the Dyplink iOS SDK.
///
/// Unlike the Android SDK which wraps FCM, the iOS SDK wraps Apple
/// Push Notification service (APNs). The developer is responsible for:
///
/// 1. Calling `UIApplication.shared.registerForRemoteNotifications()`
/// 2. Forwarding the device token to `DyplinkPush.shared.registerToken(_:)`
///    from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
///
/// Usage:
/// ```swift
/// // AppDelegate.swift
/// func application(_ app: UIApplication,
///                  didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
///     let tokenString = token.map { String(format: "%02x", $0) }.joined()
///     Task { try? await DyplinkPush.shared.registerToken(tokenString) }
/// }
/// ```
public final class DyplinkPush: @unchecked Sendable {

    public static let shared = DyplinkPush()

    private let lock = NSLock()
    private var _isInitialized = false
    private var tokenManager = PushTokenManager()

    private init() {}

    // ── Lifecycle ──────────────────────────────────────────────────────

    /// `true` after `initialize()` has been called.
    public var isInitialized: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isInitialized
    }

    /// Initialize the push module. Requires `Dyplink.shared.initialize`
    /// to have been called first.
    public func initialize() {
        lock.lock()
        defer { lock.unlock() }
        precondition(Dyplink.shared.isInitialized,
                     "Dyplink.shared.initialize(config:) must be called before DyplinkPush.shared.initialize()")
        if _isInitialized { return }
        _isInitialized = true
    }

    /// Whether a push token is currently registered with the backend.
    public var isRegistered: Bool { tokenManager.isRegistered }

    // ── Token management ───────────────────────────────────────────────

    /// Register an APNs device token with the Dyplink backend.
    ///
    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// The token should be the hex-encoded string representation of the
    /// `Data` token.
    public func registerToken(_ token: String) async throws {
        guard isInitialized else {
            throw DyplinkError.notInitialized("DyplinkPush not initialized")
        }
        try await tokenManager.registerToken(token)
    }

    /// Convenience: accepts the raw `Data` token directly and
    /// hex-encodes it.
    public func registerToken(_ tokenData: Data) async throws {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        try await registerToken(hex)
    }

    /// Unregister the current APNs token from the Dyplink backend.
    /// Call on user logout.
    public func unregisterToken() async throws {
        guard isInitialized else {
            throw DyplinkError.notInitialized("DyplinkPush not initialized")
        }
        try await tokenManager.unregisterToken()
    }

    /// Test-only reset.
    internal func resetForTesting() {
        lock.lock()
        _isInitialized = false
        tokenManager = PushTokenManager()
        lock.unlock()
    }
}
