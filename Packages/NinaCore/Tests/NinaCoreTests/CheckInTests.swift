import Foundation
import Testing
@testable import NinaCore

// Made-up plan, nothing from a real person: 80 kg; gym Mon/Wed/Fri 2600 kcal, tennis twice a week
// 2800, rest 2400 (protein 160 g and fat 80 g on every type, carbs take the rest); a gain phase of
// +0.10 to +0.20 kg/week started Mon 2030-01-07, a planned cut from 2030-06-03 to 2030-08-12.
// Check-ins on Mondays.

private var checkInUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func checkInDay(_ raw: String) -> DayKey { DayKey(raw)! }

private enum CheckInFixture {
    static let gym = DailyTargets(energy: 2600, protein: 160, carbs: 310, fat: 80, fiber: 30, water: 2500)
    static let tennis = DailyTargets(energy: 2800, protein: 160, carbs: 360, fat: 80, fiber: 30, water: 2500)
    static let rest = DailyTargets(energy: 2400, protein: 160, carbs: 260, fat: 80, fiber: 30, water: 2500)
    static let profile = DailyTargets(energy: 2200, protein: 120, carbs: 250, fat: 70)
    static let startedAt = Date(timeIntervalSince1970: 1_894_006_800) // 2030-01-07 09:00 UTC
    static let checkInDay = DayKey(year: 2030, month: 2, day: 4) // Monday, week 5

