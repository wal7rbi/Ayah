import Foundation
import XCTest
@testable import AyahKit

enum PerformanceTestSupport {
    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    static var quranResourcesDirectory: URL {
        repositoryRoot.appendingPathComponent("Resources/Quran", isDirectory: true)
    }

    static var geoNamesResourcesDirectory: URL {
        repositoryRoot.appendingPathComponent("Resources/GeoNames", isDirectory: true)
    }

    static func makeQuranRepository() throws -> QuranRepository {
        let directory = quranResourcesDirectory
        let databasePath = directory.appendingPathComponent("quran.sqlite").path
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw XCTSkip("quran.sqlite not found at \(databasePath) — run Scripts/import_quran first")
        }
        return try QuranRepository(
            databasePath: databasePath,
            checksumPath: directory.appendingPathComponent("CHECKSUM").path
        )
    }

    static func makeLocationRepository() throws -> LocationRepository {
        let directory = geoNamesResourcesDirectory
        let databasePath = directory.appendingPathComponent("cities_filtered.sqlite").path
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw XCTSkip("cities_filtered.sqlite not found at \(databasePath) — run Scripts/import_geonames first")
        }
        return try LocationRepository(
            databasePath: databasePath,
            checksumPath: directory.appendingPathComponent("GEONAMES_CHECKSUM").path
        )
    }

    static func makeMemorizationRepository() throws -> (repository: MemorizationRepository, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ayah-performance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            try MemorizationRepository(databasePath: directory.appendingPathComponent("ayah_user.sqlite").path),
            directory
        )
    }

    static func measureOptions(iterationCount: Int = 10) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterationCount
        return options
    }
}
