import Foundation
import XCTest
@testable import AyahKit

final class MemorizationRepositoryTests: XCTestCase {
    private func makeRepository() throws -> (MemorizationRepository, URL) {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ayah_user.sqlite")
        let repository = try MemorizationRepository(databasePath: dbURL.path)
        return (repository, dbURL)
    }

    func testCreateRejectsInvalidRange() throws {
        let (repository, _) = try makeRepository()
        XCTAssertThrowsError(try repository.create(surahNumber: 1, startAyah: 5, endAyah: 2)) { error in
            XCTAssertEqual(error as? MemorizationRepositoryError, .invalidRange)
        }
    }

    func testCreateAndFetchAll() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        let all = repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, set.id)
        XCTAssertEqual(all.first?.surahNumber, set.surahNumber)
        XCTAssertEqual(all.first?.startAyah, set.startAyah)
        XCTAssertEqual(all.first?.endAyah, set.endAyah)
        XCTAssertEqual(all.first?.isEnabled, set.isEnabled)
        XCTAssertEqual(all.first?.repetitionMode, set.repetitionMode)
    }

    func testFetchEnabledExcludesDisabledSets() throws {
        let (repository, _) = try makeRepository()
        let enabled = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        _ = try repository.create(surahNumber: 2, startAyah: 1, endAyah: 5, isEnabled: false)

        let fetched = repository.fetchEnabled()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, enabled.id)
    }

    func testUpdatePersistsChanges() throws {
        let (repository, _) = try makeRepository()
        var set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)
        set.isEnabled = false
        set.cursorAyah = 3

        try repository.update(set)

        let refetched = try XCTUnwrap(repository.fetchAll().first)
        XCTAssertFalse(refetched.isEnabled)
        XCTAssertEqual(refetched.cursorAyah, 3)
    }

    func testDeleteRemovesSet() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        try repository.delete(id: set.id)

        XCTAssertTrue(repository.fetchAll().isEmpty)
    }

    func testUpdateCursorAdvancesWalkPosition() throws {
        let (repository, _) = try makeRepository()
        let set = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        try repository.updateCursor(id: set.id, cursorAyah: 4)

        XCTAssertEqual(repository.fetchAll().first?.cursorAyah, 4)
    }

    func testDataSurvivesReopeningTheSameDatabaseFile() throws {
        let (repository, dbURL) = try makeRepository()
        _ = try repository.create(surahNumber: 1, startAyah: 1, endAyah: 7)

        let reopened = try MemorizationRepository(databasePath: dbURL.path)
        XCTAssertEqual(reopened.fetchAll().count, 1)
    }
}
