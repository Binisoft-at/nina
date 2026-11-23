import Foundation

// Settings that follow the person to every device: one small JSON object in the synced profile
// (`NinaProfile.syncedSettings`, a text field, so a new setting never needs a CloudKit schema
// change). Read leniently – broken text, wrong types and missing keys fall back to the defaults –
// and written back with every key it had, also the ones a newer version of Nina added, so an
// older device never throws away what a newer one wrote. Owner doc: docs/THALIA.md.

/// The settings that sync to every device, as `{"thaliaDeliver":false,"v":1}` (sorted keys).
public struct SyncedSettings: Equatable, Sendable {
    /// The format version Nina writes into "v".
    public static let version = 1
    /// The key of the format version.
    static let versionKey = "v"

    /// The settings Nina knows.
    public enum Key: String, CaseIterable, Sendable {
        /// "An Thalia liefern" (Bool, default on).
        case thaliaDeliver
    }

    /// Every key of the object but "v", as read (unknown ones included) and as set.
    public private(set) var values: [String: SyncedSettingsValue]
    /// The highest "v" seen in the text (0: none, or no text).
    public private(set) var readVersion: Int

    /// No settings: every key has its default.
    public init() {
        values = [:]
        readVersion = 0
    }

    /// Reads the profile's text. Empty or broken text, or JSON that isn't an object, gives no
    /// settings (all defaults); a key with an unexpected value reads as missing.
    public init(encoded text: String) {
        self.init()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: SyncedSettingsValue].self, from: data) else { return }
        var values = object
        if let version = values.removeValue(forKey: SyncedSettings.versionKey)?.integer, version > 0 {
            readVersion = version
        }
        self.values = values
    }

    /// The text for the profile: compact JSON with sorted keys and every unknown key kept, plus
    /// "v" – never lowered, so a newer version's text keeps its number.
    public var encoded: String {
        var object = values
        object[SyncedSettings.versionKey] = .number(Double(max(readVersion, SyncedSettings.version)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(object) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// No key set at all.
    public var isEmpty: Bool { values.isEmpty }

    /// Whether `key` has a usable value (a key with a broken value counts as missing).
    public func has(_ key: Key) -> Bool {
        bool(key) != nil
    }

    /// A Bool setting as stored; nil when it is missing or not a yes/no value. Lenient: true/false,
    /// 1/0 and the words "true", "yes", "on", "ja", "an" (and their opposites) count.
    public func bool(_ key: Key) -> Bool? {
        values[key.rawValue]?.flag
    }

    /// Sets a Bool setting; nil removes it (back to the default).
    public mutating func set(_ key: Key, _ value: Bool?) {
        values[key.rawValue] = value.map { SyncedSettingsValue.bool($0) }
    }

    /// Whether the two hold the same settings ("v" aside) – the store writes only on a change.
    public func sameValues(as other: SyncedSettings) -> Bool {
        values == other.values
    }

    // MARK: The settings

    /// "An Thalia liefern" on all devices (default on). Off on one device is off on all of them.
    public var thaliaDeliver: Bool {
        get { bool(.thaliaDeliver) ?? true }
        set { set(.thaliaDeliver, newValue) }
    }
}

/// One JSON value of the synced settings, kept exactly so unknown keys survive a rewrite.
public enum SyncedSettingsValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SyncedSettingsValue])
    case object([String: SyncedSettingsValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SyncedSettingsValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SyncedSettingsValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers without ".0", the same text on every platform.
            if value.isFinite, value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int64(value))
            } else if value.isFinite {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// A whole number (1, 1.0); nil for anything else.
    var integer: Int? {
        guard case .number(let value) = self, value.isFinite, value == value.rounded(),
              abs(value) < Double(Int32.max) else { return nil }
        return Int(value)
    }

    /// A yes/no value, read leniently; nil when it isn't one.
    var flag: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value == 1 ? true : value == 0 ? false : nil
        case .string(let text):
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "on", "1", "ja", "an": return true
            case "false", "no", "off", "0", "nein", "aus": return false
            default: return nil
            }
        default: return nil
        }
    }
}

// MARK: Thalia's switch across devices

extension SyncedSettings {
    /// What a device does with "An Thalia liefern": the synced value, and the one-time move of the
    /// old device-only switch (UserDefaults `nina.thalia.deliver`, before the switch synced).
    public struct ThaliaSwitch: Equatable, Sendable {
        /// Deliver on this device.
        public var isOn: Bool
        /// Write this value into the synced settings now (the old device-only "off"); nil: nothing to write.
        public var migrate: Bool?
        /// The old device-only value can go (once `migrate`, if any, is written).
        public var dropsDeviceValue: Bool

        public init(isOn: Bool, migrate: Bool? = nil, dropsDeviceValue: Bool = false) {
            self.isOn = isOn
            self.migrate = migrate
            self.dropsDeviceValue = dropsDeviceValue
        }
    }

    /// The switch for this device.
    ///
    /// - `synced`: the profile's synced settings; nil while this device has no profile yet (it
    ///   never creates one just for this, so a synced profile still to come isn't overridden).
    /// - `deviceValue`: the old device-only switch, if this device still has it.
    ///
    /// A synced value wins everywhere; the old device value is then dropped. Without a synced value
    /// an old device-only "off" is written into the synced settings once (then every device is
    /// off); an old "on" is the default anyway and is dropped. Without a profile the old value
    /// still counts on this device and waits until there is one.
    public static func thaliaSwitch(synced: SyncedSettings?, deviceValue: Bool?) -> ThaliaSwitch {
        guard let synced else {
            return ThaliaSwitch(isOn: deviceValue ?? true)
        }
        if let value = synced.bool(.thaliaDeliver) {
            return ThaliaSwitch(isOn: value, dropsDeviceValue: deviceValue != nil)
        }
        if deviceValue == false {
            return ThaliaSwitch(isOn: false, migrate: false, dropsDeviceValue: true)
        }
        return ThaliaSwitch(isOn: true, dropsDeviceValue: deviceValue != nil)
    }
}
