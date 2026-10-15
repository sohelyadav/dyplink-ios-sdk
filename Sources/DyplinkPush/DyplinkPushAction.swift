import Foundation
import UserNotifications

/// One button under a push notification.
///
/// Mirrors `PushAction` on the backend, which sends them as a JSON array
/// under the `dyplink_actions` data key.
public struct DyplinkPushAction: Sendable, Equatable {

    /// Reported back with the click, so "pressed Buy now" can be told from
    /// "tapped the notification".
    public let id: String

    /// The button's label.
    public let title: String

    /// Where this button leads, exactly as the campaign sent it. `nil` means
    /// it has no destination of its own and the campaign's own deep link —
    /// the `deep_link_url` key — applies.
    public let deepLinkUrl: String?
}

/// Builds the `UNNotificationCategory` a push campaign's buttons need.
///
/// ## Why this is not simply a payload field
///
/// Android renders buttons straight from the notification it builds. iOS
/// cannot: it draws the buttons belonging to the category named by
/// `aps.category`, and a payload cannot define a category — only name one
/// that is already registered. So a campaign whose buttons are authored in
/// the dashboard has nothing to name, which is why `dyplink_actions` arrived
/// on every iOS device and no iOS device ever drew a button.
///
/// The way out is the one Notification Service Extensions exist for:
/// register a category built from the payload, then point the notification
/// at it, both while the push is in flight. That is what
/// `DyplinkNotificationService` does with this.
///
/// ## What the host app must do
///
/// Nothing beyond what an image already needs — the Notification Service
/// Extension described on `DyplinkNotificationService`. One server-side
/// requirement comes with it: `aps` must carry `mutable-content: 1`, since
/// without it iOS never wakes an extension, and a campaign whose buttons
/// never reach a category shows none.
internal enum DyplinkPushActions {

    /// Data key carrying the campaign's buttons. Matches `ACTIONS_DATA_KEY`
    /// on the backend, and sits at the top level of the payload, so it
    /// arrives in `userInfo` unchanged.
    internal static let actionsKey = "dyplink_actions"

    /// How many iOS will draw. Beyond this the system silently ignores them,
    /// so the ones it would keep are the ones worth registering. Android's
    /// own handler caps at three for the same reason.
    internal static let maxActions = 4

    // ── Payload ────────────────────────────────────────────────────────

    /// Reads the campaign's buttons out of a notification payload.
    ///
    /// Buttons that are not usable are dropped individually — an id and a
    /// title are both required, because a button with no id cannot be
    /// attributed and one with no title has nothing to show.
    internal static func actions(in userInfo: [AnyHashable: Any]) -> [DyplinkPushAction] {
        guard let array = jsonValue(userInfo[actionsKey]) as? [Any] else { return [] }
        return array
            .compactMap { $0 as? [String: Any] }
            .compactMap(DyplinkPushAction.init(json:))
            .reduce(into: [DyplinkPushAction]()) { kept, action in
                // Two buttons sharing an id would be one button as far as a
                // report is concerned, and iOS keeps only the last of them —
                // so a duplicate is dropped rather than spending a slot.
                guard kept.count < maxActions,
                      !kept.contains(where: { $0.id == action.id })
                else { return }
                kept.append(action)
            }
    }

    /// The button with `id`, if the payload carries one — the per-action
    /// deep link lives only here, so a tap has to come back for it.
    internal static func action(withId id: String, in userInfo: [AnyHashable: Any]) -> DyplinkPushAction? {
        actions(in: userInfo).first { $0.id == id }
    }

