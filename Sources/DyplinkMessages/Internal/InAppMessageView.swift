#if canImport(UIKit)
import Foundation
import UIKit

/// The card an in-app message is drawn on: its copy, its picture, its
/// buttons, and the theme's colours.
///
/// Everything the backend sends is rendered here, because every field is one
/// the dashboard offers — a value read and then dropped is a setting that
/// silently does nothing. The container around this card, and where on screen
/// it sits, belong to `InAppMessagePresenter`.
internal final class InAppMessageView: UIView {

    private let message: InAppMessage
    private let onButtonTapped: (MessageButton) -> Void
    private let onClose: () -> Void

    private let stack = UIStackView()
    private var imageView: UIImageView?
    private var imageTask: URLSessionDataTask?

    /// How tall a picture is drawn. A banner and a sheet have far less room
    /// than a modal, so the container says which it is.
    private let compact: Bool

    /// Whether to draw the close control.
    ///
    /// On for every layout that takes the app over, and not a campaign
    /// setting, because the campaign can legally ask for a message with no
    /// buttons, no auto-dismiss and no tap-outside — three defaults away
    /// from a modal at `.alert` window level that swallows every touch and
    /// cannot be closed. That is not a message the user can ignore, it is an
    /// app they have to force-quit.
    private let showsCloseButton: Bool

    init(
        message: InAppMessage,
        compact: Bool,
        showsCloseButton: Bool,
        onButtonTapped: @escaping (MessageButton) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.message = message
        self.compact = compact
        self.showsCloseButton = showsCloseButton
        self.onButtonTapped = onButtonTapped
        self.onClose = onClose
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        imageTask?.cancel()
    }

    // ── Construction ───────────────────────────────────────────────────

