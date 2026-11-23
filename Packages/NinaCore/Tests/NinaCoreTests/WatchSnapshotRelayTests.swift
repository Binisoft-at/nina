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

// Made-up numbers: weigh-ins around 74 kg in March 2030, a lean gain at 0.15–0.25 kg a week.

private var relayUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func relayDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func relayPlan() -> CoachPlan {
    let start = relayDay("2030-02-01")
    let phase = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: start, end: relayDay("2030-05-31"), rateMin: 0.15,
                                rateMax: 0.25, startedAt: start.date(minutes: 8 * 60, calendar: relayUTC), status: .active)
    return CoachPlan(dayTypes: [CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default)], phases: [phase])
}

/// Daily morning weigh-ins at 07:00 from `first` through `last`, rising 0.2 kg a week from 74 kg.
private func relayMornings(from first: String, through last: String, source: WeightSignal.Reading.Source) -> [WeightSignal.Reading] {
    DayKey.range(relayDay(first), through: relayDay(last), calendar: relayUTC).enumerated().map { offset, day in
        WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: relayUTC),
                             kilograms: 74 + 0.2 / 7 * Double(offset), source: source)
    }
}

@Suite("What only the iPhone knows from Apple Health, on the watch")
struct WatchPhoneCoachTests {
    let today = "2030-03-14"
    let noon = Date(timeIntervalSinceReferenceDate: 946_000_000.123_456)

    func coach(day: String? = nil, freshness: Date?, healthWeighIns: Bool = true, morning: Double? = 74.6,
               status: WatchCoach.Status? = WatchCoach.Status(average: 74.5, rate: 0.2, word: "In range", tone: .good),
               activeEnergy: Double = 412) -> WatchSnapshotRelay.PhoneCoach {
        let health = morning.map { WatchSnapshotRelay.Morning(kilograms: $0, time: noon.addingTimeInterval(-5 * 3_600)) }
        return WatchSnapshotRelay.PhoneCoach(day: day ?? today, freshness: freshness, healthWeighIns: healthWeighIns,
                                             healthMorning: health, status: status, activeEnergy: activeEnergy,
                                             activeEnergyDay: day ?? today)
    }

    let own = WatchCoach.Status(average: 74.1, rate: 0.1, word: "Slower than planned", tone: .watch)

    /// The snapshot's own time travels in whole seconds (ISO 8601).
    func snapshot() -> TodaySnapshot {
        TodaySnapshot(day: today, energy: 1_240, energyGoal: 2_712, protein: 60, proteinGoal: 150, carbs: 200, carbsGoal: 260,
                      fat: 50, fatGoal: 75, water: 750, waterGoal: 2_500, updatedAt: Date(timeIntervalSinceReferenceDate: 946_000_000))
    }

    // MARK: The message

    @Test func theCoachPartTravelsWithTheSnapshot() throws {
        let part = coach(freshness: noon)
        let payload = WatchSnapshotRelay.Payload(snapshot: snapshot(), freshness: noon, sentAt: noon, coach: part)
        let message = try #require(WatchSnapshotRelay.message(payload))
        let back = try #require(WatchSnapshotRelay.payload(from: message))
        #expect(back == payload)
        // The freshness compares exactly after the trip (a rounded one would look older than the watch's).
        #expect(back.coach?.freshness == noon)
        #expect(try #require(back.coach?.freshness).timeIntervalSinceReferenceDate == 946_000_000.123_456)
    }

    @Test func aMessageWithoutACoachPartStillCounts() throws {
        // An older iPhone build, or one that hasn't read Apple Health since it started in the background.
        let plain = WatchSnapshotRelay.Payload(snapshot: snapshot(), freshness: noon, sentAt: noon)
        var message = try #require(WatchSnapshotRelay.message(plain))
        let back = try #require(WatchSnapshotRelay.payload(from: message))
        #expect(back.coach == nil)
        #expect(back.snapshot == plain.snapshot)
        // A coach part that doesn't read is left out; the snapshot still counts.
        message["nina.coach"] = Data("{\"day\":1}".utf8)
        let garbled = try #require(WatchSnapshotRelay.payload(from: message))
        #expect(garbled.coach == nil)
        #expect(garbled.snapshot == plain.snapshot)
    }

