import CryptoKit
import Foundation

/// Verifies a downloaded KFGQPC source archive against the MD5/SHA-1 values
/// published on the official download page (an upstream-supplied identity
/// check, not a security primitive Ayah chose), computes our own SHA-256 of
/// the archive, then extracts the CSV member from it. MD5/SHA-1 are used
/// here only because KFGQPC publishes exactly those values; they establish
/// that the local archive is byte-identical to what KFGQPC actually
/// published, nothing more.
enum ArchiveError: Error, CustomStringConvertible {
    case cannotReadArchive(String)
    case md5Mismatch(expected: String, actual: String)
    case sha1Mismatch(expected: String, actual: String)
    case extractionFailed(String)
    case invalidUTF8(String)

    var description: String {
        switch self {
        case .cannotReadArchive(let path):
            return "could not read source archive at \(path)"
        case .md5Mismatch(let expected, let actual):
            return """
            official MD5 mismatch — expected \(expected), computed \(actual).
            This archive is not byte-identical to KFGQPC's published package; aborting rather than continuing with an unverified source.
            """
        case .sha1Mismatch(let expected, let actual):
            return """
            official SHA-1 mismatch — expected \(expected), computed \(actual).
            This archive is not byte-identical to KFGQPC's published package; aborting rather than continuing with an unverified source.
            """
        case .extractionFailed(let message):
            return "failed extracting CSV member from archive: \(message)"
        case .invalidUTF8(let member):
            return "extracted archive member '\(member)' is not valid UTF-8"
        }
    }
}

struct VerifiedArchive {
    let md5: String
    let sha1: String
    let sha256: String
    let csvContent: String
}

func verifyAndExtractCSV(
    archivePath: String,
    officialMD5: String,
    officialSHA1: String,
    csvMember: String
) throws -> VerifiedArchive {
    guard let data = FileManager.default.contents(atPath: archivePath) else {
        throw ArchiveError.cannotReadArchive(archivePath)
    }

    let computedMD5 = hexDigest(Insecure.MD5.hash(data: data))
    let computedSHA1 = hexDigest(Insecure.SHA1.hash(data: data))
    let computedSHA256 = hexDigest(SHA256.hash(data: data))

    let expectedMD5 = officialMD5.lowercased()
    let expectedSHA1 = officialSHA1.lowercased()
    guard computedMD5 == expectedMD5 else {
        throw ArchiveError.md5Mismatch(expected: expectedMD5, actual: computedMD5)
    }
    guard computedSHA1 == expectedSHA1 else {
        throw ArchiveError.sha1Mismatch(expected: expectedSHA1, actual: computedSHA1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", archivePath, csvMember]
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
    } catch {
        throw ArchiveError.extractionFailed("could not launch /usr/bin/unzip: \(error)")
    }
    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errText = String(data: errData, encoding: .utf8) ?? "(no stderr output)"
        throw ArchiveError.extractionFailed(
            "unzip exited \(process.terminationStatus) extracting '\(csvMember)': \(errText)"
        )
    }
    guard var csvContent = String(data: outData, encoding: .utf8) else {
        throw ArchiveError.invalidUTF8(csvMember)
    }
    if csvContent.hasPrefix("\u{FEFF}") {
        csvContent.removeFirst()
    }

    return VerifiedArchive(md5: computedMD5, sha1: computedSHA1, sha256: computedSHA256, csvContent: csvContent)
}

func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}
