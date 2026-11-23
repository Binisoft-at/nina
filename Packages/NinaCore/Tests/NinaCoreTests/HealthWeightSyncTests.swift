import Foundation
import Testing
@testable import NinaCore

@Suite("Weigh-ins to Apple Health")
struct HealthWeightSyncTests {
    let morning = Date(timeIntervalSinceReferenceDate: 946_000_000)

    @Test func aNewWeighInIsWrittenOnceAndThenRemembered() {
        let item = HealthWeightSync.Item(id: "a", kilograms: 74.2, time: morning, version: 10)
        let steps = HealthWeightSync.plan([item], marks: [:])
        #expect(steps == [.ensure(id: "a", mark: .init(kilograms: 74.2, time: morning, version: 10))])
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        #expect(HealthWeightSync.plan([item], marks: marks).isEmpty)
    }

    @Test func anEditRemovesTheOldSampleFirst() {
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        let edited = HealthWeightSync.Item(id: "a", kilograms: 73.8, time: morning, version: 11)
        let steps = HealthWeightSync.plan([edited], marks: marks)
        #expect(steps == [
            .remove(kilograms: 74.2, time: morning),
            .ensure(id: "a", mark: .init(kilograms: 73.8, time: morning, version: 11)),
        ])
    }

    @Test func aNoteOnlyEditKeepsTheSample() {
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        let edited = HealthWeightSync.Item(id: "a", kilograms: 74.2, time: morning, version: 12)
        #expect(HealthWeightSync.plan([edited], marks: marks) == [
            .ensure(id: "a", mark: .init(kilograms: 74.2, time: morning, version: 12)),
        ])
    }

    @Test func aDeletedWeighInLeavesHealth() {
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        let deleted = HealthWeightSync.Item(id: "a", kilograms: 74.2, time: morning, version: 13, isDeleted: true)
        #expect(HealthWeightSync.plan([deleted], marks: marks) == [.remove(kilograms: 74.2, time: morning), .forget(id: "a")])
        #expect(HealthWeightSync.plan([deleted], marks: [:]).isEmpty)
    }

    @Test func importedHistoryIsNeverWritten() {
        let imported = HealthWeightSync.Item(id: "b", kilograms: 75, time: morning, version: 1, isImported: true)
        #expect(HealthWeightSync.plan([imported], marks: [:]).isEmpty)
        let implausible = HealthWeightSync.Item(id: "c", kilograms: 7.5, time: morning, version: 1)
        #expect(HealthWeightSync.plan([implausible], marks: [:]).isEmpty)
    }

    @Test func removalsComeBeforeWrites() {
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        let items = [
            HealthWeightSync.Item(id: "n", kilograms: 74.0, time: morning.addingTimeInterval(86_400), version: 20),
            HealthWeightSync.Item(id: "a", kilograms: 74.2, time: morning, version: 21, isDeleted: true),
        ]
        let steps = HealthWeightSync.plan(items, marks: marks)
        #expect(steps.first == .remove(kilograms: 74.2, time: morning))
        #expect(steps.last == .ensure(id: "n", mark: .init(kilograms: 74.0, time: morning.addingTimeInterval(86_400), version: 20)))
        #expect(HealthWeightSync.pruned(marks, keeping: ["n"]).isEmpty)
    }

    @Test func onlyLiveTypedPlausibleWeighInsAreWritten() {
        #expect(HealthWeightSync.writes(.init(id: "a", kilograms: 74.2, time: morning, version: 1)))
        #expect(!HealthWeightSync.writes(.init(id: "a", kilograms: 74.2, time: morning, version: 1, isImported: true)))
        #expect(!HealthWeightSync.writes(.init(id: "a", kilograms: 74.2, time: morning, version: 1, isDeleted: true)))
        #expect(!HealthWeightSync.writes(.init(id: "a", kilograms: 301, time: morning, version: 1)))
        #expect(!HealthWeightSync.writes(.init(id: "a", kilograms: 24.9, time: morning, version: 1)))
    }

    @Test func aWeighInGoneFromTheWindowTakesItsSampleAlong() {
        let windowStart = morning.addingTimeInterval(-13 * 86_400)
        let marks = [
            "gone": HealthWeightSync.Mark(kilograms: 74.6, time: morning.addingTimeInterval(-86_400), version: 5),
            "old": HealthWeightSync.Mark(kilograms: 75.0, time: windowStart.addingTimeInterval(-3_600), version: 4),
            "kept": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10),
        ]
        let kept = HealthWeightSync.Item(id: "kept", kilograms: 74.2, time: morning, version: 10)
        let steps = HealthWeightSync.plan([kept], marks: marks, windowStart: windowStart)
        // Deleted for good on another device (or moved far back): its sample leaves Health; one
        // older than the window is only forgotten.
        #expect(steps == [
            .remove(kilograms: 74.6, time: morning.addingTimeInterval(-86_400)),
            .forget(id: "gone"),
            .forget(id: "old"),
        ])
        // Without a window (the store couldn't be read for real) nothing is removed.
        #expect(HealthWeightSync.plan([kept], marks: marks) == [.forget(id: "gone"), .forget(id: "old")])
    }

    @Test func anEmptiedStoreIsNotTrusted() {
        let windowStart = morning.addingTimeInterval(-13 * 86_400)
        var marks: [String: HealthWeightSync.Mark] = [:]
        for day in 0..<6 {
            marks["w\(day)"] = HealthWeightSync.Mark(kilograms: 74 + Double(day) / 10, time: morning.addingTimeInterval(-Double(day) * 86_400),
                                                      version: day + 1)
        }
        // Signed out of iCloud: the window holds no weigh-in at all.
        #expect(!HealthWeightSync.trustsStore(items: [], marks: marks, windowStart: windowStart))
        // Half of them came back so far: more than three vanished at once.
        let back = (0..<2).map { HealthWeightSync.Item(id: "w\($0)", kilograms: 74, time: morning, version: $0 + 1) }
        #expect(!HealthWeightSync.trustsStore(items: back, marks: marks, windowStart: windowStart))
        // One deleted on another device: trusted, its sample leaves Health.
        let most = (0..<5).map { HealthWeightSync.Item(id: "w\($0)", kilograms: 74, time: morning, version: $0 + 1) }
        #expect(HealthWeightSync.trustsStore(items: most, marks: marks, windowStart: windowStart))
        // Nothing remembered in the window: nothing to lose.
        let old = ["old": HealthWeightSync.Mark(kilograms: 75, time: windowStart.addingTimeInterval(-3_600), version: 1)]
        #expect(HealthWeightSync.trustsStore(items: [], marks: old, windowStart: windowStart))
        #expect(HealthWeightSync.trustsStore(items: [], marks: [:], windowStart: windowStart))
    }

    @Test func anUntrustedStoreOnlyForgets() {
        let windowStart = morning.addingTimeInterval(-13 * 86_400)
        let marks = ["a": HealthWeightSync.Mark(kilograms: 74.2, time: morning, version: 10)]
        let trusted = HealthWeightSync.trustsStore(items: [], marks: marks, windowStart: windowStart)
        let steps = HealthWeightSync.plan([], marks: marks, windowStart: trusted ? windowStart : nil)
        #expect(steps == [.forget(id: "a")])
    }

    @Test func aDiaryEntryDeletedForGoodLeavesHealth() {
        let ledger = ["e1", "e2", "e3", "moved"]
        let missing = HealthLedgerSweep.missing(ledgerIDs: ledger, windowIDs: ["e1", "e2"])
        #expect(missing == ["e3", "moved"])
        // "moved" still exists on an older day; "e3" was undone right after logging.
        let sweep = HealthLedgerSweep.plan(missing: missing, found: ["moved"], storeIsEmpty: false)
        #expect(sweep == HealthLedgerSweep(remove: ["e3"], forget: ["moved"]))
        #expect(HealthLedgerSweep.plan(missing: [], found: [], storeIsEmpty: false) == HealthLedgerSweep())
        #expect(HealthLedgerSweep.plan(missing: ["moved"], found: ["moved"], storeIsEmpty: false) == HealthLedgerSweep(forget: ["moved"]))
    }

    @Test func anEmptiedDiaryOnlyForgets() {
        // Signed out of iCloud: the store has no entries at all.
        let emptied = HealthLedgerSweep.plan(missing: ["e1", "e2"], found: [], storeIsEmpty: true)
        #expect(emptied == HealthLedgerSweep(forget: ["e1", "e2"], distrusted: true))
        // An account switch half done: many vanish at once.
        let many = (0..<25).map { "e\($0)" }.sorted()
        let sweep = HealthLedgerSweep.plan(missing: many, found: [], storeIsEmpty: false)
        #expect(sweep.remove.isEmpty)
        #expect(sweep.distrusted)
        #expect(sweep.forget.count == 25)
        // A saved meal of five foods undone at once is fine.
        let meal = (0..<5).map { "m\($0)" }
        #expect(HealthLedgerSweep.plan(missing: meal, found: [], storeIsEmpty: false).remove == meal)
    }

    @Test func theLimitsAreInclusive() {
        // Exactly 20 entries gone in one pass are still removed; 21 look like an emptied store.
        let twenty = (0..<20).map { String(format: "e%02d", $0) }
        #expect(HealthLedgerSweep.plan(missing: twenty, found: [], storeIsEmpty: false).remove == twenty)
        let more = twenty + ["e20"]
        #expect(HealthLedgerSweep.plan(missing: more, found: [], storeIsEmpty: false).distrusted)
        // Entries that only moved out of the window never count towards the limit.
        let moved = (0..<30).map { "m\($0)" }
        let sweep = HealthLedgerSweep.plan(missing: moved + ["gone"], found: Set(moved), storeIsEmpty: false)
        #expect(sweep.remove == ["gone"])
        #expect(!sweep.distrusted)
        // Weigh-ins: three vanished at once are trusted, four are not.
        let windowStart = morning.addingTimeInterval(-13 * 86_400)
        var marks: [String: HealthWeightSync.Mark] = [:]
        for day in 0..<5 {
            marks["w\(day)"] = HealthWeightSync.Mark(kilograms: 74, time: morning.addingTimeInterval(-Double(day) * 86_400), version: 1)
        }
        let two = (0..<2).map { HealthWeightSync.Item(id: "w\($0)", kilograms: 74, time: morning, version: 1) }
        #expect(HealthWeightSync.trustsStore(items: two, marks: marks, windowStart: windowStart))
        let one = [HealthWeightSync.Item(id: "w0", kilograms: 74, time: morning, version: 1)]
        #expect(!HealthWeightSync.trustsStore(items: one, marks: marks, windowStart: windowStart))
    }

    @Test func weightSamplesHaveASyncIdentifier() throws {
        let id = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(HealthMapping.syncIdentifier(weight: id) == "nina.weight.6F9619FF-8B86-D011-B42D-00C04FC964FF")
        #expect(HealthMapping.syncIdentifier(weightID: id.uuidString) == HealthMapping.syncIdentifier(weight: id))
        #expect(HealthMapping.syncIdentifier(weight: id) != HealthMapping.syncIdentifier(entry: id))
    }

    @Test func theSheetHidesTheImportTagAndKeepsIt() {
        #expect(HealthWeightSync.editableNote("after holiday #import") == "after holiday")
        #expect(HealthWeightSync.editableNote("#import").isEmpty)
        #expect(HealthWeightSync.editableNote("import").isEmpty)
        #expect(HealthWeightSync.editableNote("hotel scale  #travel") == "hotel scale  #travel")
        // An imported weigh-in stays history, also when the note was cleared.
        #expect(HealthWeightSync.savedNote("", imported: true) == "#import")
        #expect(HealthWeightSync.savedNote("after holiday #salty", imported: true) == "after holiday #salty #import")
        #expect(HealthWeightSync.isImported(note: HealthWeightSync.savedNote("", imported: true)))
        // A typed one never becomes history from the field.
        #expect(HealthWeightSync.savedNote("hotel scale #import", imported: false) == "hotel scale")
        #expect(HealthWeightSync.savedNote("hotel scale  #travel", imported: false) == "hotel scale  #travel")
        #expect(!HealthWeightSync.isImported(note: HealthWeightSync.savedNote("#Import", imported: false)))
    }

    @Test func importedWeighInsCarryATag() {
        #expect(HealthWeightSync.importedNote("") == "#import")
        #expect(HealthWeightSync.importedNote("after holiday") == "after holiday #import")
        #expect(HealthWeightSync.importedNote("after holiday #import") == "after holiday #import")
        #expect(HealthWeightSync.isImported(note: "after holiday #import"))
        #expect(HealthWeightSync.isImported(note: "import"))
        #expect(!HealthWeightSync.isImported(note: "important day #salty"))
        #expect(HealthWeightSync.noteWithoutImportTag("after holiday #import") == "after holiday")
        #expect(HealthWeightSync.noteWithoutImportTag("#import").isEmpty)
    }
}
