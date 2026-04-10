import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Observes UIApplication foreground/background notifications and
/// fans them out to the SDK components that care: the session tracker,
/// the event queue (flush on background), and the connectivity
/// monitor (unused here but kept for API parity with Android).
internal final class AppLifecycleObserver {
    private let queueManager: EventQueueManager
    private let sessionTracker: SessionTracker
    private let connectivityMonitor: ConnectivityMonitor
    private var observers: [NSObjectProtocol] = []

    init(
        queueManager: EventQueueManager,
        sessionTracker: SessionTracker,
        connectivityMonitor: ConnectivityMonitor
    ) {
        self.queueManager = queueManager
        self.sessionTracker = sessionTracker
        self.connectivityMonitor = connectivityMonitor
    }

    deinit {
        stop()
    }

    func start() {
        #if canImport(UIKit)
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionTracker.onAppForegrounded()
            self?.queueManager.triggerFlush()
        })

        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.sessionTracker.onAppBackgrounded()
            self?.queueManager.triggerFlush()
        })

        observers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.queueManager.triggerFlush()
        })
        #endif
    }

    func stop() {
        let center = NotificationCenter.default
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }
}
