import Combine
import Foundation

/// The compact, identifier-only description of the most recently shown
/// notch card. Quran text and surah metadata are deliberately absent: every
/// consumer resolves IDs through the verified `QuranRepository` before use.
public enum LastShownRecord: Codable, Equatable, Sendable {
    case verses(LastShownVerseRecord)
    case prayerAlert(LastShownPrayerAlertRecord)

    public var shownAt: Date {
        switch self {
        case .verses(let record): record.shownAt
        case .prayerAlert(let record): record.shownAt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum RecordType: String, Codable {
        case verses
        case prayerAlert
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(RecordType.self, forKey: .type) {
        case .verses:
            self = .verses(try container.decode(LastShownVerseRecord.self, forKey: .value))
        case .prayerAlert:
            self = .prayerAlert(try container.decode(LastShownPrayerAlertRecord.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .verses(let record):
            try container.encode(RecordType.verses, forKey: .type)
            try container.encode(record, forKey: .value)
        case .prayerAlert(let record):
            try container.encode(RecordType.prayerAlert, forKey: .type)
            try container.encode(record, forKey: .value)
        }
    }
}

public struct LastShownVerseRecord: Codable, Equatable, Sendable {
    public let ayahIDs: [Int]
    public let shownAt: Date

    public init(ayahIDs: [Int], shownAt: Date) {
        self.ayahIDs = ayahIDs
        self.shownAt = shownAt
    }
}

public struct LastShownPrayerAlertRecord: Codable, Equatable, Sendable {
    public let prayerKey: String
    public let fireDate: Date
    public let reminderOffsetMinutes: Int
    public let ayahID: Int?
    public let shownAt: Date

    public init(
        prayerKey: String,
        fireDate: Date,
        reminderOffsetMinutes: Int,
        ayahID: Int?,
        shownAt: Date
    ) {
        self.prayerKey = prayerKey
        self.fireDate = fireDate
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.ayahID = ayahID
        self.shownAt = shownAt
    }
}

public enum LastShownStoreError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidRecord
}

/// Persists exactly one last-shown record in its own `UserDefaults` key.
/// Replacing `record` immediately replaces the previous persisted value.
public final class LastShownStore: ObservableObject {
    @Published public private(set) var record: LastShownRecord?

    public private(set) var lastLoadError: Error?
    public private(set) var lastSaveError: Error?

    private let defaults: UserDefaults
    private static let storageKey = "com.ayah.lastShown"
    private static let schemaVersion = 1

    private struct StoredEnvelope: Codable {
        let schemaVersion: Int
        let record: LastShownRecord
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else {
            record = nil
            return
        }

        do {
            let envelope = try JSONDecoder().decode(StoredEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw LastShownStoreError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
            guard Self.isValid(envelope.record) else {
                throw LastShownStoreError.invalidRecord
            }
            record = envelope.record
        } catch {
            record = nil
            lastLoadError = error
        }
    }

    public func save(_ record: LastShownRecord) {
        guard Self.isValid(record) else {
            lastSaveError = LastShownStoreError.invalidRecord
            return
        }

        do {
            let envelope = StoredEnvelope(schemaVersion: Self.schemaVersion, record: record)
            let data = try JSONEncoder().encode(envelope)
            defaults.set(data, forKey: Self.storageKey)
            self.record = record
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }

    private static func isValid(_ record: LastShownRecord) -> Bool {
        switch record {
        case .verses(let value):
            return (1...5).contains(value.ayahIDs.count)
                && value.ayahIDs.allSatisfy { $0 > 0 }
                && value.shownAt.timeIntervalSinceReferenceDate.isFinite
        case .prayerAlert(let value):
            return PrayerAlertEvent.prayerNameArabic(forKey: value.prayerKey) != nil
                && (0...180).contains(value.reminderOffsetMinutes)
                && (value.ayahID.map { $0 > 0 } ?? true)
                && value.fireDate.timeIntervalSinceReferenceDate.isFinite
                && value.shownAt.timeIntervalSinceReferenceDate.isFinite
        }
    }
}
