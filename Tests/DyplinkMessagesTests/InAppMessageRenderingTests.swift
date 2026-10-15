#if canImport(UIKit)
import XCTest
import UIKit
@testable import DyplinkMessages

/// The renderer used to be a `UIAlertController`: a centred system alert for
/// every message type, with no picture, no theme and no tap-outside. The
/// model had always parsed all of it — only the drawing was missing — so a
/// campaign's banner, its full-screen promo, its image and its colours were
/// settings the dashboard offered and the device ignored.
final class InAppMessageRenderingTests: XCTestCase {

    private func message(
        messageType: String = "modal",
        title: String = "Welcome",
        body: String? = "Glad you are here",
        imageUrl: String? = nil,
        imagePosition: String = "top",
        buttons: [MessageButton]? = nil,
        theme: MessageTheme? = nil,
        dismissOnTapOutside: Bool = true,
        autoDismissSeconds: Int? = nil
    ) -> InAppMessage {
        InAppMessage(
            id: "m1",
            messageType: messageType,
            title: title,
            body: body,
            imageUrl: imageUrl,
            imagePosition: imagePosition,
            buttons: buttons,
            theme: theme,
            dismissOnTapOutside: dismissOnTapOutside,
            autoDismissSeconds: autoDismissSeconds,
            triggerDelay: 0
        )
    }

    private func button(_ id: String, _ action: String, style: String = "primary") -> MessageButton {
        MessageButton(id: id, text: id, action: action, actionUrl: "https://app.test/x", actionEvent: nil, style: style)
    }

    private func theme(
        background: String? = nil,
        title: String? = nil,
        text: String? = nil,
        primary: String? = nil,
        secondary: String? = nil,
        overlay: String? = nil,
        radius: Int? = nil,
        animation: String? = nil
    ) -> MessageTheme {
        MessageTheme(
            backgroundColor: background, textColor: text, titleColor: title,
            buttonPrimaryColor: primary, buttonSecondaryColor: secondary,
            overlayColor: overlay, borderRadius: radius, animation: animation
        )
    }

    private func card(_ message: InAppMessage, compact: Bool = false) -> InAppMessageView {
        InAppMessageView(message: message, compact: compact, onButtonTapped: { _ in })
    }

