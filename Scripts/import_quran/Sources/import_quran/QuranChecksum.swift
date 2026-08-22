import CryptoKit
import Foundation

/// Canonical content checksum: SHA-256 over row data sorted by primary key,
/// not raw file bytes, so it stays stable across SQLite vacuum/header
/// differences. Must stay byte-for-byte identical between import_quran,
/// verify_quran, and the AyahKit integrity tests.
enum QuranChecksum {
    static func compute(surahs: [SurahRecord], ayahs: [AyahRecord]) -> String {
        var canonical = ""
        for surah in surahs.sorted(by: { $0.number < $1.number }) {
            canonical += "\(surah.number)|\(surah.nameArabic)|\(surah.nameTransliterated)|\(surah.ayahCount)\n"
        }
        for ayah in ayahs.sorted(by: { $0.id < $1.id }) {
            canonical += "\(ayah.id)|\(ayah.surahNumber)|\(ayah.ayahNumber)|\(ayah.juzNumber)|\(ayah.pageNumber)|\(ayah.uthmanicText)|\(ayah.searchableText)\n"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