    private func build() {
        let theme = message.theme
        backgroundColor = UIColor(dyplinkHex: theme?.backgroundColor) ?? .systemBackground
        layer.cornerRadius = CGFloat(theme?.borderRadius ?? Self.defaultCornerRadius)
        layer.cornerCurve = .continuous
        // The picture at `background` is a subview, so it has to be clipped
        // to the same corners the card has.
        clipsToBounds = true

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let inset: CGFloat = compact ? 12 : 16
        // Room for the close control, so the title does not run under it.
        let trailingInset = inset + (showsCloseButton ? Self.closeButtonSize - inset / 2 : 0)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])

        let hasImage = (message.imageUrl?.isEmpty == false)
        let position = message.imagePosition

        if hasImage, position == "background" {
            addBackgroundImage()
        } else if hasImage, position == "top" {
            stack.addArrangedSubview(makeImageView())
        }

        if !message.title.isEmpty {
            stack.addArrangedSubview(makeTitleLabel())
        }
        if let body = message.body, !body.isEmpty {
            stack.addArrangedSubview(makeBodyLabel(body))
        }

        // `center` is "between the copy and the call to action", which is the
        // only reading that tells it apart from `top`.
        if hasImage, position == "center" {
            stack.addArrangedSubview(makeImageView())
        }

        for button in message.buttons ?? [] {
            stack.addArrangedSubview(makeButton(button))
        }

        // Last, so it is above the copy and the background picture both.
        if showsCloseButton {
            addCloseButton()
        }

        loadImageIfNeeded()
    }

    /// The one control the campaign cannot take away.
    ///
    /// Not in the stack: it sits in the card's own corner, over the copy and
    /// over a background picture both. 44pt square — Apple's minimum target
    /// — so the tap lands, and the whole of it is the button rather than a
    /// smaller glyph with dead space around it.
    private func addCloseButton() {
        let button = UIButton(
            type: .system,
            primaryAction: UIAction { [onClose] _ in onClose() }
        )
        let glyphColour = closeGlyphColour
        if let glyph = UIImage(systemName: "xmark") {
            button.setImage(
                glyph.withConfiguration(
                    UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                ),
                for: .normal
            )
            button.tintColor = glyphColour
        } else {
            // No SF Symbols is not a reason to ship a message nobody can close.
            button.setTitle("✕", for: .normal)
            button.setTitleColor(glyphColour, for: .normal)
        }
        // Faintly filled, so the glyph reads over a photograph as well as
        // over the theme's own background colour.
        button.backgroundColor = UIColor(white: 0.5, alpha: 0.18)
        button.layer.cornerRadius = Self.closeButtonSize / 2
        button.accessibilityLabel = Self.closeAccessibilityLabel
        // So a host app's UI tests can find it, and so can ours.
        button.accessibilityIdentifier = Self.closeAccessibilityIdentifier
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor, constant: Self.closeButtonMargin),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.closeButtonMargin),
            button.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            button.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),
        ])
    }

    /// The theme chose its colours against its own background; a photograph
    /// behind the card swallows a dark glyph entirely.
    private var closeGlyphColour: UIColor {
        if message.imagePosition == "background", message.imageUrl?.isEmpty == false {
            return .white
        }
        return UIColor(dyplinkHex: message.theme?.titleColor) ?? .secondaryLabel
    }

    private func makeTitleLabel() -> UILabel {
        let label = UILabel()
        label.text = message.title
        label.font = .systemFont(ofSize: compact ? 16 : 20, weight: .semibold)
        label.textColor = UIColor(dyplinkHex: message.theme?.titleColor) ?? .label
        label.numberOfLines = 0
        return label
    }

    private func makeBodyLabel(_ body: String) -> UILabel {
        let label = UILabel()
        label.text = body
        label.font = .systemFont(ofSize: 14)
        label.textColor = UIColor(dyplinkHex: message.theme?.textColor) ?? .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func makeImageView() -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.layer.cornerCurve = .continuous
        // Zero until the picture arrives, so a message whose image never
        // loads is the message without its image rather than a gap.
        view.isHidden = true
        view.heightAnchor.constraint(equalToConstant: compact ? 120 : 200).isActive = true
        imageView = view
        return view
    }

    private func addBackgroundImage() {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(view, at: 0)

        // The theme's text colours were chosen against the background
        // *colour*; a photograph swallows either of them.
        let scrim = UIView()
        scrim.backgroundColor = UIColor(dyplinkHex: message.theme?.overlayColor) ?? Self.backgroundScrim
        scrim.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(scrim, aboveSubview: view)

        for layer in [view, scrim] {
            NSLayoutConstraint.activate([
                layer.topAnchor.constraint(equalTo: topAnchor),
                layer.leadingAnchor.constraint(equalTo: leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: trailingAnchor),
                layer.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        imageView = view
    }

    private func makeButton(_ button: MessageButton) -> UIButton {
        let theme = message.theme
        // A `UIAction` rather than a target: `UIButton(type:)` does not run a
        // subclass's `init(frame:)`, so a subclass that wires its target
        // there compiles, renders, and never responds to a tap.
        let view = UIButton(
            type: .system,
            primaryAction: UIAction { [onButtonTapped] _ in onButtonTapped(button) }
        )
        view.setTitle(button.text, for: .normal)
        view.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        view.layer.cornerRadius = 8
        view.layer.cornerCurve = .continuous
        view.heightAnchor.constraint(equalToConstant: 44).isActive = true

        switch button.style {
        case "text":
            view.backgroundColor = .clear
            view.setTitleColor(UIColor(dyplinkHex: theme?.buttonPrimaryColor) ?? Self.accent, for: .normal)
        case "secondary":
            view.backgroundColor = UIColor(dyplinkHex: theme?.buttonSecondaryColor) ?? .secondarySystemFill
            view.setTitleColor(.label, for: .normal)
        default:
            view.backgroundColor = UIColor(dyplinkHex: theme?.buttonPrimaryColor) ?? Self.accent
            view.setTitleColor(.white, for: .normal)
        }

        return view
    }

    // ── Image loading ──────────────────────────────────────────────────

    /// Fetches the picture, and leaves the message without one on any
    /// failure. A campaign that arrives is worth more than one rendered
    /// exactly, and the host app has nothing to do about a dead image URL.
    private func loadImageIfNeeded() {
        guard let view = imageView,
              let raw = message.imageUrl,
              let url = URL(string: raw)
        else { return }

        imageTask = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                view.image = image
                view.isHidden = false
            }
        }
        imageTask?.resume()
    }

    // ── Defaults ───────────────────────────────────────────────────────

    /// Matches the Android SDK's, so one campaign looks like one campaign.
    private static let defaultCornerRadius = 12
    /// Apple's minimum tap target, and the whole control is tappable.
    static let closeButtonSize: CGFloat = 44
    private static let closeButtonMargin: CGFloat = 4
    private static let closeAccessibilityLabel = "Close"
    /// How a test — ours or a host app's — finds the close control.
    static let closeAccessibilityIdentifier = "dyplink.message.close"
    private static let accent = UIColor(red: 0.098, green: 0.463, blue: 0.824, alpha: 1) // #1976D2
    /// Black at 40%, dark enough for white copy over a bright photo.
    private static let backgroundScrim = UIColor(white: 0, alpha: 0.4)
}

internal extension UIColor {

    /// Parses a theme colour.
    ///
    /// Accepts what the Android SDK's `Color.parseColor` accepts and the
    /// dashboard's colour pickers emit — `#RGB`, `#RRGGBB`, `#AARRGGBB`,
    /// with or without the `#` — and answers `nil` for anything else so the
    /// caller falls back to a system colour. A campaign with one mistyped
    /// colour must still be readable, not invisible.
    convenience init?(dyplinkHex hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("#") { text.removeFirst() }

        // Expand #RGB to #RRGGBB.
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit),
              let value = UInt32(text, radix: 16)
        else { return nil }

        let hasAlpha = text.count == 8
        let alpha = hasAlpha ? CGFloat((value >> 24) & 0xFF) / 255 : 1
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
