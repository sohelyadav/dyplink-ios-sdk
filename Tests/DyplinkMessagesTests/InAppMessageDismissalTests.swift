#if canImport(UIKit)
import XCTest
import UIKit
@testable import DyplinkMessages

/// Covers every way out of an in-app message, and the combination that used
/// to have none.
///
/// All four of these are legal campaign settings: a `modal` with no buttons
/// (`buttons` is nullable), `autoDismissSeconds: 0` (`@Min(0)`) and
/// `dismissOnTapOutside: false`. Together they left a message in a window at
/// `.alert` level — which swallows every touch beneath it — with no button
/// to press, no timer to end it and no backdrop gesture. The app was
/// unusable until it was force-quit.
final class InAppMessageDismissalTests: XCTestCase {

    private func message(
        messageType: String = "modal",
        buttons: [MessageButton]? = nil,
        theme: MessageTheme? = nil,
        dismissOnTapOutside: Bool = true,
        autoDismissSeconds: Int? = nil,
        imageUrl: String? = nil,
        imagePosition: String = "top"
    ) -> InAppMessage {
        InAppMessage(
            id: "m1",
            messageType: messageType,
            title: "Trapped?",
            body: "There has to be a way out of here",
            imageUrl: imageUrl,
            imagePosition: imagePosition,
            buttons: buttons,
            theme: theme,
            dismissOnTapOutside: dismissOnTapOutside,
            autoDismissSeconds: autoDismissSeconds,
            triggerDelay: 0
        )
    }

    private func card(
        _ message: InAppMessage,
        showsCloseButton: Bool = true,
        onClose: @escaping () -> Void = {}
    ) -> InAppMessageView {
        InAppMessageView(
            message: message,
            compact: false,
            showsCloseButton: showsCloseButton,
            onButtonTapped: { _ in },
            onClose: onClose
        )
    }

