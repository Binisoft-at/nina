import Foundation
import Testing
@testable import NinaCore

// Made-up diary days, targets and weigh-ins in 2030.

private var fixUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func fixDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func fixTotals(_ day: DayKey, _ kcal: Double?, protein: Double = 120, carbs: Double = 250, fat: Double = 70) -> DayTotals {
    guard let kcal else { return DayTotals(day: day, entries: []) }
    let facts = EntryFacts(day: day, meal: "lunch",
                           nutrients: NutrientValues([.energy: kcal, .protein: protein, .carbs: carbs, .fat: fat]),
                           name: "Made-up meal", time: day.date(minutes: 12 * 60, calendar: fixUTC))
    return DayTotals(day: day, entries: [facts], water: 2000)
}

private func fixReading(_ raw: String, _ kilograms: Double, minutes: Int = 420,
                        source: WeightSignal.Reading.Source = .nina) -> WeightSignal.Reading {
    let day = fixDay(raw)
    return WeightSignal.Reading(day: day, time: day.date(minutes: minutes, calendar: fixUTC), kilograms: kilograms, source: source)
}

@Suite("Insights: finished days only")
struct InsightsFinishedDaysTests {
    let today = fixDay("2030-03-10")

    /// A week: six full days at 2,300 kcal, one marked incomplete (900 kcal) and today half eaten (1,000).
    private func week() -> [DayTotals] {
        (0..<7).map { offset -> DayTotals in
            let day = today.adding(days: offset - 6, calendar: fixUTC)
            switch offset {
            case 6: return fixTotals(day, 1000)
            case 2: return fixTotals(day, 900)
            default: return fixTotals(day, 2300)
            }
        }
    }

    @Test func todayAndIncompleteDaysDontCount() {
        let totals = week()
        let incomplete: Set<DayKey> = [today.adding(days: -4, calendar: fixUTC)]
        let excluded = Insights.unfinishedDays(totals, today: today, incomplete: incomplete)
        #expect(excluded == [today, today.adding(days: -4, calendar: fixUTC)])

        let target = DailyTargets(energy: 2300, protein: 130, carbs: 260, fat: 75)
        let all = Insights.stats(totals: totals, targets: { _ in target }, calendar: fixUTC)
        let finished = Insights.stats(totals: totals, targets: { _ in target }, excluding: excluded, calendar: fixUTC)
        // Every logged day counted: today and the incomplete day drag the average down.
        #expect(all.loggedDays == 7)
        #expect(all.averageBalance < -300)
        #expect(all.underDays == 2)
        // Finished days only: on target.
        #expect(finished.loggedDays == 5)
        #expect(finished.days == 7)
        #expect(abs(finished.average.energy - 2300) < 0.001)
        #expect(abs(finished.averageBalance) < 0.001)
        #expect(finished.underDays == 0)
        #expect(finished.onTrackShare == 1)
    }

    @Test func nothingFinishedYet() {
        let totals = [fixTotals(today, 800)]
        let stats = Insights.stats(totals: totals, targets: { _ in .standard },
                                   excluding: Insights.unfinishedDays(totals, today: today), calendar: fixUTC)
        #expect(stats.loggedDays == 0)
        #expect(stats.averageTarget == 0)
        // The targets of the period's last day stand in.
        #expect(stats.averageTargets == .standard)
    }

    @Test func averageTargetsFollowEachDaysType() {
        // Gym days (even offsets) with more carbs, rest days with fewer.
        let gym = DailyTargets(energy: 2600, protein: 140, carbs: 320, fat: 75, fiber: 35)
        let rest = DailyTargets(energy: 2200, protein: 140, carbs: 220, fat: 75, fiber: 30)
        let start = fixDay("2030-03-01")
        let days = (0..<4).map { start.adding(days: $0, calendar: fixUTC) }
        let totals = days.map { fixTotals($0, 2400) } + [fixTotals(start.adding(days: 4, calendar: fixUTC), nil)]
        let targets: (DayKey) -> DailyTargets = { day in start.days(to: day, calendar: fixUTC) % 2 == 0 ? gym : rest }
        let stats = Insights.stats(totals: totals, targets: targets, calendar: fixUTC)
        #expect(stats.averageTargets.energy == 2400)
        #expect(stats.averageTargets.carbs == 270)
        #expect(stats.averageTargets.carbs > rest.carbs && stats.averageTargets.carbs < gym.carbs)
        #expect(stats.averageTargets.protein == 140)
        #expect(stats.averageTargets.fiber == 32.5)
        #expect(stats.averageTargets.energy == stats.averageTarget)
        // Only logged days count: one gym and one rest day logged → still the mean of both.
        let two = [fixTotals(days[0], 2000), fixTotals(days[1], 2000), fixTotals(days[2], nil)]
        #expect(Insights.stats(totals: two, targets: targets, calendar: fixUTC).averageTargets.carbs == 270)
    }

