import Foundation
import UserNotifications

/// Attaches a push campaign's image to the notification before iOS shows it.
///
/// APNs has no image field. The only way a campaign's picture reaches the
/// notification is a Notification Service Extension in the host app, which
/// downloads it and attaches it while the push is in flight — this is the
/// work Firebase's `FIRMessagingExtensionHelper` does for FCM. A library
/// can't ship an app extension, so the target has to be the app's; none of
/// the download, file-type and attachment logic below has to be.
///
/// The backend already sends the other half: a campaign with an image sets
/// `"mutable-content": 1` in `aps` — without which iOS never wakes an
/// extension at all — and carries the picture's URL in `dyplink_image_url`
/// at the top level of the payload.
///
/// Add a "Notification Service Extension" target to the app, link
/// `DyplinkPush` to it, and replace the body of the template's
/// `NotificationService` with a single call:
///
/// ```swift
/// import UserNotifications
/// import DyplinkPush
///
/// class NotificationService: UNNotificationServiceExtension {
///     override func didReceive(_ request: UNNotificationRequest,
///                              withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
///         DyplinkNotificationService.populate(request, withContentHandler: handler)
///     }
/// }
/// ```
///
/// Two properties of the target itself decide whether the extension is ever
/// run, and both fail silently — the push simply arrives without its image:
///
/// - Its bundle id must be the app's with a suffix appended, e.g.
///   `com.example.app.NotificationService` for an app id of `com.example.app`.
/// - Its deployment target must not be higher than the app's, or devices on
///   older iOS versions install the app without the extension.
public enum DyplinkNotificationService {

    /// Key under which a Dyplink campaign carries its image URL. Matches
    /// `IMAGE_DATA_KEY` on the backend, and sits at the top level of the
    /// payload, so it arrives in `userInfo` unchanged.
    private static let imageUrlKey = "dyplink_image_url"

    /// iOS allows a service extension roughly 30 seconds before
    /// `serviceExtensionTimeWillExpire` fires and the system delivers the
    /// unmodified notification over our heads. Stopping well short of that
    /// leaves room to write the file and build the attachment, so a slow
    /// image is abandoned on our terms rather than truncated on the OS's.
    private static let downloadTimeout: TimeInterval = 20

    /// Only one attachment is ever added, so a constant identifier is enough.
    private static let attachmentIdentifier = "dyplink_image"

    /// The image types `UNNotificationAttachment` accepts, keyed by the
    /// `Content-Type` a server sends for them.
    private static let fileExtensionsByMimeType: [String: String] = [
        "image/jpeg": "jpg",
        "image/jpg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/heic": "heic",
        "image/heif": "heif",
    ]

    /// The same set as extensions a URL may already carry.
    private static let supportedFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif",
    ]

    // ── Entry point ────────────────────────────────────────────────────

    /// Attaches the campaign's image to `request`'s content, if the payload
    /// carries one, and hands the result to `contentHandler`.
    ///
    /// Call this from `didReceive(_:withContentHandler:)` and do nothing
    /// else — the handler is invoked exactly once on every path, including
    /// each of the ones that give up.
    ///
    /// A push with no `dyplink_image_url` is passed straight through without
    /// waiting on anything, and any failure along the way — an unreachable
    /// host, a timeout, a response that isn't an image, an attachment the OS
    /// rejects — delivers the original notification untouched.
    public static func populate(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let delivery = ContentDelivery(original: request.content, handler: contentHandler)

        // Most pushes carry no image at all. Holding one back while an
        // extension we have nothing to add for wakes up and starts a network
        // stack is worse than not running an extension in the first place,
        // so this path never leaves the calling thread.
        guard let imageUrl = imageUrl(in: request.content.userInfo) else {
            delivery.deliverOriginal()
            return
        }

        var downloadRequest = URLRequest(url: imageUrl)
        downloadRequest.timeoutInterval = downloadTimeout

        URLSession.shared.dataTask(with: downloadRequest) { data, response, _ in
            guard let attachment = makeAttachment(data: data, response: response, url: imageUrl),
                  let content = delivery.mutableCopyOfOriginal()
            else {
                delivery.deliverOriginal()
                return
            }

            content.attachments = [attachment]
            delivery.deliver(content)
        }.resume()
    }

    // ── Payload ────────────────────────────────────────────────────────

    /// Reads the campaign's image URL out of the notification payload.
    private static func imageUrl(in userInfo: [AnyHashable: Any]) -> URL? {
        // `userInfo` comes from the OS untyped — the key may be absent or
        // hold something other than the string we expect.
        guard let raw = userInfo[imageUrlKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    // ── Attachment ─────────────────────────────────────────────────────

    /// Writes a downloaded image to a temporary file and wraps it in an
    /// attachment. `nil` for anything that isn't a usable image, which the
    /// caller turns back into the original notification.
    private static func makeAttachment(
        data: Data?,
        response: URLResponse?,
        url: URL
    ) -> UNNotificationAttachment? {
        guard let data = data, !data.isEmpty else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard let fileExtension = attachmentFileExtension(response: response, url: url) else {
            return nil
        }

        let fileUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("dyplink-push-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        do {
            try data.write(to: fileUrl)
            // Succeeds and the OS takes the file over; fails and nothing
            // else will ever look at it, so don't leave it in the container.
            return try UNNotificationAttachment(
                identifier: attachmentIdentifier,
                url: fileUrl,
                options: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: fileUrl)
            return nil
        }
    }

    /// `UNNotificationAttachment` infers an attachment's type from its file
    /// extension alone, and a campaign's image URL may carry none or carry a
    /// misleading one — a CDN path ending in a hash, say. The server's own
    /// `Content-Type` is the better answer wherever there is one; the URL is
    /// only the fallback. Getting this wrong is silent: the OS rejects the
    /// attachment and the picture never appears.
    private static func attachmentFileExtension(response: URLResponse?, url: URL) -> String? {
        if let mimeType = response?.mimeType?.lowercased() {
            if let known = fileExtensionsByMimeType[mimeType] { return known }
            // A server saying this is HTML is more trustworthy than a URL
            // ending in ".png" — an error page must not be attached as one.
            guard mimeType.hasPrefix("image/") else { return nil }
        }

        let urlExtension = url.pathExtension.lowercased()
        return supportedFileExtensions.contains(urlExtension) ? urlExtension : nil
    }
}

/// Holds the content handler and the notification it was given, so that
/// every path through `populate` ends in exactly one call.
///
/// Both halves matter in an app extension. Calling the handler twice traps,
/// and never calling it at all leaves the notification hanging until the
/// system's own deadline expires — while a picture that failed to download
/// costs the user nothing, so no error here is ever allowed to propagate.
private final class ContentDelivery: @unchecked Sendable {

    private let original: UNNotificationContent
    private let lock = NSLock()
    private var handler: ((UNNotificationContent) -> Void)?

    init(original: UNNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        self.original = original
        self.handler = handler
    }

    /// Deliver `content`, or do nothing if delivery already happened.
    func deliver(_ content: UNNotificationContent) {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()
        handler?(content)
    }

    /// The fallback every failure takes: show the notification as it arrived.
    func deliverOriginal() {
        deliver(original)
    }

    /// A mutable copy of the notification to attach the image to, or `nil`
    /// in the case the OS declines to give one.
    func mutableCopyOfOriginal() -> UNMutableNotificationContent? {
        original.mutableCopy() as? UNMutableNotificationContent
    }
}
