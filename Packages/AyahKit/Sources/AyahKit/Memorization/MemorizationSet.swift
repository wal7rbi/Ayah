import Foundation

/// A user-defined range of ayahs to memorize, persisted in the local
/// `ayah_user.sqlite` (see ARCHITECTURE.md §7/§15) — never the bundled,
/// read-only `quran.sqlite`.
public struct MemorizationSet: Codable, Equatable, Sendable, Identifiable {
    public enum RepetitionMode: String, Codable, Sendable {
        case sequential
        case random
    }

    public let id: String
    public var surahNumber: Int
    public var startAyah: Int
    public var endAyah: Int
    public var isEnabled: Bool
    public var repetitionMode: RepetitionMode
    /// Sequential mode's walk position. Nil means "not started yet" —
    /// treated as `startAyah`. Unused in `.random` mode.
    public var cursorAyah: Int?
    public let createdAt: Date

    /// Nullable placeholders for a future spaced-repetition mode (v2+) —
    /// deliberately unwritten by v1 logic, see ARCHITECTURE.md's "Weighted
    /// verse selection" section.
    public var lastShownAt: Date?
    public var easeFactor: Double?
    public var reviewIntervalDays: Int?

    public init(
        id: String = UUID().uuidString,
        surahNumber: Int,
        startAyah: Int,
        endAyah: Int,
        isEnabled: Bool = true,
        repetitionMode: RepetitionMode = .sequential,
        cursorAyah: Int? = nil,
        createdAt: Date = Date(),
        lastShownAt: Date? = nil,
        easeFactor: Double? = nil,
        reviewIntervalDays: Int? = nil
    ) {
        self.id = id
        self.surahNumber = surahNumber
        self.startAyah = startAyah
        self.endAyah = endAyah
        self.isEnabled = isEnabled
        self.repetitionMode = repetitionMode
        self.cursorAyah = cursorAyah
        self.createdAt = createdAt
        self.lastShownAt = lastShownAt
        self.easeFactor = easeFactor
        self.reviewIntervalDays = reviewIntervalDays
    }

    public var ayahCount: Int {
        endAyah - startAyah + 1
    }
}
