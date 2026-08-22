import Foundation
import XCTest
@testable import AyahKit

final class QuranRepositoryTests: XCTestCase {
    /// See `QuranIntegrityTests.quranResourcesDir` for why this is
    /// resolved via `#filePath` rather than an SPM package resource.
    private static var quranResourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Quran")
    }

    private func makeRepository() throws -> QuranRepository {
        let dir = Self.quranResourcesDir
        let dbPath = dir.appendingPathComponent("quran.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("quran.sqlite not found at \(dbPath) — run Scripts/import_quran first")
        }
        return try QuranRepository(
            databasePath: dbPath,
            checksumPath: dir.appendingPathComponent("CHECKSUM").path
        )
    }

    func testInitSucceedsAgainstBundledData() throws {
        _ = try makeRepository()
    }

    func testInitFailsWithWrongChecksum() throws {
        let dir = Self.quranResourcesDir
        let dbPath = dir.appendingPathComponent("quran.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("quran.sqlite not found at \(dbPath) — run Scripts/import_quran first")
        }

        let bogusChecksumFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "sha256:0000000000000000000000000000000000000000000000000000000000000000"
            .write(to: bogusChecksumFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bogusChecksumFile) }

        XCTAssertThrowsError(
            try QuranRepository(databasePath: dbPath, checksumPath: bogusChecksumFile.path)
        ) { error in
            XCTAssertEqual(error as? QuranIntegrityError, .checksumMismatch)
        }
    }

    func testFirstAyahIsAlFatihahOpening() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.ayah(surah: 1, ayah: 1))
        XCTAssertEqual(ayah.id, 1)
        XCTAssertEqual(ayah.juzNumber, 1)
        XCTAssertEqual(ayah.pageNumber, 1)
        XCTAssertFalse(ayah.uthmanicText.isEmpty)
        XCTAssertEqual(ayah.uthmanicText, repository.ayah(id: 1)?.uthmanicText)
    }

    func testOutOfRangeAyahReturnsNil() throws {
        let repository = try makeRepository()
        XCTAssertNil(repository.ayah(surah: 1, ayah: 999))
        XCTAssertNil(repository.ayah(id: 0))
        XCTAssertNil(repository.ayah(id: 6237))
    }

    func testSurahsReturnsAllOneHundredFourteen() throws {
        let repository = try makeRepository()
        let surahs = repository.surahs()
        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(surahs.first?.number, 1)
        XCTAssertEqual(surahs.last?.number, 114)
    }

    func testRandomAyahReturnsAValidAyah() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.randomAyah())
        XCTAssertTrue((1...6236).contains(ayah.id))
    }

    func testRandomAyahSearchableTextContainsReturnsAMatchingAyah() throws {
        let repository = try makeRepository()
        let ayah = try XCTUnwrap(repository.randomAyah(searchableTextContains: "صلاة"))
        XCTAssertTrue(ayah.searchableText.contains("صلاة"))
        XCTAssertFalse(ayah.uthmanicText.isEmpty)
    }

    func testRandomAyahSearchableTextContainsCanReturnDifferentAyahs() throws {
        let repository = try makeRepository()
        let ids = Set((0..<20).compactMap { _ in repository.randomAyah(searchableTextContains: "صلاة")?.id })
        XCTAssertGreaterThanOrEqual(ids.count, 2)
    }
}
