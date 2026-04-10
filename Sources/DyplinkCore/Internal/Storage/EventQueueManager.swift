import Foundation

/// Coordinates the offline event queue — periodic flush, on-demand
/// flush triggers, and exponential-backoff retry. Mirrors the Android
/// `EventQueueManager`.
internal final class EventQueueManager {

    private let store: EventQueueStore
    private let requestExecutor: RequestExecutor
    private let maxQueueSize: Int
    private let maxRetries: Int
    private let flushIntervalSeconds: Int

    private var periodicTask: Task<Void, Never>?
    private var flushTriggerTask: Task<Void, Never>?
    private var triggerContinuation: AsyncStream<Void>.Continuation?
    private let lock = NSLock()
    private var isFlushInFlight = false

    init(
        store: EventQueueStore,
        requestExecutor: RequestExecutor,
        maxQueueSize: Int,
        maxRetries: Int,
        flushIntervalSeconds: Int
    ) {
        self.store = store
        self.requestExecutor = requestExecutor
        self.maxQueueSize = maxQueueSize
        self.maxRetries = maxRetries
        self.flushIntervalSeconds = flushIntervalSeconds
    }

    /// Start the periodic flush loop and the trigger listener.
    func start() {
        stop() // idempotent restart

        let stream = AsyncStream<Void> { [weak self] continuation in
            self?.triggerContinuation = continuation
        }

        periodicTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.flushIntervalSeconds) * 1_000_000_000)
                if Task.isCancelled { return }
                await self.flush()
            }
        }

        flushTriggerTask = Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            for await _ in stream {
                if Task.isCancelled { return }
                await self.flush()
            }
        }
    }

    /// Stop the periodic flush loop.
    func stop() {
        periodicTask?.cancel()
        flushTriggerTask?.cancel()
        triggerContinuation?.finish()
        periodicTask = nil
        flushTriggerTask = nil
        triggerContinuation = nil
    }

    /// Enqueue a new event. If the queue exceeds `maxQueueSize`, the
    /// oldest events with exhausted retries are purged first.
    func enqueue(eventType: String, endpoint: String, payload: String) {
        store.insert(
            eventType: eventType,
            endpoint: endpoint,
            payload: payload,
            maxRetries: maxRetries
        )
        DyplinkLogger.d("EventQueueManager: enqueued \(eventType) -> \(endpoint)")
        if store.count() > maxQueueSize {
            store.purgeExhaustedRetries()
            DyplinkLogger.d("EventQueueManager: purged exhausted retries")
        }
    }

    /// Coalesced flush trigger. Safe to call from any thread.
    func triggerFlush() {
        triggerContinuation?.yield()
    }

    /// Process the next batch of ready events.
    /// - 2xx/4xx → remove
    /// - 5xx/transport → schedule retry
    func flush() async {
        // Drop overlapping flush runs.
        lock.lock()
        if isFlushInFlight {
            lock.unlock()
            return
        }
        isFlushInFlight = true
        lock.unlock()
        defer {
            lock.lock()
            isFlushInFlight = false
            lock.unlock()
        }

        let batch = store.getNextBatch()
        if batch.isEmpty { return }

        DyplinkLogger.d("EventQueueManager: flushing \(batch.count) events")

        for event in batch {
            guard let payloadData = event.payload.data(using: .utf8) else {
                store.deleteByIds([event.id])
                continue
            }
            do {
                let response = try await requestExecutor.post(event.endpoint, jsonBody: payloadData)
                let code = response.statusCode
                if (200...299).contains(code) || (400...499).contains(code) {
                    store.deleteByIds([event.id])
                    DyplinkLogger.d("EventQueueManager: event \(event.id) completed (HTTP \(code))")
                } else {
                    scheduleRetry(event)
                }
            } catch {
                DyplinkLogger.w("EventQueueManager: event \(event.id) failed: \(error.localizedDescription)")
                scheduleRetry(event)
            }
        }

        store.purgeExhaustedRetries()
    }

    /// Number of events still waiting in the queue.
    func pendingCount() -> Int { store.count() }

    // ── Helpers ────────────────────────────────────────────────────────

    private func scheduleRetry(_ event: EventQueueEntry) {
        let backoffMs = min(
            Int64(pow(2.0, Double(event.retryCount)) * 1_000),
            Self.maxBackoffMs
        )
        let nextRetryAt = EventQueueStore.nowMillis() + backoffMs
        store.incrementRetry(id: event.id, nextRetryAt: nextRetryAt)
        DyplinkLogger.d(
            "EventQueueManager: event \(event.id) retry scheduled "
            + "(retryCount=\(event.retryCount + 1), backoff=\(backoffMs)ms)"
        )
    }

    /// 5-minute cap, matching Android.
    private static let maxBackoffMs: Int64 = 300_000
}
