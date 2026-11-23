import Foundation
import Testing
@testable import BinisoftKitCore

@Suite("CSV encodings")
struct CSVEncodingTests {
    let rows = "name;kcal\nKäse;350\nÄpfel;52\nWeißbrot;250\nMüsli;370\nÖl;884\n"

    func bytes(_ text: String, _ encoding: String.Encoding) throws -> Data {
        try #require(text.data(using: encoding))
    }

    @Test func windows1252WithUmlautsIsNotReadAsUTF16() throws {
        for extra in ["", "x"] {   // even and odd lengths
            let text = rows + extra
            let data = try bytes(text, .windowsCP1252)
            #expect(CSV.decode(data) == text)
        }
        let short = "name;kcal\nKäse;350\nÄpfel;52\n"
        #expect(CSV.decode(try bytes(short, .windowsCP1252)) == short)
        let header = "name;Brennwert (kcal);Eiweiß (g)\nKäse;350;25\n"
        #expect(CSV.decode(try bytes(header, .windowsCP1252)) == header)
    }

    @Test func macRomanIsRecognised() throws {
        for extra in ["", "x"] {
            let text = rows + extra
            let data = try bytes(text, .macOSRoman)
            #expect(CSV.decode(data) == text)
        }
    }

    @Test func unicodeStillWorks() throws {
        let text = rows
        #expect(CSV.decode(try bytes(text, .utf8)) == text)
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + (try bytes(text, .utf8))
        #expect(CSV.decode(withBOM) == text)
        let utf16LE = Data([0xFF, 0xFE]) + (try bytes(text, .utf16LittleEndian))
        #expect(CSV.decode(utf16LE) == text)
        let utf16BE = Data([0xFE, 0xFF]) + (try bytes(text, .utf16BigEndian))
        #expect(CSV.decode(utf16BE) == text)
        // Without a byte-order mark: recognised by its zero bytes.
        #expect(CSV.decode(try bytes(text, .utf16LittleEndian)) == text)
        #expect(CSV.decode(try bytes(text, .utf16BigEndian)) == text)
    }

    @Test func eightBitTextIsNeverUTF16() throws {
        #expect(CSV.utf16Encoding([UInt8](try bytes(rows, .windowsCP1252))) == nil)
        #expect(!CSV.looksLikeMacRoman([UInt8](try bytes(rows, .windowsCP1252))))
        #expect(CSV.looksLikeMacRoman([UInt8](try bytes(rows, .macOSRoman))))
    }
}

@Suite("Sync state per direction")
struct SyncStateTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aFailingExportStaysVisibleWhileImportsWork() {
        var state = SyncState(mode: .iCloud(container: "iCloud.example"), account: .available)
        state.record(.export, finished: start, succeeded: false, error: "Your iCloud storage is full. Probe syncs again once there is space.")
        state.record(.import, finished: start.addingTimeInterval(60), succeeded: true)
        #expect(!state.isHealthy)
        #expect(state.lastSync == nil)
        #expect(state.summary { _ in "now" } == "Not uploading – iCloud storage full")
        // Only a successful export clears it.
        state.record(.export, finished: start.addingTimeInterval(120), succeeded: true)
        #expect(state.isHealthy)
        #expect(state.lastSync == start.addingTimeInterval(120))
        #expect(state.summary { _ in "just now" } == "On · synced just now")
    }

    @Test func anImportErrorDoesNotHideAnExportError() {
        var state = SyncState(mode: .iCloud(container: "iCloud.example"), account: .available)
        state.record(.import, finished: start, succeeded: false, error: "No network")
        #expect(state.summary { _ in "" } == "Not syncing")
        state.record(.export, finished: start, succeeded: false, error: "iCloud doesn't know the data types yet")
        #expect(state.lastError == "iCloud doesn't know the data types yet")
        #expect(state.summary { _ in "" } == "Not uploading")
        state.record(.import, finished: start, succeeded: true)
        #expect(state.lastError == "iCloud doesn't know the data types yet")
    }

    @Test func setUpNeverCountsAsASync() {
        var state = SyncState(mode: .iCloud(container: "iCloud.example"), account: .available)
        state.record(.setup, finished: start, succeeded: true)
        #expect(state.lastSync == nil)
        #expect(state.isHealthy)
    }

    @Test func callersWithoutAKindClearEverything() {
        var state = SyncState(mode: .iCloud(container: "iCloud.example"), account: .available)
        state.record(nil, finished: start, succeeded: false, error: "Something failed")
        #expect(state.lastError == "Something failed")
        state.record(nil, finished: start, succeeded: true)
        #expect(state.lastError == nil)
        #expect(state.lastSync == start)
        // A failure without a text changes nothing.
        state.record(.export, finished: start, succeeded: false)
        #expect(state.isHealthy)
    }

    @Test func iCloudThatNeedsAttentionIsNotGreen() {
        let state = SyncState(mode: .iCloud(container: "iCloud.example"), account: .temporarilyUnavailable)
        #expect(!state.isHealthy)
        #expect(state.summary { _ in "" } == "iCloud needs attention – open Settings → your name")
    }
}
