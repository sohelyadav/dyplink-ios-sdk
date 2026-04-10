import XCTest
@testable import DyplinkCore

final class EventQueueStoreTests: XCTestCase {

    private var store: EventQueueStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = EventQueueStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertAndCount() {
        XCTAssertEqual(store.count(), 0)
        store.insert(eventType: "track", endpoint: "/api/events/track", payload: "{}", maxRetries: 3)
        XCTAssertEqual(store.count(), 1)
        store.insert(eventType: "track", endpoint: "/api/events/track", payload: "{}", maxRetries: 3)
        XCTAssertEqual(store.count(), 2)
    }

    func testGetNextBatch_returnsEligibleEvents() {
        store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 3)
        store.insert(eventType: "track", endpoint: "/e2", payload: "p2", maxRetries: 3)

        let batch = store.getNextBatch(batchSize: 10)
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(batch[0].endpoint, "/e1")
        XCTAssertEqual(batch[1].endpoint, "/e2")
    }

    func testDeleteByIds() {
        let id1 = store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 3)
        let _ = store.insert(eventType: "track", endpoint: "/e2", payload: "p2", maxRetries: 3)

        store.deleteByIds([id1])
        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.getNextBatch()[0].endpoint, "/e2")
    }

    func testIncrementRetry_schedulesBackoff() {
        let id = store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 3)

        let futureMs = EventQueueStore.nowMillis() + 999_999_999
        store.incrementRetry(id: id, nextRetryAt: futureMs)

        // Not eligible yet because nextRetryAt is far in the future.
        let batch = store.getNextBatch()
        XCTAssertTrue(batch.isEmpty)

        // But eligible if we ask for "now" past that point.
        let laterBatch = store.getNextBatch(now: futureMs + 1)
        XCTAssertEqual(laterBatch.count, 1)
        XCTAssertEqual(laterBatch[0].retryCount, 1)
    }

    func testPurgeExhaustedRetries() {
        let id = store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 1)
        store.incrementRetry(id: id, nextRetryAt: 0)

        store.purgeExhaustedRetries()
        XCTAssertEqual(store.count(), 0)
    }

    func testPersistenceAcrossInstances() {
        store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 3)

        // Create a new store pointing at the same directory.
        let store2 = EventQueueStore(directory: tempDir)
        XCTAssertEqual(store2.count(), 1)
        XCTAssertEqual(store2.getNextBatch()[0].endpoint, "/e1")
    }

    func testClear() {
        store.insert(eventType: "track", endpoint: "/e1", payload: "p1", maxRetries: 3)
        store.insert(eventType: "track", endpoint: "/e2", payload: "p2", maxRetries: 3)
        store.clear()
        XCTAssertEqual(store.count(), 0)
    }
}
