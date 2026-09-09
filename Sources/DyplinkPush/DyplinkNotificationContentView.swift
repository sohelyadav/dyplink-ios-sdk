#if canImport(UIKit)
import Foundation
import UIKit

/// The view a Notification Content Extension installs to show a campaign's
/// carousel and countdown. Build it with
/// `DyplinkNotificationContent.makeView(for:)` — the initialiser is internal
/// because a view with neither slides nor a countdown has nothing to draw,
/// and deciding that is the factory's job.
///
/// A view rather than a view controller, for two reasons. The extension
/// already owns a `UIViewController` that iOS created and sizes through
/// `preferredContentSize`, so a child controller would mean an
/// `addChild`/`didMove` dance around a parent the host does not really
/// control. And a content extension's controller is not reliably sent
/// `viewWillDisappear` — the process is usually just killed — so hanging the
/// countdown's lifetime off controller callbacks would leave it running.
/// `didMoveToWindow` always arrives, which is what makes a view the safer
/// place for a repeating timer to live.
public final class DyplinkNotificationContentView: UIView {

    // ── Public API ─────────────────────────────────────────────────────

    /// The slides being paged through, in order. Empty for a countdown-only
    /// campaign.
    public let slides: [PushCarouselSlide]

    /// The countdown being shown, or `nil` for a carousel-only campaign.
    public let timer: PushTimer?

    /// Which slide is on screen. `0` when there are no slides.
    public private(set) var currentSlideIndex: Int = 0

    /// The slide on screen, so the extension can attribute a tap to it —
    /// `currentSlide?.deepLinkUrl` is the destination that was being looked at
    /// when the user tapped. `nil` for a countdown-only campaign.
    public var currentSlide: PushCarouselSlide? {
        slides.indices.contains(currentSlideIndex) ? slides[currentSlideIndex] : nil
    }

    /// Show a particular slide. Out-of-range indices are ignored: the caller
    /// is usually working from a stale count or a tap that raced the payload,
    /// and neither is worth trapping over inside an extension.
    public func showSlide(at index: Int) {
        guard slides.indices.contains(index) else { return }
        currentSlideIndex = index
        pageControl.currentPage = index
        scrollToCurrentSlide()
    }

    /// Advance one slide, wrapping past the last — the same wrap the in-app
    /// `BannerCarouselView` uses. A notification carousel is short enough that
    /// stopping dead at the end reads as a bug.
    public func showNextSlide() {
        guard !slides.isEmpty else { return }
        showSlide(at: (currentSlideIndex + 1) % slides.count)
    }

    /// Go back one slide, wrapping before the first.
    public func showPreviousSlide() {
        guard !slides.isEmpty else { return }
        showSlide(at: (currentSlideIndex - 1 + slides.count) % slides.count)
    }

    // ── Layout constants ───────────────────────────────────────────────

    private enum Layout {
        static let pageControlHeight: CGFloat = 24
        static let countdownHeight: CGFloat = 46
        static let expiredBodyHeight: CGFloat = 22
        static let horizontalInset: CGFloat = 12
    }

    /// A campaign image far larger than this is a mistake rather than a
    /// choice, and decoding one costs several times its own size in memory —
    /// which a content extension has very little of.
    private static let maxImageBytes = 10 * 1024 * 1024

    /// Long enough for a slow connection, short enough that a stalled CDN
    /// gives up while the notification is still on screen.
    private static let imageTimeout: TimeInterval = 15

