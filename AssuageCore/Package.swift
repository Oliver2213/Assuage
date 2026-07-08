// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AssuageCore",
    platforms: [
        // The app deploys to newer OSes, but the core only needs a floor recent
        // enough for CryptoKit's Secure Enclave APIs — and at least AgeKit's iOS
        // 14. (iOS 18 parallels the macOS 15 floor; the app can deploy higher.)
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "AssuageCore", targets: ["AssuageCore"]),
    ],
    dependencies: [
        // The user-provided age implementation. Referenced by local path for now;
        // its GitHub remote is https://github.com/jamesog/AgeKit
        .package(path: "/Users/blakeoliver/src/AgeKit"),
    ],
    targets: [
        .target(
            name: "AssuageCore",
            dependencies: [
                .product(name: "AgeKit", package: "AgeKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "AssuageCoreTests",
            dependencies: ["AssuageCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