    @Test func maintenanceLeavesOutPartialAndIncompleteDays() throws {
        // Stable weight, 27 finished days at 2,500 kcal, today with 600 kcal so far and two days
        // marked incomplete with 1,000 kcal.
        var totals: [DayTotals] = []
        var weights: [DayKey: Double] = [:]
        let incomplete: Set<DayKey> = [today.adding(days: -5, calendar: fixUTC), today.adding(days: -12, calendar: fixUTC)]
        for offset in 0..<42 {
            let day = today.adding(days: -offset, calendar: fixUTC)
            weights[day] = 76
            guard offset < 28 else { continue }
            let kcal: Double = offset == 0 ? 600 : (incomplete.contains(day) ? 1000 : 2500)
            totals.append(fixTotals(day, kcal))
        }
        let biased = try #require(Insights.maintenance(totals: totals, weights: weights, today: today, calendar: fixUTC))
        #expect(biased.kilocalories < 2400)
        let yesterday = today.adding(days: -1, calendar: fixUTC)
        let fair = try #require(Insights.maintenance(totals: totals, weights: weights, today: yesterday, excluding: incomplete,
                                                     calendar: fixUTC))
        #expect(fair.kilocalories == 2500)
        #expect(fair.averageIntake == 2500)
        #expect(fair.loggedDays == 25)
    }
}

@Suite("Nutrient text fast path")
struct NutrientTextTests {
    private func agree(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let slow = NutrientValues(trimming: text)
        #expect(NutrientValues(encoded: text) == slow, "\(text)", sourceLocation: sourceLocation)
        #expect(NutrientValues.energy(encoded: text) == slow.energy, "\(text)", sourceLocation: sourceLocation)
    }

    @Test func fastEqualsSlowOnTheCatalog() {
        let foods = FoodCatalog.bundled.foods
        #expect(foods.count > 1000)
        var checked = 0
        for food in foods {
            let text = food.nutrients.encoded
            #expect(NutrientText.fastValues(text) != nil, "\(food.name)")
            agree(text)
            // Diary entries carry the values scaled to a portion: longer decimals.
            for factor in [0.37, 1.18, 2.5] {
                agree(food.nutrients.scaled(by: factor).encoded)
            }
            checked += 1
        }
        #expect(checked == foods.count)
    }

    @Test func fastEqualsSlowOnOddText() {
        let odd = [
            "", ";", ";;", "energy=", "=5", "energy==5", "energy=5=6", " energy = 52 ", "energy = 52;protein=3",
            "energy=52;energy=60", "energy=60;energy=x", "energy=5abc", "energy=inf", "energy=inf;energy=5",
            "energy=5;energy=inf", "energy=nan;protein=2", "foo=1;energy=3", "energy=1e3", "énergie=5;energy=2",
            "energy=52;\tprotein=1", "energy=-0", "protein=3;;carbs=4", "energy=1,5", "ENERGY=5", "energy=+12.5",
            "energy=.5", "energy=0x10", "energy=52\n", "protein=12;fat=3", "energy=52;protein=0.26;carbs=13.81",
            "vitaminB12=0.0002;saturatedFat=1.25;energy=99.5",
        ]
        for text in odd { agree(text) }
        #expect(NutrientValues(encoded: "energy=52;protein=0.26").energy == 52)
        #expect(NutrientValues.energy(encoded: "protein=3") == 0)
        #expect(NutrientValues.energy(encoded: " energy = 52 ") == 52)
        #expect(NutrientText.fastValues(" energy=1") == nil)
        #expect(NutrientText.fastValues("énergie=1") == nil)
    }

    @Test func roundTrip() {
        let values = NutrientValues([.energy: 412.25, .protein: 31.5, .carbs: 0.0004, .sodium: 1180, .vitaminD: 2.75])
        #expect(NutrientValues(encoded: values.encoded) == values)
        #expect(NutrientValues.energy(encoded: values.encoded) == 412.25)
    }
}

