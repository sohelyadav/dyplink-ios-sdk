import XCTest
// @testable: the test builds an InAppMessage directly, and its memberwise
// init is internal — a plain import cannot see it, so this target has never
// compiled and the package's test action has been red since the file landed.
@testable import DyplinkMessages

final class MessageModelTests: XCTestCase {
    func testInAppMessageInit() {
        let message = InAppMessage(
            id: "msg-1",
            messageType: "modal",
            title: "Welcome!",
            body: "Hello world",
            imageUrl: nil,
            imagePosition: "top",
            buttons: nil,
            theme: nil,
            dismissOnTapOutside: true,
            autoDismissSeconds: nil,
            triggerDelay: 0
        )
        XCTAssertEqual(message.id, "msg-1")
        XCTAssertEqual(message.title, "Welcome!")
    }
}
