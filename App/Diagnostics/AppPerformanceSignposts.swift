import OSLog

/// Privacy-safe performance intervals for app lifecycle and presentation.
/// Names are intentionally static and intervals carry no user or content data.
enum AppPerformanceSignposts {
    private static let signposter = OSSignposter(
        subsystem: "com.ayah.app",
        category: "AppPerformance"
    )

    @inline(__always)
    static func measure<Result>(
        _ name: StaticString,
        operation: () throws -> Result
    ) rethrows -> Result {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }
}