    static let dayTypes: [CoachPlan.DayType] = [
        .init(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
        .init(id: "tennis", name: "Tennis", emoji: "🎾", schedule: .flexible, perWeek: 2),
        .init(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
    ]

    static func plan(adjust: CoachPlan.Adjust = CoachPlan.Adjust(), pauses: [CoachPlan.Pause] = [],
                     extraRevisions: [CoachPlan.Revision] = []) -> CoachPlan {
        CoachPlan(
            dayTypes: dayTypes,
            phases: [
                .init(id: "1", name: "Lean gain", goal: .gain, start: DayKey(year: 2030, month: 1, day: 7),
                      end: DayKey(year: 2030, month: 5, day: 26), endApprox: true, rateMin: 0.1, rateMax: 0.2,
                      reviewMin: 83, reviewMax: 84, targetWeight: 84, startedAt: startedAt, status: .active,
                      revisions: [.init(from: DayKey(year: 2030, month: 1, day: 7), baseline: gym,
                                        byType: ["gym": gym, "tennis": tennis, "rest": rest], reason: "import")] + extraRevisions),
                .init(id: "2", name: "Cut", goal: .lose, start: DayKey(year: 2030, month: 6, day: 3), startApprox: true,
                      end: DayKey(year: 2030, month: 8, day: 12), targetWeight: 76, targetBodyFat: 15),
            ],
            protein: .init(mealMin: 35, count: 4),
            checks: [
                .init(id: "creatine", name: "Creatine monohydrate", dose: "3–5 g", timing: .meal("breakfast"), isOptional: true),
                .init(id: "vitd", name: "Vitamin D", dose: "1 drop"),
            ],
            adjust: adjust,
            pauses: pauses
        )
    }

    /// A cut plan: gym 2200, tennis 2400, rest 2000 (protein 176 g, fat 64 g), −0.3 to −0.5 kg/week.
    static let cutGym = DailyTargets(energy: 2200, protein: 176, carbs: 230, fat: 64)
    static let cutTennis = DailyTargets(energy: 2400, protein: 176, carbs: 280, fat: 64)
    static let cutRest = DailyTargets(energy: 2000, protein: 176, carbs: 180, fat: 64)

    static var cutPlan: CoachPlan {
        CoachPlan(dayTypes: dayTypes, phases: [
            .init(id: "c", name: "Cut", goal: .lose, start: DayKey(year: 2030, month: 1, day: 7), rateMin: 0.3, rateMax: 0.5,
                  startedAt: startedAt, status: .active,
                  revisions: [.init(from: DayKey(year: 2030, month: 1, day: 7), baseline: cutGym,
                                    byType: ["gym": cutGym, "tennis": cutTennis, "rest": cutRest], reason: "import")]),
        ])
    }

    /// Three weeks of good data: 21 days, 18 morning weigh-ins, 20 of 21 days logged, 20 kcal under.
    static func input(rate: Double?, plan: CoachPlan = plan(), history: [CheckInSnapshot] = [], day: DayKey = checkInDay) -> CheckInInput {
        CheckInInput(day: day, plan: plan, fallback: profile, rate: rate, windowDays: 21, weighIns: 18, weightKg: 80,
                     countedDays: 21, loggedDays: 20, averageIntake: 2580, averageTarget: 2600, history: history, sex: .male)
    }

    static func previous(_ deviation: CheckInEngine.Deviation?, on raw: String, phase: String = "1") -> CheckInSnapshot {
        let verdict: CheckInVerdict = deviation == nil ? .inRange : (deviation == .below ? .slower : .faster)
        return CheckInSnapshot(day: DayKey(raw)!, verdict: verdict, deviation: deviation, phaseID: phase)
    }

    static func maintenance(_ kcal: Double, _ confidence: Insights.Maintenance.Confidence) -> Insights.Maintenance {
        Insights.Maintenance(kilocalories: kcal, averageIntake: kcal, weightChange: 0, days: 27, loggedDays: 25, confidence: confidence)
    }
}

// MARK: - Adherence

@Suite("Adherence")
struct AdherenceTests {
    @Test func dayRules() {
        let gym = CheckInFixture.gym
        let day = checkInDay("2030-01-07")
        // kcal band: max(10 %, 150 kcal) → 260 around 2600, 150 around 1200.
        #expect(Adherence.kcalBand(target: 2600) == 260)
        #expect(Adherence.kcalBand(target: 1200) == 150)
        #expect(Adherence.isInKcalBand(eaten: 1050, target: 1200))
        #expect(!Adherence.isInKcalBand(eaten: 1049, target: 1200))
        let onPlan = DayAdherence(day: day, isLogged: true, energy: 2340, protein: 144, targets: gym, proteinMeals: 3, proteinMealsTarget: 4)
        #expect(onPlan.isKcalInBand)
        #expect(onPlan.isProteinReached) // 144 = 90 % of 160
        #expect(onPlan.isProteinMealsReached) // 3 ≥ 4 − 1
        #expect(onPlan.isOnPlan)
        #expect(onPlan.balance == -260)
        #expect(!DayAdherence(day: day, isLogged: true, energy: 2339, protein: 160, targets: gym).isOnPlan)
        #expect(!DayAdherence(day: day, isLogged: true, energy: 2861, protein: 160, targets: gym).isOnPlan)
        #expect(DayAdherence(day: day, isLogged: true, energy: 2860, protein: 160, targets: gym).isOnPlan)
        #expect(!DayAdherence(day: day, isLogged: true, energy: 2600, protein: 143, targets: gym).isOnPlan)
        #expect(!DayAdherence(day: day, isLogged: true, energy: 2600, protein: 160, targets: gym, proteinMeals: 2, proteinMealsTarget: 4).isProteinMealsReached)
        // Protein meals aren't part of "on plan", and count as reached when not tracked.
        #expect(DayAdherence(day: day, isLogged: true, energy: 2600, protein: 160, targets: gym, proteinMeals: 1, proteinMealsTarget: 4).isOnPlan)
        #expect(DayAdherence(day: day, isLogged: true, energy: 2600, protein: 160, targets: gym).isProteinMealsReached)
        // An unlogged day is never on plan; protein meals are capped at the target.
        let unlogged = DayAdherence(day: day, isLogged: false, targets: DailyTargets(energy: 100, protein: 0, carbs: 0, fat: 0))
        #expect(!unlogged.isKcalInBand && !unlogged.isProteinReached && !unlogged.isOnPlan)
        #expect(DayAdherence(day: day, isLogged: true, targets: gym, proteinMeals: 6, proteinMealsTarget: 4).proteinMeals == 4)
    }

    @Test func proteinMealsAreCountedPerMeal() {
        let byMeal: [String: NutrientValues] = [
            "breakfast": NutrientValues([.protein: 40]), "lunch": NutrientValues([.protein: 30]),
            "snack": NutrientValues([.protein: 35]), "dinner": NutrientValues([.protein: 50]),
        ]
        #expect(Adherence.proteinMeals(byMeal: byMeal, minimum: 35) == 3)
        #expect(Adherence.proteinMeals(byMeal: byMeal, minimum: 35, meals: ["breakfast", "lunch"]) == 1)
        #expect(Adherence.proteinMeals(byMeal: byMeal, minimum: 35, count: 2) == 2)
        #expect(Adherence.proteinMeals(byMeal: byMeal, minimum: 0) == 0)
    }

    @Test func diaryDayResolvedThroughThePlan() {
        let plan = CheckInFixture.plan(pauses: [.init(start: checkInDay("2030-01-12"), end: checkInDay("2030-01-13"), reason: .holiday)])
        let wednesday = checkInDay("2030-01-09")
        let time = wednesday.date(minutes: 600, calendar: checkInUTC)
        let entries = [
            EntryFacts(day: wednesday, meal: "breakfast", nutrients: NutrientValues([.energy: 800, .protein: 45, .fiber: 10]), name: "Oats", time: time),
            EntryFacts(day: wednesday, meal: "lunch", nutrients: NutrientValues([.energy: 900, .protein: 50, .fiber: 8]), name: "Rice", time: time),
            EntryFacts(day: wednesday, meal: "snack", nutrients: NutrientValues([.energy: 300, .protein: 20]), name: "Yoghurt", time: time),
            EntryFacts(day: wednesday, meal: "dinner", nutrients: NutrientValues([.energy: 750, .protein: 40, .fiber: 12]), name: "Pasta", time: time),
            EntryFacts(day: wednesday, meal: "dinner", status: .planned, nutrients: NutrientValues([.energy: 500, .protein: 30]), name: "Later", time: time),
        ]
        let totals = DayTotals(day: wednesday, entries: entries, water: 2000)
        // Wednesday is a gym day by schedule; the mark makes it a tennis day.
        let day = DayAdherence(plan: plan, totals: totals, marks: ["2030-01-09": "tennis"], fallback: CheckInFixture.profile,
                               weightKg: 80, doneChecks: ["creatine", "other"], calendar: checkInUTC)
        #expect(day.dayTypeID == "tennis")
        #expect(day.targets == CheckInFixture.tennis)
        #expect(day.isLogged && !day.isPaused)
        #expect(day.energy == 2750)
        #expect(day.protein == 155)
        #expect(day.fiber == 30)
        #expect(day.water == 2000)
        #expect(day.proteinMeals == 3) // breakfast, lunch, dinner reach 35 g; planned entries don't count
        #expect(day.proteinMealsTarget == 4)
        #expect(day.checksDue == ["creatine", "vitd"])
        #expect(day.checksDone == ["creatine"])
        #expect(day.isOnPlan)
        // Without the mark it's a gym day; marked incomplete it isn't logged.
        let gymDay = DayAdherence(plan: plan, totals: totals, marks: [:], fallback: CheckInFixture.profile, weightKg: 80,
                                  incomplete: true, calendar: checkInUTC)
        #expect(gymDay.dayTypeID == "gym")
        #expect(gymDay.targets == CheckInFixture.gym)
        #expect(!gymDay.isLogged && !gymDay.isOnPlan)
        // Paused days and days without a phase.
        let saturday = DayAdherence(plan: plan, totals: DayTotals(day: checkInDay("2030-01-12"), entries: []), marks: [:],
                                    fallback: CheckInFixture.profile, calendar: checkInUTC)
        #expect(saturday.isPaused)
        #expect(saturday.dayTypeID == "rest")
        let before = DayAdherence(plan: plan, totals: DayTotals(day: checkInDay("2029-12-31"), entries: []), marks: [:],
                                  fallback: CheckInFixture.profile, calendar: checkInUTC)
        #expect(before.targets == CheckInFixture.profile)
    }

    /// Mon 2030-01-07 … Sun 2030-01-13: five logged days, Saturday unlogged, Sunday paused.
    static var week: [DayAdherence] {
        let f = CheckInFixture.self
        func day(_ raw: String, _ type: String, logged: Bool = true, _ kcal: Double, protein: Double, meals: Int, done: [String],
                 paused: Bool = false) -> DayAdherence {
            let targets = type == "gym" ? f.gym : (type == "tennis" ? f.tennis : f.rest)
            return DayAdherence(day: checkInDay(raw), dayTypeID: type, isPaused: paused, isLogged: logged, energy: kcal, protein: protein,
                                fiber: logged ? 28 : 0, water: logged ? 2400 : 0, targets: targets, proteinMeals: meals,
                                proteinMealsTarget: 4, checksDue: ["creatine", "vitd"], checksDone: done)
        }
        return [
            day("2030-01-07", "gym", 2550, protein: 160, meals: 4, done: ["creatine", "vitd"]),
            day("2030-01-08", "tennis", 2750, protein: 150, meals: 3, done: ["creatine", "vitd"]),
            day("2030-01-09", "gym", 2900, protein: 165, meals: 4, done: ["vitd"]), // 300 over: not on plan
            day("2030-01-10", "tennis", 2850, protein: 160, meals: 4, done: ["creatine", "vitd"]),
            day("2030-01-11", "gym", 2600, protein: 140, meals: 2, done: ["creatine", "vitd"]), // protein short
            day("2030-01-12", "rest", logged: false, 0, protein: 0, meals: 0, done: []),
            day("2030-01-13", "rest", 2400, protein: 160, meals: 4, done: ["creatine", "vitd"], paused: true),
        ]
    }

    @Test func weekSummary() {
        let summary = Adherence.summary(Self.week, plan: CheckInFixture.plan())
        #expect(summary.days == 6)
        #expect(summary.pausedDays == 1)
        #expect(summary.loggedDays == 5)
        #expect(summary.onPlanDays == 3)
        #expect(summary.kcalDays == 4)
        #expect(summary.proteinDays == 4)
        #expect(summary.proteinMealDays == 4)
        #expect(summary.proteinMeals == 17)
        #expect(summary.proteinMealsTarget == 24)
        // Average eaten vs. the average target of the day types actually used (logged days).
        #expect(summary.averageIntake == 2730)
        #expect(summary.averageTarget == 2680)
        #expect(summary.averageBalance == 50)
        #expect(summary.averageFiber == 28)
        #expect(summary.averageFiberTarget == 30)
        #expect(summary.averageWater == 2400)
        #expect(summary.averageWaterTarget == 2500)
        #expect(summary.byType.map(\.typeID) == ["gym", "tennis", "rest"])
        let tennis = summary.type("tennis")
        #expect(tennis?.days == 2)
        #expect(tennis?.averageIntake == 2800)
        #expect(tennis?.averageTarget == 2800)
        #expect(summary.type("gym")?.loggedDays == 3)
        #expect(summary.type("rest")?.days == 1)
        #expect(summary.type("rest")?.loggedDays == 0)
        // Checks: the optional one never counts as missed.
        #expect(summary.check("creatine") == .init(checkID: "creatine", done: 4, due: 6, isOptional: true))
        #expect(summary.check("creatine")?.missed == 0)
        #expect(summary.check("vitd")?.done == 5)
        #expect(summary.check("vitd")?.missed == 1)
        // "Tennis 2 of 2".
        #expect(summary.flexible == [.init(typeID: "tennis", count: 2, planned: 2)])
        #expect(summary.onPlanShare == 0.5)
        #expect(summary.grade == .off)
        #expect(summary.ratings.isEmpty)
    }

    @Test func grades() {
        #expect(AdherenceGrade(share: 6.0 / 7) == .good)
        #expect(AdherenceGrade(share: 0.85) == .good)
        #expect(AdherenceGrade(share: 5.0 / 7) == .watch)
        #expect(AdherenceGrade(share: 0.70) == .watch)
        #expect(AdherenceGrade(share: 4.0 / 7) == .off)
        // Paused days are left out: 5 of 6 counted days is "watch", all paused is no grade.
        var days = Self.week
        days[2].energy = 2700
        days[4].protein = 150
        let summary = Adherence.summary(days)
        #expect(summary.onPlanDays == 5)
        #expect(summary.days == 6)
        #expect(summary.grade == .watch)
        #expect(summary.flexible.isEmpty) // no plan given
        #expect(summary.check("creatine")?.isOptional == false)
        let paused = days.map { day -> DayAdherence in
            var copy = day
            copy.isPaused = true
            return copy
        }
        #expect(Adherence.summary(paused).grade == nil)
        #expect(Adherence.summary([]).days == 0)
    }
}

// MARK: - Check-in engine

@Suite("Check-in engine")
struct CheckInEngineTests {
    static var gainPhase: CoachPlan.Phase { CheckInFixture.plan().phases[0] }

    @Test func stepFromTheRate() {
        let phase = Self.gainPhase
        // Range +0.10…+0.20, midpoint 0.15: d × 1,100, rounded to 50, clamped to 100…150.
        #expect(CheckInEngine.step(rate: 0.05, phase: phase) == 100)
        #expect(CheckInEngine.step(rate: 0.0, phase: phase) == 150)
        #expect(CheckInEngine.step(rate: 0.25, phase: phase) == -100)
        #expect(CheckInEngine.step(rate: 0.35, phase: phase) == -150)
        #expect(CheckInEngine.step(rate: -0.4, phase: phase) == 150)
        // Inside the range (with the 0.03 tolerance) there is no step.
        #expect(CheckInEngine.step(rate: 0.15, phase: phase) == 0)
        #expect(CheckInEngine.step(rate: 0.08, phase: phase) == 0)
        #expect(CheckInEngine.step(rate: 0.23, phase: phase) == 0)
        #expect(CheckInEngine.deviation(rate: 0.06, phase: phase) == .below)
        #expect(CheckInEngine.deviation(rate: 0.24, phase: phase) == .above)
        // Configurable steps.
        let wide = CoachPlan.Adjust(stepMin: 50, stepMax: 200)
        #expect(CheckInEngine.step(rate: 0.05, phase: phase, adjust: wide) == 100)
        // Without tolerance 0.09 is outside: 66 kcal rounds to 50, raised to the 100 minimum.
        #expect(CheckInEngine.step(rate: 0.09, phase: phase, adjust: CoachPlan.Adjust(tolerance: 0)) == 100)
        // A cut of −0.3…−0.5 (midpoint −0.4): losing 0.1 is slower (eat less), losing 0.7 faster (eat more).
        let cut = CheckInFixture.cutPlan.phases[0]
        #expect(CheckInEngine.step(rate: -0.1, phase: cut) == -150)
        #expect(CheckInEngine.step(rate: -0.7, phase: cut) == 150)
        #expect(CheckInEngine.step(rate: -0.1, phase: cut, adjust: wide) == -200)
        #expect(CheckInEngine.verdict(for: .above, goal: .lose) == .slower)
        #expect(CheckInEngine.verdict(for: .below, goal: .lose) == .faster)
        #expect(CheckInEngine.verdict(for: .below, goal: .gain) == .slower)
        #expect(CheckInEngine.verdict(for: .below, goal: .maintain) == .faster)
    }

    @Test func slowerTwiceInARowProposesMoreCarbs() {
        let f = CheckInFixture.self
        let input = f.input(rate: 0.05, history: [f.previous(.below, on: "2030-01-28"), f.previous(nil, on: "2030-01-21")])
        let result = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(result.verdict == .offTarget)
        #expect(result.deviation == .below)
        #expect(result.rule == .proposal)
        #expect(result.status == .offTrack)
        #expect(result.delta == 100)
        #expect(result.step == 100)
        #expect(result.outsideInARow == 2)
        #expect(result.hasProposal)
        #expect(result.deltaText == "+100 kcal")
        #expect(result.reason == "Slower than planned two check-ins in a row – add 100 kcal a day.")
        #expect(result.notes.isEmpty)

        // The same +100 for every day type, all of it carbs (+25 g); protein and fat stay.
        let tomorrow = f.checkInDay.adding(days: 1, calendar: checkInUTC)
        let preview = CheckInEngine.preview(result.delta, plan: input.plan, from: tomorrow, weightKg: 80, fallback: f.profile)
        #expect(preview.map(\.typeID) == ["gym", "tennis", "rest"])
        #expect(preview.map(\.after.energy) == [2700, 2900, 2500])
        #expect(preview.map(\.carbsChange) == [25, 25, 25])
        #expect(preview.map(\.proteinChange) == [0, 0, 0])
        #expect(preview.map(\.fatChange) == [0, 0, 0])
        #expect(preview[0].after.carbs == 335)
        // Applied from tomorrow: past days keep their targets.
        let applied = CheckInEngine.applying(result.delta, to: input.plan, from: tomorrow, weightKg: 80, fallback: f.profile)
        #expect(applied.phases[0].revisions.last?.reason == "adjust:+100")
        #expect(applied.targets(on: f.checkInDay, marks: [:], fallback: f.profile, calendar: checkInUTC) == f.gym)
        #expect(applied.targets(on: checkInDay("2030-02-06"), marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2700)
        #expect(CheckInEngine.lastAdjustment(in: applied, on: f.checkInDay) == tomorrow)
        #expect(CheckInEngine.applying(0, to: input.plan, from: tomorrow) == input.plan)
    }

    @Test func fasterTwiceInARowProposesLess() {
        let f = CheckInFixture.self
        let result = CheckInEngine.evaluate(f.input(rate: 0.35, history: [f.previous(.above, on: "2030-01-28")]), calendar: checkInUTC)
        #expect(result.verdict == .offTarget)
        #expect(result.delta == -150)
        #expect(result.reason == "Faster than planned two check-ins in a row – eat 150 kcal less a day.")
        let preview = CheckInEngine.preview(result.delta, plan: f.plan(), from: checkInDay("2030-02-05"))
        #expect(preview[0].after.energy == 2450)
        #expect(preview[0].after.carbs == 270) // −37.5 g → −40 g in 5 g steps
        #expect(preview[0].after.protein == 160)
    }

    @Test func outsideOnlyCountsWhenThePreviousCheckInWasOutsideOnTheSameSide() {
        let f = CheckInFixture.self
        func evaluate(_ history: [CheckInSnapshot], adjust: CoachPlan.Adjust = CoachPlan.Adjust(), lastApplied: DayKey? = nil) -> CheckInResult {
            var input = f.input(rate: 0.05, plan: f.plan(adjust: adjust), history: history)
            input.lastApplied = lastApplied
            return CheckInEngine.evaluate(input, calendar: checkInUTC)
        }
        // First time outside: no change yet.
        let first = evaluate([])
        #expect(first.verdict == .slower)
        #expect(first.rule == .confirming)
        #expect(first.status == .watch)
        #expect(first.delta == 0)
        #expect(first.step == 100)
        #expect(first.outsideInARow == 1)
        #expect(first.reason == "Slower than planned (+0.05 kg/week) – if next week is the same, Nina suggests a change.")
        // Previous in range, on the other side, of another phase, or before the last applied change.
        #expect(evaluate([f.previous(nil, on: "2030-01-28")]).rule == .confirming)
        #expect(evaluate([f.previous(.above, on: "2030-01-28")]).rule == .confirming)
        #expect(evaluate([f.previous(.below, on: "2030-01-28", phase: "0")]).rule == .confirming)
        #expect(evaluate([f.previous(.below, on: "2030-01-28")], lastApplied: checkInDay("2030-01-29")).rule == .confirming)
        // Later check-ins and the newest one decide (history in any order).
        #expect(evaluate([f.previous(.below, on: "2030-02-11")]).rule == .confirming)
        #expect(evaluate([f.previous(.above, on: "2030-01-21"), f.previous(.below, on: "2030-01-28")]).rule == .proposal)
        #expect(evaluate([f.previous(.below, on: "2030-01-21"), f.previous(.above, on: "2030-01-28")]).rule == .confirming)
        // Three in a row when the plan asks for three.
        let three = CoachPlan.Adjust(confirmChecks: 3)
        #expect(evaluate([f.previous(.below, on: "2030-01-28")], adjust: three).rule == .confirming)
        let confirmed = evaluate([f.previous(.below, on: "2030-01-28"), f.previous(.below, on: "2030-01-21")], adjust: three)
        #expect(confirmed.rule == .proposal)
        #expect(confirmed.outsideInARow == 3)
        #expect(confirmed.reason == "Slower than planned three check-ins in a row – add 100 kcal a day.")
    }

    @Test func adherenceGate() {
        let f = CheckInFixture.self
        let history = [f.previous(.below, on: "2030-01-28")]
        // Logged on fewer than 80 % of the window's days (17 of 21 needed).
        var input = f.input(rate: 0.05, history: history)
        input.loggedDays = 16
        let logging = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(logging.rule == .logging)
        #expect(logging.delta == 0)
        #expect(logging.verdict == .offTarget)
        #expect(logging.reason == "You logged 16 of 21 days – log your meals this week first.")
        input.loggedDays = 17
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).rule == .proposal)
        // The average intake more than 150 kcal from the average target.
        input.averageIntake = 2360
        let intake = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(intake.rule == .intake)
        #expect(intake.delta == 0)
        #expect(intake.reason == "You ate 240 kcal under your targets – hit them this week first.")
        input.averageIntake = 2780
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).reason == "You ate 180 kcal over your targets – hit them this week first.")
        input.averageIntake = 2750 // exactly +150 passes
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).rule == .proposal)
        // The gate comes before "in range": the status shows "watch".
        var inRange = f.input(rate: 0.15)
        inRange.averageIntake = 2300
        let gated = CheckInEngine.evaluate(inRange, calendar: checkInUTC)
        #expect(gated.rule == .intake)
        #expect(gated.verdict == .inRange)
        #expect(gated.status == .watch)
        // The window summary feeds the gate.
        var fromSummary = f.input(rate: 0.05, history: history)
        fromSummary.use(window: AdherenceSummary(days: 14, loggedDays: 11, averageIntake: 2600, averageTarget: 2600),
                        week: AdherenceSummary(days: 7, onPlanDays: 6))
        #expect(fromSummary.countedDays == 14)
        #expect(fromSummary.weekGrade == .good)
        #expect(CheckInEngine.evaluate(fromSummary, calendar: checkInUTC).reason == "You logged 11 of 14 days – log your meals this week first.")
    }

    @Test func inRangeKeepsIt() {
        let f = CheckInFixture.self
        let result = CheckInEngine.evaluate(f.input(rate: 0.15, history: [f.previous(.below, on: "2030-01-28")]), calendar: checkInUTC)
        #expect(result.verdict == .inRange)
        #expect(result.rule == .inRange)
        #expect(result.deviation == nil)
        #expect(result.reason == "In range – keep it.")
        #expect(result.delta == 0 && result.step == 0)
        #expect(result.outsideInARow == 0)
        #expect(result.status == .onTrack)
        // The status line takes the week's adherence into account.
        var watch = f.input(rate: 0.21)
        watch.weekGrade = .watch
        #expect(CheckInEngine.evaluate(watch, calendar: checkInUTC).status == .watch)
        watch.weekGrade = .off
        #expect(CheckInEngine.evaluate(watch, calendar: checkInUTC).status == .offTrack)
    }

    @Test func creatineHoldsFasterFor28Days() {
        let f = CheckInFixture.self
        let creatine = CheckInEngine.WeightCheck(name: "Creatine", firstTick: checkInDay("2030-01-26"))
        var input = f.input(rate: 0.35, history: [f.previous(.above, on: "2030-01-28")])
        input.weightCheck = creatine
        let held = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(held.verdict == .faster)
        #expect(held.rule == .weightCheckHold)
        // The status line follows F11 (the rate out at 2 check-ins in a row is "Off track"), as
        // Progress and Today say; only the verdict and the proposal are held.
        #expect(held.status == .offTrack)
        #expect(held.delta == 0)
        #expect(held.step == -150)
        #expect(held.notes.first == "Creatine started 9 days ago – up to ~1 kg may be water")
        #expect(held.reason == "Faster than planned, but Creatine started 9 days ago – up to ~1 kg may be water, so keep it for now.")
        // The verdict is held even when the gate fails: no "Off track" verdict because of water.
        var gated = input
        gated.loggedDays = 5
        #expect(CheckInEngine.evaluate(gated, calendar: checkInUTC).verdict == .faster)
        // 28 days after the first tick the proposal goes ahead.
        input.weightCheck = .init(name: "Creatine", firstTick: checkInDay("2030-01-07"))
        let later = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(later.rule == .proposal)
        #expect(later.delta == -150)
        #expect(later.notes.isEmpty)
        // "Slower" proposals still go ahead while creatine is new.
        var slower = f.input(rate: 0.05, history: [f.previous(.below, on: "2030-01-28")])
        slower.weightCheck = creatine
        let ahead = CheckInEngine.evaluate(slower, calendar: checkInUTC)
        #expect(ahead.rule == .proposal)
        #expect(ahead.delta == 100)
        #expect(ahead.notes.isEmpty)
        // In a cut, water makes the loss look slower: that goes ahead too, with the caveat line.
        var cut = f.input(rate: -0.1, plan: f.cutPlan, history: [f.previous(.above, on: "2030-01-28", phase: "c")])
        cut.weightCheck = creatine
        cut.averageTarget = 2200
        cut.averageIntake = 2200
        let cutResult = CheckInEngine.evaluate(cut, calendar: checkInUTC)
        #expect(cutResult.verdict == .offTarget)
        #expect(cutResult.rule == .proposal)
        #expect(cutResult.delta == -150)
        #expect(cutResult.notes == ["Creatine started 9 days ago – up to ~1 kg may be water"])
        // Finding the first tick of a check that affects weight.
        let ticks: [(day: DayKey, checkID: String)] = [
            (checkInDay("2030-02-01"), "creatine"), (checkInDay("2030-01-26"), "creatine"), (checkInDay("2030-01-20"), "vitd"), (checkInDay("2030-01-02"), "gone"),
        ]
        #expect(CheckInEngine.weightCheck(in: f.plan(), ticks: ticks) == .init(name: "Creatine monohydrate", firstTick: checkInDay("2030-01-26")))
        #expect(CheckInEngine.weightCheck(in: f.plan(), ticks: [(checkInDay("2030-01-20"), "vitd")]) == nil)
    }

    @Test func lockAfterAnAppliedChange() {
        let f = CheckInFixture.self
        var input = f.input(rate: 0.05, history: [f.previous(.below, on: "2030-01-28")])
        input.lastApplied = checkInDay("2030-01-28")
        let locked = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(locked.rule == .locked)
        #expect(locked.delta == 0)
        #expect(locked.reason == "Targets changed 7 days ago – give them until Mon 11 Feb before the next change.")
        input.lastApplied = checkInDay("2030-01-21")
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).rule == .proposal)
        // Without an explicit day, the newest "adjust" revision of the active phase counts.
        let adjusted = f.plan(extraRevisions: [.init(from: checkInDay("2030-01-22"), baseline: f.gym, byType: [:], reason: "adjust:+100")])
        #expect(CheckInEngine.lastAdjustment(in: adjusted, on: f.checkInDay) == checkInDay("2030-01-22"))
        #expect(CheckInEngine.lastAdjustment(in: f.plan(), on: f.checkInDay) == nil)
        let derived = CheckInEngine.evaluate(f.input(rate: 0.05, plan: adjusted, history: [f.previous(.below, on: "2030-01-28")]), calendar: checkInUTC)
        #expect(derived.rule == .locked)
        #expect(derived.reason == "Targets changed 13 days ago – give them until Mon 11 Feb before the next change.")
    }

    @Test func redoAfterApplyingSaysTheTargetsAlreadyChanged() throws {
        let f = CheckInFixture.self
        let history = [f.previous(.below, on: "2030-01-28")]
        let first = CheckInEngine.evaluate(f.input(rate: 0.05, history: history), calendar: checkInUTC)
        #expect(first.rule == .proposal)
        #expect(first.delta == 100)
        // "Apply from tomorrow", then Redo the same day: the plan holds the change from Tue 5 Feb.
        let applied = CheckInEngine.applying(first.delta, to: f.plan(), from: checkInDay("2030-02-05"), weightKg: 80, fallback: f.profile)
        #expect(CheckInEngine.lastAdjustment(in: applied, on: f.checkInDay) == checkInDay("2030-02-05"))
        #expect(CheckInEngine.lastAdjustment(in: applied, on: f.checkInDay, inForce: true) == nil)
        let redo = CheckInEngine.evaluate(f.input(rate: 0.05, plan: applied, history: history), calendar: checkInUTC)
        #expect(redo.rule == .locked)
        #expect(redo.delta == 0)
        #expect(!redo.hasProposal)
        #expect(redo.reason == "Targets change from Tue 5 Feb – the next check-in judges them.")
        // Same verdict and status as before the tap.
        #expect(redo.verdict == .offTarget)
        #expect(redo.status == .offTrack)
        #expect(redo.outsideInARow == 2)
        // Never offered again, even while the window is too short to judge.
        let short = f.input(rate: nil, plan: applied, history: history)
        #expect(CheckInEngine.evaluate(short, calendar: checkInUTC).rule == .locked)
        // A week later the lock counts from the day the change started.
        let next = CheckInEngine.evaluate(f.input(rate: 0.05, plan: applied, history: history, day: checkInDay("2030-02-11")),
                                          calendar: checkInUTC)
        #expect(next.rule == .confirming || next.rule == .locked)
        #expect(next.delta == 0)

        // Saving the redo keeps the applied decision in the record.
        var saved = CheckInSnapshot(day: f.checkInDay)
        saved.record(first, phaseID: "1")
        saved.decision = .applied
        var redone = CheckInSnapshot(day: f.checkInDay)
        redone.record(redo, phaseID: "1")
        redone.ratings = CheckInRatings(sleep: 4)
        redone.keepAppliedDecision(of: saved)
        #expect(redone.decision == .applied)
        #expect(redone.deltaKcal == 100)
        #expect(redone.verdict == .offTarget)
        #expect(redone.deviation == .below)
        #expect(redone.decisionText == "+100 kcal")
        #expect(redone.ratings.sleep == 4)
        // Only after an applied change, and never over a decision of its own.
        var kept = saved
        kept.decision = .kept
        var other = CheckInSnapshot(day: f.checkInDay)
        other.keepAppliedDecision(of: kept)
        #expect(other.decision == nil)
        other.decision = .kept
        other.keepAppliedDecision(of: saved)
        #expect(other.decision == .kept)
        other.decision = nil
        other.keepAppliedDecision(of: nil)
        #expect(other.decision == nil)
    }

    @Test func gatheringNamesTheFirstAdjustmentCheck() {
        let f = CheckInFixture.self
        // A phase that started on a Thursday, checked in on the Monday after.
        var plan = f.plan()
        plan.phases[0].start = checkInDay("2030-01-10")
        plan.phases[0].revisions[0].from = checkInDay("2030-01-10")
        var input = f.input(rate: 0.3, plan: plan, day: checkInDay("2030-01-14"))
        input.windowDays = 4
        input.weighIns = 4
        let result = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(result.verdict == .gathering)
        #expect(result.rule == .gathering)
        #expect(result.delta == 0)
        #expect(result.firstAdjustmentCheck == checkInDay("2030-01-28"))
        #expect(result.reason == "Gathering data – first adjustment check on Mon 28 Jan.")
        // Long enough but too few weigh-ins: the next check-in after the window.
        var sparse = f.input(rate: 0.3)
        sparse.weighIns = 9
        sparse.windowStart = checkInDay("2030-01-15")
        let next = CheckInEngine.evaluate(sparse, calendar: checkInUTC)
        #expect(next.rule == .gathering)
        #expect(next.firstAdjustmentCheck == checkInDay("2030-02-11"))
        // No rate at all.
        #expect(CheckInEngine.evaluate(f.input(rate: nil), calendar: checkInUTC).verdict == .gathering)
        // A check-in weekday other than Monday.
        plan.routine.checkInWeekday = 7
        var sunday = f.input(rate: 0.3, plan: plan, day: checkInDay("2030-01-13"))
        sunday.windowDays = 3
        #expect(CheckInEngine.evaluate(sunday, calendar: checkInUTC).firstAdjustmentCheck == checkInDay("2030-01-27"))
    }

    @Test func firstAdjustmentCheckCountsTheFirstAndLastDay() {
        let f = CheckInFixture.self
        // The rate is valid once the weigh-ins span 14 days, both ends included: a phase from
        // Tue 8 Jan can be judged on Mon 21 Jan (8 + 13), not a week later.
        var plan = f.plan()
        plan.phases[0].start = checkInDay("2030-01-08")
        plan.phases[0].revisions[0].from = checkInDay("2030-01-08")
        var early = f.input(rate: 0.3, plan: plan, day: checkInDay("2030-01-14"))
        early.windowDays = 7
        early.weighIns = 7
        let gathering = CheckInEngine.evaluate(early, calendar: checkInUTC)
        #expect(gathering.rule == .gathering)
        #expect(gathering.firstAdjustmentCheck == checkInDay("2030-01-21"))
        #expect(gathering.reason == "Gathering data – first adjustment check on Mon 21 Jan.")
        #expect(WeightSignal.firstRateDay(from: checkInDay("2030-01-08"), calendar: checkInUTC) == checkInDay("2030-01-21"))
        // On that Monday the engine judges the rate (14 days, 14 weigh-ins).
        var judged = f.input(rate: 0.35, plan: plan, day: checkInDay("2030-01-21"))
        judged.windowDays = 14
        judged.weighIns = 14
        #expect(CheckInEngine.evaluate(judged, calendar: checkInUTC).rule == .confirming)

        // After "Apply from tomorrow" on a Monday the window restarts on Tuesday: the next check
        // but one judges it again.
        let applied = f.plan().applyingDelta(100, from: checkInDay("2030-02-05"), weightKg: 80, fallback: f.profile)
        var after = f.input(rate: 0.3, plan: applied, day: checkInDay("2030-02-11"))
        after.windowDays = 6
        after.weighIns = 6
        let wait = CheckInEngine.evaluate(after, calendar: checkInUTC)
        #expect(wait.rule == .gathering)
        #expect(wait.firstAdjustmentCheck == checkInDay("2030-02-18"))
        #expect(CheckInEngine.firstAdjustmentCheck(plan: applied, on: checkInDay("2030-02-11"), calendar: checkInUTC) == checkInDay("2030-02-18"))
    }

    @Test func aShortWindowNeverCountsAsOutside() {
        let f = CheckInFixture.self
        // 3 weigh-ins over 3 days rising fast: noise, not a side – also at the checkpoint, whose
        // result is saved and read as "the previous check-in" next week.
        var short = f.input(rate: 3.5)
        short.windowDays = 3
        short.weighIns = 3
        short.checkpointReached = true
        let checkpoint = CheckInEngine.evaluate(short, calendar: checkInUTC)
        #expect(checkpoint.rule == .checkpoint)
        #expect(checkpoint.deviation == nil)
        short.checkpointReached = false
        #expect(CheckInEngine.evaluate(short, calendar: checkInUTC).deviation == nil)
        // The snapshot saved from it doesn't make next week's first valid "faster" a proposal.
        var snapshot = CheckInSnapshot(day: checkInDay("2030-01-28"), phaseID: "1")
        snapshot.record(checkpoint, phaseID: "1")
        #expect(snapshot.deviation == nil)
        let next = CheckInEngine.evaluate(f.input(rate: 0.35, history: [snapshot]), calendar: checkInUTC)
        #expect(next.rule == .confirming)
        #expect(next.outsideInARow == 1)
    }

    @Test func noPhasePausedAndCheckpoint() {
        let f = CheckInFixture.self
        var notStarted = f.plan()
        notStarted.phases[0].startedAt = nil
        let none = CheckInEngine.evaluate(f.input(rate: 0.05, plan: notStarted), calendar: checkInUTC)
        #expect(none.rule == .noPhase)
        #expect(none.verdict == .gathering)
        let paused = f.plan(pauses: [.init(start: checkInDay("2030-02-01"), reason: .sick)])
        #expect(CheckInEngine.evaluate(f.input(rate: 0.05, plan: paused), calendar: checkInUTC).rule == .paused)
        var checkpoint = f.input(rate: 0.35, history: [f.previous(.above, on: "2030-01-28")])
        checkpoint.checkpointReached = true
        let review = CheckInEngine.evaluate(checkpoint, calendar: checkInUTC)
        #expect(review.verdict == .checkpoint)
        #expect(review.delta == 0)
        #expect(review.reason == "Review weight reached – time to review your phase.")
    }

    @Test func gainCapAndEnergyFloor() {
        let f = CheckInFixture.self
        // Planned week average 2600. Measured maintenance 2200 → cap 2700: +150 becomes +100.
        var input = f.input(rate: 0.0, history: [f.previous(.below, on: "2030-01-28")])
        input.maintenance = f.maintenance(2200, .medium)
        let capped = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(capped.rule == .proposal)
        #expect(capped.step == 150)
        #expect(capped.delta == 100)
        #expect(capped.notes.contains("Limited to your measured maintenance + 500 kcal."))
        input.maintenance = f.maintenance(2000, .high)
        let atCap = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(atCap.rule == .gainCap)
        #expect(atCap.delta == 0)
        #expect(atCap.reason == "Your targets already reach your measured maintenance + 500 kcal – keep them.")
        // Low confidence: no cap.
        input.maintenance = f.maintenance(2000, .low)
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).delta == 150)

        // Cut: lowest day 2000 kcal; floor max(1.1 × BMR, 1,500 for men).
        #expect(CheckInEngine.energyFloor(bmr: 1300, sex: .male) == 1500)
        #expect(CheckInEngine.energyFloor(bmr: 1000, sex: .female) == 1200)
        #expect(CheckInEngine.energyFloor(bmr: 1700, sex: .male) == 1870)
        var cut = f.input(rate: -0.1, plan: f.cutPlan, history: [f.previous(.above, on: "2030-01-28", phase: "c")])
        cut.averageIntake = 2200
        cut.averageTarget = 2200
        #expect(CheckInEngine.evaluate(cut, calendar: checkInUTC).delta == -150)
        cut.bmr = 1700 // floor 1870: 2000 − 150 would be below, 100 fits
        let limited = CheckInEngine.evaluate(cut, calendar: checkInUTC)
        #expect(limited.delta == -100)
        #expect(limited.notes == ["Limited by the safe minimum of 1,870 kcal."])
        cut.bmr = 1800 // floor 1980: nothing fits
        let floor = CheckInEngine.evaluate(cut, calendar: checkInUTC)
        #expect(floor.rule == .energyFloor)
        #expect(floor.delta == 0)
        #expect(floor.reason == "Your targets are at the safe minimum of 1,980 kcal – keep them.")
        // In a cut the change is split 70 % carbs / 30 % fat; protein stays.
        let preview = CheckInEngine.preview(-150, plan: f.cutPlan, from: checkInDay("2030-02-05"), weightKg: 80)
        #expect(preview[0].after == DailyTargets(energy: 2050, protein: 176, carbs: 205, fat: 59))
    }

    @Test func crossCheckFlagsIncompleteLogging() {
        let f = CheckInFixture.self
        var input = f.input(rate: 0.05)
        input.maintenance = f.maintenance(2400, .high)
        let close = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(abs((close.expectedRate ?? 0) - 180.0 * 7 / 7700) < 1e-9)
        #expect(close.notes.isEmpty)
        input.rate = 0.35
        let far = CheckInEngine.evaluate(input, calendar: checkInUTC)
        #expect(far.notes == ["Your logged intake points to +0.16 kg/week, the scale shows +0.35 – logging may be incomplete."])
        input.maintenance = f.maintenance(2400, .low)
        #expect(CheckInEngine.evaluate(input, calendar: checkInUTC).expectedRate == nil)
    }

    @Test func maintainPhase() {
        var plan = CheckInFixture.plan()
        plan.phases[0].goal = .maintain
        plan.phases[0].rateMin = 0
        plan.phases[0].rateMax = 0.1
        let phase = plan.phases[0]
        #expect(CheckInEngine.deviation(rate: 0.12, phase: phase) == nil)
        #expect(CheckInEngine.step(rate: 0.3, phase: phase) == -150)
        #expect(CheckInEngine.step(rate: -0.3, phase: phase) == 150)
        let up = CheckInEngine.evaluate(CheckInFixture.input(rate: 0.3, plan: plan), calendar: checkInUTC)
        #expect(up.verdict == .faster)
        #expect(up.deviation == .above)
        let down = CheckInEngine.evaluate(CheckInFixture.input(rate: -0.3, plan: plan), calendar: checkInUTC)
        #expect(down.verdict == .faster)
        #expect(down.deviation == .below)
    }

    @Test func windowStartAndNextCheckIn() {
        let f = CheckInFixture.self
        let day = f.checkInDay
        #expect(CheckInEngine.windowStart(plan: f.plan(), on: day, calendar: checkInUTC) == checkInDay("2030-01-15"))
        #expect(CheckInEngine.windowStart(plan: f.plan(), on: checkInDay("2030-01-14"), calendar: checkInUTC) == checkInDay("2030-01-07"))
        #expect(CheckInEngine.windowStart(plan: f.plan(), on: day, lastApplied: checkInDay("2030-01-22"), calendar: checkInUTC) == checkInDay("2030-01-22"))
        let paused = f.plan(pauses: [.init(start: checkInDay("2030-01-18"), end: checkInDay("2030-01-25"), reason: .holiday)])
        #expect(CheckInEngine.windowStart(plan: paused, on: day, calendar: checkInUTC) == checkInDay("2030-01-26"))
        let open = f.plan(pauses: [.init(start: checkInDay("2030-01-18"))])
        #expect(CheckInEngine.windowStart(plan: open, on: day, calendar: checkInUTC) == day)
        #expect(CheckInEngine.nextCheckIn(onOrAfter: checkInDay("2030-02-04"), weekday: 1, calendar: checkInUTC) == checkInDay("2030-02-04"))
        #expect(CheckInEngine.nextCheckIn(onOrAfter: checkInDay("2030-02-05"), weekday: 1, calendar: checkInUTC) == checkInDay("2030-02-11"))
        #expect(CheckInEngine.nextCheckIn(onOrAfter: checkInDay("2030-02-05"), weekday: 3, calendar: checkInUTC) == checkInDay("2030-02-06"))
    }
}

