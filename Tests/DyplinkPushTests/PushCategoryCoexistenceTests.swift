import XCTest
import UserNotifications
@testable import DyplinkPush

/// Covers a campaign that carries **both** a category of its own and action
/// buttons, driven through `DyplinkNotificationService.populate` the way the
/// host app's extension calls it.
///
/// A notification has exactly one category identifier. iOS draws the buttons
/// of whichever category object is registered under it, and matches a
/// notification **content** extension by comparing that same string against
/// the `UNNotificationExtensionCategory` compiled into the extension's
/// `Info.plist`. So registering buttons under an identifier of this SDK's
/// own and overwriting the campaign's broke the second mechanism to serve
/// the first: the carousel or countdown the campaign named silently stopped
/// rendering, and the notification arrived as an ordinary one.
///
/// Both work because only the identifier is contended: the buttons go onto
/// the category the campaign already names.
final class PushCategoryCoexistenceTests: XCTestCase {

    private let actionsJson = #"""
    [{"id":"buy_now","title":"Buy now","deepLinkUrl":"myapp://cart"},
     {"id":"later","title":"Remind me later"}]
    """#

    override func tearDown() {
        StubURLProtocol.stopIntercepting()
        super.tearDown()
    }

    /// `aps.category` reaches an extension as `content.categoryIdentifier`.
    private func makeRequest(
        category: String?,
        actions: String?,
        imageUrl: String? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Sale"
        content.body = "50% off everything"
        var userInfo: [AnyHashable: Any] = ["dyplink_campaign_id": "camp-1"]
        if let actions = actions { userInfo["dyplink_actions"] = actions }
        if let imageUrl = imageUrl { userInfo["dyplink_image_url"] = imageUrl }
        content.userInfo = userInfo
        if let category = category { content.categoryIdentifier = category }
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    /// Runs `populate` against `registry` and returns the delivered content.
    private func deliver(
        _ request: UNNotificationRequest,
        registry: RegistrySpy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UNNotificationContent {
        let delivered = Box<UNNotificationContent?>(nil)
        let called = expectation(description: "content handler called")

        DyplinkNotificationService.populate(request, registry: registry) { content in
            delivered.value = content
            called.fulfill()
        }

        // Generous: a passing test never waits, and the image path builds a
        // real PNG and goes through the URL loading system, which on a cold
        // first run has been seen to take longer than a tight limit allows.
        wait(for: [called], timeout: 15)
        return try XCTUnwrap(delivered.value, file: file, line: line)
    }

    // ── The combination ────────────────────────────────────────────────

    /// The whole conflict in one test: a carousel campaign that also has
    /// buttons keeps the category its content extension is matched on, and
    /// gets the buttons too.
    func testACarouselCampaignWithButtonsKeepsItsCategoryAndGetsTheButtons() throws {
        // The category the host app's content extension declares.
        let hostCategory = UNNotificationCategory(
            identifier: "DYPLINK_CAROUSEL",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let registry = RegistrySpy(categories: [hostCategory])
        let request = makeRequest(category: "DYPLINK_CAROUSEL", actions: actionsJson)

        let content = try deliver(request, registry: registry)

        // What the content extension is matched on, unchanged. This is the
        // assertion the defect broke: it used to be `dyplink.actions.<hash>`.
        XCTAssertEqual(content.categoryIdentifier, "DYPLINK_CAROUSEL")
        // And the buttons iOS will draw are on that same category.
        let registered = try XCTUnwrap(
            registry.categories.first { $0.identifier == "DYPLINK_CAROUSEL" }
        )
        XCTAssertEqual(registered.actions.map(\.identifier), ["buy_now", "later"])
        XCTAssertEqual(registered.actions.map(\.title), ["Buy now", "Remind me later"])
        // Nothing of this SDK's own was registered beside it.
        XCTAssertFalse(
            registry.categories.contains { $0.identifier.hasPrefix(DyplinkPushActions.categoryIdentifierPrefix) },
            "minted a category of our own as well"
        )
        XCTAssertEqual(registry.categories.count, 1)
    }

    /// Image, buttons and a category at once — the three mechanisms are
    /// independent and the extension does all of it in one pass.
    func testACampaignWithACategoryButtonsAndAnImageKeepsAllThree() throws {
        StubURLProtocol.respond { _ in
            .success(
                statusCode: 200,
                headerFields: ["Content-Type": "image/png"],
                body: Self.pngData()
            )
        }
        let registry = RegistrySpy(categories: [])
        let request = makeRequest(
            category: "DYPLINK_TIMER",
            actions: actionsJson,
            imageUrl: "https://cdn.test/campaign.png"
        )

        let content = try deliver(request, registry: registry)

        XCTAssertEqual(content.categoryIdentifier, "DYPLINK_TIMER")
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(
            registry.categories.first { $0.identifier == "DYPLINK_TIMER" }?.actions.count,
            2
        )
        // The rest of the notification survived the mutable copy.
        XCTAssertEqual(content.title, "Sale")
        XCTAssertEqual(content.userInfo["dyplink_campaign_id"] as? String, "camp-1")
    }

    // ── The paths that must not change ─────────────────────────────────

    /// With no category of its own, the hashed identifier is the only thing
    /// the notification can name. That path was already correct.
    func testACampaignWithButtonsAndNoCategoryIsNamedOntoOurOwn() throws {
        let registry = RegistrySpy(categories: [])
        let request = makeRequest(category: nil, actions: actionsJson)

        let content = try deliver(request, registry: registry)

        XCTAssertTrue(content.categoryIdentifier.hasPrefix(DyplinkPushActions.categoryIdentifierPrefix))
        XCTAssertEqual(registry.categories.count, 1)
        XCTAssertEqual(registry.categories.first?.actions.count, 2)
    }

    /// A carousel campaign with no buttons must be left completely alone —
    /// its category is the only thing making its content extension run.
    func testACategoryWithNoButtonsIsLeftUntouched() throws {
        let registry = RegistrySpy(categories: [])
        let request = makeRequest(category: "DYPLINK_CAROUSEL", actions: nil)
        let original = request.content

        let content = try deliver(request, registry: registry)

        XCTAssertTrue(content === original, "copied a notification it had nothing to add to")
        XCTAssertEqual(content.categoryIdentifier, "DYPLINK_CAROUSEL")
        XCTAssertFalse(registry.didSet, "touched the category set for a push with no buttons")
    }

    /// A malformed actions payload is no reason to disturb the category.
    func testAMalformedActionsPayloadLeavesTheCategoryAlone() throws {
        let registry = RegistrySpy(categories: [])
        let request = makeRequest(category: "DYPLINK_CAROUSEL", actions: "not json")

        let content = try deliver(request, registry: registry)

        XCTAssertEqual(content.categoryIdentifier, "DYPLINK_CAROUSEL")
        XCTAssertFalse(registry.didSet)
    }

    private static func pngData() -> Data {
        // `UNNotificationAttachment` validates the bytes, not just the name.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData()!
    }
}

/// Stands in for `UNUserNotificationCenter`, which cannot be constructed and
/// traps when reached for from a test bundle with no host app.
private final class RegistrySpy: NotificationCategoryRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Set<UNNotificationCategory>
    private var _didSet = false

    init(categories: Set<UNNotificationCategory>) {
        stored = categories
    }

    var categories: Set<UNNotificationCategory> {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var didSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return _didSet
    }

    func getNotificationCategories(
        completionHandler: @escaping @Sendable (Set<UNNotificationCategory>) -> Void
    ) {
        completionHandler(categories)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        lock.lock()
        _didSet = true
        stored = categories
        lock.unlock()
    }
}

/// Lets a test read a value written from the URL loading system's thread.
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
