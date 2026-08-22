struct SurahRecord {
    let number: Int
    let nameArabic: String
    let nameTransliterated: String
    let ayahCount: Int
}

struct AyahRecord {
    let id: Int
    let surahNumber: Int
    let ayahNumber: Int
    let juzNumber: Int
    let pageNumber: Int
    let uthmanicText: String
    let searchableText: String
}
