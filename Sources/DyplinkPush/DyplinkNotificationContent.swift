#if canImport(UIKit)
import Foundation
import UIKit
import UserNotifications

/// One frame of a push campaign's carousel.
///
/// Mirrors `PushCarouselSlide` on the backend. `imageUrl` is a `URL` rather
/// than the string that arrived: a slide whose address the OS cannot even
/// parse is not a slide, so it is dropped while parsing instead of becoming a
/// blank frame the user swipes into.
public struct PushCarouselSlide: Sendable, Equatable {

    /// The picture this slide shows.
    public let imageUrl: URL

    /// Shown under the image. Optional — an image alone is a valid slide.
    public let caption: String?

    /// Where this slide leads, exactly as the campaign sent it.
    ///
    /// Left as a string rather than a `URL` to match
    /// `DyplinkPush.reportNotificationClicked(userInfo:)`, which also hands
    /// back what the campaign sent. `nil` means the slide has no destination
    /// of its own and the campaign's own deep link — the `deep_link_url` key
    /// the rest of the SDK reads — applies.
    public let deepLinkUrl: String?
}

/// A countdown shown in the notification.
///
/// Mirrors `PushTimer` on the backend, with `endsAt` already resolved to a
/// `Date`: a timestamp that will not parse cannot be counted down to, so it
/// is rejected while parsing rather than rendered as a frozen zero.
public struct PushTimer: Sendable, Equatable {

    /// When the countdown reaches zero.
    public let endsAt: Date

    /// Copy to show once it has. Both are optional, and when both are absent
    /// the backend's contract is that the campaign's own title and body
    /// apply — which is what the notification already shows.
    public let expiredTitle: String?
    public let expiredBody: String?

    /// Whether `endsAt` is already in the past.
    public var hasExpired: Bool { endsAt.timeIntervalSinceNow <= 0 }
}

/// Renders a push campaign's rich content in the host app's Notification
/// Content Extension.
///
/// The sibling of `DyplinkNotificationService`, and needed for the same
/// reason: no push provider carries a carousel or a countdown natively, so
/// both travel as data keys — `dyplink_carousel` and `dyplink_timer` — and
/// the client draws them. On iOS the only thing allowed to draw over a
/// notification is a Notification Content Extension, which is an app extension
/// target and therefore the host app's; none of the parsing, paging or
/// counting below has to be.
///
/// ## What the host app must create
///
/// Add a "Notification Content Extension" target to the app, link
/// `DyplinkPush` to it, and replace the template's view controller with:
///
/// ```swift
/// import UIKit
/// import UserNotifications
/// import UserNotificationsUI
/// import DyplinkPush
///
/// class NotificationViewController: UIViewController, UNNotificationContentExtension {
///
///     private var contentView: DyplinkNotificationContentView?
///
///     func didReceive(_ notification: UNNotification) {
///         // `nil` when the push carries no rich content, or carries
///         // something unusable. Adding nothing leaves the plain
///         // notification iOS already drew.
///         guard let contentView = DyplinkNotificationContent.makeView(for: notification) else { return }
///         contentView.frame = view.bounds
///         contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
///         view.addSubview(contentView)
///         self.contentView = contentView
///     }
///
///     // Optional: attribute a tap to the slide that was on screen.
///     func didReceive(_ response: UNNotificationResponse,
///                     completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
///         let destination = contentView?.currentSlide?.deepLinkUrl
///         completion(destination == nil ? .dismissAndForwardAction : .dismiss)
///     }
/// }
/// ```
///
/// ## What the extension's Info.plist must say
///
/// Under `NSExtension` → `NSExtensionAttributes`:
///
/// ```xml
/// <key>UNNotificationExtensionCategory</key>
/// <string>dyplink_sale</string>
/// <key>UNNotificationExtensionInitialContentSizeRatio</key>
/// <real>1.0</real>
/// <key>UNNotificationExtensionUserInteractionEnabled</key>
/// <true/>
/// ```
///
/// - `UNNotificationExtensionCategory` must equal the campaign's iOS
///   category, which the backend sends as `aps.category`. It may also be an
///   array of strings to cover several campaigns with one extension. **A
///   campaign that sets no iOS category never matches any extension** and iOS
///   shows the ordinary notification — so the category is not an extension
///   detail, it is something the campaign has to set too.
/// - `UNNotificationExtensionInitialContentSizeRatio` is the view's height as
///   a fraction of its width before anything has loaded. `1.0` suits a
///   carousel; a countdown alone wants far less, `0.3` or so.
/// - `UNNotificationExtensionUserInteractionEnabled` is what lets the user
///   swipe between slides. Without it the extension receives no touches and
///   the carousel is a single frame, so the host should drive it with
///   `showNextSlide()` instead.
/// - `UNNotificationExtensionDefaultContentHidden` must stay absent or
///   `false`. It is what keeps the campaign's title and body on screen above
///   this view, and that is the floor everything here degrades to — see below.
///
/// Two properties of the target itself decide whether the extension is ever
/// run, and both fail silently — the push simply arrives without its
/// carousel:
///
/// - Its bundle id must be the app's with a suffix appended, e.g.
///   `com.example.app.NotificationContent` for an app id of `com.example.app`.
/// - Its deployment target must not be higher than the app's, or devices on
///   older iOS versions install the app without the extension.
///
/// ## Never failing the notification
///
/// A campaign that arrives is worth more than a campaign rendered exactly, so
/// nothing here is allowed to replace the notification with something worse.
/// `dyplink_carousel` and `dyplink_timer` cross a process boundary as strings
/// and may hold anything; every one of malformed JSON, a slide with no image,
/// a date that will not parse and an image that will not load degrades to
/// less content rather than to a blank or broken view. When nothing at all
/// survives, `makeView` returns `nil` and the host adds no view — leaving
/// exactly the notification iOS would have shown on its own. That last step
/// only works while `UNNotificationExtensionDefaultContentHidden` is false,
/// which is why it is called out above.
///
/// Both extensions can be installed together: the service extension attaches
/// the campaign's image while the push is in flight, and this one draws over
/// the notification once it is on screen. Verified extension-safe — the
/// module builds with `APPLICATION_EXTENSION_API_ONLY=YES`, and nothing here
/// reaches for `UIApplication.shared`.
public enum DyplinkNotificationContent {

