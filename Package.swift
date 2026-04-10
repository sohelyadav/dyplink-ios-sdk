// swift-tools-version: 5.9
// Dyplink iOS SDK — Swift Package Manager manifest.
//
// Four products mirror the four Android SDK modules:
//
//   DyplinkCore     — identity, events, deep links, offline queue, sessions.
//                     The minimal module: `.package(url: ...)` + `.product(name: "DyplinkCore")`.
//   DyplinkPush     — APNs push token registration. Depends on DyplinkCore.
//   DyplinkBanners  — native `BannerCarouselView` (UICollectionView). Depends on DyplinkCore.
//   DyplinkMessages — in-app message overlay. Depends on DyplinkCore.
//
// Apps pick only the products they need; DyplinkCore is the only mandatory one.
//
// Min iOS 14 — required for async/await, NWPathMonitor, modern UICollectionView.

import PackageDescription

let package = Package(
    name: "Dyplink",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(name: "DyplinkCore", targets: ["DyplinkCore"]),
        .library(name: "DyplinkPush", targets: ["DyplinkPush"]),
        .library(name: "DyplinkBanners", targets: ["DyplinkBanners"]),
        .library(name: "DyplinkMessages", targets: ["DyplinkMessages"]),
    ],
    dependencies: [
        // No external dependencies — URLSession + Foundation only.
    ],
    targets: [
        // ── Core ───────────────────────────────────────────────────────
        .target(
            name: "DyplinkCore",
            path: "Sources/DyplinkCore"
        ),
        .testTarget(
            name: "DyplinkCoreTests",
            dependencies: ["DyplinkCore"],
            path: "Tests/DyplinkCoreTests"
        ),

        // ── Push ───────────────────────────────────────────────────────
        .target(
            name: "DyplinkPush",
            dependencies: ["DyplinkCore"],
            path: "Sources/DyplinkPush"
        ),

        // ── Banners ────────────────────────────────────────────────────
        .target(
            name: "DyplinkBanners",
            dependencies: ["DyplinkCore"],
            path: "Sources/DyplinkBanners"
        ),
        .testTarget(
            name: "DyplinkBannersTests",
            dependencies: ["DyplinkBanners"],
            path: "Tests/DyplinkBannersTests"
        ),

        // ── Messages ───────────────────────────────────────────────────
        .target(
            name: "DyplinkMessages",
            dependencies: ["DyplinkCore"],
            path: "Sources/DyplinkMessages"
        ),
        .testTarget(
            name: "DyplinkMessagesTests",
            dependencies: ["DyplinkMessages"],
            path: "Tests/DyplinkMessagesTests"
        ),
    ]
)
