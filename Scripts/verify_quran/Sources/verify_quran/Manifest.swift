import Foundation

/// Decoding counterpart to `import_quran`'s `QuranManifest` — must stay
/// structurally identical to that copy (same triplication rationale as
/// `QuranChecksum.swift`).
struct QuranManifest: Codable {
    struct Source: Codable {
        let package: String
        let officialURL: String
        let officialMD5: String
        let officialSHA1: String
        let archiveSHA256: String

        enum CodingKeys: String, CodingKey {
            case package
            case officialURL = "official_url"
            case officialMD5 = "official_md5"
            case officialSHA1 = "official_sha1"
            case archiveSHA256 = "archive_sha256"
        }
    }

    struct Import: Codable {
        let importer: String
        let importerVersion: String
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case importer
            case importerVersion = "importer_version"
            case schemaVersion = "schema_version"
        }
    }

    struct Dataset: Codable {
        let surahCount: Int
        let ayahCount: Int
        let canonicalContentSHA256: String
        let sqliteSHA256: String

        enum CodingKeys: String, CodingKey {
            case surahCount = "surah_count"
            case ayahCount = "ayah_count"
            case canonicalContentSHA256 = "canonical_content_sha256"
            case sqliteSHA256 = "sqlite_sha256"
        }
    }

    let authority: String
    let narration: String
    let script: String
    let source: Source
    let importInfo: Import
    let dataset: Dataset

    enum CodingKeys: String, CodingKey {
        case authority, narration, script, source, dataset
        case importInfo = "import"
    }
}
