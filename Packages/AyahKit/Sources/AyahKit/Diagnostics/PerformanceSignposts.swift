import OSLog

/// Privacy-safe performance intervals for operations owned by AyahKit.
///
/// Keep interval names static and do not attach metadata here: repository
/// paths, Quran content, location data, settings, and memorization state must
/// never be emitted to the unified log or an Instruments trace.
enum PerformanceSignposts {
    struct Interval {
        fileprivate let state: OSSignpostIntervalState
    }

    private static let signposter = OSSignposter(
        subsystem: "com.ayah.app",
        category: "AyahKitPerformance"
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

    @inline(__always)
    static func begin(_ name: StaticString) -> Interval {
        Interval(state: signposter.beginInterval(name))
    }

    @inline(__always)
    static func end(_ name: StaticString, _ interval: Interval) {
        signposter.endInterval(name, interval.state)
    }
}
