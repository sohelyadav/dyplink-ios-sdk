import Foundation

/// A resolved in-app message ready to be displayed.
public struct InAppMessage: Sendable, Equatable {
    public let id: String
    /// "modal" | "bottom_sheet" | "banner_top" | "banner_bottom" | "fullscreen"
    public let messageType: String
    public let title: String
    public let body: String?
    public let imageUrl: String?
    /// "top" | "center" | "background"
    public let imagePosition: String
    public let buttons: [MessageButton]?
    public let theme: MessageTheme?
    public let dismissOnTapOutside: Bool
    public let autoDismissSeconds: Int?
    public let triggerDelay: Int
}

/// A CTA button within an in-app message.
public struct MessageButton: Sendable, Equatable {
    public let id: String
    public let text: String
    /// "dismiss" | "deep_link" | "url" | "custom_event"
    public let action: String
    public let actionUrl: String?
    public let actionEvent: String?
    /// "primary" | "secondary" | "text"
    public let style: String
}

/// Visual theme for an in-app message.
public struct MessageTheme: Sendable, Equatable {
    public let backgroundColor: String?
    public let textColor: String?
    public let titleColor: String?
    public let buttonPrimaryColor: String?
    public let buttonSecondaryColor: String?
    public let overlayColor: String?
    public let borderRadius: Int?
    /// "fade" | "slide_up" | "slide_down" | "scale" | "none"
    public let animation: String?
}
