// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "verify_quran",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "verify_quran",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
