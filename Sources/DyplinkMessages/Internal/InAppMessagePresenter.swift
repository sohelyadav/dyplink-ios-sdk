#if canImport(UIKit)
import UIKit

/// Presents an in-app message as a modal overlay on top of the
/// current window's root view controller.
///
/// Simplified implementation — real-world SDKs may render richer UI
/// (images, themes, animations). This covers the structural contract
/// (modal with title, body, buttons, dismiss, auto-dismiss).
internal final class InAppMessagePresenter {

    private let message: InAppMessage
    private let onAction: (_ action: String, _ button: MessageButton?) -> Void

    init(
        message: InAppMessage,
        onAction: @escaping (_ action: String, _ button: MessageButton?) -> Void
    ) {
        self.message = message
        self.onAction = onAction
    }

    @MainActor
    func present() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController?.topMost
        else { return }

        let alert = UIAlertController(
            title: message.title,
            message: message.body,
            preferredStyle: message.messageType == "bottom_sheet" ? .actionSheet : .alert
        )

        // Buttons
        for button in message.buttons ?? [] {
            let style: UIAlertAction.Style = button.action == "dismiss" ? .cancel : .default
            alert.addAction(UIAlertAction(title: button.text, style: style) { [onAction] _ in
                onAction(button.action, button)
            })
        }

        // Fallback dismiss if no buttons were provided.
        if (message.buttons ?? []).isEmpty {
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [onAction] _ in
                onAction("dismiss", nil)
            })
        }

        // Dismiss-on-tap-outside.
        if message.dismissOnTapOutside {
            // UIAlertController doesn't natively support tap-outside
            // dismissal for .alert style; we skip this for simplicity.
        }

        rootVC.present(alert, animated: true)

        // Auto-dismiss.
        if let seconds = message.autoDismissSeconds, seconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak alert, onAction] in
                alert?.dismiss(animated: true) {
                    onAction("dismiss", nil)
                }
            }
        }
    }
}

private extension UIViewController {
    /// Walk the presentation chain to find the topmost presented VC.
    var topMost: UIViewController {
        if let presented = presentedViewController {
            return presented.topMost
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMost ?? self
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMost ?? self
        }
        return self
    }
}
#endif
