#if canImport(UIKit)
import Foundation
import UIKit
import DyplinkCore

/// Coordinates message checking, display, and event recording.
/// Mirrors the Android `MessageManager`.
internal final class MessageManager {
    let apiClient: MessageApiClient
    let projectId: String
    let deviceFingerprint: String
    let distinctIdProvider: () -> String?
    weak var messageListener: MessageListener?

    /// Presenters for the messages currently on screen. Each owns the window
    /// its message lives in, so something has to hold them.
    private var presenters: [InAppMessagePresenter] = []

    init(
        apiClient: MessageApiClient,
        projectId: String,
        deviceFingerprint: String,
        distinctIdProvider: @escaping () -> String?
    ) {
        self.apiClient = apiClient
        self.projectId = projectId
        self.deviceFingerprint = deviceFingerprint
        self.distinctIdProvider = distinctIdProvider
    }

    func checkAndShow(context: MessageApiClient.CheckContext) async {
        do {
            let messages = try await apiClient.checkMessages(
                projectId: projectId,
                deviceFingerprint: deviceFingerprint,
                distinctId: distinctIdProvider(),
                context: context
            )
            for message in messages {
                await show(message)
            }
        } catch {
            // Never crash the host app.
        }
    }

    @MainActor
    private func show(_ message: InAppMessage) async {
        // Respect trigger delay.
        if message.triggerDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(message.triggerDelay) * 1_000_000_000)
        }

        report(message, eventType: "impression")

        let presenter = InAppMessagePresenter(message: message) { [weak self] outcome in
            self?.handle(outcome, for: message)
        }
        // Nothing else holds the presenter, and it owns the window the
        // message lives in — dropping it here would take the message with it.
        presenters.append(presenter)
        presenter.present()
    }

    /// Records the outcome and lets the host app act on it.
    @MainActor
    private func handle(_ outcome: InAppMessagePresenter.Outcome, for message: InAppMessage) {
        presenters.removeAll { $0.isFinished }

        switch outcome {
        case .dismissed:
            report(message, eventType: "dismiss")

        case .autoDismissed:
            report(message, eventType: "auto_dismiss")

        case .buttonTapped(let button):
            // `cta_click`, not `click`, and this is the reason: the
            // dashboard's per-button breakdown counts `cta_click` rows
            // alone, so for as long as iOS reported `click` its taps were
            // invisible there while Android's showed up. Both are summed
            // into the click-through rate, which is why nothing looked
            // wrong at the top level.
            report(message, eventType: "cta_click", buttonId: button.id)
            messageListener?.onButtonAction(message: message, button: button)

            switch button.action {
            case "deep_link", "url":
                open(button.actionUrl)
            case "custom_event":
                if let event = button.actionEvent {
                    messageListener?.onCustomEvent(message: message, eventName: event)
                }
            default:
                // `dismiss` has nothing to do beyond closing, which has
                // already happened.
                break
            }
        }
    }

    private func report(_ message: InAppMessage, eventType: String, buttonId: String? = nil) {
        Task { [apiClient, projectId, deviceFingerprint, distinctIdProvider] in
            await apiClient.recordEvent(
                messageId: message.id,
                projectId: projectId,
                deviceFingerprint: deviceFingerprint,
                distinctId: distinctIdProvider(),
                eventType: eventType,
                buttonId: buttonId
            )
        }
        messageListener?.onMessageEvent(message: message, eventType: eventType, buttonId: buttonId)
    }

    /// Opens a button's destination, the way the Android SDK's
    /// `ACTION_VIEW` does. `onButtonAction` has already run, so a host app
    /// that routes its own deep links has had its chance first.
    @MainActor
    private func open(_ raw: String?) {
        guard let raw = raw, let url = URL(string: raw) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
