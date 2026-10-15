#if canImport(UIKit)
import XCTest
import DyplinkCore
@testable import DyplinkMessages

/// Covers what happens to the messages a check returns: that they are shown
/// one at a time, and that a message which never reached the screen is
/// neither reported as seen nor left holding a window.
///
/// A check returns up to three eligible messages, priority descending. All
/// three used to be presented at once — three windows stacked on each other
/// with the *lowest* priority on top — and all three reported an impression,
/// so the dashboard counted three messages seen for the one that was
/// readable. A second check (`onAppOpen` then `onScreenView` returns the
/// same eligible set until an impression is recorded) stacked more.
///
/// A test bundle has no foreground window scene, which is the other half:
/// `present()` can do nothing, and the presenter — which owns a `UIWindow` —
/// was appended to a list pruned only when an outcome arrived. No outcome
/// ever arrives on that path, so the window was held for the lifetime of the
/// process.
@MainActor
final class MessageQueueTests: XCTestCase {

    /// Records what the SDK reports, which is the only place an impression
    /// for a message nobody saw is visible from outside.
    private final class ListenerSpy: MessageListener {
        private(set) var events: [(messageId: String, eventType: String)] = []

        func onMessageEvent(message: InAppMessage, eventType: String, buttonId: String?) {
            events.append((message.id, eventType))
        }

        var impressions: [String] {
            events.filter { $0.eventType == "impression" }.map(\.messageId)
        }
    }

    private var listener: ListenerSpy!
    private var manager: MessageManager!

    override func setUp() {
        super.setUp()
        // Nothing should reach the network; a refused port fails fast.
        DyplinkConfigBridge.baseUrl = "http://127.0.0.1:9"
        DyplinkConfigBridge.apiKey = "k"

        let listener = ListenerSpy()
        self.listener = listener
        manager = MessageManager(
            apiClient: MessageApiClient(),
            projectId: "p",
            deviceFingerprint: "f",
            distinctIdProvider: { nil }
        )
        manager.messageListener = listener
    }

    override func tearDown() {
        manager = nil
        listener = nil
        super.tearDown()
    }

    private func message(_ id: String, triggerDelay: Int = 0) -> InAppMessage {
        InAppMessage(
            id: id,
            messageType: "modal",
            title: id,
            body: nil,
            imageUrl: nil,
            imagePosition: "top",
            buttons: nil,
            theme: nil,
            dismissOnTapOutside: true,
            autoDismissSeconds: nil,
            triggerDelay: triggerDelay
        )
    }

    /// Lets the main-actor task that shows the next message run.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    // ── Nothing shown, nothing reported ────────────────────────────────

    func testAMessageThatCouldNotBeShownIsNotReportedAsAnImpression() async {
        await manager.enqueue([message("m1")])
        await settle()

        XCTAssertEqual(listener.impressions, [], "reported an impression for a message nobody saw")
    }

    /// The leak. The presenter owns the window the message lives in, and on
    /// this path it produces no outcome — so anything still holding it holds
    /// the window too, for as long as the process lives.
    func testAMessageThatCouldNotBeShownReleasesItsPresenter() async {
        await manager.enqueue([message("m1")])
        await settle()

        XCTAssertFalse(manager.isHoldingPresenter, "the presenter — and its UIWindow — was retained")
    }

    /// Three at once is what the server returns, and what used to be three
    /// impressions and three stacked windows.
    func testThreeEligibleMessagesProduceAtMostOneImpression() async {
        await manager.enqueue([message("high"), message("medium"), message("low")])
        await settle()

        XCTAssertLessThanOrEqual(listener.impressions.count, 1)
        XCTAssertFalse(manager.isHoldingPresenter)
    }

    /// With no scene there is nothing to wait for, so the rest are dropped
    /// rather than queued against a foreground that may never come — the
    /// next check offers them again, and none of them was reported as seen.
    func testTheQueueDoesNotGrowWhenThereIsNowhereToShowAnything() async {
        await manager.enqueue([message("m1"), message("m2"), message("m3")])
        await settle()

        XCTAssertEqual(manager.queuedMessageCount, 0)
    }

    /// `onAppOpen` and then `onScreenView`: two checks, the same eligible
    /// messages, because eligibility does not change until an impression is
    /// recorded.
    func testASecondCheckDoesNotQueueTheSameMessageTwice() async {
        let same = [message("m1"), message("m2")]

        await manager.enqueue(same)
        await manager.enqueue(same)
        await settle()

        XCTAssertEqual(manager.queuedMessageCount, 0)
        XCTAssertLessThanOrEqual(listener.impressions.count, 1)
    }

    /// A delayed message is claimed the moment it comes off the queue, so a
    /// check that lands during the delay cannot start a second one beside it.
    func testADelayedMessageHoldsTheQueueWhileItWaits() async {
        await manager.enqueue([message("delayed", triggerDelay: 5)])
        await settle()

        await manager.enqueue([message("immediate")])
        await settle()

        XCTAssertEqual(listener.impressions, [])
        // Waiting its turn behind the delayed one, not shown beside it.
        XCTAssertEqual(manager.queuedMessageCount, 1)
    }

    func testAnEmptyCheckDoesNothing() async {
        await manager.enqueue([])
        await settle()

        XCTAssertEqual(listener.events.count, 0)
        XCTAssertEqual(manager.queuedMessageCount, 0)
        XCTAssertFalse(manager.isHoldingPresenter)
    }
}
#endif