@Suite("Photo compare weight")
struct PhotoCompareWeightTests {
    @Test func firstPhotoDayUsesTheNearestAverage() {
        // Weigh-ins start on the first photo day: its own 7-day average isn't valid until the 4th morning.
        var readings: [WeightSignal.Reading] = []
        for (index, day) in DayKey.range(fixDay("2030-01-10"), through: fixDay("2030-01-20"), calendar: fixUTC).enumerated() {
            readings.append(fixReading(day.rawValue, 74.0 + Double(index) * 0.1))
        }
        for day in DayKey.range(fixDay("2030-02-20"), through: fixDay("2030-02-28"), calendar: fixUTC) {
            readings.append(fixReading(day.rawValue, 76.0))
        }
        let signal = WeightSignal(readings, calendar: fixUTC)
        let pair = ProgressPhotos.Pair(fixDay("2030-01-10"), fixDay("2030-02-28"))
        let comparison = PhotoComparison(pair: pair, signal: signal, tape: [], calendar: fixUTC)
        // 2030-01-13 is the first day with four mornings: 74.0, 74.1, 74.2, 74.3.
        #expect(comparison.before.weightDay == fixDay("2030-01-13"))
        #expect(abs((comparison.before.weight ?? 0) - 74.15) < 0.0001)
        #expect(comparison.after.weightDay == fixDay("2030-02-28"))
        #expect(comparison.after.weight == 76.0)
        #expect(abs((comparison.weightChange ?? 0) - 1.85) < 0.0001)

        // More than a week from any valid average: nothing.
        let far = PhotoComparison(pair: ProgressPhotos.Pair(fixDay("2030-01-01"), fixDay("2030-02-10")), signal: signal, tape: [],
                                  calendar: fixUTC)
        #expect(far.before.weight == nil && far.before.weightDay == nil)
        #expect(far.weightChange == nil)

        // Two photo days that both fall back to the same average are no change.
        let close = PhotoComparison(pair: ProgressPhotos.Pair(fixDay("2030-01-10"), fixDay("2030-01-11")), signal: signal, tape: [],
                                    calendar: fixUTC)
        #expect(close.before.weightDay == fixDay("2030-01-13") && close.after.weightDay == fixDay("2030-01-13"))
        #expect(close.weightChange == nil)
    }
}

@Suite("Phase sheet edits")
struct PhaseSheetEditsTests {
    private var opened: CoachPlan.Phase {
        CoachPlan.Phase(id: "2", name: "Lean gain", goal: .gain, start: fixDay("2030-05-06"), end: fixDay("2030-08-26"),
                        rateMin: 0.15, rateMax: 0.25, reviewMin: 76, reviewMax: 77, targetWeight: 77,
                        revisions: [CoachPlan.Revision(from: fixDay("2030-05-06"),
                                                       baseline: DailyTargets(energy: 2500, protein: 140, carbs: 300, fat: 75),
                                                       reason: "start")])
    }

    /// The phase as stored after the sheet opened: a check-in applied a new revision and it started.
    private var storedMeanwhile: CoachPlan.Phase {
        var phase = opened
        phase.status = .active
        phase.startedAt = Date(timeIntervalSince1970: 1_904_000_000)
        phase.revisions.append(CoachPlan.Revision(from: fixDay("2030-06-03"),
                                                  baseline: DailyTargets(energy: 2600, protein: 140, carbs: 325, fat: 75),
                                                  reason: "checkIn"))
        return phase
    }

    @Test func anUntouchedSheetChangesNothing() {
        let result = storedMeanwhile.applyingPhaseSheetEdits(original: opened, edited: opened)
        #expect(result == storedMeanwhile)
    }

    @Test func onlyTheEditedFieldsMove() {
        var edited = opened
        edited.name = "Slow gain"
        edited.note = "Made-up note"
        edited.rateMax = 0.3
        let result = storedMeanwhile.applyingPhaseSheetEdits(original: opened, edited: edited)
        #expect(result.name == "Slow gain" && result.note == "Made-up note")
        #expect(result.rateMin == 0.15 && result.rateMax == 0.3)
        // The check-in's revision and the start stay.
        #expect(result.revisions.count == 2)
        #expect(result.status == .active && result.startedAt != nil)
        #expect(result.end == opened.end && result.targetWeight == 77)
    }

