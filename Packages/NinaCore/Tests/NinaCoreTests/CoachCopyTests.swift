import Foundation
import Testing
@testable import NinaCore

// Made-up numbers, nothing from a real person: a man born 1990, 180 cm, 80 kg rising 0.15 kg a week
// from 2030-01-01; gym Mon/Wed/Fri 2600 kcal, rest 2400 (protein 160 g, four meals of 40 g); a gain
// phase from Mon 2030-01-07, a planned fat-loss phase from ~2030-06-01. Today is Mon 2030-02-04.

private var copyUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func copyDay(_ raw: String) -> DayKey { DayKey(raw)! }

private enum CopyFixture {
    static let gym = DailyTargets(energy: 2600, protein: 160, carbs: 310, fat: 80)
    static let rest = DailyTargets(energy: 2400, protein: 160, carbs: 260, fat: 80)
    static let start = copyDay("2030-01-07")
    static let today = copyDay("2030-02-04")

    static var plan: CoachPlan {
        CoachPlan(
            dayTypes: [
                .init(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
                .init(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
            ],
            phases: [
                .init(id: "1", name: "Lean gain", goal: .gain, start: start, end: copyDay("2030-05-31"), endApprox: true,
                      rateMin: 0.1, rateMax: 0.2, reviewMin: 82, reviewMax: 83, targetWeight: 83,
                      startedAt: start.date(calendar: copyUTC), status: .active,
                      revisions: [.init(from: start, baseline: rest, byType: ["gym": gym, "rest": rest], reason: "import")]),
                .init(id: "2", name: "Fat loss", goal: .lose, start: copyDay("2030-06-01"), startApprox: true,
                      targetWeight: 78, targetBodyFat: 14),
            ],
            longTerm: .init(weightKg: 78, bodyFat: 14, note: "Leaner and stronger"),
            protein: .init(mealMin: 35, mealMax: 45, count: 4),
            checks: [.init(id: "creatine", name: "Creatine monohydrate", dose: "3-5 g", timing: .meal("breakfast"), isOptional: true)],
            notes: ["An extra gym session counts as a gym day."]
        )
    }

    static func state(plan: CoachPlan? = CopyFixture.plan) -> SettingsState {
        SettingsState(sex: .male, birthYear: 1990, heightCm: 180, weightKg: 80, activity: .moderate, goal: .gain, ratePerWeek: 0.15,
                      targets: rest, plan: plan)
    }

    /// One 07:00 weigh-in a day from 2030-01-01 through today, rising 0.15 kg a week from 80; days
    /// from `healthFrom` on come from Apple Health at 90 kg instead.
    static func readings(healthFrom: DayKey? = nil) -> [WeightSignal.Reading] {
        DayKey.range(copyDay("2030-01-01"), through: today, calendar: copyUTC).enumerated().map { index, day in
            let time = day.date(minutes: 7 * 60, calendar: copyUTC)
            if let healthFrom, day >= healthFrom {
                return WeightSignal.Reading(day: day, time: time, kilograms: 90, source: .health)
            }
            return WeightSignal.Reading(day: day, time: time, kilograms: 80 + Double(index) * 0.15 / 7)
        }
    }

    /// Every day from the phase start logged 20 kcal under its target, 40 g protein in each of four meals.
    static var totals: [DayKey: DayTotals] {
        var result: [DayKey: DayTotals] = [:]
        for day in DayKey.range(start, through: today.adding(days: -1, calendar: copyUTC), calendar: copyUTC) {
            let target = plan.targets(on: day, marks: [:], fallback: rest, calendar: copyUTC).energy - 20
            let time = day.date(minutes: 12 * 60, calendar: copyUTC)
            let entries = ["breakfast", "lunch", "snack", "dinner"].map { meal in
                EntryFacts(day: day, meal: meal, nutrients: NutrientValues([.energy: target / 4, .protein: 40]), name: meal, time: time)
            }
            result[day] = DayTotals(day: day, entries: entries)
        }
        return result
    }

    /// Creatine ticked every day except Sundays.
    static var doneChecks: [DayKey: Set<String>] {
        var result: [DayKey: Set<String>] = [:]
        for day in DayKey.range(start, through: today, calendar: copyUTC) where day.weekday(calendar: copyUTC) != 7 {
            result[day] = ["creatine"]
        }
        return result
    }

    /// A full set on the phase start, then the waist every Monday.
    static var tape: [BodyTapeRecord] {
        var records = [BodyTapeRecord(day: start, values: BodyValues([.neck: 39, .chest: 104, .arm: 36.5, .waist: 84, .hip: 100, .thigh: 58]),
                                      conditions: "morning,fasted")]
        for (offset, raw) in ["2030-01-14", "2030-01-21", "2030-01-28", "2030-02-04"].enumerated() {
            records.append(BodyTapeRecord(day: copyDay(raw), values: BodyValues([.waist: 84.2 + Double(offset) * 0.1]), conditions: "morning,fasted"))
        }
        return records
    }

    static var bodyFat: [BodyFatReading] {
        [BodyFatReading(day: start, bodyFat: 20, method: .dexa, leanKg: 61.5, fatKg: 16)]
    }

    static func input(includeHealth: Bool = false, healthFrom: DayKey? = nil, plan: CoachPlan? = CopyFixture.plan) -> CoachCopy.Input {
        CoachCopy.Input(today: today, state: state(plan: plan), readings: readings(healthFrom: healthFrom), includeHealth: includeHealth,
                        totals: totals, doneChecks: doneChecks, tape: tape, bodyFat: bodyFat,
                        checkIns: [CheckInSnapshot(day: copyDay("2030-01-28"), verdict: .inRange)],
                        currentSettings: "setting,value\ngoal,gain")
    }
}

@Suite("Copy for my AI")
struct CoachCopyTests {
    @Test func weeksAreSevenWholeDaysEndingYesterday() {
        let weeks = CoachCopy.weekSpans(today: CopyFixture.today, calendar: copyUTC)
        #expect(weeks.map(\.start.rawValue) == ["2030-01-07", "2030-01-14", "2030-01-21", "2030-01-28"])
        #expect(weeks.last?.end == copyDay("2030-02-03"))
        #expect(CoachCopy.firstDay(today: CopyFixture.today, calendar: copyUTC) == copyDay("2030-01-07"))
    }

    @Test func endsWithTheAnswerRulesAndTheKeyTable() throws {
        let text = CoachCopy.text(CopyFixture.input(), calendar: copyUTC)
        #expect(text.contains(CoachCopy.closingLine))
        let last = try #require(SettingsCSV.planKeys.last)
        #expect(text.split(separator: "\n").last?.hasPrefix("| \(last.name) |") == true)
        #expect(text.contains("| rate_kg_per_week | "))
        #expect(text.contains("| phase.N.ID.calories | "))
        // The closing line comes after everything else.
        let closing = try #require(text.range(of: CoachCopy.closingLine))
        let notes = try #require(text.range(of: "## Notes from my plan"))
        let current = try #require(text.range(of: "```csv\nsetting,value\ngoal,gain\n```"))
        #expect(notes.upperBound < closing.lowerBound)
        #expect(current.upperBound < closing.lowerBound)
    }

    @Test func summarizesThePlan() {
        let text = CoachCopy.text(CopyFixture.input(), calendar: copyUTC)
        #expect(text.contains("- male · born 1990 · height 180 cm · activity: moderately active"))
        #expect(text.contains("- Phase 1 \"Lean gain\" (gain, running, week 5 of 21): 2030-01-07 to ~2030-05-31; rate +0.10 to +0.20 kg/week; "
                              + "review at 82.0–83.0 kg; target 83.0 kg; baseline 2,400 kcal, protein 160 g, carbs 260 g, fat 80 g"))
        #expect(text.contains("- Phase 2 \"Fat loss\" (lose, planned, not started yet): ~2030-06-01 to open end; target 78.0 kg; "
                              + "target body fat 14.0 %; no targets yet"))
        #expect(text.contains("  - 🏋️ Gym (id gym): Mon, Wed, Fri – 2,600 kcal, protein 160 g, carbs 310 g, fat 80 g"))
        #expect(text.contains("  - 🛋️ Rest (id rest): all other days – 2,400 kcal"))
        #expect(text.contains("  - Planned week average: 2,486 kcal a day"))
        #expect(text.contains("- Protein per meal: 35–45 g per protein meal, 4 protein meals a day"))
        #expect(text.contains("  - Creatine monohydrate (3-5 g), with breakfast, every day, optional, can move the scale"))
        #expect(text.contains("- Weekly check-in on Monday; calories are adjusted after 14–21 days of weigh-ins, by 100–150 kcal a day"))
        #expect(text.contains("- Long-term goal: 78.0 kg, 14.0 % body fat – Leaner and stronger"))
        #expect(text.contains("## Notes from my plan\n- An extra gym session counts as a gym day."))
    }

    @Test func lastFourWeeks() {
        let text = CoachCopy.text(CopyFixture.input(), calendar: copyUTC)
        #expect(text.contains("### 2030-01-07 to 2030-01-13"))
        #expect(text.contains("### 2030-01-28 to 2030-02-03\n- Morning weight: average 80.6 kg (7 of 7 mornings), +0."))
        #expect(text.contains("- Rate: +0.15 kg/week"))
        // The first week is too short for a rate (the window starts with the phase).
        #expect(text.contains("### 2030-01-07 to 2030-01-13\n- Morning weight: average 80.2 kg (7 of 7 mornings), +0.1 kg vs. the week before\n- Rate: not enough weigh-ins yet"))
        #expect(text.contains("- Logged: 7 of 7 days, on plan 7"))
        #expect(text.contains("- By day type: Gym 2,580 of 2,600 kcal (3 days) · Rest 2,380 of 2,400 kcal (4 days)"))
        #expect(text.contains("- Protein: target reached on 7 of 7 logged days, average 160 of 160 g; protein meals 28 of 28"))
        #expect(text.contains("- Checks: Creatine monohydrate 6 of 7 (optional)"))
        #expect(text.contains("- Waist: 84.4 cm on 2030-01-28"))
        #expect(text.contains("- Check-in on 2030-01-28: In range"))
    }

    @Test func bodyNumbers() {
        let text = CoachCopy.text(CopyFixture.input(), calendar: copyUTC)
        #expect(text.contains("- Latest full measurement (2030-01-07, morning, before eating): Waist 84.0 cm · Hip 100.0 cm · "
                              + "Chest 104.0 cm · Arm 36.5 cm · Thigh 58.0 cm · Neck 39.0 cm"))
        #expect(text.contains("  - DEXA scan: 20.0 % on 2030-01-07 (typical error ±1.5 points); lean 61.5 kg, fat 16.0 kg"))
        #expect(text.contains("  - Tape estimate: "))
        // Without a height there is no tape estimate.
        var input = CopyFixture.input()
        input.state.heightCm = 0
        let noHeight = CoachCopy.text(input, calendar: copyUTC)
        #expect(!noHeight.contains("Tape estimate"))
        #expect(noHeight.contains("height not set"))
    }

    @Test func appleHealthWeightsOnlyWhenAllowed() {
        let healthFrom = copyDay("2030-01-28")
        let without = CoachCopy.text(CopyFixture.input(healthFrom: healthFrom), calendar: copyUTC)
        #expect(without.contains("- Weigh-ins from Apple Health are left out."))
        #expect(!without.contains("90.0"))
        #expect(without.contains("### 2030-01-28 to 2030-02-03\n- Morning weight: no weigh-ins"))

        let with = CoachCopy.text(CopyFixture.input(includeHealth: true, healthFrom: healthFrom), calendar: copyUTC)
        #expect(!with.contains("left out."))
        #expect(with.contains("### 2030-01-28 to 2030-02-03\n- Morning weight: average 90.0 kg (7 of 7 mornings)"))
    }

    @Test func withoutAPlan() {
        var input = CopyFixture.input(plan: nil)
        input.state.goal = .lose
        input.state.ratePerWeek = 0.5
        input.state.targets = .standard
        let text = CoachCopy.text(input, calendar: copyUTC)
        #expect(text.contains("- No coach plan yet. Goal: lose weight, 0.50 kg/week"))
        #expect(text.contains("- Daily targets: 2,000 kcal, protein 125 g, carbs 225 g, fat 67 g"))
        #expect(!text.contains("Phase 1"))
        #expect(!text.contains("## Notes from my plan"))
        #expect(text.contains(CoachCopy.closingLine))
    }

    @Test func numbersUseADecimalPoint() {
        #expect(CoachCopy.fixed(80.04, 1) == "80.0")
        #expect(CoachCopy.fixed(-0.04, 1) == "0.0")
        #expect(CoachCopy.signed(0.153, 2) == "+0.15")
        #expect(CoachCopy.signed(-0.2, 2) == "-0.20")
        #expect(CoachCopy.signed(-0.001, 2) == "+0.00")
    }
}
