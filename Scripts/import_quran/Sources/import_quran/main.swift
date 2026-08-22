import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("import_quran: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

struct Options {
    var sourceArchivePath: String
    var officialMD5: String
    var officialSHA1: String
    var archiveCSVMember: String
    var outDir: String
    var sourceURL: String
    var sourcePackage: String
    var sourceVersion: String
    var sourceDate: String
    var contentVersion: String
}

func parseOptions() -> Options {
    var raw: [String: String] = [:]
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let key = args.next() {
        guard key.hasPrefix("--"), let value = args.next() else {
            fail("bad argument '\(key)' — expected --flag value pairs")
        }
        raw[String(key.dropFirst(2))] = value
    }
    func require(_ name: String) -> String {
        guard let v = raw[name] else { fail("missing required --\(name)") }
        return v
    }
    return Options(
        sourceArchivePath: require("source-archive"),
        officialMD5: require("official-md5"),
        officialSHA1: require("official-sha1"),
        archiveCSVMember: raw["archive-csv-member"] ?? "UthmanicHafs_v2-0 data/hafsData_v2-0.csv",
        outDir: require("out-dir"),
        sourceURL: require("source-url"),
        sourcePackage: require("source-package"),
        sourceVersion: require("source-version"),
        sourceDate: require("source-date"),
        contentVersion: raw["content-version"] ?? "1.0.0"
    )
}

let expectedHeader = [
    "id", "jozz", "page", "sura_no", "sura_name_en", "sura_name_ar",
    "line_start", "line_end", "aya_no", "aya_text", "aya_text_emlaey",
]

let options = parseOptions()

let verifiedArchive: VerifiedArchive
do {
    verifiedArchive = try verifyAndExtractCSV(
        archivePath: options.sourceArchivePath,
        officialMD5: options.officialMD5,
        officialSHA1: options.officialSHA1,
        csvMember: options.archiveCSVMember
    )
} catch {
    fail("\(error)")
}
print("source archive verified against official MD5/SHA-1 — sha256:\(verifiedArchive.sha256)")

let content = verifiedArchive.csvContent

let rows = CSVParser.parse(content)
guard let header = rows.first else { fail("CSV is empty") }
guard header == expectedHeader else {
    fail("""
    unexpected CSV header — KFGQPC export format may have changed.
    expected: \(expectedHeader.joined(separator: ","))
    got:      \(header.joined(separator: ","))
    """)
}

let dataRows = rows.dropFirst().filter { !($0.count == 1 && $0[0].isEmpty) }
guard dataRows.count == 6236 else {
    fail("expected 6236 ayah rows, found \(dataRows.count)")
}

var ayahs: [AyahRecord] = []
ayahs.reserveCapacity(dataRows.count)

// Running per-surah accumulation, relying on the export being pre-sorted by
// (sura_no, aya_no) — validated below rather than assumed.
var surahs: [SurahRecord] = []
var currentSurahNumber = 0
var currentSurahNameAr = ""
var currentSurahNameEn = ""
var currentSurahAyahCount = 0
var expectedNextGlobalID = 1
var expectedNextAyahNumber = 1

@MainActor
func flushSurah() {
    guard currentSurahNumber != 0 else { return }
    surahs.append(SurahRecord(
        number: currentSurahNumber,
        nameArabic: currentSurahNameAr,
        nameTransliterated: currentSurahNameEn,
        ayahCount: currentSurahAyahCount
    ))
}

for (rowIndex, row) in dataRows.enumerated() {
    guard row.count == expectedHeader.count else {
        fail("row \(rowIndex + 2) has \(row.count) fields, expected \(expectedHeader.count)")
    }
    guard let id = Int(row[0]), let jozz = Int(row[1]), let page = Int(row[2]),
          let suraNo = Int(row[3]), let ayaNo = Int(row[8])
    else {
        fail("row \(rowIndex + 2) has a non-numeric id/jozz/page/sura_no/aya_no field")
    }
    let suraNameEn = row[4]
    let suraNameAr = row[5]
    let ayaText = row[9]
    let ayaTextEmlaey = row[10]

    guard id == expectedNextGlobalID else {
        fail("global id \(id) is out of sequence at row \(rowIndex + 2); expected \(expectedNextGlobalID)")
    }
    expectedNextGlobalID += 1

    guard !ayaText.isEmpty, !ayaTextEmlaey.isEmpty else {
        fail("row \(rowIndex + 2) (surah \(suraNo):\(ayaNo)) has empty ayah text")
    }

    if suraNo != currentSurahNumber {
        guard suraNo == currentSurahNumber + 1 else {
            fail("surah number jumped from \(currentSurahNumber) to \(suraNo) at row \(rowIndex + 2); expected \(currentSurahNumber + 1)")
        }
        flushSurah()
        currentSurahNumber = suraNo
        currentSurahNameAr = suraNameAr
        currentSurahNameEn = suraNameEn
        currentSurahAyahCount = 0
        expectedNextAyahNumber = 1
    } else {
        guard suraNameAr == currentSurahNameAr, suraNameEn == currentSurahNameEn else {
            fail("inconsistent surah name within surah \(suraNo) at row \(rowIndex + 2)")
        }
    }

    guard ayaNo == expectedNextAyahNumber else {
        fail("surah \(suraNo) ayah number \(ayaNo) out of sequence at row \(rowIndex + 2); expected \(expectedNextAyahNumber)")
    }
    expectedNextAyahNumber += 1
    currentSurahAyahCount += 1

    ayahs.append(AyahRecord(
        id: id,
        surahNumber: suraNo,
        ayahNumber: ayaNo,
        juzNumber: jozz,
        pageNumber: page,
        uthmanicText: ayaText,
        searchableText: ayaTextEmlaey
    ))
}
flushSurah()

guard surahs.count == 114 else {
    fail("expected 114 surahs, found \(surahs.count)")
}
guard let maxJuz = ayahs.map(\.juzNumber).max(), maxJuz == 30 else {
    fail("expected juz numbers to reach 30")
}
guard let maxPage = ayahs.map(\.pageNumber).max(), maxPage == 604 else {
    fail("expected page numbers to reach 604")
}
for i in 1..<ayahs.count {
    guard ayahs[i].juzNumber >= ayahs[i - 1].juzNumber, ayahs[i].pageNumber >= ayahs[i - 1].pageNumber else {
        fail("juz/page numbers are not monotonically non-decreasing at global id \(ayahs[i].id)")
    }
}

let checksum = QuranChecksum.compute(surahs: surahs, ayahs: ayahs)

try? FileManager.default.createDirectory(atPath: options.outDir, withIntermediateDirectories: true)

let dbPath = (options.outDir as NSString).appendingPathComponent("quran.sqlite")
let isoFormatter = ISO8601DateFormatter()
let generatedAt = isoFormatter.string(from: Date())

do {
    try writeQuranDatabase(
        path: dbPath,
        surahs: surahs,
        ayahs: ayahs,
        meta: [
            ("source_url", options.sourceURL),
            ("source_package", options.sourcePackage),
            ("source_version", options.sourceVersion),
            ("source_date", options.sourceDate),
            ("source_sha256", verifiedArchive.sha256),
            ("content_version", options.contentVersion),
            ("checksum", checksum),
        ]
    )
} catch {
    fail("failed writing database: \(error)")
}

let versionPath = (options.outDir as NSString).appendingPathComponent("VERSION")
try? options.contentVersion.write(toFile: versionPath, atomically: true, encoding: .utf8)

let checksumPath = (options.outDir as NSString).appendingPathComponent("CHECKSUM")
try? checksum.write(toFile: checksumPath, atomically: true, encoding: .utf8)

let sourceMD = """
# Quran text source

- **Upstream**: \(options.sourcePackage), version \(options.sourceVersion)
- **Downloaded from**: \(options.sourceURL)
- **Export date**: \(options.sourceDate)
- **Official MD5** (published by KFGQPC): \(verifiedArchive.md5)
- **Official SHA-1** (published by KFGQPC): \(verifiedArchive.sha1)
- **Source archive SHA-256** (computed by this importer): \(verifiedArchive.sha256)
- **Imported**: \(generatedAt)
- **Content version**: \(options.contentVersion)

Generated by `Scripts/import_quran`. Do not hand-edit `quran.sqlite`,
`VERSION`, `CHECKSUM`, or `MANIFEST.json` — re-run the importer against a
(re-)downloaded source archive instead. See `ARCHITECTURE.md` §5–§8 and
`THIRD_PARTY_LICENSES.md` for licensing context. `MANIFEST.json` in this
same directory is the machine-readable counterpart to this file.

## Known gap (deliberate, not an oversight)

This KFGQPC export does not include `hizb_quarter`, `ruku_number`,
`manzil_number`, `sajda` markers, translated (non-transliterated) English
surah names, or `revelation_place`/`revelation_order`. No currently
in-scope feature needs them, so the bundled schema omits those columns.
See `ARCHITECTURE.md` §7 for the resolution and the path to adding a
secondary source later if a feature ever needs them.
"""
try? sourceMD.write(toFile: (options.outDir as NSString).appendingPathComponent("SOURCE.md"), atomically: true, encoding: .utf8)

guard let sqliteData = FileManager.default.contents(atPath: dbPath) else {
    fail("could not re-read \(dbPath) to compute its file-bytes checksum")
}
let sqliteSHA256 = "sha256:" + hexDigest(SHA256.hash(data: sqliteData))

let manifest = QuranManifest(
    authority: "King Fahd Glorious Quran Printing Complex (KFGQPC)",
    narration: "Hafs",
    script: "Uthmanic Unicode",
    source: QuranManifest.Source(
        package: options.sourcePackage,
        officialURL: options.sourceURL,
        officialMD5: verifiedArchive.md5,
        officialSHA1: verifiedArchive.sha1,
        archiveSHA256: verifiedArchive.sha256
    ),
    importInfo: QuranManifest.Import(
        importer: "Scripts/import_quran",
        importerVersion: quranImporterVersion,
        schemaVersion: quranManifestSchemaVersion
    ),
    dataset: QuranManifest.Dataset(
        surahCount: surahs.count,
        ayahCount: ayahs.count,
        canonicalContentSHA256: checksum,
        sqliteSHA256: sqliteSHA256
    )
)
do {
    try writeManifest(manifest, toPath: (options.outDir as NSString).appendingPathComponent("MANIFEST.json"))
} catch {
    fail("failed writing MANIFEST.json: \(error)")
}

print("Wrote \(surahs.count) surahs, \(ayahs.count) ayahs to \(dbPath)")
print("checksum: \(checksum)")
