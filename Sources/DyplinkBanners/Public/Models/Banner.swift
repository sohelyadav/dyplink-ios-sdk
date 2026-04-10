import Foundation
import DyplinkCore

/// A single banner within a category.
public struct DyplinkBanner: Sendable, Equatable {
    public let id: String
    public let title: String
    public let imageUrl: String?
    public let clickUrl: String?
    public let ctaText: String?
    public let sortOrder: Int
    public let isActive: Bool
    public let metadata: [String: AnyJSONValue]?

    public init(
        id: String,
        title: String,
        imageUrl: String? = nil,
        clickUrl: String? = nil,
        ctaText: String? = nil,
        sortOrder: Int = 0,
        isActive: Bool = true,
        metadata: [String: AnyJSONValue]? = nil
    ) {
        self.id = id
        self.title = title
        self.imageUrl = imageUrl
        self.clickUrl = clickUrl
        self.ctaText = ctaText
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.metadata = metadata
    }
}

/// A category of banners with layout/display settings.
public struct BannerCategory: Sendable, Equatable {
    public let id: String
    public let name: String
    public let layout: String
    public let aspectRatio: String?
    public let autoRotate: Bool
    public let rotationInterval: Int
    public let heading: String?
    public let backgroundColor: String
    public let padding: Int
    public let banners: [DyplinkBanner]

    public init(
        id: String,
        name: String,
        layout: String = "carousel",
        aspectRatio: String? = nil,
        autoRotate: Bool = true,
        rotationInterval: Int = 5,
        heading: String? = nil,
        backgroundColor: String = "#ffffff",
        padding: Int = 0,
        banners: [DyplinkBanner] = []
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.aspectRatio = aspectRatio
        self.autoRotate = autoRotate
        self.rotationInterval = rotationInterval
        self.heading = heading
        self.backgroundColor = backgroundColor
        self.padding = padding
        self.banners = banners
    }
}