    // ── Views ──────────────────────────────────────────────────────────

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.backgroundColor = .clear
        // The extension's view is short; a bounce here fights the shade's own.
        view.alwaysBounceHorizontal = false
        return view
    }()

    private let pageControl: UIPageControl = {
        let control = UIPageControl()
        control.isUserInteractionEnabled = false
        control.hidesForSinglePage = true
        return control
    }()

    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        // Monospaced digits so the countdown does not jitter as the numbers
        // change width — the one place per second a proportional font shows.
        label.font = .monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.textColor = .label
        return label
    }()

    private let expiredBodyLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.isHidden = true
        return label
    }()

    private var pages: [SlidePageView] = []
    private var countdownTimer: Timer?
    private var imageTasks: [URLSessionDataTask] = []

    // ── Init ───────────────────────────────────────────────────────────

    internal init(slides: [PushCarouselSlide], timer: PushTimer?) {
        self.slides = slides
        self.timer = timer
        super.init(frame: .zero)

        backgroundColor = .clear
        scrollView.delegate = self

        for slide in slides {
            let page = SlidePageView(slide: slide)
            pages.append(page)
            scrollView.addSubview(page)
        }
        if !slides.isEmpty {
            addSubview(scrollView)
            pageControl.numberOfPages = slides.count
            addSubview(pageControl)
        }

        if timer != nil {
            addSubview(countdownLabel)
            addSubview(expiredBodyLabel)
            // Paint the countdown before it ticks, so the view never appears
            // with an empty gap for a second — and so an already-expired
            // campaign shows its expired copy without needing a tick at all.
            refreshCountdown()
        } else {
            countdownLabel.isHidden = true
        }

        loadImages()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("DyplinkNotificationContentView is built by DyplinkNotificationContent.makeView(for:)")
    }

    deinit {
        // Both also happen when the view leaves its window; this is the case
        // where it never had one.
        countdownTimer?.invalidate()
        imageTasks.forEach { $0.cancel() }
    }

    // ── Layout ─────────────────────────────────────────────────────────

    public override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        let contentWidth = max(0, width - Layout.horizontalInset * 2)
        let countdownHeight = countdownLabel.isHidden ? 0 : Layout.countdownHeight
        let expiredBodyHeight = expiredBodyLabel.isHidden ? 0 : Layout.expiredBodyHeight
        let pageControlHeight = pages.count > 1 ? Layout.pageControlHeight : 0
        let carouselHeight = max(
            0,
            bounds.height - countdownHeight - expiredBodyHeight - pageControlHeight
        )

        scrollView.frame = CGRect(x: 0, y: 0, width: width, height: carouselHeight)
        for (index, page) in pages.enumerated() {
            page.frame = CGRect(
                x: CGFloat(index) * width, y: 0,
                width: width, height: carouselHeight
            )
        }
        scrollView.contentSize = CGSize(
            width: width * CGFloat(pages.count),
            height: carouselHeight
        )
        // The index is what says which slide is showing, so a resize moves the
        // offset to match it — never the other way round, which would land
        // between two slides and report whichever won the rounding.
        scrollView.contentOffset = CGPoint(x: CGFloat(currentSlideIndex) * width, y: 0)

        var y = carouselHeight
        pageControl.frame = CGRect(x: 0, y: y, width: width, height: pageControlHeight)
        y += pageControlHeight
        countdownLabel.frame = CGRect(
            x: Layout.horizontalInset, y: y,
            width: contentWidth, height: countdownHeight
        )
        y += countdownHeight
        expiredBodyLabel.frame = CGRect(
            x: Layout.horizontalInset, y: y,
            width: contentWidth, height: expiredBodyHeight
        )
    }

    private func scrollToCurrentSlide() {
        guard bounds.width > 0 else { return }
        scrollView.contentOffset = CGPoint(x: CGFloat(currentSlideIndex) * bounds.width, y: 0)
    }

    // ── Countdown ──────────────────────────────────────────────────────

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // A repeating timer left running in an extension is a battery
        // complaint, and the window is the only signal that reliably arrives
        // when the notification is dismissed — a content extension's view
        // controller is often never told it disappeared, because the process
        // is killed instead.
        if window == nil {
            stopCountdown()
            imageTasks.forEach { $0.cancel() }
        } else {
            startCountdown()
        }
    }

    private func startCountdown() {
        guard let timer = timer, countdownTimer == nil else { return }
        refreshCountdown()
        // Nothing left to count. Scheduling here would be a timer whose only
        // job is to invalidate itself on its first tick.
        guard !timer.hasExpired else { return }

        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshCountdown()
        }
        // A second is a long time to the scheduler; letting it coalesce our
        // wakeup with one it was making anyway costs nothing visible.
        ticker.tolerance = 0.25
        // `.common`, not the default mode: a default-mode timer stops firing
        // while the user drags the carousel, which is exactly when a frozen
        // countdown gets noticed.
        RunLoop.main.add(ticker, forMode: .common)
        countdownTimer = ticker
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    /// Redraws the countdown from the clock, and switches to the expired copy
    /// the first time it reaches zero.
    private func refreshCountdown() {
        guard let timer = timer else { return }

        let remaining = timer.endsAt.timeIntervalSinceNow
        guard remaining <= 0 else {
            countdownLabel.text = Self.formattedCountdown(remaining: remaining)
            return
        }

        stopCountdown()
        showExpiredCopy(for: timer)
    }

    private func showExpiredCopy(for timer: PushTimer) {
        // The backend's contract is that absent expired copy falls back to the
        // campaign's own title and body — which the notification is already
        // showing above this view. So there is nothing left to draw, and a
        // zeroed clock would only be a worse version of it.
        countdownLabel.isHidden = timer.expiredTitle == nil
        countdownLabel.text = timer.expiredTitle
        // Expired copy is prose, not digits; the countdown's size and
        // monospacing stop earning their keep the moment it stops counting.
        countdownLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        expiredBodyLabel.isHidden = timer.expiredBody == nil
        expiredBodyLabel.text = timer.expiredBody

        setNeedsLayout()
    }

    /// Formats a positive interval as a clock. Days are spelled out with a
    /// suffix because `51:14:07` reads as an error rather than as two days.
    internal static func formattedCountdown(remaining: TimeInterval) -> String {
        let total = Int(max(0, remaining.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // ── Images ─────────────────────────────────────────────────────────

    /// Fills the slides in as their pictures arrive.
    ///
    /// A slide whose image never loads keeps its caption, and the campaign's
    /// own title and body are on screen above regardless — so a dead image URL
    /// costs a picture, never the notification.
    private func loadImages() {
        for (index, slide) in slides.enumerated() {
            var request = URLRequest(url: slide.imageUrl)
            request.timeoutInterval = Self.imageTimeout

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                guard let data = data,
                      !data.isEmpty,
                      data.count <= Self.maxImageBytes,
                      Self.isSuccessful(response),
                      let image = UIImage(data: data)
                else { return }

                DispatchQueue.main.async {
                    guard let self = self, self.pages.indices.contains(index) else { return }
                    self.pages[index].setImage(image)
                }
            }
            imageTasks.append(task)
            task.resume()
        }
    }

    /// A CDN's 404 page is a successful download of something that is not the
    /// campaign's image, and `UIImage` will happily decode nothing from it.
    private static func isSuccessful(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }

    // ── Test hooks ─────────────────────────────────────────────────────

    /// Test-only: what the countdown line currently reads, or `nil` when it is
    /// not being shown.
    internal var countdownText: String? {
        countdownLabel.isHidden ? nil : countdownLabel.text
    }

    /// Test-only: what the expired body line currently reads, if any.
    internal var expiredBodyText: String? {
        expiredBodyLabel.isHidden ? nil : expiredBodyLabel.text
    }

    /// Test-only: whether a repeating timer is currently scheduled.
    internal var isCountdownRunning: Bool { countdownTimer != nil }
}

// MARK: - UIScrollViewDelegate

extension DyplinkNotificationContentView: UIScrollViewDelegate {

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only a scroll the user is driving moves the index. Programmatic
        // offsets — `showSlide(at:)` and the restore in `layoutSubviews` —
        // are set *from* the index, and reading them back would let a resize
        // mid-animation reset it.
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating,
              bounds.width > 0,
              !slides.isEmpty
        else { return }

        let page = Int((scrollView.contentOffset.x / bounds.width).rounded())
        let clamped = min(max(page, 0), slides.count - 1)
        guard clamped != currentSlideIndex else { return }

        currentSlideIndex = clamped
        pageControl.currentPage = clamped
    }
}

