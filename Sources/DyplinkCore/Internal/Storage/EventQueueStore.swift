import Foundation

/// One entry in the offline event queue. Mirrors the Android
/// `EventQueueEntity` Room record.
internal struct EventQueueEntry: Codable, Equatable {
    var id: Int64
    var eventType: String
    var endpoint: String
    var payload: String
    var createdAt: Int64
    var retryCount: Int
    var maxRetries: Int
    /// Epoch millis (same units as Android); `0` means eligible now.
    var nextRetryAt: Int64
}

/// JSON-file-backed append queue. Not a database — we chose a flat
/// file because the queue is append-mostly and iterates linearly.
///
/// Thread safety: all methods acquire a private `NSLock`. All I/O runs
/// synchronously on the caller's thread; the queue manager only calls
/// into the store from a dedicated background task.
internal final class EventQueueStore {

    private let fileURL: URL
    private let lock = NSLock()

    private var entries: [EventQueueEntry] = []
    private var nextId: Int64 = 1

    init(directory: URL? = nil) {
        let dir: URL
        if let directory = directory {
            dir = directory
        } else {
            // ~/Library/Application Support/dyplink/
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("dyplink", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("event_queue.json")
        self.load()
    }

    // ── Public operations ──────────────────────────────────────────────

    /// Insert a new entry; returns its generated id.
    @discardableResult
    func insert(eventType: String, endpoint: String, payload: String, maxRetries: Int) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let entry = EventQueueEntry(
            id: nextId,
            eventType: eventType,
            endpoint: endpoint,
            payload: payload,
            createdAt: Self.nowMillis(),
            retryCount: 0,
            maxRetries: maxRetries,
            nextRetryAt: 0
        )
        nextId += 1
        entries.append(entry)
        persist()
        return entry.id
    }

    /// Total queued events (including ones currently backing off).
    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// Return up to `batchSize` entries whose `nextRetryAt` is in the
    /// past, sorted by `createdAt ASC`.
    func getNextBatch(now: Int64 = Self.nowMillis(), batchSize: Int = 50) -> [EventQueueEntry] {
        lock.lock(); defer { lock.unlock() }
        let ready = entries.filter { $0.nextRetryAt <= now }
            .sorted { $0.createdAt < $1.createdAt }
        return Array(ready.prefix(batchSize))
    }

    /// Delete entries by id.
    func deleteByIds(_ ids: [Int64]) {
        lock.lock(); defer { lock.unlock() }
        let set = Set(ids)
        entries.removeAll { set.contains($0.id) }
        persist()
    }

    /// Increment the retry counter and schedule the next attempt.
    func incrementRetry(id: Int64, nextRetryAt: Int64) {
        lock.lock(); defer { lock.unlock() }
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            entries[idx].retryCount += 1
            entries[idx].nextRetryAt = nextRetryAt
            persist()
        }
    }

    /// Drop entries whose retry budget is exhausted.
    func purgeExhaustedRetries() {
        lock.lock(); defer { lock.unlock() }
        let before = entries.count
        entries.removeAll { $0.retryCount >= $0.maxRetries }
        if entries.count != before {
            persist()
        }
    }

    /// Drop entries older than `cutoff` millis.
    func purgeOlderThan(_ cutoff: Int64) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.createdAt < cutoff }
        persist()
    }

    /// Remove everything (test utility / `reset()` scenarios).
    func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
        persist()
    }

    // ── Persistence ────────────────────────────────────────────────────

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else { return }
        do {
            let decoded = try JSONDecoder().decode([EventQueueEntry].self, from: data)
            self.entries = decoded
            self.nextId = (decoded.map(\.id).max() ?? 0) + 1
        } catch {
            DyplinkLogger.e("EventQueueStore: failed to load queue", error)
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DyplinkLogger.e("EventQueueStore: failed to persist queue", error)
        }
    }

    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