// MARK: - Phase transition

@Suite("Phase transition")
struct PhaseTransitionTests {
    static let body = BodyProfile(sex: .male, age: 35, heightCm: 180, weightKg: 72, activity: .moderate, goal: .lose)

    @Test func cutTargetsFromMeasuredMaintenance() {
        let f = CheckInFixture.self
        let plan = f.plan()
        let cut = plan.phases[1]
        let start = checkInDay("2030-06-03")
        // 80 → 76 kg in 10 weeks: 0.40 kg/week (0.5 % of body weight), range 0.35–0.45, −450 kcal a day.
        #expect(PhaseTransition.rate(for: cut, weightKg: 80, from: start, calendar: checkInUTC) == 0.35...0.45)
        let proposal = PhaseTransition.proposal(for: cut, in: plan, on: start, weightKg: 80, maintenance: f.maintenance(2700, .medium),
                                                body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(proposal.source == .measured)
        #expect(proposal.maintenance == 2700)
        #expect(proposal.rateMin == 0.35 && proposal.rateMax == 0.45)
        #expect(proposal.rateDerived)
        #expect(proposal.adjustment == -450)
        #expect(proposal.energy == 2250)
        // The gain phase's week averaged 2600: every day type moves by the same −350 kcal.
        #expect(proposal.shift == -350)
        let gym = proposal.revision.byType["gym"]
        let tennis = proposal.revision.byType["tennis"]
        let rest = proposal.revision.byType["rest"]
        // Protein at least 2.2 g/kg in a cut (176 g), fat keeps 80 g (above its floor), carbs take the rest.
        #expect(gym == DailyTargets(energy: 2250, protein: 176, carbs: 205, fat: 80, fiber: 30, water: 2500))
        #expect(tennis?.energy == 2450)
        #expect(tennis?.carbs == 255)
        #expect(rest?.energy == 2050)
        #expect(rest?.carbs == 155)
        #expect(proposal.revision.baseline?.energy == 2250)
        #expect(proposal.revision.from == start)
        #expect(proposal.revision.reason == "transition")
        #expect(proposal.notes.isEmpty)
        // Applying stores the derived rate and the revision; starting the phase then uses it.
        let applied = proposal.applied(to: plan)
        #expect(applied.phases[1].rateMin == 0.35 && applied.phases[1].rateMax == 0.45)
        #expect(applied.phases[1].revisions.count == 1)
        let started = applied.starting(phase: "2", on: start, now: f.startedAt, calendar: checkInUTC)
        #expect(started.targets(on: checkInDay("2030-06-04"), marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2050)
        #expect(started.targets(on: checkInDay("2030-06-05"), marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2250)
        #expect(started.plannedWeekAverage(started.phases[1].revisions[0]) == 2250)
    }

    @Test func proposalAfterStartKeepsTheCycling() {
        let f = CheckInFixture.self
        let plan = f.plan()
        let start = checkInDay("2030-06-03")
        func propose(_ plan: CoachPlan) -> PhaseTransition.Proposal {
            PhaseTransition.proposal(for: plan.phases[1], in: plan, on: start, weightKg: 80, maintenance: f.maintenance(2700, .medium),
                                     body: Self.body, fallback: f.profile, calendar: checkInUTC)
        }
        let before = propose(plan)
        // Tapped Start first (or an import confirmed the phase): the phase that ran before it
        // still gives the targets, so the day types keep their differences.
        let started = plan.starting(phase: "2", on: start, now: f.startedAt, calendar: checkInUTC)
        #expect(started.activePhase(on: start)?.id == "2")
        let after = propose(started)
        #expect(after == before)
        #expect(after.shift == -350)
        let byType = after.revision.byType
        #expect(byType["gym"]?.energy == 2250 && byType["tennis"]?.energy == 2450 && byType["rest"]?.energy == 2050)
        #expect(PhaseTransition.targetsBefore(started.phases[1], in: started, on: start, calendar: checkInUTC)
                == plan.phases[0].revisions[0])
        // Applied after the start: Monday is a gym day, Tuesday a rest day.
        let applied = after.applied(to: started)
        #expect(applied.targets(on: start, marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2250)
        #expect(applied.targets(on: checkInDay("2030-06-04"), marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2050)
        // Days before the start keep the gain phase's targets.
        #expect(applied.targets(on: checkInDay("2030-05-27"), marks: [:], fallback: f.profile, calendar: checkInUTC).energy == 2600)
        // A later adjustment of the gain phase counts: the one in force on its last day.
        let adjusted = plan.applyingDelta(100, from: checkInDay("2030-05-20"), weightKg: 80, fallback: f.profile)
            .starting(phase: "2", on: start, now: f.startedAt, calendar: checkInUTC)
        #expect(propose(adjusted).shift == -450)
    }

