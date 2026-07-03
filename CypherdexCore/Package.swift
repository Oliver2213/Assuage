// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CypherdexCore",
    platforms: [
        // The app deploys to a newer macOS, but the core logic only needs a
        // floor recent enough for CryptoKit's Secure Enclave APIs.
        .macOS(.v15)
    ],
    products: [
        .library(name: "CypherdexCore", targets: ["CypherdexCore"]),
    ],
    dependencies: [
        // The user-provided age implementation. Referenced by local path for now;
        // its GitHub remote is https://github.com/jamesog/AgeKit
        .package(path: "/Users/blakeoliver/src/AgeKit"),
    ],
    targets: [
        .target(
            name: "CypherdexCore",
            dependencies: [
                .product(name: "AgeKit", package: "AgeKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "CypherdexCoreTests",
            dependencies: ["CypherdexCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
