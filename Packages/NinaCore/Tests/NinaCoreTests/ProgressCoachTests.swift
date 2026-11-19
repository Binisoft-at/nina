import Foundation
import Testing
@testable import NinaCore

// A made-up plan set up on Mon 4 Feb 2030: a daily creatine check (affects weight), a fish oil
// check (optional), a vitamin check only on gym days, one paused week.

private var progressUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func progressDay(_ raw: String) -> DayKey { DayKey(raw)! }

private enum ProgressFixture {
    static let setUp = progressDay("2030-02-04")

    static func plan(pauses: [CoachPlan.Pause] = []) -> CoachPlan {
        let phase = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: setUp, rateMin: 0.1, rateMax: 0.2,
                                    startedAt: setUp.date(calendar: progressUTC), status: .active)
        let gym = CoachPlan.DayType(id: "gym", name: "Gym", schedule: .fixed, weekdays: Weekdays([1, 3, 5]))
        let rest = CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default)
        let checks = [
            CoachPlan.Check(id: "creatine", name: "Creatine"),
            CoachPlan.Check(id: "fish", name: "Fish oil", isOptional: true),
            CoachPlan.Check(id: "vit", name: "Vitamin", days: .dayTypes(["gym"])),
        ]
        return CoachPlan(dayTypes: [gym, rest], phases: [phase], checks: checks, pauses: pauses)
    }

    /// Creatine done every day from `from` through `through`, except the given days.
    static func done(_ id: String, from: String, through: String, except: Set<String> = []) -> [DayKey: Set<String>] {
        var done: [DayKey: Set<String>] = [:]
        for day in DayKey.range(progressDay(from), through: progressDay(through), calendar: progressUTC) where !except.contains(day.rawValue) {
            done[day, default: []].insert(id)
        }
        return done
    }

    static func merge(_ parts: [DayKey: Set<String>]...) -> [DayKey: Set<String>] {
        var result: [DayKey: Set<String>] = [:]
        for part in parts {
            for (day, ids) in part { result[day, default: []].formUnion(ids) }
        }
        return result
    }
}

@Suite("Progress: checks, events and check-in history")
struct ProgressCoachTests {
    @Test func windowStart() {
        let cal = progressUTC
        let today = progressDay("2030-04-01")
        #expect(ProgressChecks.windowStart(today: today, setUp: nil, calendar: cal) == progressDay("2030-03-05"))
        // A plan set up long ago: the full 28 days.
        #expect(ProgressChecks.windowStart(today: today, setUp: ProgressFixture.setUp, calendar: cal) == progressDay("2030-03-05"))
        // A plan set up 10 days ago: from that day.
        #expect(ProgressChecks.windowStart(today: today, setUp: progressDay("2030-03-22"), calendar: cal) == progressDay("2030-03-22"))
        // Never after today.
        #expect(ProgressChecks.windowStart(today: today, setUp: progressDay("2030-05-01"), calendar: cal) == today)
    }

    @Test func adherenceOverTwentyEightDays() throws {
        let cal = progressUTC
        let plan = ProgressFixture.plan()
        let today = progressDay("2030-04-01") // a Monday
        let start = ProgressChecks.windowStart(today: today, setUp: ProgressFixture.setUp, calendar: cal)
        // Creatine missed on two days and not yet ticked today; fish oil ticked 3 times.
        let done = ProgressFixture.merge(
            ProgressFixture.done("creatine", from: "2030-03-05", through: "2030-03-31", except: ["2030-03-10", "2030-03-20"]),
            ProgressFixture.done("fish", from: "2030-03-29", through: "2030-03-31"))
        let line = try #require(ProgressChecks.adherence(plan: plan, today: today, start: start, done: done, calendar: cal))
        // 27 days counted (today is still open), 25 ticked. Vitamin: gym days (Mon, Wed, Fri) without today = 11, none ticked.
        #expect(line.text == "Creatine 25 of 27 days · Fish oil 3 days · Vitamin 0 of 11 days")
        #expect(line.start == progressDay("2030-03-05"))
        #expect(!line.isShortened)

        // Ticked today too: today counts.
        var withToday = done
        withToday[today, default: []].insert("creatine")
        let full = try #require(ProgressChecks.adherence(plan: plan, today: today, start: start, done: withToday, calendar: cal))
        #expect(full.text.hasPrefix("Creatine 26 of 28 days"))

        // A day marked as another type: the vitamin is due on the marked gym day only.
        let marks = ["2030-03-30": "gym", "2030-03-29": "rest"] // Sat becomes gym, Fri becomes rest
        let marked = try #require(ProgressChecks.adherence(plan: plan, today: today, start: start, done: done, marks: marks, calendar: cal))
        #expect(marked.text.hasSuffix("Vitamin 0 of 11 days"))
    }

