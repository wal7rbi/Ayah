import Darwin.malloc
import Foundation
import XCTest
@testable import AyahKit

/// Regression coverage for the sqlite3-handle leak on open failure:
/// `sqlite3_open_v2` can allocate a real native handle even when it
/// returns an error (used just to read `sqlite3_errmsg`), and since each
/// repository's `init` threw before `self.db` was ever assigned,
/// `deinit`'s `sqlite3_close` never ran — leaking that handle's heap
/// allocation for the process lifetime. There's no direct Swift API to
/// assert "no leak," so this drives many failed opens and checks the
/// process's live heap allocation total via `malloc_zone_statistics`
/// (`size_in_use`) barely moves — confirmed empirically that this
/// specific failure path leaks ~1.4KB per call without the fix (measured
/// via a standalone probe) and 0 bytes with it, so the threshold below
/// has wide margin in both directions.
final class SQLiteHandleLeakTests: XCTestCase {
    /// A path whose parent isn't a real directory — `sqlite3_open_v2`
    /// fails with a real "disk I/O error" here (confirmed empirically)
    /// while still allocating a handle, exactly the case that used to leak.
    private func makeUnopenablePath() throws -> (path: String, cleanup: () -> Void) {
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: blockingFile)
        let badPath = blockingFile.appendingPathComponent("nested/ayah_user.sqlite").path
        return (badPath, { try? FileManager.default.removeItem(at: blockingFile) })
    }

    private func heapBytesInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// Runs `attempt` `count` times, each inside its own `autoreleasepool`
    /// — without this, unrelated Foundation/Objective-C bridging calls
    /// inside `init` (`NSString.deletingLastPathComponent`,
    /// `String(cString:)`, `FileManager`) accumulate autoreleased temporary
    /// objects across a tight loop and dwarf the native sqlite3-handle
    /// signal this test is actually trying to isolate (confirmed
    /// empirically: without per-iteration draining, heap growth was
    /// dominated by that noise even with the leak already fixed).
    private func runManyTimesDrainingAutoreleasePool(count: Int, _ attempt: () throws -> Void) rethrows {
        for _ in 0..<count {
            try autoreleasepool { try attempt() }
        }
    }

    func testSQLiteConnectionInitDoesNotLeakAHandleWhenOpenFails() throws {
        let (badPath, cleanup) = try makeUnopenablePath()
        defer { cleanup() }
        let attempt = { XCTAssertThrowsError(try SQLiteConnection(path: badPath)) }

        try runManyTimesDrainingAutoreleasePool(count: 20, attempt) // warm up allocator
        let before = heapBytesInUse()
        try runManyTimesDrainingAutoreleasePool(count: 2_000, attempt)
        let after = heapBytesInUse()

        XCTAssertLessThan(
            after - before, 200_000,
            "2,000 failed opens must not leak ~2,000 native sqlite3 handles (~1.4KB each, measured)"
        )
    }

    func testQuranRepositoryInitDoesNotLeakAHandleWhenOpenFails() throws {
        let (badPath, cleanup) = try makeUnopenablePath()
        defer { cleanup() }
        let attempt = {
            XCTAssertThrowsError(try QuranRepository(databasePath: badPath, checksumPath: badPath))
        }

        try runManyTimesDrainingAutoreleasePool(count: 20, attempt)
        let before = heapBytesInUse()
        try runManyTimesDrainingAutoreleasePool(count: 2_000, attempt)
        let after = heapBytesInUse()

        XCTAssertLessThan(after - before, 200_000)
    }

    func testLocationRepositoryInitDoesNotLeakAHandleWhenOpenFails() throws {
        let (badPath, cleanup) = try makeUnopenablePath()
        defer { cleanup() }
        let attempt = { XCTAssertThrowsError(try LocationRepository(databasePath: badPath)) }

        try runManyTimesDrainingAutoreleasePool(count: 20, attempt)
        let before = heapBytesInUse()
        try runManyTimesDrainingAutoreleasePool(count: 2_000, attempt)
        let after = heapBytesInUse()

        XCTAssertLessThan(after - before, 200_000)
    }
}
