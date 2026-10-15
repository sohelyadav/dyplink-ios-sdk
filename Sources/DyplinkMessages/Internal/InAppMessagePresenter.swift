#if canImport(UIKit)
import UIKit

/// Puts an in-app message on screen in the shape the campaign asked for, and
/// takes it away again exactly once.
///
/// ## Why a window of its own
///
/// The obvious approach — present a view controller from whatever is on
/// screen — fails in the ordinary cases: nothing can be presented over a
/// `UIAlertController`, or during a push or a modal transition, and finding
/// "whatever is on screen" means walking a presentation chain that any host
/// app can arrange differently. A window above the app's own has none of
/// those problems and does not disturb the app's hierarchy at all.
///
/// ## What the campaign decides
///
/// Everything: which of the five layouts, whether a tap outside closes it,
/// how long until it closes itself, and which animation it arrives with.
/// This mirrors `InAppMessageDialog` on Android, because one campaign should
/// look like one campaign on both.
///
/// A banner is the one layout that must not take the app over: there is no
/// backdrop, and touches outside the banner itself go through to the app.
/// The other three are modal by nature and swallow what they cover.
internal final class InAppMessagePresenter {

    /// What ended the message, for the one report it is allowed to make.
    enum Outcome {
        /// The user closed it: tapped outside, or let a banner be.
        case dismissed
        /// It closed itself after `autoDismissSeconds`.
        case autoDismissed
        /// A button was tapped.
        case buttonTapped(MessageButton)
    }

    private let message: InAppMessage
    private let onOutcome: (Outcome) -> Void

    private var window: UIWindow?
    private var card: InAppMessageView?
    private var backdrop: UIView?
    private var autoDismissTimer: Timer?
    /// Guards the single report. Every path out goes through `finish`.
    private var hasFinished = false

    /// Whether the message is over, so whoever is holding this can let go.
    var isFinished: Bool { hasFinished }

    init(message: InAppMessage, onOutcome: @escaping (Outcome) -> Void) {
        self.message = message
        self.onOutcome = onOutcome
    }

    deinit {
        autoDismissTimer?.invalidate()
    }

    // ── Presenting ─────────────────────────────────────────────────────

    /// Builds the window and shows the message. Does nothing, silently, when
    /// there is no foreground scene to show it in — which is the right
    /// answer for a message that arrived as the app went to the background.
    @MainActor
    func present() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let layout = Layout(messageType: message.messageType)

        let host = PassthroughView()
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        let controller = UIViewController()
        controller.view = host
        window.rootViewController = controller
        self.window = window

        if layout.hasBackdrop {
            let backdrop = UIView()
            backdrop.backgroundColor = UIColor(dyplinkHex: message.theme?.overlayColor)
                ?? UIColor(white: 0, alpha: 0.45)
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(backdrop)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: host.topAnchor),
                backdrop.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                backdrop.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
            self.backdrop = backdrop

