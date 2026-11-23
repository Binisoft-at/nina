import Foundation
import Testing
@testable import NinaCore

/// The settings that sync to every device (`NinaProfile.syncedSettings`) and the move of Thalia's
/// old device-only switch into them.
@Suite("Synced settings")
struct SyncedSettingsTests {
    /// The written text as JSON values (the same reading on every platform).
    static func object(_ text: String) throws -> [String: SyncedSettingsValue] {
        try JSONDecoder().decode([String: SyncedSettingsValue].self, from: Data(text.utf8))
    }

    @Test func emptyTextHasTheDefaults() {
        for text in ["", "   ", "\n"] {
            let settings = SyncedSettings(encoded: text)
            #expect(settings.isEmpty)
            #expect(settings.thaliaDeliver)
            #expect(!settings.has(.thaliaDeliver))
            #expect(settings.readVersion == 0)
        }
        #expect(SyncedSettings() == SyncedSettings(encoded: ""))
    }

    @Test func brokenTextReadsAsNoSettings() {
        for text in ["no json", "{", "[1,2]", "true", "\"thaliaDeliver\"", "{\"thaliaDeliver\":}"] {
            let settings = SyncedSettings(encoded: text)
            #expect(settings.isEmpty, "\(text)")
            #expect(settings.thaliaDeliver, "\(text)")
        }
    }

    @Test func roundTrip() throws {
        var settings = SyncedSettings()
        settings.thaliaDeliver = false
        #expect(settings.encoded == #"{"thaliaDeliver":false,"v":1}"#)
        let read = SyncedSettings(encoded: settings.encoded)
        #expect(read.has(.thaliaDeliver))
        #expect(!read.thaliaDeliver)
        #expect(read.readVersion == 1)
        #expect(read.sameValues(as: settings))
        // Back on: stored as true (a value, not the default), so it wins on every device.
        var on = read
        on.thaliaDeliver = true
        #expect(on.encoded == #"{"thaliaDeliver":true,"v":1}"#)
        #expect(SyncedSettings(encoded: on.encoded).has(.thaliaDeliver))
        // Removing a key brings back its default.
        on.set(.thaliaDeliver, nil)
        #expect(!on.has(.thaliaDeliver))
        #expect(on.thaliaDeliver)
        #expect(on.encoded == #"{"v":1}"#)
    }

