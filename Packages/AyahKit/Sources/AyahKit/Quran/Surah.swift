/// A surah's metadata, as bundled in `Resources/Quran/quran.sqlite`.
///
/// `nameEnglish`, `revelationPlace`, and `revelationOrder` are
/// deliberately not present — the bundled KFGQPC export doesn't include
/// them, and no in-scope feature needs them yet. See `ARCHITECTURE.md`
/// §7 and `Resources/Quran/SOURCE.md`.
public struct Surah: Codable, Equatable, Sendable {
    public let number: Int
    public let nameArabic: String
    public let nameTransliterated: String
    public let ayahCount: Int

    public init(number: Int, nameArabic: String, nameTransliterated: String, ayahCount: Int) {
        self.number = number
        self.nameArabic = nameArabic
        self.nameTransliterated = nameTransliterated
        self.ayahCount = ayahCount
    }
}