    /// Decodes the actions key.
    ///
    /// It travels as a JSON string, because APNs data values are strings —
    /// but a payload decoded and re-encoded somewhere along the way can
    /// arrive already structured, so an array is accepted as it stands.
    private static func jsonValue(_ value: Any?) -> Any? {
        guard let string = value as? String else { return value }
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // ── Category ───────────────────────────────────────────────────────

    /// Registers a category carrying `actions` and answers the identifier the
    /// notification should name, or `nil` when there are no usable buttons.
    ///
    /// ## Which identifier
    ///
    /// `preferredIdentifier` — the campaign's own `aps.category` — wins when
    /// it has one, and the buttons are registered *onto* it rather than onto
    /// an identifier of this SDK's own. That is the whole of the fix for a
    /// campaign carrying both a category and buttons: a notification has
    /// exactly one category identifier, a content extension is matched
    /// against that string (`UNNotificationExtensionCategory` in its
    /// `Info.plist`), and the buttons are a property of whichever category
    /// object is registered under it. Minting an identifier of our own and
    /// overwriting the campaign's therefore matched no content extension,
    /// and the carousel or countdown it names simply vanished — the richer
    /// content traded away for the buttons, silently.
    ///
    /// With no `aps.category` the hashed identifier is used, which is the
    /// only option: there is nothing else for the notification to name.
    ///
    /// ## What is preserved
    ///
    /// The host app's other categories, read first and kept — replacing the
    /// set outright would delete every category an app registered at launch.
    /// And when the identifier is already registered, that category's own
    /// `intentIdentifiers`, options and hidden-preview copy are carried over
    /// onto the new one, since only its actions are ours to decide.
    ///
    /// One consequence worth knowing: a category is app-wide, so attaching a
    /// campaign's buttons to an identifier the host app also uses for its own
    /// notifications gives those notifications the same buttons until
    /// something re-registers it. An identifier a campaign names is in
    /// practice a Dyplink-specific one, and the alternative — dropping the
    /// buttons — loses something the campaign explicitly asked for.
    internal static func registerCategory(
        for actions: [DyplinkPushAction],
        preferredIdentifier: String? = nil,
        registry: NotificationCategoryRegistry? = nil,
        completion: @escaping (String?) -> Void
    ) {
        guard !actions.isEmpty else {
            completion(nil)
            return
        }

        // `.current()` is reached only here, and only for a push that
        // actually carries buttons: it traps in a bundle with no host app,
        // and a plain notification must never wake the notification centre
        // for nothing.
        let registry = registry ?? UNUserNotificationCenter.current()
        let identifier = usableIdentifier(preferredIdentifier) ?? categoryIdentifier(for: actions)

        registry.getNotificationCategories { existing in
            let previous = existing.first { $0.identifier == identifier }
            let category = makeCategory(for: actions, identifier: identifier, inheriting: previous)
            // Keyed by identifier, so re-registering the same buttons
            // replaces that category rather than accumulating duplicates.
            var categories = existing.filter { $0.identifier != identifier }
            categories.insert(category)
            registry.setNotificationCategories(categories)
            completion(identifier)
        }
    }

    /// The category a campaign named, or `nil` when it named none.
    ///
    /// `UNNotificationContent.categoryIdentifier` is the empty string for a
    /// payload with no `aps.category`, not `nil`, and registering buttons
    /// under `""` would attach them to nothing.
    internal static func usableIdentifier(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// The category iOS draws `actions` from, under an identifier of this
    /// SDK's own. The shape a campaign with no `aps.category` gets.
    internal static func makeCategory(for actions: [DyplinkPushAction]) -> UNNotificationCategory {
        makeCategory(for: actions, identifier: categoryIdentifier(for: actions), inheriting: nil)
    }

    /// The category iOS draws `actions` from, under `identifier`, keeping
    /// everything about `previous` that is not ours to decide.
    internal static func makeCategory(
        for actions: [DyplinkPushAction],
        identifier: String,
        inheriting previous: UNNotificationCategory?
    ) -> UNNotificationCategory {
        let notificationActions = actions.map { action in
            // `.foreground` because every button leads somewhere: a
            // destination of its own, or the campaign's. A background action
            // would report the tap and leave the user where they were.
            UNNotificationAction(
                identifier: action.id,
                title: action.title,
                options: [.foreground]
            )
        }

        let intentIdentifiers = previous?.intentIdentifiers ?? []
        let options = previous?.options ?? []

        // The richer initializer only where there is something to carry: the
        // placeholder is what shows with previews hidden, and passing an
        // empty string would replace the system's own wording with nothing.
        if let placeholder = previous?.hiddenPreviewsBodyPlaceholder {
            if let summary = previous?.categorySummaryFormat {
                return UNNotificationCategory(
                    identifier: identifier,
                    actions: notificationActions,
                    intentIdentifiers: intentIdentifiers,
                    hiddenPreviewsBodyPlaceholder: placeholder,
                    categorySummaryFormat: summary,
                    options: options
                )
            }
            return UNNotificationCategory(
                identifier: identifier,
                actions: notificationActions,
                intentIdentifiers: intentIdentifiers,
                hiddenPreviewsBodyPlaceholder: placeholder,
                options: options
            )
        }

        return UNNotificationCategory(
            identifier: identifier,
            actions: notificationActions,
            intentIdentifiers: intentIdentifiers,
            options: options
        )
    }

    /// A category identifier derived from the buttons themselves.
    ///
    /// Deliberately not one fixed identifier: two campaigns in flight at
    /// once would share it, and the second registration would re-letter the
    /// first notification's buttons while it sat in the shade. Deriving it
    /// from the contents makes the same buttons the same category — so
    /// registering is idempotent — and different buttons a different one.
    ///
    /// Hashed by hand rather than with `Hashable`, whose seed changes every
    /// launch: the notification naming this category is drawn by the system
    /// in another process, and may still be on screen after the next launch.
    internal static func categoryIdentifier(for actions: [DyplinkPushAction]) -> String {
        let seed = actions.map { "\($0.id)\u{1F}\($0.title)" }.joined(separator: "\u{1E}")
        return "\(categoryIdentifierPrefix)\(String(fnv1a(seed), radix: 16))"
    }

    /// Namespaced, so the set this SDK manages can never be mistaken for one
    /// the host app registered itself.
    internal static let categoryIdentifierPrefix = "dyplink.actions."

    /// FNV-1a, 64-bit: stable across processes and launches, which is the
    /// only property needed of it here.
    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(text.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}

// MARK: - Registry

/// Where registered notification categories live.
///
/// `UNUserNotificationCenter` already satisfies this; it exists so the part
/// worth testing — that the host app's own categories survive the
/// registration — can be. `UNUserNotificationCenter` cannot be constructed,
/// and `current()` traps in a test bundle that has no host app.
internal protocol NotificationCategoryRegistry {
    /// `@Sendable` to match `UNUserNotificationCenter`'s own signature,
    /// which hands the categories back on a queue of its own choosing.
    func getNotificationCategories(
        completionHandler: @escaping @Sendable (Set<UNNotificationCategory>) -> Void
    )
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

extension UNUserNotificationCenter: NotificationCategoryRegistry {}

// MARK: - Parsing

extension DyplinkPushAction {

    /// `nil` for anything that is not a button that can be drawn and
    /// attributed.
    fileprivate init?(json: [String: Any]) {
        guard let id = Self.nonEmptyString(json["id"]),
              let title = Self.nonEmptyString(json["title"])
        else { return nil }

        self.id = id
        self.title = title
        self.deepLinkUrl = Self.nonEmptyString(json["deepLinkUrl"])
    }

    /// Trims a payload string and rejects it when nothing is left: a title of
    /// `"   "` is a button with no label, not a button labelled with spaces.
    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
