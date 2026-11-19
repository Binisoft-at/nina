import Foundation
import Testing
@testable import NinaCore

// Made-up numbers, nothing from a real person: 80 kg; gym Mon/Wed/Fri 2600 kcal, rest 2400
// (protein 160 g); a gain phase of +0.10 to +0.20 kg/week from Mon 2030-01-07, review at 82–83 kg.
// The scale rises 0.05 kg a week. Check-in on Mon 2030-02-04.

private var glueUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func glueDay(_ raw: String) -> DayKey { DayKey(raw)! }

private enum GlueFixture {
    static let gym = DailyTargets(energy: 2600, protein: 160, carbs: 310, fat: 80)
    static let rest = DailyTargets(energy: 2400, protein: 160, carbs: 260, fat: 80)
    static let start = glueDay("2030-01-07")
    static let checkIn = glueDay("2030-02-04")

    static func plan(rateMin: Double = 0.1, rateMax: Double = 0.2) -> CoachPlan {
        CoachPlan(
            dayTypes: [
                .init(id: "gym", name: "Gym", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
                .init(id: "rest", name: "Rest", schedule: .default),
            ],
            phases: [
                .init(id: "1", name: "Lean gain", goal: .gain, start: start, rateMin: rateMin, rateMax: rateMax,
                      reviewMin: 82, reviewMax: 83, startedAt: start.date(calendar: glueUTC), status: .active,
                      revisions: [.init(from: start, baseline: gym, byType: ["gym": gym, "rest": rest], reason: "import")]),
            ]
        )
    }

    /// One 07:00 weigh-in a day from the phase start through `end`, rising `perWeek` kg a week from 80.
    static func readings(through end: DayKey = checkIn, perWeek: Double = 0.05, from first: Double = 80,
                         source: (DayKey) -> WeightSignal.Reading.Source = { _ in .nina }) -> [WeightSignal.Reading] {
        DayKey.range(start, through: end, calendar: glueUTC).enumerated().map { index, day in
            WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: glueUTC),
                                 kilograms: first + Double(index) * perWeek / 7, source: source(day))
        }
    }

    static func signal(_ readings: [WeightSignal.Reading]) -> WeightSignal {
        WeightSignal(readings, calendar: glueUTC)
    }

    /// Every adherence day logged, 20 kcal under the day's target, protein reached.
    static func adherence(_ days: [DayKey], plan: CoachPlan) -> AdherenceSummary {
        Adherence.summary(days.map { day in
            let targets = plan.targets(on: day, marks: [:], fallback: rest, calendar: glueUTC)
            return DayAdherence(day: day, dayTypeID: plan.dayType(on: day, marks: [:], calendar: glueUTC)?.id, isLogged: true,
                                energy: targets.energy - 20, protein: targets.protein, targets: targets)
        }, plan: plan)
    }
}

@Suite("Coach glue")
struct CoachGlueTests {
    @Test func weightSignalFeedsTheCheckIn() {
        let plan = GlueFixture.plan()
        let signal = GlueFixture.signal(GlueFixture.readings())
        var input = CheckInInput(day: GlueFixture.checkIn, plan: plan, fallback: GlueFixture.rest,
                                 history: [CheckInSnapshot(day: glueDay("2030-01-28"), verdict: .slower, deviation: .below, phaseID: "1")],
                                 sex: .male)
        input.use(signal: signal)
        // The window: the last 21 days (Tue 15 Jan – Mon 4 Feb), all weighed.
        #expect(input.windowStart == glueDay("2030-01-15"))
        #expect(input.windowDays == 21)
        #expect(input.weighIns == 21)
        #expect(input.rate.map { abs($0 - 0.05) < 1e-9 } == true)
        #expect(input.weightKg > 80 && input.weightKg < 81)
        #expect(!input.checkpointReached)

        // Adherence covers the window up to Sunday; "How it went" is the 7 days before Monday.
        let days = input.adherenceDays(calendar: glueUTC)
        #expect(days.first == glueDay("2030-01-15"))
        #expect(days.last == glueDay("2030-02-03"))
        #expect(days.count == 20)
        let week = input.weekDays(calendar: glueUTC)
        #expect(week == DayKey.range(glueDay("2030-01-28"), through: glueDay("2030-02-03"), calendar: glueUTC))
        input.use(window: GlueFixture.adherence(days, plan: plan), week: GlueFixture.adherence(week, plan: plan))
        #expect(input.countedDays == 20)
        #expect(input.loggedDays == 20)

        // Slower twice in a row: +100 kcal (rule 5: (0.15 − 0.05) × 1,100 = 110 → 100).
        let result = CheckInEngine.evaluate(input, calendar: glueUTC)
        #expect(result.rule == .proposal)
        #expect(result.deviation == .below)
        #expect(result.delta == 100)
    }

