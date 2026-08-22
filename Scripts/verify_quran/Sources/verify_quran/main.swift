import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("verify_quran: FAIL: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fail("usage: verify_quran <path-to-Resources/Quran-dir>")
}
let dir = args[1]
let dbPath = (dir as NSString).appendingPathComponent("quran.sqlite")
let checksumPath = (dir as NSString).appendingPathComponent("CHECKSUM")

guard let expectedChecksum = try? String(contentsOfFile: checksumPath, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines), !expectedChecksum.isEmpty
else {
    fail("could not read CHECKSUM at \(checksumPath)")
}

let (surahs, ayahs): ([SurahRecord], [AyahRecord])
do {
    (surahs, ayahs) = try readQuranDatabase(path: dbPath)
} catch {
    fail("could not read database at \(dbPath): \(error)")
}

guard surahs.count == 114 else {
    fail("expected 114 surahs, found \(surahs.count)")
}
guard ayahs.count == 6236 else {
    fail("expected 6236 ayahs, found \(ayahs.count)")
}

for surah in surahs {
    guard let expected = canonicalAyahCounts[surah.number] else {
        fail("surah \(surah.number) is outside the canonical 1...114 range")
    }
    guard surah.ayahCount == expected else {
        fail("surah \(surah.number) has ayah_count \(surah.ayahCount), expected \(expected)")
    }
}

let ayahsByID = ayahs.sorted { $0.id < $1.id }
guard ayahsByID.first?.id == 1, ayahsByID.last?.id == 6236 else {
    fail("global ayah id range is not exactly 1...6236")
}
for i in 0..<ayahsByID.count {
    guard ayahsByID[i].id == i + 1 else {
        fail("global ayah id is not contiguous at position \(i): got id \(ayahsByID[i].id), expected \(i + 1)")
    }
}

var seenPerSurah: [Int: Set<Int>] = [:]
for ayah in ayahsByID {
    seenPerSurah[ayah.surahNumber, default: []].insert(ayah.ayahNumber)
}
for surah in surahs {
    let seen = seenPerSurah[surah.number] ?? []
    guard seen.count == surah.ayahCount else {
        fail("surah \(surah.number) has \(seen.count) distinct ayah numbers, expected \(surah.ayahCount)")
    }
    for n in 1...surah.ayahCount {
        guard seen.contains(n) else {
            fail("surah \(surah.number) is missing ayah number \(n)")
        }
    }
}

for i in 1..<ayahsByID.count {
    guard ayahsByID[i].juzNumber >= ayahsByID[i - 1].juzNumber else {
        fail("juz_number decreases at global id \(ayahsByID[i].id)")
    }
    guard ayahsByID[i].pageNumber >= ayahsByID[i - 1].pageNumber else {
        fail("page_number decreases at global id \(ayahsByID[i].id)")
    }
}
guard ayahsByID.first?.juzNumber == 1, ayahsByID.last?.juzNumber == 30 else {
    fail("juz_number does not cover the full 1...30 range")
}
guard ayahsByID.first?.pageNumber == 1, ayahsByID.last?.pageNumber == 604 else {
    fail("page_number does not cover the full 1...604 range")
}

for ayah in ayahsByID {
    guard !ayah.uthmanicText.isEmpty, !ayah.searchableText.isEmpty else {
        fail("ayah id \(ayah.id) has empty text")
    }
}
for surah in surahs {
    guard !surah.nameArabic.isEmpty, !surah.nameTransliterated.isEmpty else {
        fail("surah \(surah.number) has an empty name field")
    }
}

let recomputedChecksum = QuranChecksum.compute(surahs: surahs, ayahs: ayahs)
guard recomputedChecksum == expectedChecksum else {
    fail("checksum mismatch: recomputed \(recomputedChecksum), expected \(expectedChecksum)")
}

let manifestPath = (dir as NSString).appendingPathComponent("MANIFEST.json")
if FileManager.default.fileExists(atPath: manifestPath) {
    guard let manifestData = FileManager.default.contents(atPath: manifestPath) else {
        fail("could not read MANIFEST.json at \(manifestPath)")
    }
    let manifest: QuranManifest
    do {
        manifest = try JSONDecoder().decode(QuranManifest.self, from: manifestData)
    } catch {
        fail("could not decode MANIFEST.json: \(error)")
    }
    guard manifest.dataset.canonicalContentSHA256 == expectedChecksum else {
        fail("""
        MANIFEST.json dataset.canonical_content_sha256 (\(manifest.dataset.canonicalContentSHA256)) \
        does not match CHECKSUM (\(expectedChecksum))
        """)
    }
    guard manifest.dataset.surahCount == 114, manifest.dataset.ayahCount == 6236 else {
        fail("""
        MANIFEST.json dataset counts (\(manifest.dataset.surahCount) surahs, \
        \(manifest.dataset.ayahCount) ayahs) do not match the canonical 114/6236
        """)
    }
    guard let sqliteData = FileManager.default.contents(atPath: dbPath) else {
        fail("could not read \(dbPath) to verify MANIFEST.json's sqlite_sha256")
    }
    let recomputedSQLiteSHA256 = "sha256:" + SHA256.hash(data: sqliteData).map { String(format: "%02x", $0) }.joined()
    guard manifest.dataset.sqliteSHA256 == recomputedSQLiteSHA256 else {
        fail("""
        MANIFEST.json dataset.sqlite_sha256 (\(manifest.dataset.sqliteSHA256)) does not match \
        the recomputed file-bytes hash of quran.sqlite (\(recomputedSQLiteSHA256)) — the bundled \
        database file has changed since the manifest was generated
        """)
    }
    print("verify_quran: MANIFEST.json cross-checked OK.")
} else {
    print("verify_quran: no MANIFEST.json found — skipping manifest cross-check.")
}

print("verify_quran: OK — 114 surahs, 6236 ayahs, checksum verified.")
