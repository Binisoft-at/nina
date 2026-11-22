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
}