    @Test func howItWentStartsWhenThePlanWasSetUp() throws {
        // Set up on Thursday 10 Jan (import), every day since on plan; first check-in Monday 14 Jan.
        let thursday = glueDay("2030-01-10"), monday = glueDay("2030-01-14")
        var plan = GlueFixture.plan()
        plan.phases[0].start = thursday
        plan.phases[0].startedAt = thursday.date(minutes: 6 * 60 + 30, calendar: glueUTC)
        plan.phases[0].revisions[0].from = thursday
        var input = CheckInInput(day: monday, plan: plan, fallback: GlueFixture.rest)
        input.use(signal: GlueFixture.signal(GlueFixture.readings(through: monday).filter { $0.day >= thursday }))
        let week = input.weekDays(calendar: glueUTC)
        #expect(week == DayKey.range(thursday, through: glueDay("2030-01-13"), calendar: glueUTC))
        let summary = GlueFixture.adherence(week, plan: plan)
        #expect(summary.days == 4)
        #expect(summary.loggedDays == 4)
        #expect(summary.grade == .good)
        input.use(window: GlueFixture.adherence(input.adherenceDays(calendar: glueUTC), plan: plan), week: summary)
        let result = CheckInEngine.evaluate(input, calendar: glueUTC)
        #expect(result.rule == .gathering)
        #expect(result.status == .onTrack)
        // The week after: the full 7 days; a check-in on the set-up day has no "How it went" yet.
        var later = CheckInInput(day: glueDay("2030-01-21"), plan: plan, fallback: GlueFixture.rest)
        later.use(signal: GlueFixture.signal([]))
        #expect(later.weekDays(calendar: glueUTC).count == 7)
        let setUpDay = CheckInInput(day: thursday, plan: plan, fallback: GlueFixture.rest)
        #expect(setUpDay.weekDays(calendar: glueUTC).isEmpty)
    }

    @Test func tooFewWeighInsKeepGathering() {
        let plan = GlueFixture.plan()
        // Only the last 9 mornings weighed.
        let readings = GlueFixture.readings().filter { $0.day >= glueDay("2030-01-27") }
        var input = CheckInInput(day: GlueFixture.checkIn, plan: plan, fallback: GlueFixture.rest)
        input.use(signal: GlueFixture.signal(readings))
        #expect(input.weighIns == 9)
        #expect(input.windowDays == 9)
        let result = CheckInEngine.evaluate(input, calendar: glueUTC)
        #expect(result.rule == .gathering)
        #expect(result.verdict == .gathering)
    }

    @Test func checkpointStopsTheCheckInUntilReviewed() throws {
        let plan = GlueFixture.plan()
        // Rising 0.7 kg a week from 80: the 7-day average passes 82 kg in week 4.
        let signal = GlueFixture.signal(GlueFixture.readings(perWeek: 0.7))
        let crossing = signal.checkpointCrossing(in: plan, through: GlueFixture.checkIn)
        #expect(crossing != nil)
        // The schedule's review checkpoint reads the same averages and finds the same day.
        let history = signal.averageHistory(from: GlueFixture.start, through: GlueFixture.checkIn)
        #expect(BodySchedule.checkpointCrossed(avg7History: history, phase: plan.phases[0]) == crossing)

        var input = CheckInInput(day: GlueFixture.checkIn, plan: plan, fallback: GlueFixture.rest)
        input.use(signal: signal)
        #expect(input.checkpointReached)
        #expect(CheckInEngine.evaluate(input, calendar: glueUTC).verdict == .checkpoint)
        let crossed = try #require(crossing)
        // A decision on the crossing day (or later) ends it; one from before (a ceiling review) doesn't.
        input.use(signal: signal, reviews: ["1": crossed])
        #expect(!input.checkpointReached)
        #expect(CheckInEngine.evaluate(input, calendar: glueUTC).verdict != .checkpoint)
        input.use(signal: signal, reviews: ["1": crossed.adding(days: -1, calendar: glueUTC)])
        #expect(input.checkpointReached)
        #expect(CheckInEngine.evaluate(input, calendar: glueUTC).verdict == .checkpoint)
    }

