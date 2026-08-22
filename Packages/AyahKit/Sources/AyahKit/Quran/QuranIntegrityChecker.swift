import CryptoKit
import Foundation

public enum QuranIntegrityError: Error, Equatable, Sendable {
    case surahCountMismatch(expected: Int, actual: Int)
    case ayahCountMismatch(expected: Int, actual: Int)
    case checksumMismatch
}

/// Runtime counterpart to `Scripts/verify_quran`'s checksum/row-count
/// check (see ARCHITECTURE.md §8), run once when `QuranRepository` opens
/// the bundled database — so a corrupted or tampered `quran.sqlite` is
/// caught before any unverified text is ever displayed, rather than
/// trusting the bundle silently.
public enum QuranIntegrityChecker {
    public static func verify(surahs: [Surah], ayahs: [QuranAyah], expectedChecksum: String) throws {
        guard surahs.count == 114 else {
            throw QuranIntegrityError.surahCountMismatch(expected: 114, actual: surahs.count)
        }
        guard ayahs.count == 6236 else {
            throw QuranIntegrityError.ayahCountMismatch(expected: 6236, actual: ayahs.count)
        }
        guard checksum(surahs: surahs, ayahs: ayahs) == expectedChecksum else {
            throw QuranIntegrityError.checksumMismatch
        }
    }

    /// Must stay byte-for-byte identical to the canonicalization in
    /// `Scripts/import_quran`/`Scripts/verify_quran` and
    /// `QuranIntegrityTests` — all four independently compute this same
    /// checksum over the same bundled data.
    static func checksum(surahs: [Surah], ayahs: [QuranAyah]) -> String {
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