    private func stack(of view: InAppMessageView) throws -> UIStackView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? UIStackView }.first)
    }

    // ── The five layouts ───────────────────────────────────────────────

    func testEveryMessageTypeGetsItsOwnPlacement() {
        let placements: [(String, InAppMessagePresenter.Layout.Placement)] = [
            ("modal", .centre),
            ("bottom_sheet", .bottomSheet),
            ("fullscreen", .fullscreen),
            ("banner_top", .topBanner),
            ("banner_bottom", .bottomBanner),
        ]
        for (type, expected) in placements {
            XCTAssertEqual(
                InAppMessagePresenter.Layout(messageType: type).placement,
                expected,
                "\(type) was placed wrongly"
            )
        }
    }

    func testAnUnknownMessageTypeIsAModal() {
        // A type added to the API later must still show something.
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "carousel").placement, .centre)
    }

    func testOnlyBannersLetTheAppThrough() {
        for type in ["banner_top", "banner_bottom"] {
            XCTAssertFalse(
                InAppMessagePresenter.Layout(messageType: type).hasBackdrop,
                "\(type) would take the app over"
            )
        }
        for type in ["modal", "bottom_sheet", "fullscreen"] {
            XCTAssertTrue(InAppMessagePresenter.Layout(messageType: type).hasBackdrop)
        }
    }

    func testBannersAndSheetsGetTheSmallerPicture() {
        for type in ["banner_top", "banner_bottom", "bottom_sheet"] {
            XCTAssertTrue(InAppMessagePresenter.Layout(messageType: type).isCompact, type)
        }
        for type in ["modal", "fullscreen"] {
            XCTAssertFalse(InAppMessagePresenter.Layout(messageType: type).isCompact, type)
        }
    }

    func testEachLayoutArrivesFromTheRightDirection() {
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "banner_top").defaultAnimation, "slide_down")
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "banner_bottom").defaultAnimation, "slide_up")
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "bottom_sheet").defaultAnimation, "slide_up")
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "modal").defaultAnimation, "fade")
    }

    func testOnlyBannersLeaveOnTheirOwn() {
        // A banner has nothing to tap, so without this nothing would ever
        // close it. The 4s matches the Android SDK.
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "banner_top").defaultAutoDismissSeconds, 4)
        XCTAssertEqual(InAppMessagePresenter.Layout(messageType: "banner_bottom").defaultAutoDismissSeconds, 4)
        XCTAssertNil(InAppMessagePresenter.Layout(messageType: "modal").defaultAutoDismissSeconds)
        XCTAssertNil(InAppMessagePresenter.Layout(messageType: "bottom_sheet").defaultAutoDismissSeconds)
        XCTAssertNil(InAppMessagePresenter.Layout(messageType: "fullscreen").defaultAutoDismissSeconds)
    }

    // ── Image positions ────────────────────────────────────────────────

    func testAnImageAtTheTopSitsAboveTheTitle() throws {
        let view = card(message(imageUrl: "https://cdn.test/i.png", imagePosition: "top"))
        let arranged = try stack(of: view).arrangedSubviews

        XCTAssertTrue(arranged.first is UIImageView)
    }

    func testAnImageInTheCentreSitsAfterTheCopy() throws {
        let view = card(message(
            imageUrl: "https://cdn.test/i.png",
            imagePosition: "center",
            buttons: [button("ok", "dismiss")]
        ))
        let arranged = try stack(of: view).arrangedSubviews

        XCTAssertFalse(arranged.first is UIImageView)
        let imageIndex = try XCTUnwrap(arranged.firstIndex { $0 is UIImageView })
        let bodyIndex = try XCTUnwrap(arranged.lastIndex { $0 is UILabel })
        let buttonIndex = try XCTUnwrap(arranged.firstIndex { $0 is UIButton })
        XCTAssertGreaterThan(imageIndex, bodyIndex)
        XCTAssertLessThan(imageIndex, buttonIndex)
    }

    func testAnImageAsTheBackgroundGoesBehindTheCopy() throws {
        let view = card(message(imageUrl: "https://cdn.test/i.png", imagePosition: "background"))

        // Picture, scrim, then the copy's stack: three layers, in that order.
        XCTAssertEqual(view.subviews.count, 3)
        XCTAssertTrue(view.subviews[0] is UIImageView)
        XCTAssertTrue(view.subviews[2] is UIStackView)
        // It must not also be in the stack, or it would appear twice.
        XCTAssertFalse(try stack(of: view).arrangedSubviews.contains { $0 is UIImageView })
    }

    func testNoImageRendersNoImage() throws {
        let view = card(message(imageUrl: nil))

        XCTAssertFalse(view.subviews.contains { $0 is UIImageView })
        XCTAssertFalse(try stack(of: view).arrangedSubviews.contains { $0 is UIImageView })
    }

    func testAPictureStaysHiddenUntilItArrives() throws {
        // Otherwise a message whose image never loads has a gap in it.
        let view = card(message(imageUrl: "https://cdn.test/i.png", imagePosition: "top"))
        let image = try XCTUnwrap(try stack(of: view).arrangedSubviews.first as? UIImageView)

        XCTAssertTrue(image.isHidden)
        XCTAssertNil(image.image)
    }

    // ── Copy and buttons ───────────────────────────────────────────────

    func testCopyAndButtonsAreAllRendered() throws {
        let view = card(message(buttons: [button("yes", "deep_link"), button("no", "dismiss")]))
        let arranged = try stack(of: view).arrangedSubviews

        XCTAssertEqual(arranged.compactMap { ($0 as? UILabel)?.text }, ["Welcome", "Glad you are here"])
        XCTAssertEqual(arranged.compactMap { ($0 as? UIButton)?.title(for: .normal) }, ["yes", "no"])
    }

    func testAMessageWithNoBodyRendersOnlyItsTitle() throws {
        let view = card(message(body: nil))

        XCTAssertEqual(try stack(of: view).arrangedSubviews.compactMap { ($0 as? UILabel)?.text }, ["Welcome"])
    }

    func testAnEmptyTitleIsNotRenderedAsABlankLine() throws {
        let view = card(message(title: "", body: "Only a body"))

        XCTAssertEqual(try stack(of: view).arrangedSubviews.compactMap { ($0 as? UILabel)?.text }, ["Only a body"])
    }

    func testTappingBubblesTheButtonBack() throws {
        var tapped: [String] = []
        let view = InAppMessageView(
            message: message(buttons: [button("go", "deep_link")]),
            compact: false,
            onButtonTapped: { tapped.append($0.id) }
        )
        let tap = try XCTUnwrap(try stack(of: view).arrangedSubviews.compactMap { $0 as? UIButton }.first)

        tap.sendActions(for: .touchUpInside)

        XCTAssertEqual(tapped, ["go"])
    }

    // ── Theme ──────────────────────────────────────────────────────────

    func testTheThemeDecidesEveryColourItSupplies() throws {
        let view = card(message(
            buttons: [button("a", "dismiss"), button("b", "dismiss", style: "secondary"), button("c", "dismiss", style: "text")],
            theme: theme(background: "#101828", title: "#FFFFFF", text: "#AAB7C4", primary: "#2563EB", secondary: "#E5E7EB")
        ))
        let arranged = try stack(of: view).arrangedSubviews
        let labels = arranged.compactMap { $0 as? UILabel }
        let buttons = arranged.compactMap { $0 as? UIButton }

        XCTAssertEqual(view.backgroundColor, UIColor(dyplinkHex: "#101828"))
        XCTAssertEqual(labels.first?.textColor, UIColor(dyplinkHex: "#FFFFFF"))
        XCTAssertEqual(labels.last?.textColor, UIColor(dyplinkHex: "#AAB7C4"))
        XCTAssertEqual(buttons[0].backgroundColor, UIColor(dyplinkHex: "#2563EB"))
        XCTAssertEqual(buttons[1].backgroundColor, UIColor(dyplinkHex: "#E5E7EB"))
        // A text button is the label alone, tinted with the primary colour.
        XCTAssertEqual(buttons[2].backgroundColor, .clear)
        XCTAssertEqual(buttons[2].titleColor(for: .normal), UIColor(dyplinkHex: "#2563EB"))
    }

    func testTheCornerRadiusReachesTheCard() {
        XCTAssertEqual(card(message(theme: theme(radius: 24))).layer.cornerRadius, 24)
        // 12 matches the Android SDK's default.
        XCTAssertEqual(card(message()).layer.cornerRadius, 12)
        XCTAssertEqual(card(message(theme: theme(radius: 0))).layer.cornerRadius, 0)
    }

    func testAMistypedColourFallsBackRatherThanDisappearing() throws {
        let view = card(message(
            buttons: [button("a", "dismiss")],
            theme: theme(background: "not a colour", title: "#", primary: "rgb(1,2,3)")
        ))
        let arranged = try stack(of: view).arrangedSubviews

        // A campaign with one mistyped colour must still be readable.
        XCTAssertEqual(view.backgroundColor, .systemBackground)
        XCTAssertEqual((arranged.first as? UILabel)?.textColor, .label)
        XCTAssertNotNil((arranged.compactMap { $0 as? UIButton }.first)?.backgroundColor)
    }

    // ── Colour parsing ─────────────────────────────────────────────────

    func testColourParsingAcceptsWhatTheDashboardEmits() {
        XCTAssertEqual(UIColor(dyplinkHex: "#FF0000"), UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(UIColor(dyplinkHex: "00FF00"), UIColor(red: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(UIColor(dyplinkHex: "#F00"), UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(UIColor(dyplinkHex: "  #0000FF  "), UIColor(red: 0, green: 0, blue: 1, alpha: 1))
        // `#AARRGGBB`, the form Android's Color.parseColor also takes.
        XCTAssertEqual(UIColor(dyplinkHex: "#80FF0000"), UIColor(red: 1, green: 0, blue: 0, alpha: 128.0 / 255))
    }

    func testColourParsingRefusesEverythingElse() {
        for input in [nil, "", "   ", "#", "#12", "#12345", "#1234567", "rgb(1,2,3)", "red", "#GGGGGG"] {
            XCTAssertNil(UIColor(dyplinkHex: input), "expected nil for \(input ?? "nil")")
        }
    }

    // ── The presenter without a scene ──────────────────────────────────

    @MainActor
    func testPresentingWithNoForegroundSceneDoesNothing() {
        // A test bundle has no scene, and neither does an app that went to
        // the background while the check was in flight. Either way the
        // message is skipped rather than crashing.
        var outcomes = 0
        let presenter = InAppMessagePresenter(message: message()) { _ in outcomes += 1 }

        presenter.present()

        XCTAssertFalse(presenter.isFinished)
        XCTAssertEqual(outcomes, 0)
    }
}
#endif

/// Where each layout actually lands once the constraints are resolved.
///
/// The structural tests above check which placement a message type gets;
/// these lay it out in a phone-sized container and check the frames, which
/// is the part a reader of the constraints cannot verify by eye. A test
/// bundle has no scene to present into, so the container is built here and
/// `Layout.constrain` — the same code the presenter calls — is applied to it.
final class InAppMessageLayoutTests: XCTestCase {

    /// An iPhone-ish container with a notch-ish safe area.
    private let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let safeInsets = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)

    private func laidOut(_ messageType: String) -> (host: UIView, card: UIView) {
        let host = SafeAreaStub(insets: safeInsets)
        host.frame = bounds

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        // Stands in for the copy, so the card has something to be as tall as.
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.heightAnchor.constraint(equalToConstant: 160),
        ])
        host.addSubview(card)

        InAppMessagePresenter.Layout(messageType: messageType).constrain(card: card, in: host)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        return (host, card)
    }

    func testATopBannerSitsUnderTheStatusBarNotBehindIt() {
        let (_, card) = laidOut("banner_top")

        // Below the safe-area top, or the notch eats the copy.
        XCTAssertGreaterThanOrEqual(card.frame.minY, safeInsets.top)
        XCTAssertLessThan(card.frame.minY, 100)
        // Inset from both edges, so it reads as a banner and not a bar.
        XCTAssertGreaterThan(card.frame.minX, 0)
        XCTAssertLessThan(card.frame.maxX, bounds.width)
    }

    func testABottomBannerSitsAboveTheHomeIndicator() {
        let (host, card) = laidOut("banner_bottom")

        XCTAssertLessThanOrEqual(card.frame.maxY, host.bounds.height - safeInsets.bottom)
        XCTAssertGreaterThan(card.frame.minY, bounds.height / 2)
    }

    func testAModalIsCentredAndDoesNotFillTheScreen() {
        let (host, card) = laidOut("modal")

        XCTAssertEqual(card.frame.midX, host.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(card.frame.midY, host.bounds.midY, accuracy: 0.5)
        XCTAssertLessThan(card.frame.height, host.bounds.height)
        XCTAssertGreaterThan(card.frame.width, 200)
        XCTAssertLessThan(card.frame.width, host.bounds.width)
    }

    func testASheetIsPinnedToTheBottomEdgeAndFullWidth() {
        let (host, card) = laidOut("bottom_sheet")

        XCTAssertEqual(card.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(card.frame.width, host.bounds.width, accuracy: 0.5)
        // Past the bottom edge, so only its top corners are rounded.
        XCTAssertGreaterThanOrEqual(card.frame.maxY, host.bounds.height)
    }

    func testFullscreenFillsEverything() {
        let (host, card) = laidOut("fullscreen")

        XCTAssertEqual(card.frame, host.bounds)
    }

    func testAWideScreenDoesNotStretchTheModalAcrossIt() {
        let host = SafeAreaStub(insets: .zero)
        host.frame = CGRect(x: 0, y: 0, width: 1194, height: 834) // iPad landscape
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 160).isActive = true
        host.addSubview(card)

        InAppMessagePresenter.Layout(messageType: "modal").constrain(card: card, in: host)
        host.layoutIfNeeded()

        // A modal stretched to 1194pt wide is a band, not a card.
        XCTAssertLessThanOrEqual(card.frame.width, 420)
        XCTAssertEqual(card.frame.midX, host.bounds.midX, accuracy: 0.5)
    }
}

/// A view with a safe area, which a plain view in a test bundle has not got.
private final class SafeAreaStub: UIView {

    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var safeAreaInsets: UIEdgeInsets { insets }
}
