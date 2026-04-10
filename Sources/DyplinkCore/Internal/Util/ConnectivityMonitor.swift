import Foundation
import Network

/// Observes network reachability using Apple's `NWPathMonitor`.
/// Mirrors the Android `ConnectivityMonitor` API surface: `start`,
/// `stop`, and a list of listeners invoked whenever connectivity
/// transitions to "satisfied" (i.e. reachable).
internal final class ConnectivityMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.dyplink.sdk.connectivity")
    private var listeners: [() -> Void] = []
    private var isStarted = false
    private var lastStatusSatisfied = false
    private let listenersLock = NSLock()

    /// Register a closure to be invoked each time the network becomes
    /// reachable. The closure runs on the monitor's private queue.
    func addListener(_ listener: @escaping () -> Void) {
        listenersLock.lock()
        listeners.append(listener)
        listenersLock.unlock()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let nowSatisfied = path.status == .satisfied
            let wasSatisfied = self.lastStatusSatisfied
            self.lastStatusSatisfied = nowSatisfied

            // Trigger listeners on transition from unreachable → reachable.
            if nowSatisfied && !wasSatisfied {
                DyplinkLogger.d("ConnectivityMonitor: network reachable, notifying listeners")
                self.listenersLock.lock()
                let snapshot = self.listeners
                self.listenersLock.unlock()
                for listener in snapshot {
                    listener()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.cancel()
    }

    /// `true` when the most recent path was satisfied.
    var isConnected: Bool { lastStatusSatisfied }
}