    @Test func adherenceShortWindowAndPauses() throws {
        let cal = progressUTC
        let today = progressDay("2030-04-01")
        // Set up 6 days ago: "Since 26 Mar".
        let start = ProgressChecks.windowStart(today: today, setUp: progressDay("2030-03-26"), calendar: cal)
        let done = ProgressFixture.done("creatine", from: "2030-03-26", through: "2030-03-31")
        let short = try #require(ProgressChecks.adherence(plan: ProgressFixture.plan(), today: today, start: start, done: done, calendar: cal))
        #expect(short.text.hasPrefix("Creatine 6 of 6 days"))
        #expect(short.isShortened)
        #expect(short.start == progressDay("2030-03-26"))

        // Paused days are left out.
        let paused = ProgressFixture.plan(pauses: [CoachPlan.Pause(start: progressDay("2030-03-28"), end: progressDay("2030-03-30"))])
        let line = try #require(ProgressChecks.adherence(plan: paused, today: today, start: start, done: done, calendar: cal))
        #expect(line.text.hasPrefix("Creatine 3 of 3 days"))

        // Nothing to count: no plan, no checks, or only optional checks never ticked.
        #expect(ProgressChecks.adherence(plan: CoachPlan(), today: today, start: start, done: done, calendar: cal) == nil)
        var optionalOnly = ProgressFixture.plan()
        optionalOnly.checks = [CoachPlan.Check(id: "fish", name: "Fish oil", isOptional: true)]
        #expect(ProgressChecks.adherence(plan: optionalOnly, today: today, start: start, done: done, calendar: cal) == nil)
        #expect(ProgressChecks.adherence(plan: ProgressFixture.plan(), today: today, start: progressDay("2030-04-02"),
                                         done: done, calendar: cal) == nil)
    }

    @Test func weightEvents() throws {
        let cal = progressUTC
        var plan = ProgressFixture.plan()
        plan.checks.append(CoachPlan.Check(id: "kreatin", name: "", affectsWeight: true))
        let ticks: [(day: DayKey, checkID: String)] = [
            (progressDay("2030-03-12"), "creatine"), (progressDay("2030-03-10"), "creatine"), (progressDay("2030-03-01"), "fish"),
            (progressDay("2030-03-20"), "kreatin"), (progressDay("2030-01-02"), "gone"),
        ]
        let events = ProgressWeightEvent.events(in: plan, ticks: ticks)
        #expect(events.map(\.checkID) == ["creatine", "kreatin"])
        let creatine = try #require(events.first)
        #expect(creatine.day == progressDay("2030-03-10"))
        #expect(creatine.title == "Creatine started")
        // A check without a name goes by its id.
        #expect(events.last?.name == "kreatin")

        #expect(creatine.note(on: progressDay("2030-03-10"), calendar: cal) == "Creatine started today – up to ~1 kg may be water")
        #expect(creatine.note(on: progressDay("2030-03-11"), calendar: cal) == "Creatine started 1 day ago – up to ~1 kg may be water")
        #expect(creatine.note(on: progressDay("2030-03-19"), calendar: cal) == "Creatine started 9 days ago – up to ~1 kg may be water")
        // The note lasts as long as the check-in's hold.
        #expect(creatine.isHolding(on: progressDay("2030-04-06"), calendar: cal))
        #expect(!creatine.isHolding(on: progressDay("2030-04-07"), calendar: cal))
        #expect(creatine.note(on: progressDay("2030-04-07"), calendar: cal) == nil)
        #expect(creatine.note(on: progressDay("2030-03-09"), calendar: cal) == nil)
        // The same first tick as the check-in engine's hold.
        #expect(CheckInEngine.weightCheck(in: plan, ticks: ticks)?.firstTick == creatine.day)
        #expect(ProgressWeightEvent.events(in: plan, ticks: [(progressDay("2030-03-01"), "fish")]).isEmpty)
    }

    @Test func checkInHistoryWeights() {
        let cal = progressUTC
        let plan = ProgressFixture.plan()
        // Mornings around 76 kg, +0.02 kg a day, from 4 Feb.
        let readings: [WeightSignal.Reading] = (0..<42).map { offset in
            let day = ProgressFixture.setUp.adding(days: offset, calendar: cal)
            return WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: cal), kilograms: 76 + Double(offset) * 0.02)
        }
        let signal = WeightSignal(readings, calendar: cal)
        let day = progressDay("2030-03-11")

        // Saved numbers are used as they are.
        let saved = CheckInSnapshot(day: day, avg7: 74.6, rate: 0.18)
        let weight = ProgressCheckIns.weight(of: saved, signal: signal, plan: plan)
        #expect(weight.average == 74.6 && weight.rate == 0.18)

        // With Health weights nothing was stored: recomputed live.
        let health = CheckInSnapshot(day: day, usesHealthWeights: true)
        let live = ProgressCheckIns.weight(of: health, signal: signal, plan: plan)
        #expect(live.average == signal.average(on: day).value)
        #expect(live.rate == signal.rate(on: day, plan: plan).value)
        #expect(abs((live.average ?? 0) - (76 + 32 * 0.02)) < 1e-9)
        #expect(abs((live.rate ?? 0) - 0.14) < 1e-6)
    }
}