            if message.dismissOnTapOutside {
                backdrop.addGestureRecognizer(
                    UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
                )
            }
        }

        let card = InAppMessageView(
            message: message,
            compact: layout.isCompact,
            onButtonTapped: { [weak self] button in
                self?.finish(.buttonTapped(button))
            }
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(card)
        host.card = card
        self.card = card

        layout.constrain(card: card, in: host)

        window.isHidden = false
        animateIn(layout: layout)
        armAutoDismiss(layout: layout)
    }

    // ── Layout ─────────────────────────────────────────────────────────

    /// Where the card sits, and what that implies.
    ///
    /// Internal rather than private so the five layouts' decisions can be
    /// tested: a unit-test bundle has no foreground scene, so `present` has
    /// nowhere to draw and returns early.
    internal struct Layout {
        enum Placement { case centre, bottomSheet, fullscreen, topBanner, bottomBanner }

        let placement: Placement

        init(messageType: String) {
            switch messageType {
            case "bottom_sheet": placement = .bottomSheet
            case "fullscreen": placement = .fullscreen
            case "banner_top": placement = .topBanner
            case "banner_bottom": placement = .bottomBanner
            default: placement = .centre
            }
        }

        /// A banner lets the app through; everything else is modal.
        var hasBackdrop: Bool {
            switch placement {
            case .topBanner, .bottomBanner: return false
            case .centre, .bottomSheet, .fullscreen: return true
            }
        }

        /// A banner and a sheet have far less room for a picture.
        var isCompact: Bool {
            switch placement {
            case .topBanner, .bottomBanner, .bottomSheet: return true
            case .centre, .fullscreen: return false
            }
        }

        /// Which way it arrives, when the campaign does not say.
        var defaultAnimation: String {
            switch placement {
            case .topBanner: return "slide_down"
            case .bottomBanner, .bottomSheet: return "slide_up"
            case .centre, .fullscreen: return "fade"
            }
        }

        /// A banner has nothing to tap, so it leaves on its own.
        var defaultAutoDismissSeconds: Int? {
            switch placement {
            case .topBanner, .bottomBanner: return 4
            case .centre, .bottomSheet, .fullscreen: return nil
            }
        }

        func constrain(card: UIView, in host: UIView) {
            let safe = host.safeAreaLayoutGuide
            let margin: CGFloat = 16

            switch placement {
            case .centre:
                NSLayoutConstraint.activate([
                    card.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                    card.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                    card.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: margin),
                    card.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -margin),
                    card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
                    card.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: margin),
                    card.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -margin),
                ])
                // Fill the width it is allowed, rather than hugging short copy.
                let width = card.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -2 * margin)
                width.priority = .defaultHigh
                width.isActive = true

            case .bottomSheet:
                NSLayoutConstraint.activate([
                    card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    // Past the bottom edge, so its rounded corners are only
                    // visible at the top — the shape a sheet has.
                    card.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: 24),
                    card.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: margin),
                ])

            case .fullscreen:
                NSLayoutConstraint.activate([
                    card.topAnchor.constraint(equalTo: host.topAnchor),
                    card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    card.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                ])

            case .topBanner, .bottomBanner:
                NSLayoutConstraint.activate([
                    card.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: margin),
                    card.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -margin),
                ])
                if placement == .topBanner {
                    card.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8).isActive = true
                } else {
                    card.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8).isActive = true
                }
            }
        }
    }

    // ── Animation ──────────────────────────────────────────────────────

    private func animateIn(layout: Layout) {
        guard let card = card else { return }
        let animation = message.theme?.animation ?? layout.defaultAnimation

        guard animation != "none" else {
            backdrop?.alpha = 1
            return
        }

        backdrop?.alpha = 0
        switch animation {
        case "slide_up":
            card.transform = CGAffineTransform(translationX: 0, y: 160)
        case "slide_down":
            card.transform = CGAffineTransform(translationX: 0, y: -160)
        case "scale":
            card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            card.alpha = 0
        default: // "fade"
            card.alpha = 0
        }

        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.backdrop?.alpha = 1
            card.transform = .identity
            card.alpha = 1
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let card = card else {
            completion()
            return
        }
        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.backdrop?.alpha = 0
                card.alpha = 0
            },
            completion: { _ in completion() }
        )
    }

    // ── Dismissal ──────────────────────────────────────────────────────

    private func armAutoDismiss(layout: Layout) {
        guard let seconds = message.autoDismissSeconds ?? layout.defaultAutoDismissSeconds,
              seconds > 0
        else { return }

        autoDismissTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(seconds),
            repeats: false
        ) { [weak self] _ in
            self?.finish(.autoDismissed)
        }
    }

    @objc private func backdropTapped() {
        finish(.dismissed)
    }

    /// Reports the outcome and takes the message away.
    ///
    /// Both halves happen exactly once. A tapped button and an auto-dismiss
    /// both end with the window going away, and reporting that as a
    /// dismissal *as well* would count every tap of every button against the
    /// message's own dismiss rate.
    private func finish(_ outcome: Outcome) {
        guard !hasFinished else { return }
        hasFinished = true

        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        onOutcome(outcome)

        animateOut { [self] in
            window?.isHidden = true
            window?.rootViewController = nil
            // The window is the only thing holding the view alive, and the
            // scene holds the window until it is released.
            window = nil
            card = nil
            backdrop = nil
        }
    }
}

/// The message's own root view. Touches that miss the card go to the app
/// below, which is what lets a banner be a banner rather than a takeover.
///
/// When the message has a backdrop, the backdrop *is* a subview covering
/// everything, so this returns it and nothing passes through.
private final class PassthroughView: UIView {

    weak var card: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // `self` means the touch landed on bare window: no backdrop to
        // swallow it and not inside the card.
        return hit === self ? nil : hit
    }
}
#endif
