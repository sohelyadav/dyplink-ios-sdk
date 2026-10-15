import XCTest
@testable import DyplinkMessages

/// `/api/messages/check` answers `{"data":{"messages":[…]}}`. The client
/// read `messages` off the root, found nothing, and returned an empty list —
/// which is exactly what "nobody is eligible" looks like, so in-app
/// messaging was dead on every device without a single error anywhere.
final class MessageApiClientTests: XCTestCase {

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    /// The body the live API returns, copied from a real check.
    private let enveloped = #"""
    {"data":{"messages":[{
      "id":"c63c74dc-d52d-44ab-89a3-73e7f929704d",
      "messageType":"banner_bottom",
      "title":"Parity probe",
      "body":"Checking the SDK envelope",
      "imageUrl":null,
      "imagePosition":"top",
      "buttons":[{"id":"b1","text":"Got it","style":"primary","action":"dismiss"}],
      "theme":{"animation":"slide_up","titleColor":"#FFFFFF","borderRadius":16,"backgroundColor":"#101828"},
      "dismissOnTapOutside":true,
      "autoDismissSeconds":6,
      "triggerDelay":0
    }]}}
    """#

    func testReadsMessagesFromInsideTheEnvelope() throws {
        let messages = MessageApiClient.parseMessages(from: data(enveloped))

        XCTAssertEqual(messages.count, 1)
        // `messages[0]` would trap and take the rest of the suite with it.
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.id, "c63c74dc-d52d-44ab-89a3-73e7f929704d")
        XCTAssertEqual(message.messageType, "banner_bottom")
        XCTAssertEqual(message.title, "Parity probe")
        XCTAssertEqual(message.body, "Checking the SDK envelope")
        XCTAssertEqual(message.autoDismissSeconds, 6)
        XCTAssertEqual(message.buttons?.count, 1)
        XCTAssertEqual(message.buttons?.first?.text, "Got it")
        XCTAssertEqual(message.theme?.backgroundColor, "#101828")
        XCTAssertEqual(message.theme?.borderRadius, 16)
    }

    func testReadsMessagesFromAnUnwrappedBody() {
        let messages = MessageApiClient.parseMessages(
            from: data(#"{"messages":[{"id":"m1","messageType":"modal","title":"Hi"}]}"#)
        )

        XCTAssertEqual(messages.map(\.id), ["m1"])
    }

    func testNoMessagesIsAnEmptyList() {
        XCTAssertTrue(MessageApiClient.parseMessages(from: data(#"{"data":{"messages":[]}}"#)).isEmpty)
    }

    func testUnreadableBodiesYieldNoMessages() {
        for body in ["", "not json", "[]", #"{"data":{}}"#, #"{"data":{"messages":"soon"}}"#] {
            XCTAssertTrue(
                MessageApiClient.parseMessages(from: data(body)).isEmpty,
                "expected no messages for \(body)"
            )
        }
    }

    func testAbsentFieldsTakeTheirDefaults() throws {
        // The serve DTO always sends every field, but a message authored
        // against an older API, or a field added later, must not drop the
        // message — a plain modal is a better outcome than nothing.
        let messages = MessageApiClient.parseMessages(from: data(#"{"data":{"messages":[{"id":"m2"}]}}"#))

        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.messageType, "modal")
        XCTAssertEqual(message.imagePosition, "top")
        XCTAssertTrue(message.dismissOnTapOutside)
        XCTAssertNil(message.autoDismissSeconds)
        XCTAssertEqual(message.triggerDelay, 0)
    }
}
