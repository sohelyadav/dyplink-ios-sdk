import XCTest
import DyplinkMessages

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
