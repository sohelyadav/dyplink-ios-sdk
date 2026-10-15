import XCTest
import UserNotifications
@testable import DyplinkCore
@testable import DyplinkPush

/// Covers the campaign action buttons, which never appeared on iOS.
///
/// The server has always sent them — a JSON array under `dyplink_actions`,
/// the same key Android reads — and nothing in the iOS SDK ever read it, nor
/// built the `UNNotificationCategory` iOS draws buttons from. iOS cannot be
/// told about buttons in a payload; it draws the ones belonging to the
/// category the notification names, so a campaign whose buttons were
/// authored in the dashboard had nothing to name.
final class PushActionTests: XCTestCase {

    private func payload(_ actionsJson: String) -> [AnyHashable: Any] {
        ["dyplink_campaign_id": "camp-1", "dyplink_actions": actionsJson]
    }

    private let twoActions = #"""
    [{"id":"buy_now","title":"Buy now","deepLinkUrl":"myapp://cart"},
     {"id":"later","title":"Remind me later"}]
    """#

    // ── Reading the payload ────────────────────────────────────────────

    func testActionsAreReadFromTheDataKey() {
        let actions = DyplinkPushActions.actions(in: payload(twoActions))

        XCTAssertEqual(actions.map(\.id), ["buy_now", "later"])
        XCTAssertEqual(actions.map(\.title), ["Buy now", "Remind me later"])
        XCTAssertEqual(actions.first?.deepLinkUrl, "myapp://cart")
        // No destination of its own: the campaign's own deep link applies.
        XCTAssertNil(actions.last?.deepLinkUrl)
    }

    /// A payload decoded and re-encoded along the way arrives structured
    /// rather than as a string.
    func testAnAlreadyStructuredPayloadIsAccepted() {
        let actions = DyplinkPushActions.actions(in: [
            "dyplink_actions": [["id": "a", "title": "A"]],
        ])

        XCTAssertEqual(actions.map(\.id), ["a"])
    }

    func testAPushWithNoActionsHasNone() {
        XCTAssertTrue(DyplinkPushActions.actions(in: ["dyplink_campaign_id": "c"]).isEmpty)
    }

    /// A notification with no buttons is a smaller failure than no
    /// notification, so anything unreadable is dropped and the rest kept.
    func testUnusableActionsAreDroppedIndividually() {
        let actions = DyplinkPushActions.actions(in: payload(#"""
        [{"title":"No id"},
         {"id":"no_title"},
         {"id":"blank_title","title":"   "},
         {"id":42,"title":"Not a string id"},
         {"id":"good","title":"Good"}]
        """#))

        XCTAssertEqual(actions.map(\.id), ["good"])
    }

    func testAMalformedActionsPayloadYieldsNoActions() {
        for raw in ["", "not json", "{}", #"{"actions":[]}"#, "[]"] {
            XCTAssertTrue(
                DyplinkPushActions.actions(in: payload(raw)).isEmpty,
                "expected no actions for \(raw)"
            )
        }
    }

    /// iOS draws at most four and silently ignores the rest, so the ones it
    /// would keep are the ones registered.
    func testNoMoreActionsAreKeptThanIosWillDraw() {
        let many = (1...8).map { #"{"id":"a\#($0)","title":"A\#($0)"}"# }.joined(separator: ",")
        let actions = DyplinkPushActions.actions(in: payload("[\(many)]"))

        XCTAssertEqual(actions.count, DyplinkPushActions.maxActions)
        XCTAssertEqual(actions.map(\.id), ["a1", "a2", "a3", "a4"])
    }

    /// Two buttons sharing an id would be one button as far as a report is
    /// concerned, and iOS keeps only the last of them.
    func testADuplicateIdDoesNotSpendASlot() {
        let actions = DyplinkPushActions.actions(in: payload(#"""
        [{"id":"a","title":"First"},{"id":"a","title":"Second"},{"id":"b","title":"Other"}]
        """#))

        XCTAssertEqual(actions.map(\.id), ["a", "b"])
        XCTAssertEqual(actions.first?.title, "First")
    }

    func testTheActionBehindAnIdCanBeFound() {
        let found = DyplinkPushActions.action(withId: "buy_now", in: payload(twoActions))

        XCTAssertEqual(found?.deepLinkUrl, "myapp://cart")
        XCTAssertNil(DyplinkPushActions.action(withId: "nope", in: payload(twoActions)))
    }

    // ── The category ───────────────────────────────────────────────────

    func testTheCategoryCarriesOneActionPerButton() {
        let actions = DyplinkPushActions.actions(in: payload(twoActions))
        let category = DyplinkPushActions.makeCategory(for: actions)

        XCTAssertEqual(category.actions.map(\.identifier), ["buy_now", "later"])
        XCTAssertEqual(category.actions.map(\.title), ["Buy now", "Remind me later"])
        // Every button leads somewhere, so every one of them opens the app.
        XCTAssertTrue(category.actions.allSatisfy { $0.options.contains(.foreground) })
        XCTAssertTrue(category.identifier.hasPrefix(DyplinkPushActions.categoryIdentifierPrefix))
    }

    /// Registering the same buttons again must land on the same category
    /// rather than accumulate one per notification.
    func testTheSameButtonsGiveTheSameCategoryIdentifier() {
        let first = DyplinkPushActions.actions(in: payload(twoActions))
        let second = DyplinkPushActions.actions(in: payload(twoActions))

        XCTAssertEqual(
            DyplinkPushActions.categoryIdentifier(for: first),
            DyplinkPushActions.categoryIdentifier(for: second)
        )
    }

    /// And two campaigns in flight at once must not share one: the second
    /// registration would re-letter the first notification's buttons while
    /// it sat in the shade.
    func testDifferentButtonsGiveDifferentCategoryIdentifiers() {
        let a = DyplinkPushActions.actions(in: payload(twoActions))
        let b = DyplinkPushActions.actions(in: payload(#"[{"id":"buy_now","title":"Order now"}]"#))

        XCTAssertNotEqual(
            DyplinkPushActions.categoryIdentifier(for: a),
            DyplinkPushActions.categoryIdentifier(for: b)
        )
    }

    // ── Registering it ─────────────────────────────────────────────────

    /// The host app's own categories must survive. Replacing the set
    /// outright would delete the ones it registered at launch, and its own
    /// notifications would lose their buttons — a worse bug than this one.
    func testRegisteringKeepsTheHostAppsOwnCategories() {
        let hostCategory = UNNotificationCategory(
            identifier: "HOST_APP_MESSAGE",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let registry = RegistrySpy(categories: [hostCategory])
        let actions = DyplinkPushActions.actions(in: payload(twoActions))

        var registered: String?
        DyplinkPushActions.registerCategory(for: actions, registry: registry) { registered = $0 }

        XCTAssertNotNil(registered)
        XCTAssertTrue(registry.categories.contains(hostCategory))
        XCTAssertEqual(registry.categories.count, 2)
    }

    func testRegisteringTheSameButtonsTwiceLeavesOneCategory() {
        let registry = RegistrySpy(categories: [])
        let actions = DyplinkPushActions.actions(in: payload(twoActions))

        DyplinkPushActions.registerCategory(for: actions, registry: registry) { _ in }
        DyplinkPushActions.registerCategory(for: actions, registry: registry) { _ in }

        XCTAssertEqual(registry.categories.count, 1)
    }

    // ── Coexisting with a campaign's own category ──────────────────────

    /// A campaign carrying **both** an `iosCategory` and buttons.
    ///
    /// A notification has exactly one category identifier; a content
    /// extension is matched against that string, and the buttons belong to
    /// whichever category object is registered under it. So minting an
    /// identifier of our own and overwriting the campaign's matched no
    /// content extension at all — the carousel or countdown it names
    /// vanished, traded silently for the buttons. Registering the buttons
    /// onto the campaign's identifier is what lets both happen.
    func testACampaignsOwnCategorySurvivesHavingButtonsAttached() {
        let registry = RegistrySpy(categories: [])
        let actions = DyplinkPushActions.actions(in: payload(twoActions))

        var registered: String?
        DyplinkPushActions.registerCategory(
            for: actions,
            preferredIdentifier: "DYPLINK_CAROUSEL",
            registry: registry
        ) { registered = $0 }

        // The identifier the notification keeps naming, so the content
        // extension still matches it.
        XCTAssertEqual(registered, "DYPLINK_CAROUSEL")
        XCTAssertFalse(
            registered?.hasPrefix(DyplinkPushActions.categoryIdentifierPrefix) ?? true,
            "overwrote the campaign's category with one of ours"
        )
        // And the buttons are on it.
        let category = registry.categories.first { $0.identifier == "DYPLINK_CAROUSEL" }
        XCTAssertEqual(category?.actions.map(\.identifier), ["buy_now", "later"])
        XCTAssertEqual(registry.categories.count, 1)
    }

    /// Only the category's *actions* are ours to decide. Everything else the
    /// host app registered under that identifier has to come through.
    func testTheHostAppsOwnCategorySettingsAreCarriedOver() throws {
        let hostCategory = UNNotificationCategory(
            identifier: "DYPLINK_CAROUSEL",
            actions: [],
            intentIdentifiers: ["INSendMessageIntent"],
            hiddenPreviewsBodyPlaceholder: "A new offer",
            categorySummaryFormat: "%u more offers",
            options: [.customDismissAction]
        )
        let registry = RegistrySpy(categories: [hostCategory])

        DyplinkPushActions.registerCategory(
            for: DyplinkPushActions.actions(in: payload(twoActions)),
            preferredIdentifier: "DYPLINK_CAROUSEL",
            registry: registry
        ) { _ in }

        let category = try XCTUnwrap(registry.categories.first { $0.identifier == "DYPLINK_CAROUSEL" })
        XCTAssertEqual(category.actions.count, 2)
        XCTAssertEqual(category.intentIdentifiers, ["INSendMessageIntent"])
        XCTAssertTrue(category.options.contains(.customDismissAction))
        XCTAssertEqual(category.hiddenPreviewsBodyPlaceholder, "A new offer")
        XCTAssertEqual(category.categorySummaryFormat, "%u more offers")
    }

    /// With no `aps.category` there is nothing else for the notification to
    /// name, so the hashed identifier stands. That path was already right.
    func testACampaignWithNoCategoryOfItsOwnGetsTheHashedIdentifier() {
        let registry = RegistrySpy(categories: [])
        let actions = DyplinkPushActions.actions(in: payload(twoActions))

        for preferred in [nil, "", "   "] as [String?] {
            var registered: String?
            DyplinkPushActions.registerCategory(
                for: actions,
                preferredIdentifier: preferred,
                registry: registry
            ) { registered = $0 }

            XCTAssertEqual(registered, DyplinkPushActions.categoryIdentifier(for: actions))
        }
    }

    /// `content.categoryIdentifier` is `""` for a payload with no
    /// `aps.category`, not nil — registering under `""` would attach the
    /// buttons to nothing.
    func testAnAbsentCategoryIsTheEmptyStringNotNil() {
        XCTAssertNil(DyplinkPushActions.usableIdentifier(""))
        XCTAssertNil(DyplinkPushActions.usableIdentifier("   "))
        XCTAssertNil(DyplinkPushActions.usableIdentifier(nil))
        XCTAssertEqual(DyplinkPushActions.usableIdentifier("  PROMO\n"), "PROMO")
    }

    func testThereIsNothingToRegisterForAPushWithNoButtons() {
        let registry = RegistrySpy(categories: [])

        var called = false
        var registered: String? = "unset"
        DyplinkPushActions.registerCategory(for: [], registry: registry) {
            called = true
            registered = $0
        }

        XCTAssertTrue(called, "the handler must run on every path")
        XCTAssertNil(registered)
        XCTAssertTrue(registry.categories.isEmpty)
        XCTAssertFalse(registry.didSet, "touched the category set for nothing")
    }
}

/// Stands in for `UNUserNotificationCenter`, which cannot be constructed and
/// traps when reached for from a test bundle with no host app.
private final class RegistrySpy: NotificationCategoryRegistry {
    private(set) var categories: Set<UNNotificationCategory>
    private(set) var didSet = false

    init(categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func getNotificationCategories(
        completionHandler: @escaping (Set<UNNotificationCategory>) -> Void
    ) {
        completionHandler(categories)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        didSet = true
        self.categories = categories
    }
}
