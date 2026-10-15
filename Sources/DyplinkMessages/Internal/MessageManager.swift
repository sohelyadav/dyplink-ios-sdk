#if canImport(UIKit)
import Foundation
import UIKit
import DyplinkCore

/// Coordinates message checking, display, and event recording.
/// Mirrors the Android `MessageManager`.
internal final class MessageManager {
    let apiClient: MessageApiClient
    let projectId: String
    let deviceFingerprint: String
    let distinctIdProvider: () -> String?
    weak var messageListener: MessageListener?

    /// The message on screen. It owns the window its message lives in, so
    /// something has to hold it — and let go of it again on every path out.
    @MainActor
    private var presenter: InAppMessagePresenter?

    /// Eligible messages waiting their turn, highest priority first.
    @MainActor
    private var queue: [InAppMessage] = []

    /// Set from the moment a message is taken off the queue until it leaves
    /// the screen. Not the same as `presenter != nil`: a message with a
    /// trigger delay is claimed seconds before it is built.
    @MainActor
    private var isPresenting = false

    /// Ids queued or on screen.
    ///
    /// A check answers with every message that is eligible *now*, and
    /// eligibility does not change until an impression has been recorded —
    /// so `onAppOpen` followed by `onScreenView` hands back the same
    /// messages, and without this the second copy would be shown again
    /// after the first was dismissed.
    @MainActor
    private var pendingIds: Set<String> = []

    init(
        apiClient: MessageApiClient,
        projectId: String,
        deviceFingerprint: String,
        distinctIdProvider: @escaping () -> String?
    ) {
        self.apiClient = apiClient
        self.projectId = projectId
        self.deviceFingerprint = deviceFingerprint
        self.distinctIdProvider = distinctIdProvider
    }

    func checkAndShow(context: MessageApiClient.CheckContext) async {
        do {
            let messages = try await apiClient.checkMessages(
                projectId: projectId,
                deviceFingerprint: deviceFingerprint,
                distinctId: distinctIdProvider(),
                context: context
            )
            await enqueue(messages)
        } catch {
            // Never crash the host app — but never silently, either: a check
            // that fails and a check that finds nobody eligible are the same
            // thing from the outside.
            DyplinkDiagnostics.error("In-app message check failed", error)
        }
    }

    /// Queues what a check returned and starts the first of them.
    ///
    /// Internal rather than private so the queueing can be driven without a
    /// server: a unit-test bundle has no foreground scene, which is also the
    /// case this has to get right.
    ///
    /// The server sorts by priority descending and returns at most three.
    /// They are shown one at a time in that order. Presenting all of them at
    /// once — which is what this used to do — stacked three windows on top of
    /// each other with the *lowest* priority message on top, and reported
    /// three impressions for the one message anybody could read.
    @MainActor
    func enqueue(_ messages: [InAppMessage]) async {
        let fresh = messages.filter { !pendingIds.contains($0.id) }
        guard !fresh.isEmpty else { return }

        queue.append(contentsOf: fresh)
        pendingIds.formUnion(fresh.map(\.id))
        presentNext()
    }

    /// Shows the highest-priority queued message, if nothing is showing.
    @MainActor
    private func presentNext() {
        guard presenter == nil, !isPresenting, !queue.isEmpty else { return }

        let message = queue.removeFirst()
        isPresenting = true
        Task { @MainActor [weak self] in
            await self?.show(message)
        }
    }

    @MainActor
    private func show(_ message: InAppMessage) async {
        // Respect trigger delay.
        if message.triggerDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(message.triggerDelay) * 1_000_000_000)
        }

        let presenter = InAppMessagePresenter(message: message) { [weak self] outcome in
            self?.finish(outcome, for: message)
        }

        // Nothing else holds the presenter, and it owns the window the
        // message lives in — dropping it while it is showing would take the
        // message with it.
        guard presenter.present() else {
            // Nothing reached the screen, so there is no impression to
            // report and nothing to hold: `present` produces no outcome on
            // this path, so a presenter kept here would hold its `UIWindow`
            // for the lifetime of the process with nothing ever coming to
            // prune it.
            DyplinkDiagnostics.debug(
                "In-app message \(message.id) was not shown: no foreground window scene"
            )
            isPresenting = false
            pendingIds.remove(message.id)
            // Whatever stopped this one stops the rest — there is no scene
            // to draw in — so they are dropped rather than held against a
            // foreground that may never come. The next check offers them
            // again, and none of them was reported as seen.
            queue.removeAll()
            pendingIds.removeAll()
            return
        }

        self.presenter = presenter
        report(message, eventType: "impression")
    }

    /// The message left the screen: let go of it, then show whatever is next.
    @MainActor
    private func finish(_ outcome: InAppMessagePresenter.Outcome, for message: InAppMessage) {
        // The presenter keeps itself alive through its own dismissal
        // animation, so releasing it here is safe and releasing it anywhere
        // later is a window leaked.
        presenter = nil
        isPresenting = false
        pendingIds.remove(message.id)

        handle(outcome, for: message)
        presentNext()
    }

    /// Records the outcome and lets the host app act on it.
    @MainActor
    private func handle(_ outcome: InAppMessagePresenter.Outcome, for message: InAppMessage) {
        switch outcome {
        case .dismissed:
            report(message, eventType: "dismiss")

        case .autoDismissed:
            report(message, eventType: "auto_dismiss")

        case .buttonTapped(let button):
            // `cta_click`, not `click`, and this is the reason: the
            // dashboard's per-button breakdown counts `cta_click` rows
            // alone, so for as long as iOS reported `click` its taps were
            // invisible there while Android's showed up. Both are summed
            // into the click-through rate, which is why nothing looked
            // wrong at the top level.
            report(message, eventType: "cta_click", buttonId: button.id)
            messageListener?.onButtonAction(message: message, button: button)

            switch button.action {
            case "deep_link", "url":
                open(button.actionUrl)
            case "custom_event":
                if let event = button.actionEvent {
                    messageListener?.onCustomEvent(message: message, eventName: event)
                }
            default:
                // `dismiss` has nothing to do beyond closing, which has
                // already happened.
                break
            }
        }
    }

    private func report(_ message: InAppMessage, eventType: String, buttonId: String? = nil) {
        Task { [apiClient, projectId, deviceFingerprint, distinctIdProvider] in
            await apiClient.recordEvent(
                messageId: message.id,
                projectId: projectId,
                deviceFingerprint: deviceFingerprint,
                distinctId: distinctIdProvider(),
                eventType: eventType,
                buttonId: buttonId
            )
        }
        messageListener?.onMessageEvent(message: message, eventType: eventType, buttonId: buttonId)
    }

    /// Opens a button's destination, the way the Android SDK's
    /// `ACTION_VIEW` does. `onButtonAction` has already run, so a host app
    /// that routes its own deep links has had its chance first.
    @MainActor
    private func open(_ raw: String?) {
        guard let raw = raw, let url = URL(string: raw) else { return }
        UIApplication.shared.open(url)
    }

    // ── Test hooks ─────────────────────────────────────────────────────

    /// Whether a presenter — and so a `UIWindow` — is being held.
    @MainActor
    var isHoldingPresenter: Bool { presenter != nil }

    /// How many messages are still waiting for their turn.
    @MainActor
    var queuedMessageCount: Int { queue.count }
}
#endif
