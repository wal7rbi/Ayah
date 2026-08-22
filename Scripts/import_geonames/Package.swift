// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "import_geonames",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "import_geonames",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