// MARK: - SlidePageView

/// One frame of the carousel: the campaign's picture with its caption beneath.
private final class SlidePageView: UIView {

    private let imageView: UIImageView = {
        let view = UIImageView()
        // Aspect *fit*, unlike the in-app banner carousel: a notification
        // image is the campaign's whole message and cropping it to fill would
        // cut the half that carries the offer.
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 2
        return label
    }()

    private let hasCaption: Bool

    init(slide: PushCarouselSlide) {
        hasCaption = slide.caption != nil
        super.init(frame: .zero)

        backgroundColor = .clear
        captionLabel.text = slide.caption
        captionLabel.isHidden = !hasCaption
        addSubview(imageView)
        addSubview(captionLabel)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func setImage(_ image: UIImage) {
        imageView.image = image
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset: CGFloat = 12
        let contentWidth = max(0, bounds.width - inset * 2)
        var captionHeight: CGFloat = 0
        if hasCaption, contentWidth > 0 {
            let fitting = captionLabel.sizeThatFits(
                CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            )
            captionHeight = min(fitting.height, 40)
        }

        captionLabel.frame = CGRect(
            x: inset, y: max(0, bounds.height - captionHeight),
            width: contentWidth, height: captionHeight
        )
        imageView.frame = CGRect(
            x: 0, y: 0,
            width: bounds.width,
            height: max(0, bounds.height - captionHeight)
        )
    }
}
#endif
