import Foundation
import Testing
@testable import NinaCore

// Made-up weights: about 80 kg, a gain phase from Mon 2030-01-07 at +0.15 to +0.25 kg/week with a
// review at 82–83 kg; a cut from 90 kg for the loss direction.

private var weightUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func weightDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func weightTime(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date {
    day.date(minutes: hour * 60 + minute, calendar: weightUTC)
}

private func weightReading(_ raw: String, _ kilograms: Double, hour: Int = 7, minute: Int = 0, note: String = "",
                           source: WeightSignal.Reading.Source = .nina) -> WeightSignal.Reading {
    let day = weightDay(raw)
    return WeightSignal.Reading(day: day, time: weightTime(day, hour, minute), kilograms: kilograms, note: note, source: source)
}

/// One 07:00 weigh-in per day from `start` for `days` days (offsets in `skip` left out).
private func weightSeries(from start: String, days: Int, skip: Set<Int> = [], _ kilograms: (Int) -> Double) -> [WeightSignal.Reading] {
    let first = weightDay(start)
    return (0..<days).filter { !skip.contains($0) }.map { offset in
        let day = first.adding(days: offset, calendar: weightUTC)
        return WeightSignal.Reading(day: day, time: weightTime(day, 7), kilograms: kilograms(offset))
    }
}

private func weightClose(_ lhs: Double?, _ rhs: Double, _ tolerance: Double = 1e-9) -> Bool {
    guard let lhs else { return false }
    return abs(lhs - rhs) <= tolerance
}

@Suite("Weight signal")
struct WeightSignalTests {
    static let startedAt = Date(timeIntervalSince1970: 1_894_006_800) // 2030-01-07 09:00 UTC

    static var gain: CoachPlan.Phase {
        CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: weightDay("2030-01-07"), end: weightDay("2030-05-26"),
                        endApprox: true, rateMin: 0.15, rateMax: 0.25, reviewMin: 82, reviewMax: 83, targetWeight: 83,
                        startedAt: startedAt, status: .active,
                        revisions: [.init(from: weightDay("2030-01-07"), baseline: DailyTargets(energy: 2600, protein: 150, carbs: 330, fat: 75),
                                          reason: "import")])
    }

    static var cut: CoachPlan.Phase {
        CoachPlan.Phase(id: "2", name: "Cut", goal: .lose, start: weightDay("2030-06-03"), end: weightDay("2030-08-25"),
                        rateMin: 0.3, rateMax: 0.5, reviewMin: 83, reviewMax: 84, targetWeight: 83, startedAt: startedAt, status: .active)
    }

    static func signal(_ readings: [WeightSignal.Reading], cutoff: Int = 660, dayStartHour: Int = 0) -> WeightSignal {
        WeightSignal(readings, cutoffMinutes: cutoff, dayStartHour: dayStartHour, calendar: weightUTC)
    }

    // MARK: Morning weight

    @Test func morningWeightIsTheEarliestBeforeTheCutoff() {
        let signal = Self.signal([
            weightReading("2030-01-07", 80.2, hour: 7, minute: 10),
            weightReading("2030-01-07", 80.4, hour: 6, minute: 50, source: .health),
            weightReading("2030-01-07", 81.3, hour: 19),
            weightReading("2030-01-08", 81.0, hour: 12),
            weightReading("2030-01-08", 80.9, hour: 18),
        ])
        let morning = signal.morning(on: weightDay("2030-01-07"))
        #expect(morning?.kilograms == 80.4)
        #expect(morning?.source == .health)
        // Only afternoon weigh-ins: no morning weight; they are faint dots, left out of everything.
        #expect(signal.morning(on: weightDay("2030-01-08")) == nil)
        #expect(signal.days == [weightDay("2030-01-07")])
        #expect(signal.others.map(\.kilograms) == [80.2, 81.3, 81.0, 80.9])
        #expect(signal.morningCount(from: weightDay("2030-01-01"), through: weightDay("2030-01-08")) == 1)
        // An earlier cutoff (10:00) leaves 10:30 out.
        let early = Self.signal([weightReading("2030-01-09", 80.0, hour: 10, minute: 30)], cutoff: 600)
        #expect(early.days.isEmpty)
    }

    @Test func dayStartHourAndBackFilledWeighIns() {
        // 01:30 on the 8th still belongs to the 7th (day start 03:00): late at night, not a morning.
        let night = WeightSignal.Reading(time: weightTime(weightDay("2030-01-08"), 1, 30), kilograms: 80.5, source: .nina,
                                         dayStartHour: 3, calendar: weightUTC)
        #expect(night.day == weightDay("2030-01-07"))
        #expect(night.minutes(dayStartHour: 3, calendar: weightUTC) == 25 * 60 + 30)
        #expect(!night.isMorning(dayStartHour: 3, calendar: weightUTC))
        // A morning weight typed in a day later (filed under the 7th, saved on the 8th at 07:30) uses its clock time.
        let typedLater = WeightSignal.Reading(day: weightDay("2030-01-07"), time: weightTime(weightDay("2030-01-08"), 7, 30), kilograms: 80.1)
        #expect(typedLater.isMorning(dayStartHour: 3, calendar: weightUTC))
        let signal = Self.signal([night, typedLater], dayStartHour: 3)
        #expect(signal.morning(on: weightDay("2030-01-07"))?.kilograms == 80.1)
        #expect(signal.others == [night])
    }

    @Test func healthCopiesOfTypedWeightsCountOnce() {
        let signal = Self.signal([
            weightReading("2030-01-07", 80.2, hour: 7),
            weightReading("2030-01-07", 80.2, hour: 7, minute: 5, source: .health), // Nina's own copy in Health
            weightReading("2030-01-08", 80.3, hour: 7),
            weightReading("2030-01-08", 79.9, hour: 6, minute: 55, source: .health), // a different, earlier reading
            weightReading("2030-01-09", 0, hour: 7, source: .health),
            weightReading("2030-01-09", 400, hour: 8),
            weightReading("2030-01-09", .nan, hour: 9),
        ])
        #expect(signal.morning(on: weightDay("2030-01-07"))?.source == .nina)
        #expect(signal.morning(on: weightDay("2030-01-08"))?.kilograms == 79.9)
        #expect(signal.others.map(\.kilograms) == [80.3])
        #expect(signal.morning(on: weightDay("2030-01-09")) == nil)
        #expect(signal.usesHealth(from: weightDay("2030-01-08"), through: weightDay("2030-01-08")))
        #expect(!signal.usesHealth(from: weightDay("2030-01-07"), through: weightDay("2030-01-07")))
    }

    // MARK: Tags

    @Test func tagsAreReadFromTheNote() {
        typealias Tag = WeightSignal.Tag
        #expect(Tag.parse("#salty") == [.salty])
        #expect(Tag.parse("Pizza night #Late-Meal and #late_meal again") == [.lateMeal])
        #expect(Tag.parse("#salzig #krank #reise") == [.salty, .ill, .travel])
        #expect(Tag.parse("#salty#travel") == [.salty, .travel])
        #expect(Tag.parse("x#salty, #newscale, # alone").isEmpty)
        #expect(Tag.parse("Wedding (#alcohol), #poor-sleep.") == [.alcohol, .poorSleep])
        #expect(Tag.parse("import").isEmpty)
        #expect(Tag.lateMeal.token == "#late_meal")
        #expect(Tag(token: Tag.poorSleep.token) == .poorSleep)
        #expect(Tag.allCases.count == 8)
        #expect(!Tag.options(for: .male).contains(.period))
        #expect(Tag.options(for: .female).contains(.period))

        #expect(Tag.note("Hotel scale #salty #newscale", setting: [.travel, .alcohol, .travel]) == "Hotel scale #newscale #travel #alcohol")
        #expect(Tag.note("#salty", setting: []) == "")
        #expect(Tag.note("", setting: [.refeed]) == "#refeed")

        #expect(weightReading("2030-01-07", 80, note: "#salty").isTagged)
        #expect(!weightReading("2030-01-07", 80, note: "after #newscale").isTagged)
    }

    // MARK: Average, change, trend

    @Test func sevenDayAverageNeedsFourMornings() {
        let three = Self.signal(weightSeries(from: "2030-01-01", days: 7, skip: [0, 2, 4, 6]) { 80 + Double($0) * 0.1 })
        let average = three.average(on: weightDay("2030-01-07"))
        #expect(average.count == 3)
        #expect(!average.isValid)
        #expect(average.value == nil)
        #expect(weightClose(average.mean, 80.3))
        #expect(average.prompt == "Weigh in 1 more morning to see your average")
        #expect(Self.signal([]).average(on: weightDay("2030-01-07")).prompt == "Weigh in 4 more mornings to see your average")

        let four = Self.signal(weightSeries(from: "2030-01-01", days: 7, skip: [1, 3, 5]) { [80.0, 0, 80.4, 0, 80.2, 0, 80.6][$0] })
        let valid = four.average(on: weightDay("2030-01-07"))
        #expect(valid.isValid)
        #expect(weightClose(valid.value, 80.3))
        #expect(valid.prompt == nil)
        // The window is the 7 days ending on the day: the 1st drops out on the 8th.
        #expect(four.average(on: weightDay("2030-01-08")).count == 3)
    }

    @Test func weeklyChangeAndCrossCheck() {
        // +0.03 kg a day = +0.21 kg/week.
        let signal = Self.signal(weightSeries(from: "2030-01-01", days: 21) { 80 + Double($0) * 0.03 })
        let change = signal.weeklyChange(on: weightDay("2030-01-21"))
        #expect(weightClose(change?.kilograms, 0.21))
        #expect(weightClose(change?.current, 80 + 17 * 0.03))
        #expect(weightClose(change?.percent, 0.21 / (80 + 17 * 0.03) * 100))
        #expect(weightClose(signal.crossCheckRate(on: weightDay("2030-01-21")), 0.21))
        // The previous week isn't valid yet.
        #expect(signal.weeklyChange(on: weightDay("2030-01-10")) == nil)
        #expect(signal.crossCheckRate(on: weightDay("2030-01-17")) == nil)
    }

    @Test func trendAndBodyWeight() {
        let two = Self.signal([weightReading("2030-01-01", 80.0), weightReading("2030-01-03", 81.0),
                               weightReading("2030-01-04", 82.0, hour: 18)])
        #expect(two.trend(on: weightDay("2029-12-31")) == nil)
        #expect(two.trend(on: weightDay("2030-01-02")) == 80.0)
        #expect(weightClose(two.trend(on: weightDay("2030-01-09")), 80.1))
        let estimate = two.bodyWeight(on: weightDay("2030-01-05"))
        #expect(estimate?.basis == .trend)
        #expect(weightClose(estimate?.kilograms, 80.1))
        #expect(estimate?.isEstimate == true)

        let evening = Self.signal([weightReading("2030-01-04", 82.0, hour: 18)])
        #expect(evening.bodyWeight(on: weightDay("2030-01-05")) == WeightSignal.Estimate(kilograms: 82.0, basis: .latest))
        #expect(evening.bodyWeight(on: weightDay("2030-01-03")) == nil)

        let week = Self.signal(weightSeries(from: "2030-01-01", days: 7) { _ in 80.5 })
        #expect(week.bodyWeight(on: weightDay("2030-01-07")) == WeightSignal.Estimate(kilograms: 80.5, basis: .average))
        #expect(week.averages(from: weightDay("2030-01-03"), through: weightDay("2030-01-05")).map(\.day)
                == [weightDay("2030-01-04"), weightDay("2030-01-05")])
    }

    // MARK: Decision rate

    @Test func decisionRateIsTheLeastSquaresSlope() {
        // 21 days at +0.03 kg/day, one salty spike: tagged readings are left out.
        var readings = weightSeries(from: "2030-01-01", days: 21) { 80 + Double($0) * 0.03 }
        readings[18].kilograms += 1.5
        readings[18].note = "Ramen #salty"
        let window = WeightSignal.Window(start: weightDay("2030-01-01"), end: weightDay("2030-01-21"))
        let rate = Self.signal(readings).rate(in: window)
        #expect(rate.isValid)
        #expect(weightClose(rate.value, 0.21))
        #expect(rate.weighIns == 20)
        #expect(rate.tagged == 1)
        #expect(rate.spanDays == 21)
        #expect(!rate.usesHealth)
        #expect(window.days(calendar: weightUTC) == 21)

        // Untagged, the spike pulls the slope.
        readings[18].note = ""
        #expect(!weightClose(Self.signal(readings).rate(in: window).value, 0.21, 1e-6))
    }

    @Test func decisionRateNeedsFourteenDaysAndTenWeighIns() {
        let readings = weightSeries(from: "2030-01-01", days: 21) { 80 + Double($0) * 0.03 }
        let signal = Self.signal(readings)
        // 13 days: not enough.
        let short = signal.rate(in: .init(start: weightDay("2030-01-09"), end: weightDay("2030-01-21")))
        #expect(short.spanDays == 13)
        #expect(!short.isValid)
        #expect(short.value == nil)
        #expect(weightClose(short.kilogramsPerWeek, 0.21))
        // 14 days: enough.
        #expect(signal.rate(in: .init(start: weightDay("2030-01-08"), end: weightDay("2030-01-21"))).isValid)
        // Only 9 weigh-ins over 21 days: not enough.
        let sparse = Self.signal(weightSeries(from: "2030-01-01", days: 21, skip: Set([1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 16, 18])) {
            80 + Double($0) * 0.03
        })
        let thin = sparse.rate(in: .init(start: weightDay("2030-01-01"), end: weightDay("2030-01-21")))
        #expect(thin.weighIns == 9)
        #expect(!thin.isValid)
        // Nothing in the window.
        #expect(signal.rate(in: .init(start: weightDay("2030-02-01"), end: weightDay("2030-02-10"))).kilogramsPerWeek == nil)
        // With daily weigh-ins from a Monday start, the first valid day is the Sunday two weeks on.
        #expect(WeightSignal.firstRateDay(from: weightDay("2030-01-07"), calendar: weightUTC) == weightDay("2030-01-20"))
        #expect(weightClose(WeightSignal.percent(0.2, of: 80), 0.25))
        #expect(WeightSignal.percent(0.2, of: 0) == nil)
        #expect(WeightSignal.slope([(x: 1, y: 2), (x: 1, y: 3)]) == nil)
        #expect(weightClose(WeightSignal.slope([(x: 0, y: 1), (x: 2, y: 2), (x: 4, y: 3)]), 0.5))
    }

    @Test func rateWindowFollowsThePlan() {
        let day = weightDay("2030-02-28")
        // Plain: the last 21 days.
        #expect(WeightSignal.rateWindow(on: day, calendar: weightUTC) == .init(start: weightDay("2030-02-08"), end: day))
        #expect(WeightSignal.rateWindow(on: day, maxDays: 21, notBefore: [nil, weightDay("2030-02-12"), weightDay("2030-01-01")],
                                        calendar: weightUTC).start == weightDay("2030-02-12"))

        var phase = Self.gain
        phase.revisions.append(.init(from: weightDay("2030-02-10"), baseline: DailyTargets(energy: 2700, protein: 150, carbs: 355, fat: 75),
                                     reason: "adjust:+100"))
        phase.revisions.append(.init(from: weightDay("2030-02-20"), baseline: DailyTargets(energy: 2700, protein: 160, carbs: 345, fat: 75),
                                     reason: "edit"))
        phase.revisions.append(.init(from: weightDay("2030-03-01"), reason: "adjust:-100"))
        #expect(WeightSignal.lastAdjustment(in: phase, on: day) == weightDay("2030-02-10"))
        var plan = CoachPlan(phases: [phase])
        #expect(WeightSignal.rateWindow(on: day, plan: plan, calendar: weightUTC).start == weightDay("2030-02-10"))
        // The day after a pause that ended.
        plan.pauses = [.init(start: weightDay("2030-02-11"), end: weightDay("2030-02-15"), reason: .sick),
                       .init(start: weightDay("2030-03-10"), end: nil, reason: .holiday)]
        #expect(WeightSignal.rateWindow(on: day, plan: plan, calendar: weightUTC).start == weightDay("2030-02-16"))
        // Phase start, early in the phase.
        let early = CoachPlan(phases: [Self.gain])
        #expect(WeightSignal.rateWindow(on: weightDay("2030-01-20"), plan: early, calendar: weightUTC)
                == .init(start: weightDay("2030-01-07"), end: weightDay("2030-01-20")))
        // The plan's window length.
        var long = early
        long.adjust.windowMaxDays = 28
        #expect(WeightSignal.rateWindow(on: day, plan: long, calendar: weightUTC).start == weightDay("2030-02-01"))
    }

    @Test func rateOnADayLeavesPausedDaysOut() {
        let readings = weightSeries(from: "2030-01-07", days: 30) { offset in
            // A holiday from day 20 to 24 adds 2 kg that the rate must not see.
            (20...24).contains(offset) ? 82 + Double(offset) * 0.03 : 80 + Double(offset) * 0.03
        }
        let signal = Self.signal(readings)
        var plan = CoachPlan(phases: [Self.gain])
        plan.pauses = [.init(start: weightDay("2030-01-27"), end: nil, reason: .holiday)]
        // The pause hasn't ended: its days are left out, the window keeps its 21 days.
        let rate = signal.rate(on: weightDay("2030-01-31"), plan: plan)
        #expect(rate.window.start == weightDay("2030-01-11"))
        #expect(rate.weighIns == 16)
        #expect(weightClose(rate.value, 0.21))
        // Early in the phase (the 1st check-in after 12 days): gathering data.
        let first = signal.rate(on: weightDay("2030-01-18"), plan: CoachPlan(phases: [Self.gain]))
        #expect(!first.isValid)
        #expect(WeightSignal.status(rate: first.value, phase: Self.gain) == .gathering)
    }

    // MARK: Status

    @Test func statusComparesWithTheRangeAndTolerance() {
        let gain = Self.gain // +0.15 … +0.25
        #expect(WeightSignal.status(rate: 0.20, phase: gain) == .inRange)
        #expect(WeightSignal.status(rate: 0.12, phase: gain) == .inRange)
        #expect(WeightSignal.status(rate: 0.28, phase: gain) == .inRange)
        #expect(WeightSignal.status(rate: 0.11, phase: gain) == .slower)
        #expect(WeightSignal.status(rate: -0.1, phase: gain) == .slower)
        #expect(WeightSignal.status(rate: 0.29, phase: gain) == .faster)
        #expect(WeightSignal.status(rate: nil, phase: gain) == .gathering)
        #expect(WeightSignal.status(rate: 0.13, phase: gain, tolerance: 0) == .slower)
        #expect(weightClose(WeightSignal.deviation(0.33, phase: gain), 0.05))
        #expect(weightClose(WeightSignal.deviation(0.02, phase: gain), -0.1))
        #expect(WeightSignal.deviation(0.2, phase: gain) == 0)

        let cut = Self.cut // −0.5 … −0.3
        #expect(WeightSignal.range(for: cut) == -0.5...(-0.3))
        #expect(WeightSignal.status(rate: -0.4, phase: cut) == .inRange)
        #expect(WeightSignal.status(rate: -0.2, phase: cut) == .slower)
        #expect(WeightSignal.status(rate: 0.1, phase: cut) == .slower)
        #expect(WeightSignal.status(rate: -0.6, phase: cut) == .faster)

        // Maintain without a rate: ±0.1 plus the tolerance; upward counts as faster.
        let maintain = CoachPlan.Phase(id: "3", goal: .maintain, start: weightDay("2030-09-01"), startedAt: Self.startedAt, status: .active)
        #expect(WeightSignal.range(for: maintain) == -0.1...0.1)
        #expect(WeightSignal.status(rate: 0.12, phase: maintain) == .inRange)
        #expect(WeightSignal.status(rate: 0.2, phase: maintain) == .faster)
        // Maintaining, moving either way is faster than planned (the check-in's words too).
        #expect(WeightSignal.status(rate: -0.2, phase: maintain) == .faster)

        // A gain phase without a rate has nothing to compare with.
        let open = CoachPlan.Phase(id: "4", goal: .gain, start: weightDay("2030-09-01"))
        #expect(WeightSignal.status(rate: 0.2, phase: open) == nil)

        #expect(WeightSignal.Status.inRange.title == "In range")
        #expect(WeightSignal.Status.slower.title == "Slower than planned")
        #expect(WeightSignal.Status.faster.title == "Faster than planned")
        #expect(WeightSignal.Status.gathering.title == "Gathering data")
        // "Off track" only after two check-ins in a row outside on the same side, as the check-in
        // counts them: slower then faster is not off track.
        #expect(WeightSignal.Status.isOffTrack([.inRange, .faster, .faster]))
        #expect(WeightSignal.Status.isOffTrack([.slower, .slower]))
        #expect(!WeightSignal.Status.isOffTrack([.inRange, .slower, .faster]))
        #expect(!WeightSignal.Status.isOffTrack([.slower, .inRange]))
        #expect(!WeightSignal.Status.isOffTrack([.slower]))
        #expect(!WeightSignal.Status.isOffTrack([.gathering, .slower]))
        #expect(!WeightSignal.Status.isOffTrack([.gathering, .gathering]))
        // From the check-ins' sides (a maintain phase reads "faster" on both sides).
        #expect(WeightSignal.Status.isOffTrack(deviations: [nil, .above, .above]))
        #expect(!WeightSignal.Status.isOffTrack(deviations: [.below, .above]))
        #expect(!WeightSignal.Status.isOffTrack(deviations: [.above, nil]))
        #expect(!WeightSignal.Status.isOffTrack(deviations: [.above]))
    }

    // MARK: Unusual readings and sanity

    @Test func unusualReadingsAndTypos() {
        #expect(WeightSignal.isUnusual(81.3, trend: 80))
        #expect(!WeightSignal.isUnusual(81.2, trend: 80))
        #expect(WeightSignal.isUnusual(78.7, trend: 80))
        #expect(!WeightSignal.isUnusual(81.3, trend: nil))

        var readings = weightSeries(from: "2030-01-01", days: 10) { _ in 80 }
        readings[6].kilograms = 81.5
        let signal = Self.signal(readings)
        #expect(signal.unusualDays(from: weightDay("2030-01-01"), through: weightDay("2030-01-10")) == [weightDay("2030-01-07")])
        #expect(signal.isUnusual(78.6, on: weightDay("2030-01-11")))

        #expect(WeightSignal.sanity(24.9, reference: nil) == .outOfRange)
        #expect(WeightSignal.sanity(300.1, reference: nil) == .outOfRange)
        #expect(WeightSignal.sanity(.nan, reference: nil) == .outOfRange)
        #expect(WeightSignal.sanity(25, reference: nil) == .ok)
        #expect(WeightSignal.sanity(80, reference: 83.5) == .typo(reference: 83.5))
        #expect(WeightSignal.sanity(80, reference: 83) == .ok)
        let week = Self.signal(weightSeries(from: "2030-01-01", days: 7) { _ in 80 })
        #expect(week.sanity(84.1, on: weightDay("2030-01-08")) == .typo(reference: 80))
        #expect(week.sanity(80.4, on: weightDay("2030-01-08")) == .ok)
    }

    // MARK: Phase

    @Test func corridorFromTheStartWeight() {
        let gain = Self.gain
        let week16 = weightDay("2030-01-07").adding(days: 112, calendar: weightUTC)
        let corridor = WeightSignal.corridor(startWeight: 80, phase: gain, on: week16, calendar: weightUTC)
        #expect(weightClose(corridor?.lowerBound, 82.4))
        #expect(weightClose(corridor?.upperBound, 84))
        #expect(WeightSignal.corridor(startWeight: 80, phase: gain, on: weightDay("2030-01-07"), calendar: weightUTC) == 80...80)
        #expect(WeightSignal.corridor(startWeight: 80, phase: gain, on: weightDay("2030-01-06"), calendar: weightUTC) == nil)
        #expect(WeightSignal.corridor(startWeight: 0, phase: gain, on: week16, calendar: weightUTC) == nil)

        let cut = WeightSignal.corridor(startWeight: 95, phase: Self.cut, on: weightDay("2030-08-12"), calendar: weightUTC)
        #expect(weightClose(cut?.lowerBound, 90))
        #expect(weightClose(cut?.upperBound, 92))
    }

    @Test func phaseStartWeightRule() {
        var phase = Self.gain
        let full = Self.signal(weightSeries(from: "2029-12-31", days: 14) { 80 + Double($0) * 0.02 })
        // The 7-day average on the start day (1 … 7 Jan).
        #expect(weightClose(full.startWeight(of: phase), 80 + 4 * 0.02))
        // A stored start weight wins.
        phase.startWeight = 79.5
        #expect(full.startWeight(of: phase) == 79.5)
        phase.startWeight = 0
        // Only from the start on: the first valid average in the first 7 days (the 10th, with 4 mornings).
        let fresh = Self.signal(weightSeries(from: "2030-01-07", days: 10) { 80 + Double($0) * 0.02 })
        #expect(weightClose(fresh.startWeight(of: phase), 80.03))
        // No valid average in the first week: the imported or typed weight.
        let sparse = Self.signal([weightReading("2030-01-07", 80.2), weightReading("2030-01-12", 80.4)])
        #expect(sparse.startWeight(of: phase, fallback: 80.6) == 80.6)
        #expect(sparse.startWeight(of: phase) == nil)
    }

    @Test func projectedEndWeight() {
        #expect(weightClose(WeightSignal.projectedWeight(average: 80, rate: 0.2, from: weightDay("2030-03-04"), to: weightDay("2030-05-13"),
                                                         calendar: weightUTC), 82))
        let signal = Self.signal(weightSeries(from: "2030-03-01", days: 7) { _ in 80 })
        var phase = Self.gain
        phase.end = weightDay("2030-05-16") // 10 weeks on
        #expect(weightClose(signal.projectedEndWeight(of: phase, on: weightDay("2030-03-07"), rate: 0.2), 82))
        #expect(signal.projectedEndWeight(of: phase, on: weightDay("2030-03-07"), rate: nil) == nil)
        phase.end = nil
        #expect(signal.projectedEndWeight(of: phase, on: weightDay("2030-03-07"), rate: 0.2) == nil)
    }

    // MARK: Review checkpoint

    @Test func checkpointProjection() {
        let gain = Self.gain // review 82–83
        #expect(WeightSignal.checkpoint(of: gain) == 82)
        #expect(weightClose(WeightSignal.weeksToCheckpoint(average: 80, rate: 0.25, phase: gain), 8))
        #expect(WeightSignal.weeksToCheckpoint(average: 82.1, rate: 0.25, phase: gain) == 0)
        #expect(WeightSignal.weeksToCheckpoint(average: 80, rate: -0.1, phase: gain) == nil)
        #expect(WeightSignal.weeksToCheckpoint(average: 80, rate: 0, phase: gain) == nil)
        let start = weightDay("2030-01-07")
        #expect(WeightSignal.checkpointDate(average: 80, rate: 0.25, on: start, phase: gain, calendar: weightUTC) == weightDay("2030-03-04"))
        // Between the fast end (+0.25: 8 weeks) and the slow end (+0.15: 13.3 weeks).
        #expect(WeightSignal.checkpointDates(average: 80, on: start, phase: gain, calendar: weightUTC)
                == weightDay("2030-03-04")...weightDay("2030-04-10"))

        // Losing: the lower bound, reached from above.
        let cut = Self.cut // review 83–84
        #expect(WeightSignal.checkpoint(of: cut) == 83)
        #expect(weightClose(WeightSignal.weeksToCheckpoint(average: 87, rate: -0.5, phase: cut), 8))
        #expect(WeightSignal.weeksToCheckpoint(average: 82.9, rate: -0.5, phase: cut) == 0)
        #expect(WeightSignal.weeksToCheckpoint(average: 83.5, rate: -0.5, phase: cut).map { $0 > 0 } == true)
        #expect(WeightSignal.weeksToCheckpoint(average: 87, rate: 0.1, phase: cut) == nil)
        #expect(WeightSignal.checkpointDates(average: 87, on: weightDay("2030-06-03"), phase: cut, calendar: weightUTC)
                == weightDay("2030-07-29")...weightDay("2030-09-04"))

        var noReview = gain
        noReview.reviewMin = 0
        noReview.reviewMax = 0
        #expect(WeightSignal.checkpoint(of: noReview) == nil)
        noReview.reviewMax = 83
        #expect(WeightSignal.checkpoint(of: noReview) == 83)
        let maintain = CoachPlan.Phase(id: "3", goal: .maintain, reviewMin: 80, reviewMax: 81)
        #expect(WeightSignal.checkpoint(of: maintain) == nil)
    }

    @Test func checkpointCrossingUsesTheSevenDayAverage() {
        let gain = Self.gain
        // Rises 0.1 kg a day from 81.0 on the 1st of March, with one 83.5 spike on the 3rd.
        var readings = weightSeries(from: "2030-03-01", days: 20) { 81 + Double($0) * 0.1 }
        readings[2].kilograms = 83.5
        let signal = Self.signal(readings)
        // A single weigh-in never fires it; the 7-day average first reaches 82.0 on the 14th.
        let crossing = signal.checkpointCrossing(of: gain, through: weightDay("2030-03-20"))
        #expect(crossing == weightDay("2030-03-14"))
        #expect(signal.average(on: weightDay("2030-03-09")).value.map { $0 > 81.8 && $0 < 82 } == true) // the spike lifts it
        #expect(signal.average(on: weightDay("2030-03-13")).value.map { $0 < 82 } == true)
        #expect(signal.checkpointCrossing(of: gain, through: weightDay("2030-03-13")) == nil)

        // Losing, from averages handed in (any order).
        let points = [WeightSignal.Point(day: weightDay("2030-07-20"), kilograms: 82.9),
                      WeightSignal.Point(day: weightDay("2030-07-10"), kilograms: 83.4),
                      WeightSignal.Point(day: weightDay("2030-07-15"), kilograms: 83.0),
                      WeightSignal.Point(day: weightDay("2030-05-01"), kilograms: 80.0)] // before the phase
        #expect(WeightSignal.checkpointCrossing(points, phase: Self.cut) == weightDay("2030-07-15"))
    }

    // MARK: Noise band

    @Test func noiseBandIsTheSpreadAroundTheCentredAverage() {
        let flat = Self.signal(weightSeries(from: "2030-01-01", days: 28) { _ in 80 })
        #expect(weightClose(flat.noiseBand(on: weightDay("2030-01-28")), 0))
        // ±0.6 kg day to day.
        let swinging = Self.signal(weightSeries(from: "2030-01-01", days: 28) { $0.isMultiple(of: 2) ? 80.6 : 79.4 })
        let band = swinging.noiseBand(on: weightDay("2030-01-28"))
        #expect(band.map { $0 > 0.6 && $0 < 0.8 } == true)
        // Too few mornings.
        let few = Self.signal(weightSeries(from: "2030-01-19", days: 9) { _ in 80 })
        #expect(few.noiseBand(on: weightDay("2030-01-28")) == nil)
    }

    // MARK: Summary

    @Test func summaryForTheWeightCard() {
        let plan = CoachPlan(phases: [Self.gain])
        // Three weeks from the phase start at +0.03 kg/day (+0.21 kg/week), the last morning from Health.
        var readings = weightSeries(from: "2030-01-07", days: 21) { 80 + Double($0) * 0.03 }
        readings[20].source = .health
        let day = weightDay("2030-01-27")
        let summary = Self.signal(readings).summary(on: day, plan: plan, fallbackWeight: 79)
        #expect(summary.phaseID == "1")
        #expect(summary.average.isValid)
        #expect(weightClose(summary.average.value, 80 + 17 * 0.03))
        #expect(summary.bodyWeight?.basis == .average)
        #expect(weightClose(summary.rate.value, 0.21))
        #expect(summary.rate.window.start == weightDay("2030-01-07"))
        #expect(summary.status == .inRange)
        #expect(weightClose(summary.startWeight, 80.045)) // the first valid 7-day average, on the 10th
        #expect(weightClose(summary.sinceStart?.kilograms, 80.51 - 80.045))
        #expect(weightClose(summary.weeklyChange?.kilograms, 0.21))
        #expect(weightClose(summary.crossCheck, 0.21))
        #expect(summary.corridor.map { $0.contains(80.51) } == true)
        #expect(weightClose(summary.projectedEnd, 80.51 + 0.21 * Double(day.days(to: weightDay("2030-05-26"), calendar: weightUTC)) / 7))
        #expect(summary.checkpoint == 82)
        #expect(weightClose(summary.weeksToCheckpoint, (82 - 80.51) / 0.21))
        #expect(summary.checkpointReached == nil)
        #expect(summary.usesHealth)
        #expect(summary.rate.usesHealth)

        // Without a plan: the numbers still work, no status.
        let plain = Self.signal(readings).summary(on: day, plan: CoachPlan())
        #expect(plain.phaseID == nil)
        #expect(plain.status == nil)
        #expect(plain.corridor == nil)
        #expect(weightClose(plain.rate.value, 0.21))
    }
}