    @Test func theWatchKeepsTheLastCoachPartItGot() {
        let previous = coach(freshness: noon)
        let plain = WatchSnapshotRelay.Payload(snapshot: snapshot(), freshness: noon, sentAt: noon.addingTimeInterval(60))
        #expect(WatchSnapshotRelay.keptCoach(plain, previous: previous) == previous)
        #expect(WatchSnapshotRelay.keptCoach(plain, previous: nil) == nil)
        let newer = coach(freshness: noon.addingTimeInterval(30), morning: nil)
        let withCoach = WatchSnapshotRelay.Payload(snapshot: snapshot(), freshness: noon, sentAt: noon.addingTimeInterval(90), coach: newer)
        #expect(WatchSnapshotRelay.keptCoach(withCoach, previous: previous) == newer)
    }

    @Test func storedOnTheWatchAsJSON() throws {
        let part = coach(freshness: noon)
        let data = try #require(part.encoded())
        #expect(WatchSnapshotRelay.PhoneCoach(encoded: data) == part)
        #expect(WatchSnapshotRelay.PhoneCoach(encoded: Data("nope".utf8)) == nil)
        let empty = coach(freshness: nil, healthWeighIns: false, morning: nil, status: nil, activeEnergy: 0)
        #expect(WatchSnapshotRelay.PhoneCoach(encoded: try #require(empty.encoded())) == empty)
    }

    // MARK: Freshness

    @Test func theIPhonesNumbersCountOnceTheyHaveEverythingTheWatchHas() {
        let part = coach(freshness: noon)
        // The watch's store is behind, caught up, or empty.
        #expect(WatchSnapshotRelay.usesPhoneNumbers(part, watchFreshness: noon.addingTimeInterval(-3_600), watchToday: today))
        #expect(WatchSnapshotRelay.usesPhoneNumbers(part, watchFreshness: noon, watchToday: today))
        #expect(WatchSnapshotRelay.usesPhoneNumbers(part, watchFreshness: nil, watchToday: today))
        // A weigh-in just saved on the watch the iPhone hasn't seen yet.
        #expect(!WatchSnapshotRelay.usesPhoneNumbers(part, watchFreshness: noon.addingTimeInterval(1), watchToday: today))
        // An iPhone with no weigh-ins and no profile against a watch with some.
        #expect(!WatchSnapshotRelay.usesPhoneNumbers(coach(freshness: nil), watchFreshness: noon, watchToday: today))
        #expect(WatchSnapshotRelay.usesPhoneNumbers(coach(freshness: nil), watchFreshness: nil, watchToday: today))
        // Only on the watch's own diary day: yesterday's (the iPhone wasn't opened since) or a day ahead.
        #expect(!WatchSnapshotRelay.usesPhoneNumbers(coach(day: "2030-03-13", freshness: noon), watchFreshness: nil, watchToday: today))
        #expect(!WatchSnapshotRelay.usesPhoneNumbers(coach(day: "2030-03-15", freshness: noon), watchFreshness: nil, watchToday: today))
    }

    // MARK: What the watch shows

