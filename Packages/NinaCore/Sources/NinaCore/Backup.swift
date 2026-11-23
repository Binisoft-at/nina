import Foundation

// "Back Up Everything": one folder with everything Nina keeps in iCloud – diary, foods, meals &
// recipes, water, weigh-ins, routines, goals & plan, measurements, day marks (day types, checks,
// check-ins, phase decisions), progress photos and Recently Deleted – and a restore that adds what
// is missing without touching what is there. No Apple Health value is in it (Nina stores none).
//
//   Nina Backup 2030-01-07/
//     manifest.json      format, version, app, date, device, counts
//     records.jsonl      one JSON object per line: {"t":"LogEntry","uuid":"…", every stored field}
//     photos/<UUID>.jpg  progress photos (and <UUID>-thumb.jpg), when they are included
//
// Records are generic (type, uuid, fields) so this file doesn't need to know the SwiftData models:
// the app maps them (Shared/Store/NinaStore+Backup.swift). A newer version may add fields; an
// older Nina ignores them, and missing fields get the model's default.

/// One stored field of a backup record.
public enum BackupValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// Records that belong to this one (a recipe's ingredients).
    case records([BackupRecord])
    case null
}

/// One record of a backup: its model, its uuid and its stored fields.
public struct BackupRecord: Equatable, Sendable {
    public var type: String
    public var uuid: UUID
    public var fields: [String: BackupValue]

    public init(type: String, uuid: UUID, fields: [String: BackupValue] = [:]) {
        self.type = type
        self.uuid = uuid
        self.fields = fields
    }

    public init(_ type: BackupType, uuid: UUID, fields: [String: BackupValue] = [:]) {
        self.init(type: type.rawValue, uuid: uuid, fields: fields)
    }

    public var kind: BackupType? { BackupType(rawValue: type) }

    public subscript(_ key: String) -> BackupValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }

    // MARK: Reading fields (a missing or unexpected value gives the fallback)

    public func string(_ key: String, _ fallback: String = "") -> String {
        switch fields[key] {
        case .string(let value)?: value
        case .number(let value)?: NumberText.plain(value)
        default: fallback
        }
    }

    public func double(_ key: String, _ fallback: Double = 0) -> Double {
        switch fields[key] {
        case .number(let value)?: value
        case .bool(let value)?: value ? 1 : 0
        case .string(let text)?: Double(text) ?? fallback
        default: fallback
        }
    }

    public func int(_ key: String, _ fallback: Int = 0) -> Int {
        let value = double(key, Double(fallback))
        return value.isFinite ? Int(value.rounded()) : fallback
    }

    public func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        switch fields[key] {
        case .bool(let value)?: value
        case .number(let value)?: value != 0
        default: fallback
        }
    }

    /// A date written by `set(_:date:)`; nil when missing or null.
    public func date(_ key: String) -> Date? {
        guard case .string(let text)? = fields[key] else { return nil }
        return NinaBackup.date(from: text)
    }

    public func uuidValue(_ key: String) -> UUID? {
        UUID(uuidString: string(key))
    }

    public func records(_ key: String) -> [BackupRecord] {
        guard case .records(let list)? = fields[key] else { return [] }
        return list
    }

    // MARK: Writing fields

    public mutating func set(_ key: String, _ value: String) { fields[key] = .string(value) }
    public mutating func set(_ key: String, _ value: Double) { fields[key] = .number(value) }
    public mutating func set(_ key: String, _ value: Int) { fields[key] = .number(Double(value)) }
    public mutating func set(_ key: String, _ value: Bool) { fields[key] = .bool(value) }
    public mutating func set(_ key: String, date: Date?) { fields[key] = date.map { .string(NinaBackup.text(of: $0)) } ?? .null }
    public mutating func set(_ key: String, _ records: [BackupRecord]) { fields[key] = .records(records) }

    // MARK: Common fields

    public var createdAt: Date? { date("createdAt") }
    public var modifiedAt: Date? { date("modifiedAt") }
    public var deletedAt: Date? { date("deletedAt") }
}

/// The kinds of records a backup holds, in the order a restore inserts them.
public enum BackupType: String, CaseIterable, Sendable, Identifiable {
    case profile = "NinaProfile"
    case food = "Food"
    case recipe = "Recipe"
    case entry = "LogEntry"
    case water = "WaterLog"
    case weight = "WeightEntry"
    case rule = "PlanRule"
    case measurement = "BodyMeasurement"
    case mark = "DayMark"
    case photo = "ProgressPhoto"

    public var id: String { rawValue }

    /// The preview's line title.
    public var title: String {
        switch self {
        case .profile: "Goals & plan"
        case .food: "Foods"
        case .recipe: "Meals & recipes"
        case .entry: "Diary entries"
        case .water: "Water"
        case .weight: "Weigh-ins"
        case .rule: "Routines"
        case .measurement: "Measurements"
        case .mark: "Day types, checks & check-ins"
        case .photo: "Progress photos"
        }
    }
}

/// The backup format: the manifest, the records file and the photo paths.
public enum NinaBackup {
    public static let format = "nina-backup"
    /// The newest format this version reads and writes.
    public static let version = 1
    public static let manifestName = "manifest.json"
    public static let recordsName = "records.jsonl"
    public static let photosFolder = "photos"

