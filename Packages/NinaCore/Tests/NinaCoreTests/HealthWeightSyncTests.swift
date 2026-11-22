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