    @Test func theIPhonesStatusLineAndHealthMorningWhenFresh() {
        let part = coach(freshness: noon)
        let view = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon.addingTimeInterval(-60), typedMornings: 1,
                                                phone: part, watchToday: today)
        #expect(view.isFromPhone)
        #expect(view.status == part.status)
        #expect(view.healthMorning == part.healthMorning)
        #expect(view.hidesWeighIn)
        // Its numbers include the Health weigh-ins: no note.
        #expect(!view.showsHealthHint)
    }

    @Test func theWatchsOwnNumbersAfterAWeighInOnTheWatch() {
        let part = coach(freshness: noon)
        let view = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon.addingTimeInterval(120), typedMornings: 6,
                                                phone: part, watchToday: today)
        #expect(!view.isFromPhone)
        #expect(view.status == own)
        // This morning's Health weigh-in still counts: it can't be undone on the watch.
        #expect(view.healthMorning == part.healthMorning)
        #expect(view.hidesWeighIn)
        // The watch's own numbers leave Health out, and the iPhone said it has Health weigh-ins.
        #expect(view.showsHealthHint)
        // An iPhone without Health weigh-ins: the numbers are the same, no note.
        let typedOnly = coach(freshness: noon, healthWeighIns: false, morning: nil)
        let same = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon.addingTimeInterval(120), typedMornings: 1,
                                                phone: typedOnly, watchToday: today)
        #expect(!same.showsHealthHint)
        #expect(!same.hidesWeighIn)
    }

    @Test func yesterdaysWordFromTheIPhoneOnlyKeepsTheNote() {
        let yesterday = coach(day: "2030-03-13", freshness: noon)
        let view = WatchSnapshotRelay.coachView(own: own, watchFreshness: nil, typedMornings: 6, phone: yesterday, watchToday: today)
        #expect(!view.isFromPhone)
        #expect(view.status == own)
        #expect(view.healthMorning == nil)
        #expect(!view.hidesWeighIn)
        #expect(view.showsHealthHint)
        // The iPhone said it has no Health weigh-ins: no note, however few mornings were typed.
        let typedOnly = coach(day: "2030-03-13", freshness: noon, healthWeighIns: false, morning: nil)
        let none = WatchSnapshotRelay.coachView(own: own, watchFreshness: nil, typedMornings: 1, phone: typedOnly, watchToday: today)
        #expect(!none.isFromPhone)
        #expect(!none.showsHealthHint)
    }

    @Test func withoutWordFromTheIPhoneTheNoteFollowsTheTypedMornings() {
        let few = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon, typedMornings: 3, phone: nil, watchToday: today)
        #expect(few.status == own)
        #expect(!few.isFromPhone)
        #expect(few.showsHealthHint)
        #expect(few.healthMorning == nil)
        let enough = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon, typedMornings: 4, phone: nil, watchToday: today)
        #expect(!enough.showsHealthHint)
        #expect(WatchSnapshotRelay.coachView(own: nil, watchFreshness: nil, typedMornings: 0, phone: nil, watchToday: today).status == nil)
    }

    @Test func aFreshIPhoneDecidesEvenWithNothingToShow() {
        // Fresher iPhone without a status line (nothing to show yet): the watch shows none either.
        let part = coach(freshness: noon, morning: nil, status: nil)
        let view = WatchSnapshotRelay.coachView(own: own, watchFreshness: noon, typedMornings: 0, phone: part, watchToday: today)
        #expect(view.isFromPhone)
        #expect(view.status == nil)
        #expect(!view.showsHealthHint)
        // The watch has no status line of its own, the iPhone has one from Health weigh-ins.
        let fromHealth = WatchSnapshotRelay.coachView(own: nil, watchFreshness: nil, typedMornings: 0, phone: coach(freshness: noon),
                                                      watchToday: today)
        #expect(fromHealth.status?.average == 74.5)
    }

    // MARK: Activity bonus

    @Test func theActivityBonusIsTheIPhonesReadingOfToday() {
        #expect(WatchSnapshotRelay.activeEnergy(coach(freshness: noon), on: today) == 412)
        // Yesterday's never raises today's budget.
        #expect(WatchSnapshotRelay.activeEnergy(coach(freshness: noon), on: "2030-03-15") == 0)
        #expect(WatchSnapshotRelay.activeEnergy(nil, on: today) == 0)
        #expect(WatchSnapshotRelay.activeEnergy(coach(freshness: noon, activeEnergy: -5), on: today) == 0)
        #expect(WatchSnapshotRelay.activeEnergy(coach(freshness: noon, activeEnergy: .nan), on: today) == 0)
    }

    // MARK: On the iPhone

    @Test func theIPhoneSendsItsHealthMorningAndItsNumbers() {
        let plan = relayPlan()
        let day = relayDay(today)
        // Three weeks of morning weigh-ins from a scale (Apple Health), two typed in Nina later in the day.
        let health = relayMornings(from: "2030-02-22", through: today, source: .health)
        let typed = [relayDay("2030-03-12"), day].map { day in
            WeightSignal.Reading(day: day, time: day.date(minutes: 19 * 60, calendar: relayUTC), kilograms: 75.4)
        }
        let signal = WeightSignal(health + typed, calendar: relayUTC)
        let part = WatchSnapshotRelay.phoneCoach(signal: signal, plan: plan, checkIns: [], today: day, freshness: noon,
                                                 activeEnergy: 412, activeEnergyDay: day, calendar: relayUTC)
        #expect(part.day == today)
        #expect(part.freshness == noon)
        #expect(part.healthWeighIns)
        let morning = signal.morning(on: day)
        #expect(part.healthMorning == morning.map { WatchSnapshotRelay.Morning(kilograms: $0.kilograms, time: $0.time) })
        #expect(part.healthMorning != nil)
        #expect(part.status == WatchCoach.status(summary: signal.summary(on: day, plan: plan), plan: plan, checkIns: [], calendar: relayUTC))
        #expect(part.status?.average != nil)
        #expect(part.status?.rate != nil)
        #expect(part.activeEnergy == 412)
        #expect(part.activeEnergyDay == today)

        // The same weigh-ins without Health: the watch's own numbers differ (the evening ones aren't mornings).
        let typedOnly = WeightSignal(typed, calendar: relayUTC)
        #expect(WatchCoach.status(summary: typedOnly.summary(on: day, plan: plan), plan: plan, checkIns: [], calendar: relayUTC)
            != part.status)
    }

    @Test func aMorningTypedInNinaIsNotSentAsHealth() {
        let day = relayDay(today)
        let health = relayMornings(from: "2030-03-01", through: today, source: .health)
        // Typed at 06:30, before the scale's 07:00: the typed one is the morning weigh-in.
        let typed = WeightSignal.Reading(day: day, time: day.date(minutes: 6 * 60 + 30, calendar: relayUTC), kilograms: 74.2)
        let signal = WeightSignal(health + [typed], calendar: relayUTC)
        let part = WatchSnapshotRelay.phoneCoach(signal: signal, plan: relayPlan(), checkIns: [], today: day, freshness: noon,
                                                 activeEnergy: 0, activeEnergyDay: day, calendar: relayUTC)
        #expect(part.healthMorning == nil)
        // Earlier days' Health mornings still count in its numbers.
        #expect(part.healthWeighIns)
    }

    @Test func oldHealthWeighInsAndNoPlan() {
        let day = relayDay(today)
        // Health weigh-ins only until more than three weeks ago, typed ones since.
        let old = relayMornings(from: "2030-01-20", through: "2030-02-21", source: .health)
        let typed = relayMornings(from: "2030-02-22", through: today, source: .nina)
        let signal = WeightSignal(old + typed, calendar: relayUTC)
        let part = WatchSnapshotRelay.phoneCoach(signal: signal, plan: relayPlan(), checkIns: [], today: day, freshness: noon,
                                                 activeEnergy: .infinity, activeEnergyDay: day, calendar: relayUTC)
        #expect(!part.healthWeighIns)
        #expect(part.healthMorning == nil)
        #expect(part.activeEnergy == 0)
        // Without a plan: the Health facts, no status line.
        let none = WatchSnapshotRelay.phoneCoach(signal: WeightSignal(relayMornings(from: "2030-03-01", through: today, source: .health),
                                                                      calendar: relayUTC),
                                                 plan: CoachPlan(), checkIns: [], today: day, freshness: nil, activeEnergy: 120,
                                                 activeEnergyDay: day, calendar: relayUTC)
        #expect(none.status == nil)
        #expect(none.healthMorning != nil)
        #expect(none.healthWeighIns)
    }
}
