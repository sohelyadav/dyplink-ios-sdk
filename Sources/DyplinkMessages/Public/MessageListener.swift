import Foundation

/// Listener for in-app message interactions.
///
/// Register via `DyplinkMessages.shared.messageListener = self`.
public protocol MessageListener: AnyObject {
    /// Called on each message lifecycle event, as it is reported.
    ///
    /// One message produces an `impression` and then exactly one of:
    ///
    /// - `cta_click` — a button was tapped, and `buttonId` says which.
    /// - `auto_dismiss` — it closed itself after `autoDismissSeconds`.
    /// - `dismiss` — the user closed it.
    ///
    /// Only one, because the alternative double-counts: a tapped button also
    /// closes the message, and reporting that as a dismissal as well would
    /// count every tap against the message's own dismiss rate.
    func onMessageEvent(message: InAppMessage, eventType: String, buttonId: String?)

    /// Called when a CTA button is tapped, before the SDK acts on it.
    ///
    /// A `deep_link` or `url` button is then opened with
    /// `UIApplication.open`, so an app that routes its own links should do
    /// that here and expect the SDK's attempt to follow.
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