    @Test func statusAndVerdictUseTheSameWords() {
        let gain = GlueFixture.plan().phases[0]
        var cut = gain
        cut.goal = .lose
        cut.rateMin = 0.3
        cut.rateMax = 0.5
        var hold = gain
        hold.goal = .maintain
        hold.rateMin = 0
        hold.rateMax = 0
        for phase in [gain, cut, hold] {
            for rate in stride(from: -0.8, through: 0.8, by: 0.05) {
                let status = WeightSignal.status(rate: rate, phase: phase)
                let deviation = CheckInEngine.deviation(rate: rate, phase: phase)
                let verdict = deviation.map { CheckInEngine.verdict(for: $0, goal: phase.goal) } ?? .inRange
                #expect(status.map(CheckInVerdict.init) == verdict, "\(phase.goal) at \(rate)")
            }
        }
    }

    @Test func aPhaseWithoutARateGetsNoProposal() {
        let plan = GlueFixture.plan(rateMin: 0, rateMax: 0)
        var input = CheckInInput(day: GlueFixture.checkIn, plan: plan, fallback: GlueFixture.rest,
                                 history: [CheckInSnapshot(day: glueDay("2030-01-28"), verdict: .faster, deviation: .above, phaseID: "1")])
        input.use(signal: GlueFixture.signal(GlueFixture.readings()))
        let result = CheckInEngine.evaluate(input, calendar: glueUTC)
        #expect(result.rule == .noRate)
        #expect(result.delta == 0)
        #expect(WeightSignal.status(rate: input.rate, phase: plan.phases[0]) == nil)
    }

    @Test func snapshotTakesTheWeightNumbers() {
        let plan = GlueFixture.plan()
        var typed = CheckInSnapshot(day: GlueFixture.checkIn)
        typed.record(GlueFixture.signal(GlueFixture.readings()), plan: plan)
        #expect(typed.avg7 != nil)
        #expect(typed.prevAvg7 != nil)
        #expect(typed.rate.map { abs($0 - 0.05) < 1e-9 } == true)
        #expect(typed.weighIns == 21)
        #expect(!typed.usesHealthWeights)
        #expect(typed.values.contains("avg7="))

        // One Health weight in the week before: the weight numbers stay out of the stored mark.
        let health = GlueFixture.readings { $0 == glueDay("2030-01-29") ? .health : .nina }
        var live = CheckInSnapshot(day: GlueFixture.checkIn)
        live.record(GlueFixture.signal(health), plan: plan)
        #expect(live.usesHealthWeights)
        #expect(!live.values.contains("avg7"))
        #expect(live.meta.contains("source=health"))
    }

    @Test func compositionWeighsWithTheMorningWeights() {
        // Flat 80 kg around a 20 % reading: 16 kg fat, 64 kg lean.
        let signal = GlueFixture.signal(GlueFixture.readings(perWeek: 0))
        #expect(signal.morningWeights.count == 29)
        let reading = BodyFatReading(day: glueDay("2030-01-20"), bodyFat: 20, method: .bodpod)
        let points = signal.compositionPoints([reading], today: GlueFixture.checkIn)
        #expect(points.count == 1)
        #expect(points.first.map { abs($0.composition.fatKg - 16) < 1e-9 } == true)
        #expect(points.first.map { abs($0.composition.leanKg - 64) < 1e-9 } == true)
        #expect(points.first?.weight?.source == .morningAverage)
    }

    @Test func proteinMealsCountAsThePillShowsThem() {
        // 34.7 g shows as "35 / 35 g": a protein meal for the pill and for adherence alike.
        let byMeal: [String: NutrientValues] = ["breakfast": NutrientValues([.protein: 34.7]), "lunch": NutrientValues([.protein: 20])]
        #expect(Adherence.proteinMeals(byMeal: byMeal, minimum: 35, meals: ["breakfast", "lunch"]) == 1)
        let rule = ProteinMeals.Rule(minimum: 35, meals: ["breakfast", "lunch"])
        let time = GlueFixture.checkIn.date(minutes: 8 * 60, calendar: glueUTC)
        let totals = DayTotals(day: GlueFixture.checkIn, entries: [
            EntryFacts(day: GlueFixture.checkIn, meal: "breakfast", nutrients: NutrientValues([.energy: 400, .protein: 34.7]),
                       name: "Made-up breakfast", time: time),
            EntryFacts(day: GlueFixture.checkIn, meal: "lunch", nutrients: NutrientValues([.energy: 500, .protein: 20]),
                       name: "Made-up lunch", time: time),
        ])
        #expect(ProteinMeals.day(totals, rule: rule).count == 1)
        let adherence = DayAdherence(totals: totals, targets: GlueFixture.rest, proteinMinimum: 35, proteinMealCount: 2,
                                     proteinMealIDs: ["breakfast", "lunch"])
        #expect(adherence.proteinMeals == 1)
    }
}
