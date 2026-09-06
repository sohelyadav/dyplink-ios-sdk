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
/// 3. Forwarding notification delegate callbacks to
///    `reportNotificationDelivered(userInfo:)` and
///    `reportNotificationClicked(userInfo:)` so campaign click-through
///    can be measured. An SDK can't intercept these on its own — the
///    host app's `UNUserNotificationCenterDelegate` owns them.
///
/// Reporting a click also routes the campaign's destination URL, if it
/// carries one, to `Dyplink.shared.handleCampaignDeepLink(url:)` — so a
/// tap reaches `Dyplink.shared.onDeepLink` / `deepLinkListener` alongside
/// links opened from Universal Links and deferred matching. Apps that
/// would rather route the tap themselves can ignore those listeners and
/// use the URL `reportNotificationClicked(userInfo:)` returns.
///
/// Usage:
/// ```swift
/// // AppDelegate.swift
/// func application(_ app: UIApplication,
///                  didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
///     let tokenString = token.map { String(format: "%02x", $0) }.joined()
///     Task { try? await DyplinkPush.shared.registerToken(tokenString) }
/// }
///
/// // UNUserNotificationCenterDelegate
/// func userNotificationCenter(_ center: UNUserNotificationCenter,
///                              willPresent notification: UNNotification,
///                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
///     DyplinkPush.shared.reportNotificationDelivered(userInfo: notification.request.content.userInfo)
///     completionHandler([.banner, .sound])
/// }
///
/// func userNotificationCenter(_ center: UNUserNotificationCenter,
///                              didReceive response: UNNotificationResponse,
///                              withCompletionHandler completionHandler: @escaping () -> Void) {
///     // Reports the click and delivers the campaign's deep link, if any,
///     // to `Dyplink.shared.onDeepLink`. The destination is also returned:
///     //   let url = DyplinkPush.shared.reportNotificationClicked(userInfo: ...)
///     DyplinkPush.shared.reportNotificationClicked(userInfo: response.notification.request.content.userInfo)
///     completionHandler()
/// }
///
/// // Background/silent pushes instead arrive via:
/// func application(_ application: UIApplication,
///                  didReceiveRemoteNotification userInfo: [AnyHashable: Any],
///                  fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
///     DyplinkPush.shared.reportNotificationDelivered(userInfo: userInfo)
///     completionHandler(.newData)
/// }
/// ```
public final class DyplinkPush: @unchecked Sendable {

    public static let shared = DyplinkPush()

    /// Key under which outgoing Dyplink campaign pushes carry their
    /// campaign id in the notification's data payload / `userInfo`.
    private static let campaignIdKey = "dyplink_campaign_id"

    /// Keys under which a campaign carries its destination URL, in the
    /// order Android's `PushNotificationHandler` reads them.
    private static let deepLinkUrlKeys = ["deep_link_url", "link"]

    private let lock = NSLock()
    private var _isInitialized = false
    private var tokenManager = PushTokenManager()
    private let eventReporter = PushEventReporter()

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

    // ── Push event reporting ──────────────────────────────────────────

    /// Report that a Dyplink campaign push was delivered to the device.
    ///
    /// Call from `userNotificationCenter(_:willPresent:withCompletionHandler:)`
    /// (foreground) or `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// (background/silent pushes). Does nothing if `userInfo` doesn't
    /// carry a Dyplink campaign id — i.e. the push wasn't sent by a
    /// Dyplink campaign. Fire-and-forget: never throws, never blocks.
    public func reportNotificationDelivered(userInfo: [AnyHashable: Any]) {
        reportEvent(.delivered, userInfo: userInfo)
    }

    /// Report that the user tapped a Dyplink campaign push notification and
    /// route the destination URL the campaign carries, if any.
    ///
    /// Call from `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    /// Returns that destination URL, so an app that would rather route taps
    /// itself can do so without subscribing to `Dyplink.shared.onDeepLink`,
    /// or `nil` when the push carries none.
    ///
    /// The two halves are independent: reporting does nothing when `userInfo`
    /// carries no Dyplink campaign id, routing does nothing when it carries no
    /// destination URL, and a failure of either — a dropped analytics request,
    /// say — leaves the other untouched. Fire-and-forget: never throws, never
    /// blocks.
    @discardableResult
    public func reportNotificationClicked(userInfo: [AnyHashable: Any]) -> String? {
        reportEvent(.click, userInfo: userInfo)
        return routeDeepLink(userInfo: userInfo)
    }

    /// Report an arbitrary push engagement event — for `impression` and
    /// `dismissed`, which don't map to a single delegate callback the
    /// way delivery and clicks do. Does nothing if `userInfo` doesn't
    /// carry a Dyplink campaign id. Fire-and-forget: never throws,
    /// never blocks.
    public func reportNotificationEvent(_ event: PushEvent, userInfo: [AnyHashable: Any]) {
        reportEvent(event, userInfo: userInfo)
    }

    /// Hands the campaign's destination URL to
    /// `Dyplink.shared.handleCampaignDeepLink(url:)`, reading the same data
    /// keys in the same order as Android's `PushNotificationHandler`:
    /// `deep_link_url` first, then `link`. Returns the URL it found.
    ///
    /// Delivering it automatically is deliberate. Android opens the URL itself
    /// on tap without consulting the host app, so an iOS SDK that only reported
    /// the click would leave the deep link on every push campaign dead. Nor can
    /// this duplicate routing an app already does: the data keys aren't public
    /// API, so an app never told about them can't be reading them out of
    /// `userInfo` today.
    private func routeDeepLink(userInfo: [AnyHashable: Any]) -> String? {
        guard isInitialized else { return nil }
        // `userInfo` comes from the OS untyped — every key may be absent or
        // hold something other than the string we expect.
        guard let raw = Self.deepLinkUrlKeys
            .lazy
            .compactMap({ userInfo[$0] as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }

        // A URL the OS can't even parse is still handed back to the caller —
        // it is what the campaign sent — but there is nothing to route.
        if let url = URL(string: raw) {
            Dyplink.shared.handleCampaignDeepLink(url: url)
        }
        return raw
    }

    private func reportEvent(_ event: PushEvent, userInfo: [AnyHashable: Any]) {
        guard isInitialized else { return }
        guard let campaignId = userInfo[Self.campaignIdKey] as? String else {
            // Not a Dyplink campaign push — nothing to report.
            return
        }
        Task {
            await eventReporter.report(campaignId: campaignId, type: event.rawValue)
        }
    }

    /// Test-only reset.
    internal func resetForTesting() {
        lock.lock()
        _isInitialized = false
        tokenManager = PushTokenManager()
        lock.unlock()
    }
}
