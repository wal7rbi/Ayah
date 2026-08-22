// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AyahKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AyahKit", targets: ["AyahKit"])
    ],
    dependencies: [
        // Offline prayer-time calculation — ARCHITECTURE.md §9. Zero
        // dependencies of its own, no networking.
        .package(url: "https://github.com/batoulapps/adhan-swift.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "AyahKit",
            dependencies: [.product(name: "Adhan", package: "adhan-swift")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "AyahKitTests",
            dependencies: ["AyahKit", .product(name: "Adhan", package: "adhan-swift")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