    @Test func anotherDevicesEditOfAnUntouchedFieldStays() {
        var stored = storedMeanwhile
        stored.end = fixDay("2030-09-30")
        var edited = opened
        edited.targetWeight = 78
        let result = stored.applyingPhaseSheetEdits(original: opened, edited: edited)
        #expect(result.end == fixDay("2030-09-30"))
        #expect(result.targetWeight == 78)
    }

    @Test func theReviewMovesAsAPair() {
        var stored = storedMeanwhile
        stored.reviewMin = 75
        stored.reviewMax = 76
        var edited = opened
        edited.reviewMax = 78
        let result = stored.applyingPhaseSheetEdits(original: opened, edited: edited)
        #expect(result.reviewMin == 76 && result.reviewMax == 78)
    }
}

@Suite("Weigh-in rules")
struct WeighInRulesTests {
    @Test func afterTheCutoff() {
        let signal = WeightSignal([], cutoffMinutes: 660, calendar: fixUTC)
        let day = fixDay("2030-04-06")
        #expect(signal.standing(time: day.date(minutes: 11 * 60 + 30, calendar: fixUTC), day: day) == .afterCutoff)
        #expect(signal.standing(time: day.date(minutes: 10 * 60 + 59, calendar: fixUTC), day: day) == .counts)
        #expect(signal.countsAsMorning(time: day.date(minutes: 7 * 60, calendar: fixUTC), day: day))
        #expect(!signal.countsAsMorning(time: day.date(minutes: 19 * 60, calendar: fixUTC), day: day))
    }

    @Test func aSecondMorningWeighInIsExtra() {
        let first = fixReading("2030-04-06", 74.2, minutes: 7 * 60)
        let signal = WeightSignal([first], calendar: fixUTC)
        let day = fixDay("2030-04-06")
        #expect(signal.standing(time: day.date(minutes: 8 * 60, calendar: fixUTC), day: day) == .extra(morning: first))
        // Earlier than the one there: it takes its place.
        #expect(signal.standing(time: day.date(minutes: 6 * 60, calendar: fixUTC), day: day) == .counts)
        // Editing that weigh-in itself: it doesn't compete with itself.
        #expect(signal.standing(time: day.date(minutes: 8 * 60, calendar: fixUTC), day: day, excluding: first) == .counts)
        // Another day is free.
        let next = fixDay("2030-04-07")
        #expect(signal.countsAsMorning(time: next.date(minutes: 8 * 60, calendar: fixUTC), day: next))
    }

    @Test func editingTheMorningWeightLater() {
        // 07:00 is the morning weight, 08:00 is extra. Moving 07:00 to 09:00 makes 08:00 the morning one.
        let early = fixReading("2030-04-06", 74.2, minutes: 7 * 60)
        let second = fixReading("2030-04-06", 74.6, minutes: 8 * 60)
        let signal = WeightSignal([early, second], calendar: fixUTC)
        let day = fixDay("2030-04-06")
        #expect(signal.standing(time: day.date(minutes: 9 * 60, calendar: fixUTC), day: day, excluding: early)
                == .extra(morning: second))
        // A late reading the same day isn't a morning weight to compete with.
        let late = fixReading("2030-04-06", 75.0, minutes: 20 * 60)
        let withLate = WeightSignal([late], calendar: fixUTC)
        #expect(withLate.countsAsMorning(time: day.date(minutes: 8 * 60, calendar: fixUTC), day: day))
    }

    @Test func aHealthCopyOfTheSameWeighInIsNotEarlier() {
        let health = fixReading("2030-04-06", 74.2, minutes: 7 * 60, source: .health)
        let signal = WeightSignal([health], calendar: fixUTC)
        let day = fixDay("2030-04-06")
        let typedTime = day.date(minutes: 7 * 60 + 5, calendar: fixUTC)
        #expect(signal.standing(time: typedTime, day: day, kilograms: 74.2) == .counts)
        // A different weight is another weigh-in.
        #expect(signal.standing(time: typedTime, day: day, kilograms: 75.0) == .extra(morning: health))
    }

    @Test func dayStartAfterMidnight() {
        // Day start 03:00: a 01:30 weigh-in belongs to the evening before (25:30), after any cutoff.
        let signal = WeightSignal([], cutoffMinutes: 660, dayStartHour: 3, calendar: fixUTC)
        let day = fixDay("2030-04-06")
        let time = fixDay("2030-04-07").date(minutes: 90, calendar: fixUTC)
        #expect(signal.standing(time: time, day: day) == .afterCutoff)
    }
}