    private func closeButton(in view: InAppMessageView) -> UIButton? {
        view.subviews
            .compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == InAppMessageView.closeAccessibilityIdentifier }
    }

    // ── An explicit zero no longer suppresses the default ──────────────

    /// `0` and absent mean the same thing — let the layout decide. Read as
    /// an explicit zero, it armed no timer *and* suppressed the banner's
    /// four-second default, which is the only thing that ever closes a
    /// banner: it has nothing to tap.
    func testAnExplicitZeroAutoDismissIsReadAsAbsent() throws {
        let messages = MessageApiClient.parseMessages(
            from: Data(#"{"data":{"messages":[{"id":"m1","messageType":"banner_top","autoDismissSeconds":0}]}}"#.utf8)
        )

        let message = try XCTUnwrap(messages.first)
        XCTAssertNil(message.autoDismissSeconds)
    }

    func testAPositiveAutoDismissIsStillHonoured() throws {
        let messages = MessageApiClient.parseMessages(
            from: Data(#"{"data":{"messages":[{"id":"m1","autoDismissSeconds":6}]}}"#.utf8)
        )

        XCTAssertEqual(try XCTUnwrap(messages.first).autoDismissSeconds, 6)
    }

    /// A banner with an explicit zero gets the four seconds that are the
    /// only way it ever leaves the screen.
    func testABannerWithAnExplicitZeroStillLeavesOnItsOwn() throws {
        let messages = MessageApiClient.parseMessages(
            from: Data(#"{"data":{"messages":[{"id":"m1","messageType":"banner_bottom","autoDismissSeconds":0}]}}"#.utf8)
        )
        let message = try XCTUnwrap(messages.first)
        let layout = InAppMessagePresenter.Layout(messageType: message.messageType)

        XCTAssertEqual(message.autoDismissSeconds ?? layout.defaultAutoDismissSeconds, 4)
    }

    // ── The close control ──────────────────────────────────────────────

    /// Every layout that takes the app over draws one. Unconditionally: the
    /// campaign decides how the message looks, not whether it can be left.
    func testEveryLayoutThatTakesTheAppOverDrawsACloseControl() {
        for type in ["modal", "bottom_sheet", "fullscreen"] {
            XCTAssertTrue(
                InAppMessagePresenter.Layout(messageType: type).needsCloseButton,
                "\(type) could trap the user"
            )
        }
        // A banner needs none: no backdrop, touches pass through it to the
        // app, and it leaves on its own after four seconds.
        for type in ["banner_top", "banner_bottom"] {
            XCTAssertFalse(InAppMessagePresenter.Layout(messageType: type).needsCloseButton, type)
        }
    }

    /// An unknown message type is drawn as a modal, so it must be closable
    /// as one — a layout added to the API later must not arrive untrappable.
    func testAnUnknownMessageTypeAlsoGetsACloseControl() {
        XCTAssertTrue(InAppMessagePresenter.Layout(messageType: "takeover").needsCloseButton)
    }

    // ── The whole bricking combination, in one go ──────────────────────

    /// The four values that made the app unusable, from a server body
    /// through to a tap that closes the message.
    ///
    /// Chained deliberately rather than split: each of the four settings is
    /// legal on its own and harmless on its own, and the defect only existed
    /// in their combination — so testing the parser, the layout rule and the
    /// control separately would leave the thing that actually bricked the app
    /// covered by nothing.
    ///
    /// `present()` itself cannot run here: it needs a foreground window
    /// scene and a test bundle has none. So this builds the card exactly as
    /// `present()` does — same layout, same `needsCloseButton` — and
    /// exercises everything from there.
    func testTheMessageThatUsedToBrickTheAppCanBeClosed() throws {
        let body = #"""
        {"data":{"messages":[{
          "id":"brick",
          "messageType":"modal",
          "title":"No way out",
          "body":"No buttons, no timer, no tap-outside",
          "buttons":null,
          "autoDismissSeconds":0,
          "dismissOnTapOutside":false
        }]}}
        """#
        let message = try XCTUnwrap(MessageApiClient.parseMessages(from: Data(body.utf8)).first)
        let layout = InAppMessagePresenter.Layout(messageType: message.messageType)

        // Every exit the campaign controls is shut, and all four values
        // survived parsing as the campaign meant them.
        XCTAssertNil(message.buttons, "a button would have been a way out")
        XCTAssertFalse(message.dismissOnTapOutside, "the backdrop would have been a way out")
        // The exact expression `armAutoDismiss` guards on: nil means no
        // timer is ever armed, so nothing will close this on its own.
        XCTAssertNil(
            message.autoDismissSeconds ?? layout.defaultAutoDismissSeconds,
            "a timer would have been a way out"
        )
        // And it is one of the layouts whose backdrop swallows every touch,
        // so the app underneath cannot be reached either.
        XCTAssertTrue(layout.hasBackdrop)

        // Which leaves exactly one exit, the one the campaign cannot switch
        // off. Built the way the presenter builds it.
        XCTAssertTrue(layout.needsCloseButton)
        var closed = 0
        let view = InAppMessageView(
            message: message,
            compact: layout.isCompact,
            showsCloseButton: layout.needsCloseButton,
            onButtonTapped: { _ in XCTFail("this message has no buttons") },
            onClose: { closed += 1 }
        )
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let close = try XCTUnwrap(closeButton(in: view), "the message has no way out at all")
        // A touch at its centre reaches it rather than the copy or the card.
        let centre = CGPoint(x: close.frame.midX, y: close.frame.midY)
        XCTAssertTrue(view.hitTest(centre, with: nil) === close)

        close.sendActions(for: .touchUpInside)

        XCTAssertEqual(closed, 1, "tapping the only way out did nothing")
    }

    func testTheCloseControlIsDrawnEvenWithNoOtherWayOut() throws {
        let view = card(message(
            buttons: nil,
            dismissOnTapOutside: false,
            autoDismissSeconds: nil
        ))

        let close = try XCTUnwrap(closeButton(in: view), "nothing to close the message with")
        XCTAssertEqual(close.accessibilityLabel, "Close")
        XCTAssertTrue(close.isUserInteractionEnabled)
        XCTAssertFalse(close.isHidden)
    }

    func testTappingTheCloseControlDismisses() throws {
        var closed = 0
        let view = card(message(dismissOnTapOutside: false), onClose: { closed += 1 })
        let close = try XCTUnwrap(closeButton(in: view))

        close.sendActions(for: .touchUpInside)

        XCTAssertEqual(closed, 1)
    }

    /// Drawn, but behind the copy or outside the card, is still a message
    /// nobody can close — so this lays the card out and checks the control
    /// is where a thumb can reach it and big enough to hit.
    func testTheCloseControlIsHitTestableAtApplesMinimumSize() throws {
        let view = card(message(buttons: [MessageButton(
            id: "b1", text: "Buy now", action: "dismiss",
            actionUrl: nil, actionEvent: nil, style: "primary"
        )]))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let close = try XCTUnwrap(closeButton(in: view))
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        // Inside the card, in its top-trailing corner.
        XCTAssertTrue(view.bounds.contains(close.frame), "\(close.frame) is outside \(view.bounds)")
        XCTAssertGreaterThan(close.frame.midX, view.bounds.midX)
        XCTAssertLessThan(close.frame.midY, view.bounds.midY)
        // And the topmost thing at that point, so the touch lands on it.
        XCTAssertTrue(view.hitTest(CGPoint(x: close.frame.midX, y: close.frame.midY), with: nil) === close)
    }

    /// The copy must not run under the control, or a long title is drawn
    /// beneath it and reads as an overlap.
    func testTheCopyLeavesRoomForTheCloseControl() throws {
        let view = card(message())
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let close = try XCTUnwrap(closeButton(in: view))
        let stack = try XCTUnwrap(view.subviews.compactMap { $0 as? UIStackView }.first)

        XCTAssertLessThanOrEqual(stack.frame.maxX, close.frame.minX)
    }

    func testABannerDrawsNoCloseControl() {
        XCTAssertNil(closeButton(in: card(message(messageType: "banner_top"), showsCloseButton: false)))
    }

    /// The glyph is drawn over whatever the campaign put behind it, so a
    /// photograph must not swallow it.
    func testTheCloseGlyphStaysVisibleOverABackgroundPicture() throws {
        let overPicture = try XCTUnwrap(closeButton(in: card(message(
            imageUrl: "https://cdn.test/i.png",
            imagePosition: "background"
        ))))
        XCTAssertEqual(overPicture.tintColor, .white)

        // Over a colour it follows the theme, like the rest of the copy.
        let themed = try XCTUnwrap(closeButton(in: card(message(
            theme: MessageTheme(
                backgroundColor: "#101828", textColor: nil, titleColor: "#FFEEDD",
                buttonPrimaryColor: nil, buttonSecondaryColor: nil, overlayColor: nil,
                borderRadius: nil, animation: nil
            )
        ))))
        XCTAssertEqual(themed.tintColor, UIColor(dyplinkHex: "#FFEEDD"))
    }
}
#endif
