#if canImport(UIKit)
import UIKit
import DyplinkCore

/// A horizontally-paging banner carousel backed by `UICollectionView`.
///
/// Mirrors the Android `BannerCarouselView` (ViewPager2-based). Loads
/// banners from the Dyplink API when `categoryId` is set. Supports
/// auto-rotation.
///
/// Usage:
/// ```swift
/// let carousel = BannerCarouselView()
/// carousel.categoryId = "home-top"
/// carousel.onBannerTap = { banner in print(banner.clickUrl) }
/// view.addSubview(carousel)
/// ```
public final class BannerCarouselView: UIView {

    // ── Public API ─────────────────────────────────────────────────────

    /// Set to trigger an API load + display.
    public var categoryId: String? {
        didSet { if let id = categoryId { loadBanners(id) } }
    }

    /// Called when a banner is tapped.
    public var onBannerTap: ((DyplinkBanner) -> Void)?

    /// Manually set banner data without an API call.
    public func setBanners(_ category: BannerCategory) {
        self.category = category
        self.banners = category.banners
        collectionView.reloadData()
        if category.autoRotate {
            startAutoRotation(interval: TimeInterval(category.rotationInterval))
        }
    }

    // ── Private state ──────────────────────────────────────────────────

    private var category: BannerCategory?
    private var banners: [DyplinkBanner] = []
    private let apiClient = BannerApiClient()
    private var autoRotateTimer: Timer?

    private lazy var layout: UICollectionViewFlowLayout = {
        let l = UICollectionViewFlowLayout()
        l.scrollDirection = .horizontal
        l.minimumLineSpacing = 0
        return l
    }()

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(BannerCell.self, forCellWithReuseIdentifier: BannerCell.reuseId)
        cv.backgroundColor = .clear
        return cv
    }()

    private let headingLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        l.isHidden = true
        return l
    }()

    // ── Init ───────────────────────────────────────────────────────────

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(headingLabel)
        addSubview(collectionView)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let headingHeight: CGFloat = headingLabel.isHidden ? 0 : 40
        headingLabel.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: headingHeight)
        collectionView.frame = CGRect(
            x: 0, y: headingHeight,
            width: bounds.width,
            height: bounds.height - headingHeight
        )
        layout.itemSize = collectionView.bounds.size
    }

    // ── Loading ────────────────────────────────────────────────────────

    private func loadBanners(_ id: String) {
        Task { @MainActor in
            do {
                let cat = try await apiClient.fetchBanners(categoryId: id)
                setBanners(cat)
                if let heading = cat.heading {
                    headingLabel.text = heading
                    headingLabel.isHidden = false
                }
            } catch {
                // Fail silently — banner space stays empty.
            }
        }
    }

    // ── Auto-rotation ──────────────────────────────────────────────────

    public func startAutoRotation(interval: TimeInterval = 5) {
        stopAutoRotation()
        autoRotateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advancePage()
        }
    }

    public func stopAutoRotation() {
        autoRotateTimer?.invalidate()
        autoRotateTimer = nil
    }

    private func advancePage() {
        guard banners.count > 1 else { return }
        let visible = collectionView.indexPathsForVisibleItems.sorted()
        guard let current = visible.first else { return }
        let nextItem = (current.item + 1) % banners.count
        collectionView.scrollToItem(
            at: IndexPath(item: nextItem, section: 0),
            at: .centeredHorizontally,
            animated: true
        )
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension BannerCarouselView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        banners.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BannerCell.reuseId, for: indexPath) as! BannerCell
        cell.configure(with: banners[indexPath.item])
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let banner = banners[indexPath.item]
        Task { await apiClient.trackClick(bannerId: banner.id) }
        onBannerTap?(banner)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }
}

// MARK: - BannerCell

private final class BannerCell: UICollectionViewCell {
    static let reuseId = "DyplinkBannerCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textAlignment = .center
        l.numberOfLines = 2
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelHeight: CGFloat = 40
        imageView.frame = CGRect(
            x: 0, y: 0,
            width: contentView.bounds.width,
            height: contentView.bounds.height - labelHeight
        )
        titleLabel.frame = CGRect(
            x: 8, y: contentView.bounds.height - labelHeight,
            width: contentView.bounds.width - 16,
            height: labelHeight
        )
    }

    func configure(with banner: DyplinkBanner) {
        titleLabel.text = banner.title
        imageView.image = nil
        if let urlString = banner.imageUrl, let url = URL(string: urlString) {
            BannerImageLoader.shared.load(url: url) { [weak self] image in
                self?.imageView.image = image
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        titleLabel.text = nil
    }
}
#endif
