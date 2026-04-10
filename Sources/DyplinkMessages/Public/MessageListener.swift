import Foundation

/// Listener for in-app message interactions.
///
/// Register via `DyplinkMessages.shared.messageListener = self`.
public protocol MessageListener: AnyObject {
    /// Called on message lifecycle events (impression, click, dismiss, etc.).
    func onMessageEvent(message: InAppMessage, eventType: String, buttonId: String?)
    /// Called when a CTA button is tapped.
    func onButtonAction(message: InAppMessage, button: MessageButton)
    /// Called when a button with action="custom_event" is tapped.
    func onCustomEvent(message: InAppMessage, eventName: String)
}

/// Default implementations so conformers only need to override what
/// they care about.
public extension MessageListener {
    func onMessageEvent(message: InAppMessage, eventType: String, buttonId: String?) {}
    func onButtonAction(message: InAppMessage, button: MessageButton) {}
    func onCustomEvent(message: InAppMessage, eventName: String) {}
}