    public struct Manifest: Codable, Equatable, Sendable {
        public var format: String
        public var version: Int
        public var app: String
        public var appVersion: String
        public var created: Date
        public var device: String
        /// Records per type (`BackupType.rawValue`), the profile included.
        public var counts: [String: Int]
        /// Photo files in the folder (0 when photos were left out).
        public var photos: Int

        public init(app: String, appVersion: String, created: Date, device: String, counts: [String: Int], photos: Int) {
            format = NinaBackup.format
            version = NinaBackup.version
            self.app = app
            self.appVersion = appVersion
            self.created = created
            self.device = device
            self.counts = counts
            self.photos = photos
        }

        /// Everything in the backup ("1,204 records · 36 photos").
        public var total: Int { counts.values.reduce(0, +) }
    }

    /// Why a folder can't be restored, in plain words.
    public enum ReadError: Error, Equatable, Sendable {
        case notABackup
        case newerVersion(Int)
        case unreadable

        public var message: String {
            switch self {
            case .notABackup: "This folder isn't a Nina backup. Choose the folder named \u{201C}Nina Backup …\u{201D}."
            case .newerVersion: "This backup was made by a newer version of Nina. Update Nina, then restore it."
            case .unreadable: "The backup couldn't be read. Is it complete? If it is in iCloud Drive, wait until it has downloaded."
            }
        }
    }

    /// "Nina Backup 2030-01-07".
    public static func folderName(app: String, day: DayKey) -> String {
        "\(app) Backup \(day.rawValue)"
    }

    /// "photos/<UUID>.jpg", or "photos/<UUID>-thumb.jpg" for the thumbnail.
    public static func photoPath(_ uuid: UUID, thumbnail: Bool = false) -> String {
        "\(photosFolder)/\(uuid.uuidString)\(thumbnail ? "-thumb" : "").jpg"
    }

    /// How many of each type, for the manifest.
    public static func counts(_ records: [BackupRecord]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for record in records { counts[record.type, default: 0] += 1 }
        return counts
    }

    // MARK: Dates

    /// ISO 8601 in UTC with milliseconds: "2030-01-07T07:30:00.125Z".
    public static func text(of date: Date) -> String {
        withMilliseconds.string(from: date)
    }

    public static func date(from text: String) -> Date? {
        withMilliseconds.date(from: text) ?? withoutMilliseconds.date(from: text)
    }

    // Made once: a backup has thousands of dates. (ISO8601DateFormatter is thread-safe.)
    private static let withMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let withoutMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: Writing

    public static func encode(_ manifest: Manifest) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(text(of: date))
        }
        return (try? encoder.encode(manifest)) ?? Data()
    }

    /// One record as one line of JSON (no line break inside).
    public static func line(_ record: BackupRecord) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(record)) ?? Data()
    }

    /// The records file: one line per record.
    public static func encode(_ records: [BackupRecord]) -> Data {
        var data = Data()
        for record in records {
            data.append(line(record))
            data.append(0x0A)
        }
        return data
    }

    // MARK: Reading

    public static func decodeManifest(_ data: Data) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "date"))
            }
            return date
        }
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else {
            throw (try? JSONSerialization.jsonObject(with: data)) == nil ? ReadError.unreadable : ReadError.notABackup
        }
        guard manifest.format == format else { throw ReadError.notABackup }
        guard manifest.version <= version else { throw ReadError.newerVersion(manifest.version) }
        return manifest
    }

    /// The records of the file, and how many lines couldn't be read.
    public static func decode(_ data: Data) -> (records: [BackupRecord], unreadable: Int) {
        let decoder = JSONDecoder()
        var records: [BackupRecord] = []
        var unreadable = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            if let record = try? decoder.decode(BackupRecord.self, from: Data(line)) {
                records.append(record)
            } else {
                unreadable += 1
            }
        }
        return (records, unreadable)
    }
}

// MARK: - JSON

private struct BackupKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension BackupRecord: Codable {
    /// {"t": type, "uuid": …, field: value …}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BackupKey.self)
        type = try container.decode(String.self, forKey: BackupKey("t"))
        guard let uuid = UUID(uuidString: try container.decode(String.self, forKey: BackupKey("uuid"))) else {
            throw DecodingError.dataCorruptedError(forKey: BackupKey("uuid"), in: container, debugDescription: "uuid")
        }
        self.uuid = uuid
        var fields: [String: BackupValue] = [:]
        for key in container.allKeys where key.stringValue != "t" && key.stringValue != "uuid" {
            fields[key.stringValue] = try container.decode(BackupValue.self, forKey: key)
        }
        self.fields = fields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BackupKey.self)
        try container.encode(type, forKey: BackupKey("t"))
        try container.encode(uuid.uuidString, forKey: BackupKey("uuid"))
        for (key, value) in fields where key != "t" && key != "uuid" {
            try container.encode(value, forKey: BackupKey(key))
        }
    }
}

extension BackupValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .records(try container.decode([BackupRecord].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .bool(let flag): try container.encode(flag)
        case .records(let list): try container.encode(list)
        case .null: try container.encodeNil()
        }
    }
}
