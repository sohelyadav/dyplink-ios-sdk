import XCTest
import DyplinkBanners

final class BannerModelTests: XCTestCase {
    func testBannerCategoryInit() {
        let category = BannerCategory(id: "home", name: "Home")
        XCTAssertEqual(category.id, "home")
        XCTAssertEqual(category.layout, "carousel")
        XCTAssertTrue(category.banners.isEmpty)
    }
}
