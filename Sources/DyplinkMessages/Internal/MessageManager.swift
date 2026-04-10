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

        // Record impression.
        Task {
            await apiClient.recordEvent(
                messageId: message.id,
                projectId: projectId,
                deviceFingerprint: deviceFingerprint,
                distinctId: distinctIdProvider(),
                eventType: "impression"
            )
        }
        messageListener?.onMessageEvent(message: message, eventType: "impression", buttonId: nil)

        // Present the in-app message.
        let presenter = InAppMessagePresenter(message: message) { [weak self] action, button in
            guard let self = self else { return }

            // Record dismiss/click event.
            let eventType = (action == "dismiss") ? "dismiss" : "click"
            Task {
                await self.apiClient.recordEvent(
                    messageId: message.id,
                    projectId: self.projectId,
                    deviceFingerprint: self.deviceFingerprint,
                    distinctId: self.distinctIdProvider(),
                    eventType: eventType,
                    buttonId: button?.id
                )
            }
            self.messageListener?.onMessageEvent(message: message, eventType: eventType, buttonId: button?.id)

            if let button = button {
                self.messageListener?.onButtonAction(message: message, button: button)
                if button.action == "custom_event", let event = button.actionEvent {
                    self.messageListener?.onCustomEvent(message: message, eventName: event)
                }
            }
        }
        presenter.present()
    }
}
#endif