    @Test func calculatedMaintenanceWhenNotConfident() {
        let f = CheckInFixture.self
        let plan = f.plan()
        let proposal = PhaseTransition.proposal(for: plan.phases[1], in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                                maintenance: f.maintenance(2700, .low), body: Self.body, fallback: f.profile,
                                                calendar: checkInUTC)
        // Mifflin-St Jeor at 80 kg: 10 × 80 + 6.25 × 180 − 5 × 35 + 5 = 1755; × 1.55 = 2720.
        #expect(proposal.source == .calculated)
        #expect(proposal.maintenance == 2720)
        #expect(proposal.energy == 2270)
        let none = PhaseTransition.proposal(for: plan.phases[1], in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                            maintenance: nil, body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(none.source == .calculated)
    }

    @Test func rateIsClampedToBodyWeight() {
        var phase = CoachPlan.Phase(id: "x", goal: .lose, start: checkInDay("2030-06-03"), end: checkInDay("2030-08-12"), targetWeight: 79.5)
        let start = checkInDay("2030-06-03")
        // 0.05 kg/week is below 0.25 % of 80 kg (0.20).
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == 0.15...0.25)
        // 2 kg/week is above 1 % (0.80).
        phase.targetWeight = 60
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == 0.75...0.85)
        // The target the wrong way, no end, no weight, maintaining: no rate.
        phase.targetWeight = 82
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == nil)
        phase.goal = .gain
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == 0.15...0.25)
        #expect(PhaseTransition.rate(for: phase, weightKg: 0, from: start, calendar: checkInUTC) == nil)
        phase.end = nil
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == nil)
        phase.goal = .maintain
        #expect(PhaseTransition.rate(for: phase, weightKg: 80, from: start, calendar: checkInUTC) == nil)
    }

    @Test func ownRateMaintainAndNoTargetsSoFar() {
        let f = CheckInFixture.self
        var plan = f.plan()
        plan.phases[1].rateMin = 0.5
        plan.phases[1].rateMax = 0.5
        let own = PhaseTransition.proposal(for: plan.phases[1], in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                           maintenance: f.maintenance(2700, .high), body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(!own.rateDerived)
        #expect(own.adjustment == -550)
        #expect(own.applied(to: plan).phases[1].rateMin == 0.5)
        // A maintenance phase eats at maintenance.
        var hold = CoachPlan.Phase(id: "m", goal: .maintain)
        hold.start = checkInDay("2030-06-03")
        let maintain = PhaseTransition.proposal(for: hold, in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                                maintenance: f.maintenance(2700, .high), body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(maintain.adjustment == 0)
        #expect(maintain.energy == 2700)
        #expect(maintain.shift == 100)
        #expect(maintain.revision.byType["rest"]?.energy == 2500)
        // No targets anywhere yet: the profile's targets become the baseline.
        let empty = CoachPlan(phases: [plan.phases[1]])
        let first = PhaseTransition.proposal(for: plan.phases[1], in: empty, on: checkInDay("2030-06-03"), weightKg: 80,
                                             maintenance: f.maintenance(2700, .high), body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(first.revision.byType.isEmpty)
        #expect(first.revision.baseline?.energy == 2150)
        #expect(first.revision.baseline?.protein == 176)
        // Without a rate a note asks for one.
        var noRate = plan.phases[1]
        noRate.rateMin = 0
        noRate.rateMax = 0
        noRate.targetWeight = 0
        let ask = PhaseTransition.proposal(for: noRate, in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                           maintenance: f.maintenance(2700, .high), body: Self.body, fallback: f.profile, calendar: checkInUTC)
        #expect(ask.adjustment == 0)
        #expect(ask.notes == ["Set a rate for this phase to get a deficit."])
    }

    @Test func cutNeverGoesBelowTheSafeMinimum() {
        let f = CheckInFixture.self
        var plan = f.plan()
        plan.phases[1].rateMin = 0.5
        plan.phases[1].rateMax = 0.5
        // Maintenance 1900 − 550 = 1350 would put the rest day far below max(1.1 × 1755, 1500) = 1930.5.
        let proposal = PhaseTransition.proposal(for: plan.phases[1], in: plan, on: checkInDay("2030-06-03"), weightKg: 80,
                                                maintenance: f.maintenance(1900, .high), body: Self.body, fallback: f.profile,
                                                calendar: checkInUTC)
        #expect(proposal.shift == -460)
        #expect(proposal.revision.byType["rest"]?.energy == 1940)
        #expect(proposal.notes.count == 1)
    }

    @Test func macrosAndBridge() {
        let targets = DailyTargets(energy: 2400, protein: 160, carbs: 250, fat: 50)
        let cut = PhaseTransition.macros(targets, energy: 2000, weightKg: 80, cut: true)
        #expect(cut.protein == 176)
        #expect(cut.fat == 50) // floor max(48, 44.4) → 48; 50 kept
        #expect(cut.carbs == 210)
        let gain = PhaseTransition.macros(targets, energy: 2900, weightKg: 80, cut: false)
        #expect(gain.protein == 160)
        #expect(gain.fat == 65) // 20 % of 2900 kcal = 64.4 g
        #expect(gain.carbs == 420)
        let gainPhase = CheckInFixture.plan().phases[0]
        #expect(!PhaseTransition.suggestsBridge(after: gainPhase, on: checkInDay("2030-04-01"), calendar: checkInUTC))
        #expect(PhaseTransition.suggestsBridge(after: gainPhase, on: checkInDay("2030-04-02"), calendar: checkInUTC))
        #expect(!PhaseTransition.suggestsBridge(after: CheckInFixture.plan().phases[1], on: checkInDay("2030-12-01"), calendar: checkInUTC))
    }
}

// MARK: - Check-in snapshot

@Suite("Check-in snapshot")
struct CheckInSnapshotTests {
    static var snapshot: CheckInSnapshot {
        CheckInSnapshot(day: checkInDay("2030-02-04"), avg7: 80.4, prevAvg7: 80.3, rate: 0.05, weighIns: 18, days: 7, logged: 7, onPlan: 6,
                        kcalAvg: 2580, kcalTarget: 2600, proteinDays: 6, proteinMeals: 25, proteinMealsTarget: 28, waist: 86.2,
                        deltaKcal: 100, ratings: CheckInRatings(hunger: 3, energy: 4), verdict: .offTarget, deviation: .below,
                        decision: .applied, phaseID: "1")
    }

    @Test func roundTripsThroughDayMarkText() {
        let snapshot = Self.snapshot
        #expect(snapshot.values == "avg7=80.4;days=7;deltaKcal=100;energy=4;hunger=3;kcalAvg=2580;kcalTarget=2600;logged=7;onPlan=6;prevAvg7=80.3;proteinDays=6;proteinMeals=25;proteinMealsTarget=28;rate=0.05;waist=86.2;weighIns=18")
        #expect(snapshot.meta == "applied=yes;deviation=below;phase=1;verdict=offTarget")
        #expect(CheckInSnapshot(day: snapshot.day, values: snapshot.values, meta: snapshot.meta) == snapshot)
        #expect(snapshot.key(calendar: checkInUTC) == "week-2030-02-04")
        #expect(CheckInSnapshot(day: checkInDay("2030-02-06"), values: "", meta: "").key(calendar: checkInUTC) == "week-2030-02-04")
        #expect(snapshot.decisionText == "+100 kcal")
    }

    @Test func healthWeightsAreNeverStored() {
        var snapshot = Self.snapshot
        snapshot.usesHealthWeights = true
        #expect(!snapshot.values.contains("avg7"))
        #expect(!snapshot.values.contains("rate"))
        #expect(!snapshot.values.contains("weighIns"))
        #expect(snapshot.values.contains("kcalAvg=2580"))
        #expect(snapshot.meta == "applied=yes;deviation=below;phase=1;source=health;verdict=offTarget")
        let read = CheckInSnapshot(day: snapshot.day, values: Self.snapshot.values, meta: snapshot.meta)
        #expect(read.usesHealthWeights)
        #expect(read.avg7 == nil && read.prevAvg7 == nil && read.rate == nil && read.weighIns == nil)
        #expect(read.kcalAvg == 2580)
    }

    @Test func readsLeniently() {
        let read = CheckInSnapshot(day: checkInDay("2030-02-04"), values: "avg7=abc;logged=6.6;hunger=9;mood=0;junk;x=1",
                                   meta: "verdict=bogus;applied=edited;phase=2;deviation=sideways")
        #expect(read.avg7 == nil)
        #expect(read.logged == 7)
        #expect(read.ratings.hunger == 5)
        #expect(read.ratings.mood == 1)
        #expect(read.verdict == nil)
        #expect(read.deviation == nil)
        #expect(read.decision == .edited)
        #expect(read.phaseID == "2")
        #expect(CheckInSnapshot(day: checkInDay("2030-02-04"), values: "", meta: "") == CheckInSnapshot(day: checkInDay("2030-02-04")))
    }

    @Test func recordsTheWeekAndTheResult() {
        var snapshot = CheckInSnapshot(day: checkInDay("2030-02-04"))
        var week = Adherence.summary(AdherenceTests.week, plan: CheckInFixture.plan())
        week.ratings = CheckInRatings(sleep: 2, performance: 4)
        snapshot.record(week)
        #expect(snapshot.days == 6)
        #expect(snapshot.logged == 5)
        #expect(snapshot.onPlan == 3)
        #expect(snapshot.kcalAvg == 2730)
        #expect(snapshot.kcalTarget == 2680)
        #expect(snapshot.proteinDays == 4)
        #expect(snapshot.proteinMeals == 17)
        #expect(snapshot.proteinMealsTarget == 24)
        #expect(snapshot.ratings.sleep == 2)
        let f = CheckInFixture.self
        let result = CheckInEngine.evaluate(f.input(rate: 0.05, history: [f.previous(.below, on: "2030-01-28")]), calendar: checkInUTC)
        snapshot.record(result, phaseID: "1")
        #expect(snapshot.verdict == .offTarget)
        #expect(snapshot.deviation == .below)
        #expect(snapshot.deltaKcal == 100)
        #expect(snapshot.decisionText == "Off track")
        snapshot.decision = .kept
        #expect(snapshot.decisionText == "Kept")
        snapshot.decision = .edited
        snapshot.deltaKcal = -50
        #expect(snapshot.decisionText == "−50 kcal")
        // A snapshot from this week feeds the next check-in's two-in-a-row rule.
        let next = CheckInEngine.evaluate(f.input(rate: 0.05, history: [snapshot], day: checkInDay("2030-02-11")), calendar: checkInUTC)
        #expect(next.outsideInARow == 2)
        // Ratings by key stay within 1–5.
        var ratings = CheckInRatings()
        ratings["stress"] = 7
        ratings["unknown"] = 3
        #expect(ratings.stress == 5)
        #expect(ratings["unknown"] == nil)
        #expect(CheckInRatings(digestion: -2).digestion == 1)
    }
}
