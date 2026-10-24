// swift-tools-version:5.9
//
// Command Line Tools build for Logoer.
//
// This exists so the app can be built and packaged without a full Xcode install:
// `swift build` compiles the sources and resolves the same package dependencies
// (pinned in Package.resolved), then `scripts/build.sh` assembles the .app bundle
// by hand. The Xcode project remains the source of truth for Developer ID signing
// and Sparkle releases; keep the dependency versions in both places in sync.
import PackageDescription

let package = Package(
    name: "Logoer",
    platforms: [.macOS(.v11)],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", exact: "3.1.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.6.4"),
    ],
    targets: [
        .executableTarget(
            name: "Logoer",
            dependencies: [
                .product(name: "SDWebImageSwiftUI", package: "SDWebImageSwiftUI"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Logoer",
            // Handled by scripts/build.sh, not by SwiftPM. Assets.xcassets needs
            // `actool` (Xcode only), so the script flattens it into loose files in
            // Contents/Resources and the app loads artwork through logoImage()/
            // logoColor(), which check NSImage/NSColor as well as the catalog.
            exclude: [
                "Assets.xcassets",
                "Resources",
                "zh-Hans.lproj",
                "Preview Content",
                "Info.plist",
                "Logoer.entitlements",
            ]
        )
    ]
)