    @Test func lenientValues() {
        let values: [(String, Bool?)] = [
            (#"{"thaliaDeliver":false}"#, false), (#"{"thaliaDeliver":true}"#, true),
            (#"{"thaliaDeliver":0}"#, false), (#"{"thaliaDeliver":1}"#, true), (#"{"thaliaDeliver":1.0}"#, true),
            (#"{"thaliaDeliver":"off"}"#, false), (#"{"thaliaDeliver":" No "}"#, false), (#"{"thaliaDeliver":"aus"}"#, false),
            (#"{"thaliaDeliver":"YES"}"#, true), (#"{"thaliaDeliver":"an"}"#, true),
            (#"{"thaliaDeliver":2}"#, nil), (#"{"thaliaDeliver":"maybe"}"#, nil), (#"{"thaliaDeliver":null}"#, nil),
            (#"{"thaliaDeliver":[false]}"#, nil), (#"{"thaliaDeliver":{"on":false}}"#, nil),
            (#"{"ThaliaDeliver":false}"#, nil),
        ]
        for (text, expected) in values {
            let settings = SyncedSettings(encoded: text)
            #expect(settings.bool(.thaliaDeliver) == expected, "\(text)")
            #expect(settings.has(.thaliaDeliver) == (expected != nil), "\(text)")
            // A value that isn't yes or no is the default.
            #expect(settings.thaliaDeliver == (expected ?? true), "\(text)")
        }
    }

    @Test func unknownKeysAreKept() throws {
        // A newer Nina wrote more settings, some nested, and a newer format version.
        let newer = #"{"futureList":[1,2.5,"x",null,true],"futureNumber":12345678,"futureObject":{"a":{"b":"c/d"}},"#
            + #""futureText":"Grüß Gott","thaliaDeliver":true,"v":3}"#
        var settings = SyncedSettings(encoded: newer)
        #expect(settings.readVersion == 3)
        #expect(settings.thaliaDeliver)
        settings.thaliaDeliver = false
        let written = settings.encoded
        let object = try Self.object(written)
        #expect(Set(object.keys) == ["futureList", "futureNumber", "futureObject", "futureText", "thaliaDeliver", "v"])
        #expect(object["thaliaDeliver"] == .bool(false))
        // The version is never lowered.
        #expect(object["v"] == .number(3))
        #expect(object["futureText"] == .string("Grüß Gott"))
        #expect(object["futureNumber"] == .number(12345678))
        #expect(object["futureObject"] == .object(["a": .object(["b": .string("c/d")])]))
        #expect(object["futureList"] == .array([.number(1), .number(2.5), .string("x"), .null, .bool(true)]))
        #expect(written.contains(#""futureList":[1,2.5,"x",null,true]"#), "\(written)")
        #expect(!written.contains("\\/"))
        // Read again and written again: the same text (stable, sorted keys).
        #expect(SyncedSettings(encoded: written).encoded == written)
        // Only the value changed.
        var back = SyncedSettings(encoded: written)
        back.thaliaDeliver = true
        #expect(back.sameValues(as: SyncedSettings(encoded: newer)))
    }

    @Test func anOlderOrMissingVersionIsWrittenAsTheCurrentOne() throws {
        let old = SyncedSettings(encoded: #"{"thaliaDeliver":false}"#)
        #expect(old.readVersion == 0)
        #expect(try Self.object(old.encoded)["v"] == .number(Double(SyncedSettings.version)))
        let broken = SyncedSettings(encoded: #"{"thaliaDeliver":false,"v":"two"}"#)
        #expect(broken.readVersion == 0)
        #expect(!broken.thaliaDeliver)
        #expect(try Self.object(broken.encoded)["v"] == .number(1))
        // "v" is no setting.
        #expect(broken.values["v"] == nil)
    }

    // MARK: Thalia's switch on every device

    @Test func aSyncedValueWinsEverywhere() {
        var off = SyncedSettings()
        off.thaliaDeliver = false
        var on = SyncedSettings()
        on.thaliaDeliver = true
        for device: Bool? in [nil, true, false] {
            let offHere = SyncedSettings.thaliaSwitch(synced: off, deviceValue: device)
            #expect(offHere.isOn == false)
            #expect(offHere.migrate == nil)
            #expect(offHere.dropsDeviceValue == (device != nil))
            let onHere = SyncedSettings.thaliaSwitch(synced: on, deviceValue: device)
            #expect(onHere.isOn)
            #expect(onHere.migrate == nil)
            #expect(onHere.dropsDeviceValue == (device != nil))
        }
    }

    @Test func theOldDeviceOffMovesIntoTheSyncedSettingsOnce() {
        // A profile without the synced value: the old device-only "off" is written once.
        let first = SyncedSettings.thaliaSwitch(synced: SyncedSettings(), deviceValue: false)
        #expect(first == SyncedSettings.ThaliaSwitch(isOn: false, migrate: false, dropsDeviceValue: true))
        // After the write (and the device value dropped) every device follows it.
        var migrated = SyncedSettings()
        if let value = first.migrate { migrated.thaliaDeliver = value }
        let afterwards = SyncedSettings.thaliaSwitch(synced: SyncedSettings(encoded: migrated.encoded), deviceValue: nil)
        #expect(afterwards == SyncedSettings.ThaliaSwitch(isOn: false))
        // Another device that never turned it off now is off too.
        #expect(!SyncedSettings.thaliaSwitch(synced: migrated, deviceValue: true).isOn)
    }

    @Test func theOldDeviceOnIsTheDefault() {
        // Nothing to write: on is the default; the old value just goes.
        #expect(SyncedSettings.thaliaSwitch(synced: SyncedSettings(), deviceValue: true)
            == SyncedSettings.ThaliaSwitch(isOn: true, migrate: nil, dropsDeviceValue: true))
        #expect(SyncedSettings.thaliaSwitch(synced: SyncedSettings(), deviceValue: nil)
            == SyncedSettings.ThaliaSwitch(isOn: true, migrate: nil, dropsDeviceValue: false))
    }

    @Test func withoutAProfileTheDeviceValueWaits() {
        // No profile on this device yet (the synced one may still come): nothing is written, the
        // old value keeps counting here.
        #expect(SyncedSettings.thaliaSwitch(synced: nil, deviceValue: false) == SyncedSettings.ThaliaSwitch(isOn: false))
        #expect(SyncedSettings.thaliaSwitch(synced: nil, deviceValue: true) == SyncedSettings.ThaliaSwitch(isOn: true))
        #expect(SyncedSettings.thaliaSwitch(synced: nil, deviceValue: nil) == SyncedSettings.ThaliaSwitch(isOn: true))
    }

    @Test func aBrokenSyncedTextDoesntLoseTheOldOff() {
        // The synced text can't be read: no value there, so the old "off" is written into it.
        let broken = SyncedSettings(encoded: "{oops")
        let result = SyncedSettings.thaliaSwitch(synced: broken, deviceValue: false)
        #expect(result.migrate == false)
        #expect(!result.isOn)
    }
}