    /// Keys under which a campaign carries its rich content. Match
    /// `CAROUSEL_DATA_KEY` and `TIMER_DATA_KEY` on the backend, and sit at the
    /// top level of the payload, so they arrive in `userInfo` unchanged.
    private static let carouselKey = "dyplink_carousel"
    private static let timerKey = "dyplink_timer"

    /// The backend rejects a carousel longer than this at compose time, so a
    /// payload claiming more has already been tampered with or corrupted.
    /// Capping matters because each slide costs a decoded image, and a content
    /// extension is killed for memory long before an app would be.
    internal static let maxSlides = 10

    // ── Entry point ────────────────────────────────────────────────────

    /// Builds the view for `notification`'s rich content, or `nil` when it
    /// carries none that can be rendered.
    ///
    /// Call this from `didReceive(_:)` and add what it returns to the
    /// extension's view. A `nil` result is the ordinary outcome for every push
    /// that isn't a rich campaign, and adding nothing is the correct response
    /// to it.
    public static func makeView(for notification: UNNotification) -> DyplinkNotificationContentView? {
        makeView(for: notification.request)
    }

    /// The same, from a request — the form the notification's content is
    /// reachable in outside a delivered notification.
    public static func makeView(for request: UNNotificationRequest) -> DyplinkNotificationContentView? {
        let userInfo = request.content.userInfo
        let slides = carouselSlides(in: userInfo)
        let timer = self.timer(in: userInfo)

        // The two keys are independent on the wire and stay independent here:
        // a campaign whose countdown is malformed still gets its carousel.
        guard !slides.isEmpty || timer != nil else { return nil }
        return DyplinkNotificationContentView(slides: slides, timer: timer)
    }

    // ── Payload ────────────────────────────────────────────────────────

    /// Reads the campaign's carousel out of the notification payload. Slides
    /// that aren't usable are dropped individually, so one bad frame in ten
    /// costs one frame rather than the carousel.
    internal static func carouselSlides(in userInfo: [AnyHashable: Any]) -> [PushCarouselSlide] {
        guard let array = jsonValue(userInfo[carouselKey]) as? [Any] else { return [] }
        return array
            .prefix(maxSlides)
            .compactMap { $0 as? [String: Any] }
            .compactMap(PushCarouselSlide.init(json:))
    }

    /// Reads the campaign's countdown out of the notification payload.
    internal static func timer(in userInfo: [AnyHashable: Any]) -> PushTimer? {
        guard let object = jsonValue(userInfo[timerKey]) as? [String: Any] else { return nil }
        return PushTimer(json: object)
    }

    /// Decodes one of the rich-content keys.
    ///
    /// Both travel as JSON strings, because APNs data keys are strings — but
    /// a payload that was decoded and re-encoded somewhere along the way can
    /// arrive already structured, so an array or dictionary is accepted as it
    /// stands rather than being refused for not being a string.
    private static func jsonValue(_ value: Any?) -> Any? {
        guard let string = value as? String else { return value }
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Trims a payload string and rejects it when nothing is left. A caption
    /// or destination of `"   "` is absent, not present-and-blank.
    fileprivate static func nonEmptyString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Parsing

extension PushCarouselSlide {

    /// `nil` for anything that isn't a slide with a usable image.
    fileprivate init?(json: [String: Any]) {
        guard let raw = DyplinkNotificationContent.nonEmptyString(json["imageUrl"]),
              let url = URL(string: raw)
        else { return nil }

        self.imageUrl = url
        self.caption = DyplinkNotificationContent.nonEmptyString(json["caption"])
        self.deepLinkUrl = DyplinkNotificationContent.nonEmptyString(json["deepLinkUrl"])
    }
}

extension PushTimer {

    /// `nil` for anything without an end time that can be counted down to.
    fileprivate init?(json: [String: Any]) {
        guard let raw = DyplinkNotificationContent.nonEmptyString(json["endsAt"]),
              let endsAt = PushTimer.parseDate(raw)
        else { return nil }

        self.endsAt = endsAt
        self.expiredTitle = DyplinkNotificationContent.nonEmptyString(json["expiredTitle"])
        self.expiredBody = DyplinkNotificationContent.nonEmptyString(json["expiredBody"])
    }

    /// Parses an ISO 8601 instant.
    ///
    /// Tried with fractional seconds and then without, because neither option
    /// parses the other's output and the backend produces both: a countdown
    /// serialized from a JavaScript `Date` carries milliseconds, while one
    /// typed into the campaign composer usually does not.
    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
#endif
