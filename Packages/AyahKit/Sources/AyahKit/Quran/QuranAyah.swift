/// A single ayah, as bundled in `Resources/Quran/quran.sqlite`.
///
/// `uthmanicText` is stored and displayed exactly as supplied by KFGQPC —
/// never normalized, never stripped of diacritics or waqf marks.
/// `searchableText` is the separate, already diacritic-stripped column
/// KFGQPC provides for search, never derived from `uthmanicText` by
/// mutating it.
///
/// `hizbQuarter`, `rukuNumber`, `manzilNumber`, and `sajda` are
/// deliberately not present — see `ARCHITECTURE.md` §7 and
/// `Resources/Quran/SOURCE.md`.
public struct QuranAyah: Codable, Equatable, Sendable {
    public let id: Int
    public let surahNumber: Int
    public let ayahNumber: Int
    public let juzNumber: Int
    public let pageNumber: Int
    public let uthmanicText: String
    public let searchableText: String

    public init(
        id: Int,
        surahNumber: Int,
        ayahNumber: Int,
        juzNumber: Int,
        pageNumber: Int,
        uthmanicText: String,
        searchableText: String
    ) {
        self.id = id
        self.surahNumber = surahNumber
        self.ayahNumber = ayahNumber
        self.juzNumber = juzNumber
        self.pageNumber = pageNumber
        self.uthmanicText = uthmanicText
        self.searchableText = searchableText
    }
}
