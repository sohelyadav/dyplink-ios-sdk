import Foundation
import DyplinkCore

/// Entry point for Dyplink in-app messages.
///
/// Requires `Dyplink.shared.initialize` first.
///
/// ```swift
/// // On app foreground:
/// DyplinkMessages.shared.onAppOpen()
///
/// // On screen change:
/// DyplinkMessages.shared.onScreenView("HomeScreen")
///
/// // On custom event:
/// DyplinkMessages.shared.onEvent("purchase_complete")
/// ```
public final class DyplinkMessages: @unchecked Sendable {
    public static let shared = DyplinkMessages()

    private let apiClient = MessageApiClient()
    private let lock = NSLock()

    #if canImport(UIKit)
    private lazy var manager: MessageManager = {
        MessageManager(
            apiClient: apiClient,
            projectId: DyplinkConfigBridge.projectId,
            deviceFingerprint: DyplinkConfigBridge.deviceFingerprint,
            distinctIdProvider: { DyplinkConfigBridge.distinctId.isEmpty ? nil : DyplinkConfigBridge.distinctId }
        )
    }()
    #endif

    /// Protocol-based listener for message interactions. Set this before
    /// triggering checks to receive callbacks.
    public weak var messageListener: MessageListener? {
        didSet {
            #if canImport(UIKit)
            manager.messageListener = messageListener
            #endif
        }
    }

    private init() {}

    // ── Trigger points ─────────────────────────────────────────────────

    /// Check for and display `on_app_open` / `scheduled` messages.
    /// Call from your app's foreground lifecycle callback.
    public func onAppOpen() {
        checkAndShow(.init())
    }

    /// Check for and display `on_screen` messages targeting `screen`.
    public func onScreenView(_ screen: String) {
        checkAndShow(.init(screen: screen))
    }

    /// Check for and display `on_event` messages targeting `event`.
    public func onEvent(_ event: String) {
        checkAndShow(.init(event: event))
    }

    // ── Internal ───────────────────────────────────────────────────────

    private func checkAndShow(_ context: MessageApiClient.CheckContext) {
        precondition(Dyplink.shared.isInitialized,
                     "Dyplink.shared.initialize(config:) must be called before using DyplinkMessages")
        #if canImport(UIKit)
        Task {
            await manager.checkAndShow(context: context)
        }
        #endif
    }
}
