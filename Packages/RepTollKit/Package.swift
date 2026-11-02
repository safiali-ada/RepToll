// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RepTollKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RepTollKit", targets: ["RepTollKit"]),
        .library(name: "RepTollShared", targets: ["RepTollShared"]),
    ],
    targets: [
        // Pure logic: pose model, detectors, earning rules, ledger, streaks. Runs on macOS for tests.
        .target(name: "RepTollKit"),
        // iOS Screen Time glue shared by the app and its extensions.
        .target(name: "RepTollShared", dependencies: ["RepTollKit"]),
        .testTarget(name: "RepTollKitTests", dependencies: ["RepTollKit"], resources: [.copy("Fixtures")]),
    ]
)
