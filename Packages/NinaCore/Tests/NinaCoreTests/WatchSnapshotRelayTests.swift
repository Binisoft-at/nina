import Foundation
import Testing
@testable import NinaCore

@Suite("iPhone to Apple Watch snapshot")
struct WatchSnapshotRelayTests {
    let noon = Date(timeIntervalSinceReferenceDate: 946_000_000)
    let day = "2030-03-14"

    func snapshot(_ energy: Double, day: String? = nil) -> TodaySnapshot {
        TodaySnapshot(day: day ?? self.day, energy: energy, energyGoal: 2_300, protein: 60, proteinGoal: 150, carbs: 200,
                      carbsGoal: 260, fat: 50, fatGoal: 75, water: 750, waterGoal: 2_500, updatedAt: noon)
    }

    @Test func theMessageRoundTrips() throws {
        let payload = WatchSnapshotRelay.Payload(snapshot: snapshot(1_240), freshness: noon.addingTimeInterval(-60), sentAt: noon)
        let message = try #require(WatchSnapshotRelay.message(payload))
        let back = try #require(WatchSnapshotRelay.payload(from: message))
        #expect(back == payload)
        // Without a freshness (nothing logged on the iPhone that day).
        let empty = WatchSnapshotRelay.Payload(snapshot: snapshot(0), freshness: nil, sentAt: noon)
        #expect(WatchSnapshotRelay.payload(from: try #require(WatchSnapshotRelay.message(empty))) == empty)
        // Anything else is ignored, also a newer format.
        #expect(WatchSnapshotRelay.payload(from: [:]) == nil)
        var future = message
        future["nina.relay"] = 99
        #expect(WatchSnapshotRelay.payload(from: future) == nil)
    }

    @Test func olderOrRepeatedMessagesAreIgnored() {
        let first = WatchSnapshotRelay.Payload(snapshot: snapshot(800), freshness: noon, sentAt: noon)
        #expect(WatchSnapshotRelay.isNewer(first, than: nil))
        #expect(!WatchSnapshotRelay.isNewer(first, than: first.mark))
        let later = WatchSnapshotRelay.Payload(snapshot: snapshot(1_200), freshness: noon, sentAt: noon.addingTimeInterval(30))
        #expect(WatchSnapshotRelay.isNewer(later, than: first.mark))
        #expect(!WatchSnapshotRelay.isNewer(first, than: later.mark))
    }

    @Test func theWatchTakesTheIPhonesNumbersUnlessItHasNewerOnes() {
        let lunch = WatchSnapshotRelay.Payload(snapshot: snapshot(1_240), freshness: noon, sentAt: noon)
        // The watch's store is behind (its import hasn't come yet) or empty.
        #expect(WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: noon.addingTimeInterval(-3_600), watchToday: day))
        #expect(WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: nil, watchToday: day))
        #expect(WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: noon, watchToday: day))
        // Water added on the watch the iPhone hasn't seen yet: keep the watch's numbers.
        #expect(!WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: noon.addingTimeInterval(60), watchToday: day))
        let nothing = WatchSnapshotRelay.Payload(snapshot: snapshot(0), freshness: nil, sentAt: noon)
        #expect(!WatchSnapshotRelay.acceptsPhone(nothing, watchFreshness: noon, watchToday: day))
        // A day that is over on the watch, or one the watch hasn't reached yet.
        #expect(!WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: nil, watchToday: "2030-03-15"))
        #expect(WatchSnapshotRelay.acceptsPhone(lunch, watchFreshness: noon.addingTimeInterval(600), watchToday: "2030-03-13"))
    }

    @Test func aWatchRefreshNeverOverwritesFresherIPhoneNumbers() {
        let phone = WatchSnapshotRelay.PhoneMark(day: day, freshness: noon, sentAt: noon)
        // Opened before its CloudKit import: the watch's store is behind.
        #expect(!WatchSnapshotRelay.acceptsOwn(day: day, freshness: noon.addingTimeInterval(-3_600), phone: phone))
        #expect(!WatchSnapshotRelay.acceptsOwn(day: day, freshness: nil, phone: phone))
        // Caught up, or newer.
        #expect(WatchSnapshotRelay.acceptsOwn(day: day, freshness: noon, phone: phone))
        #expect(WatchSnapshotRelay.acceptsOwn(day: day, freshness: noon.addingTimeInterval(60), phone: phone))
        // Nothing from the iPhone, a new day, or an iPhone with nothing that day.
        #expect(WatchSnapshotRelay.acceptsOwn(day: day, freshness: nil, phone: nil))
        #expect(WatchSnapshotRelay.acceptsOwn(day: "2030-03-15", freshness: nil, phone: phone))
        #expect(!WatchSnapshotRelay.acceptsOwn(day: "2030-03-13", freshness: noon, phone: phone))
        let empty = WatchSnapshotRelay.PhoneMark(day: day, freshness: nil, sentAt: noon)
        #expect(WatchSnapshotRelay.acceptsOwn(day: day, freshness: nil, phone: empty))
    }

    @Test func freshnessIsTheNewestChange() {
        let changes = [noon.addingTimeInterval(-600), noon, noon.addingTimeInterval(-60)]
        #expect(WatchSnapshotRelay.freshness(changes) == noon)
        #expect(WatchSnapshotRelay.freshness([]) == nil)
        // An Undo that deleted the newest entry leaves no record behind: the save itself counts.
        #expect(WatchSnapshotRelay.freshness(changes, localChange: noon.addingTimeInterval(5)) == noon.addingTimeInterval(5))
        #expect(WatchSnapshotRelay.freshness([], localChange: noon) == noon)
    }

    @Test func thePhoneMarkIsStoredAsJSON() throws {
        let mark = WatchSnapshotRelay.PhoneMark(day: day, freshness: noon, sentAt: noon.addingTimeInterval(1))
        let data = try JSONEncoder().encode(mark)
        #expect(try JSONDecoder().decode(WatchSnapshotRelay.PhoneMark.self, from: data) == mark)
    }
}
