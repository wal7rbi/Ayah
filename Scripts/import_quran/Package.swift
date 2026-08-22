// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "import_quran",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "import_quran",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
