// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnscrollKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "UnscrollKit", targets: ["UnscrollKit"]),
        .library(name: "UnscrollShared", targets: ["UnscrollShared"]),
    ],
    targets: [
        // Pure logic: pose model, detectors, earning rules, ledger, streaks. Runs on macOS for tests.
        .target(name: "UnscrollKit"),
        // iOS Screen Time glue shared by the app and its extensions.
        .target(name: "UnscrollShared", dependencies: ["UnscrollKit"]),
        .testTarget(name: "UnscrollKitTests", dependencies: ["UnscrollKit"]),
    ]
)
