import Foundation
import Testing
@testable import NinaCore

// A coaching scenario end to end, with made-up numbers (78 kg, dates in 2030), nothing from a
// real person. Mirrors the app's glue: SettingsCSV import -> NinaStore.applySettings (plan +
// mirror, body records, weight), CoachContext.load (signal, schedule, board, review decisions),
// CheckInEvaluation.evaluate (the recipe), NinaStore.applyCheckIn, the check-in's Redo
// (AppModel.checkInCommit), PhaseReviewSheet "Start fat loss now" (PhaseSheetPlan.starting).
// The oracle below encodes the spec's rules independently of the engine.

private var cal: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func d(_ raw: String) -> DayKey { DayKey(raw)! }

private let settingsFile = """
setting,value
weight_kg,78
activity,moderate
goal,gain
rate_kg_per_week,0.1-0.2
target_weight_kg,81
macro_split,24/50/26
calories,2700
protein_g,160
carbs_g,335
fat_g,80
fiber_g,30
water_ml,2500
focus_nutrients,protein;carbs;fat;fiber
body_fat_percent,18
body_fat_method,estimate
long_term.weight_kg,77
long_term.body_fat_percent,14
long_term.note,Stronger and leaner
day_type.gym.name,Gym
day_type.gym.days,mon;wed;fri
day_type.gym.workouts,strength
day_type.tennis.name,Tennis
day_type.tennis.days,flexible
day_type.tennis.per_week,2
day_type.tennis.workouts,tennis
day_type.rest.name,Rest
day_type.rest.days,default
phase.1.name,Muscle building
phase.1.goal,gain
phase.1.start,2030-01-03
phase.1.end,~2030-05-15
phase.1.rate_kg_per_week,0.1-0.2
phase.1.review_weight_kg,80.5-81
phase.1.target_weight_kg,81
phase.1.gym.calories,2700
phase.1.gym.macros_g,160/335/80
phase.1.tennis.calories,2900
phase.1.tennis.macros_g,160/385/80
phase.1.rest.calories,2500
phase.1.rest.macros_g,160/285/80
phase.2.name,Fat loss
phase.2.goal,lose
phase.2.start,~2030-06
phase.2.end,~2030-08
phase.2.target_weight_kg,77
phase.2.target_body_fat_percent,14
checkin.day,mon
checkin.adjust_after_weeks,2-3
checkin.step_kcal,100-150
measure.weigh_in,daily 07:00
measure.weekly,waist
measure.full,waist;chest;arm;thigh;hip
measure.full_every_weeks,8
measure.body_fat_every_weeks,8
check.creatine.name,Creatine monohydrate
check.creatine.dose,3-5 g
check.creatine.when,breakfast
check.creatine.optional,yes
meal_protein_g,35-45
protein_meals,4
note,An extra gym session counts as a gym day.
note,Keep the rest days easy.
note,The fat-loss start depends on how the gain goes.
"""

/// The app's state, reduced to plain values (what the store holds).
private struct World {
    var plan = CoachPlan()
    var state: SettingsState
    var weights: [WeightSignal.Reading] = []
    var tape: [BodyTapeRecord] = []
    var assessmentDays: [DayKey] = []
    var marks: [String: String] = [:]
    var checkStates: [DayKey: [String: CheckState]] = [:]
    var facts: [DayKey: [EntryFacts]] = [:]
    var water: [DayKey: Double] = [:]
    var checkIns: [CheckInSnapshot] = []
    var phaseEvents: [(phaseID: String, event: PhaseEvent, day: DayKey)] = []
    var dismissed: [String: DayKey] = [:]

    var ticks: [(day: DayKey, checkID: String)] {
        checkStates.flatMap { day, states in states.filter { $0.value == .done }.map { (day: day, checkID: $0.key) } }
    }

    /// NinaStore.phaseReviews: the newest review decision per phase.
    var reviews: PhaseReviews { PhaseReviews(events: phaseEvents) }

    func signal() -> WeightSignal {
        WeightSignal(weights, cutoffMinutes: plan.routine.morningCutoffMinutes, dayStartHour: 0, calendar: cal)
    }

    /// NinaStore.writePlan: plan + mirror on `day`.
    mutating func savePlan(_ new: CoachPlan, on day: DayKey) {
        plan = new
        var copy = state
        copy.plan = new
        if let mirror = new.mirror(on: day) {
            copy.trainingTargets = state.trainingTargets
            copy = mirror.applied(to: copy)
        }
        state = copy
    }

    /// NinaSettings.legacyTargets.
    func legacyTargets(for day: DayKey) -> DailyTargets {
        if let training = state.trainingTargets, state.trainingDays.contains(day, calendar: cal) { return training }
        return state.targets
    }

    func body(today: DayKey) -> BodyProfile {
        BodyProfile(sex: state.sex, age: 35, heightCm: state.heightCm,
                    weightKg: signal().bodyWeight(on: today)?.kilograms ?? 72, activity: state.activity,
                    goal: state.goal, ratePerWeek: state.ratePerWeek)
    }

    func totals(from start: DayKey, through end: DayKey) -> [DayKey: DayTotals] {
        var result: [DayKey: DayTotals] = [:]
        guard start <= end else { return result }
        for day in DayKey.range(start, through: end, calendar: cal) {
            result[day] = DayTotals(day: day, entries: facts[day] ?? [], water: water[day] ?? 0)
        }
        return result
    }

    func schedule(today: DayKey) -> BodySchedule {
        BodySchedule(plan: plan, start: BodySchedule.setUpDay(of: plan, calendar: cal), tape: tape,
                     assessmentDays: assessmentDays, checkpoint: signal().checkpointCrossing(in: plan, through: today))
    }

    /// NinaStore.coachBoard.
    func board(day: DayKey, today: DayKey, now: Date, ceilings: [BodyCeiling] = []) -> CoachBoard {
        let signal = signal()
        let has = signal.morning(on: today) != nil
        let schedule = schedule(today: today)
        let monday = day.startOfWeek(calendar: cal)
        var eaten: [DayKey: Double] = [:]
        for (key, totals) in self.totals(from: monday, through: min(today, monday.adding(days: 6, calendar: cal))) where totals.isLogged {
            eaten[key] = totals.eaten.energy
        }
        let input = CoachBoard.Input(
            plan: plan, day: day, today: today, now: now, mealSlots: MealSlot.defaults, fallback: legacyTargets(for: day),
            dayTypeMarks: marks, checkStates: checkStates[day] ?? [:], hasMorningWeighIn: has,
            bodyItems: CoachBoard.bodyItems(schedule, on: day, today: today, now: now, hasMorningWeighIn: has, calendar: cal),
            checkInKeys: Set(checkIns.map { $0.key(calendar: cal) }), checkpoint: signal.checkpointCrossing(in: plan, through: today),
            ceilings: ceilings, reviews: reviews, dismissed: dismissed, eaten: eaten, calendar: cal)
        return CoachBoard(input)
    }

    func maintenance(on end: DayKey) -> Insights.Maintenance? {
        let totals = self.totals(from: end.adding(days: -27, calendar: cal), through: end)
        return Insights.maintenance(totals: totals.values.sorted { $0.day < $1.day }, weights: signal().morningWeights,
                                    today: end, calendar: cal)
    }

    struct Evaluation {
        var day: DayKey
        var input: CheckInInput
        var result: CheckInResult
        var snapshot: CheckInSnapshot
        var window: AdherenceSummary
        var week: AdherenceSummary
    }

    /// CheckInEvaluation.evaluate, line by line.
    func evaluate(week: DayKey, today: DayKey) -> Evaluation {
        let signal = signal()
        let monday = week.startOfWeek(calendar: cal)
        let scheduled = CheckInEngine.nextCheckIn(onOrAfter: monday, weekday: plan.routine.checkInWeekday, calendar: cal)
        let day = scheduled <= today ? scheduled : max(today, monday)
        let key = DayMarks.checkInKey(week: day, calendar: cal)
        let phase = plan.activePhase(on: day)
        let history = checkIns.filter { $0.key(calendar: cal) != key }
        var input = CheckInInput(day: day, plan: plan, fallback: state.targets, history: history,
                                 weightCheck: CheckInEngine.weightCheck(in: plan, ticks: ticks),
                                 bmr: GoalCalculator.bmr(body(today: today)), sex: state.sex)
        input.use(signal: signal, reviews: reviews)
        let windowKeys = input.adherenceDays(calendar: cal)
        let weekKeys = input.weekDays(calendar: cal)
        let start = min(windowKeys.first ?? day, weekKeys.first ?? day, day.adding(days: -27, calendar: cal))
        let totals = self.totals(from: start, through: day)
        input.maintenance = Insights.maintenance(totals: totals.values.sorted { $0.day < $1.day }, weights: signal.morningWeights,
                                                 today: day, calendar: cal)
        let weightKg = input.weightKg
        func adherence(_ date: DayKey) -> DayAdherence {
            let done = Set((checkStates[date] ?? [:]).filter { $0.value == .done }.map(\.key))
            return DayAdherence(plan: plan, totals: totals[date] ?? DayTotals(day: date, entries: []), marks: marks,
                                fallback: legacyTargets(for: date), weightKg: weightKg, mealSlots: MealSlot.defaults.count,
                                doneChecks: done, incomplete: false, calendar: cal)
        }
        let windowSummary = Adherence.summary(windowKeys.map { adherence($0) }, plan: plan)
        let weekSummary = Adherence.summary(weekKeys.map { adherence($0) }, plan: plan)
        input.use(window: windowSummary, week: weekSummary)
        let result = CheckInEngine.evaluate(input, calendar: cal)
        var snapshot = CheckInSnapshot(day: day)
        snapshot.record(signal, plan: plan)
        snapshot.record(weekSummary)
        snapshot.record(result, phaseID: phase?.id ?? "")
        return Evaluation(day: day, input: input, result: result, snapshot: snapshot, window: windowSummary, week: weekSummary)
    }

    mutating func save(_ snapshot: CheckInSnapshot) {
        let key = snapshot.key(calendar: cal)
        checkIns.removeAll { $0.key(calendar: cal) == key }
        checkIns.append(snapshot)
        checkIns.sort { $0.day < $1.day }
    }

    /// NinaStore.applyCheckIn (from = today + 1 as CheckInEvaluation.applyFrom); the mirror
    /// follows the revision it adds.
    mutating func apply(_ evaluation: Evaluation, today: DayKey) {
        let delta = evaluation.result.delta
        let from = today.adding(days: 1, calendar: cal)
        let new = CheckInEngine.applying(delta, to: plan, from: from, weightKg: evaluation.input.weightKg, fallback: state.targets)
        savePlan(new, on: max(from, today))
        var decided = evaluation.snapshot
        decided.decision = .applied
        decided.deltaKcal = delta
        save(decided)
    }
}

// MARK: - Spec oracle (independent of the engine)

private struct Oracle {
    enum Outcome: Equatable, CustomStringConvertible {
        case gathering(first: DayKey)
        case checkpoint
        case gate
        case inRange
        case confirming(above: Bool)
        case locked
        case hold
        case proposal(Double)
        var description: String {
            switch self {
            case .gathering(let first): return "gathering(first: \(first))"
            case .checkpoint: return "checkpoint"
            case .gate: return "gate"
            case .inRange: return "inRange"
            case .confirming(let above): return "confirming(\(above ? "above" : "below"))"
            case .locked: return "locked"
            case .hold: return "hold"
            case .proposal(let delta): return "proposal(\(delta))"
            }
        }
    }

    static func outcome(world: World, day: DayKey, rateOut: inout Double?) -> Outcome {
        let plan = world.plan
        guard let phase = plan.activePhase(on: day), let start = phase.start else { return .gate }
        // F4 window: last 21 days, not before phase start, last applied adjustment (in force).
        let lastApplied = phase.revisions.filter { $0.reason.hasPrefix("adjust") && $0.from <= day }.map(\.from).max()
        var windowStart = day.adding(days: -20, calendar: cal)
        windowStart = max(windowStart, start)
        if let lastApplied { windowStart = max(windowStart, lastApplied) }
        // Morning weights: earliest weigh-in of the day before 11:00, untagged.
        var points: [(x: Double, y: Double)] = []
        var first: DayKey?, last: DayKey?
        for date in DayKey.range(windowStart, through: day, calendar: cal) {
            let ofDay = world.weights.filter { $0.day == date }.sorted { $0.time < $1.time }
            guard let earliest = ofDay.first, ClockTime.minutes(of: earliest.time, calendar: cal) < 660 else { continue }
            guard !earliest.note.contains("#") else { continue }
            points.append((x: Double(windowStart.days(to: date, calendar: cal)), y: earliest.kilograms))
            if first == nil { first = date }
            last = date
        }
        let span = (first != nil && last != nil) ? first!.days(to: last!, calendar: cal) + 1 : 0
        var rate: Double?
        if points.count >= 2 {
            let mx = points.map(\.x).reduce(0, +) / Double(points.count)
            let my = points.map(\.y).reduce(0, +) / Double(points.count)
            var sxy = 0.0, sxx = 0.0
            for p in points { sxy += (p.x - mx) * (p.y - my); sxx += (p.x - mx) * (p.x - mx) }
            rate = sxx > 0 ? sxy / sxx * 7 : nil
        }
        rateOut = rate
        // F5 checkpoint (7-day average >= lower review bound), unless a review decision was made
        // on or after the day it was reached (a ceiling review before that doesn't count).
        if let crossed = world.signal().checkpointCrossing(of: phase, through: day) {
            let reviewDays = world.phaseEvents
                .filter { $0.phaseID == phase.id && [.reviewKeep, .reviewHold, .reviewCut].contains($0.event) }.map(\.day)
            if !reviewDays.contains(where: { $0 >= crossed }) { return .checkpoint }
        }
        guard let rate, span >= 14, points.count >= 10 else {
            let valid = windowStart.adding(days: 13, calendar: cal)
            let earliest = max(valid, day.adding(days: 1, calendar: cal))
            let offset = (1 - earliest.weekday(calendar: cal) + 7) % 7
            return .gathering(first: earliest.adding(days: offset, calendar: cal))
        }
        // Adherence gate over the window up to the day before.
        let days = windowStart <= day.adding(days: -1, calendar: cal)
            ? DayKey.range(windowStart, through: day.adding(days: -1, calendar: cal), calendar: cal) : []
        var logged = 0, intake = 0.0, target = 0.0
        for date in days {
            let totals = DayTotals(day: date, entries: world.facts[date] ?? [])
            guard totals.isLogged else { continue }
            logged += 1
            intake += totals.eaten.energy
            target += plan.targets(on: date, marks: world.marks, fallback: world.state.targets, calendar: cal).energy
        }
        if days.isEmpty || Double(logged) < 0.8 * Double(days.count) - 1e-9 { return .gate }
        if abs(intake / Double(logged) - target / Double(logged)) > 150 { return .gate }
        // Range with the 0.03 tolerance.
        let low = phase.rateMin - 0.03, high = phase.rateMax + 0.03
        if rate >= low && rate <= high { return .inRange }
        let above = rate > high
        // The previous check-in of this phase since the last change, outside on the same side.
        func previousDay(_ s: CheckInSnapshot) -> DayKey { s.day }
        let previous = world.checkIns.filter { (snap: CheckInSnapshot) -> Bool in
            snap.day < day && snap.phaseID == phase.id && (lastApplied.map { a in snap.day >= a } ?? true)
        }.max { $0.day < $1.day }
        guard let previous, previous.deviation == (above ? .above : .below) else { return .confirming(above: above) }
        if let lastApplied, lastApplied.days(to: day, calendar: cal) < 14 { return .locked }
        if above, let creatine = world.ticks.filter({ $0.checkID == "creatine" }).map(\.day).min(),
           creatine.days(to: day, calendar: cal) < 28 { return .hold }
        let mid = (phase.rateMin + phase.rateMax) / 2
        let raw = (mid - rate) * 1100
        let size = min(max((abs(raw) / 50).rounded() * 50, 100), 150)
        return .proposal(raw < 0 ? -size : size)
    }
}

// MARK: - The simulation

@Suite("Coach scenario (made-up numbers)")
struct CoachScenarioTests {
    /// True weight on day index `i` (0 = 2030-01-03).
    static func trueWeight(_ i: Int) -> Double {
        let slow = 0.04 / 7, fast = 0.35 / 7, inRange = 0.15 / 7
        if i < 26 { return 78.0 + Double(i) * slow }
        let w26 = 78.0 + 26 * slow
        if i < 61 { return w26 + Double(i - 26) * fast }
        let w61 = w26 + 35 * fast
        return w61 + Double(i - 61) * inRange
    }

    /// Small deterministic noise, mean ~0 (morning-after-tennis bumps included).
    static func noise(_ i: Int) -> Double {
        let pattern = [0.10, -0.05, 0.02, -0.12, 0.06, -0.02, 0.01, -0.08, 0.09, -0.01, 0.03, -0.06, 0.05, -0.04]
        return pattern[i % pattern.count]
    }

    @Test func scenarioEndToEnd() {
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("SCN " + s) }

        let start = d("2030-01-03")
        let importNow = start.date(minutes: 6 * 60 + 30, calendar: cal)
        // The profile before: sex, birth year and height set in Goals (not in the settings file).
        let previous = SettingsState(sex: .male, birthYear: 1995, heightCm: 176)

        // 1. Import (ImportPreview.make + NinaStore.applySettings).
        let draft = SettingsCSV.parse(settingsFile)
        note("skipped: \(draft.skipped) wishes: \(draft.wishes)")
        #expect(draft.skipped.isEmpty, "a full plan file: rows skipped \(draft.skipped)")
        #expect(draft.wishes.isEmpty)
        let result = SettingsCSV.apply(draft, to: previous, year: 2030, today: start, now: importNow, calendar: cal)
        note("import notes: \(result.notes)")
        #expect(result.notes.isEmpty, "import notes on a full plan file: \(result.notes)")
        var world = World(state: previous)
        var state = result.state
        state.plan = previous.plan
        world.state = state
        world.savePlan(result.state.plan ?? CoachPlan(), on: start)
        for record in result.bodyRecords {
            if let tape = record.tapeRecord { world.tape.append(tape) }
            if record.kind == .assessment { world.assessmentDays.append(record.day) }
        }
        if let weight = result.newWeight {
            world.weights.append(WeightSignal.Reading(day: start, time: importNow, kilograms: weight, note: "import"))
        }
        let plan = world.plan
        note("plan dayTypes: \(plan.dayTypes.map { "\($0.id):\($0.schedule.rawValue):\($0.weekdays.days):\($0.perWeek):\($0.emoji)" })")
        #expect(plan.dayTypes.map(\.id) == ["gym", "tennis", "rest"])
        #expect(plan.dayType(id: "gym")?.weekdays.days.sorted() == [1, 3, 5])
        #expect(plan.dayType(id: "tennis")?.schedule == .flexible && plan.dayType(id: "tennis")?.perWeek == 2)
        #expect(plan.dayType(id: "rest")?.schedule == .default)
        let p1 = plan.phase(id: "1"), p2 = plan.phase(id: "2")
        note("p1 start \(String(describing: p1?.start)) end \(String(describing: p1?.end)) approx \(String(describing: p1?.endApprox)) started \(String(describing: p1?.isStarted)) rate \(String(describing: p1?.rateMin))-\(String(describing: p1?.rateMax)) review \(String(describing: p1?.reviewMin))-\(String(describing: p1?.reviewMax)) target \(String(describing: p1?.targetWeight)) waist \(String(describing: p1?.maxWaistGainCm))")
        note("p2 start \(String(describing: p2?.start)) approx \(String(describing: p2?.startApprox)) end \(String(describing: p2?.end)) started \(String(describing: p2?.isStarted)) status \(String(describing: p2?.status)) target \(String(describing: p2?.targetWeight)) bf \(String(describing: p2?.targetBodyFat)) revisions \(String(describing: p2?.revisions.count))")
        #expect(p1?.isStarted == true && p1?.start == start)
        #expect(p1?.end == d("2030-05-15") && p1?.endApprox == true)
        #expect(p1?.rateMin == 0.1 && p1?.rateMax == 0.2)
        #expect(p1?.reviewMin == 80.5 && p1?.reviewMax == 81)
        #expect(p2?.isStarted == false && p2?.start == d("2030-06-01") && p2?.startApprox == true)
        #expect(p2?.end == d("2030-08-31") && p2?.endApprox == true)
        let rev = p1?.revision(on: start)
        note("p1 rev from \(String(describing: rev?.from)) baseline \(String(describing: rev?.baseline?.energy)) types \(rev?.byType.mapValues { "\($0.energy)/\($0.protein)/\($0.carbs)/\($0.fat)" } ?? [:])")
        #expect(rev?.byType["gym"]?.energy == 2700 && rev?.byType["gym"]?.carbs == 335)
        #expect(rev?.byType["tennis"]?.energy == 2900 && rev?.byType["tennis"]?.carbs == 385)
        #expect(rev?.byType["rest"]?.energy == 2500 && rev?.byType["rest"]?.carbs == 285)
        #expect(plan.plannedWeekAverage(rev!) == 2700)
        let creatine = plan.check(id: "creatine")
        note("creatine: \(String(describing: creatine))")
        #expect(creatine?.affectsWeight == true, "creatine should hold 'faster' (F11 rule 7)")
        #expect(creatine?.timing == .meal("breakfast"))
        #expect(plan.routine.weeklySites == [.waist])
        #expect(plan.routine.fullEveryWeeks == 8 && plan.routine.bodyFatEveryWeeks == 8 && plan.routine.checkInWeekday == 1)
        #expect(plan.routine.weighInMinutes == 420)
        #expect(plan.adjust.windowMinDays == 14 && plan.adjust.windowMaxDays == 21)
        #expect(plan.adjust.stepMin == 100 && plan.adjust.stepMax == 150)
        #expect(plan.protein.mealMin == 35 && plan.protein.mealMax == 45 && plan.protein.count == 4)
        #expect(plan.notes.count == 3)
        #expect(plan.longTerm.weightKg == 77 && plan.longTerm.bodyFat == 14)
        #expect(world.assessmentDays == [start])
        note("mirror: targets \(world.state.targets.energy) training \(String(describing: world.state.trainingTargets?.energy)) days \(world.state.trainingDays.days) goal \(world.state.goal) rate \(world.state.ratePerWeek) target \(world.state.targetWeight)")
        #expect(world.state.targets.energy == 2500)
        #expect(world.state.trainingTargets?.energy == 2700)
        #expect(abs(world.state.ratePerWeek - 0.15) < 1e-9)

        // F12: the baseline is due on the set-up day; F13 card = baseline.
        let board0 = world.board(day: start, today: start, now: start.date(minutes: 6 * 60 + 40, calendar: cal))
        note("day0 card: \(String(describing: board0.card?.key)) strip: \(board0.strip.map(\.id))")
        #expect(board0.card?.kind == .baseline)
        #expect(board0.strip.map(\.id).first == "body.full" || board0.strip.map(\.id).first == "weighIn")
        #expect(board0.chip?.id == "rest")

        // Baseline full set at 06:45 on day 0.
        world.tape.append(BodyTapeRecord(day: start, time: start.date(minutes: 405, calendar: cal),
                                         values: BodyValues([.waist: 84.0, .chest: 100, .arm: 35, .thigh: 56, .hip: 97]),
                                         conditions: "morning,fasted"))
        let board0b = world.board(day: start, today: start, now: start.date(minutes: 7 * 60, calendar: cal))
        note("day0 after baseline: card \(String(describing: board0b.card?.key)) strip \(board0b.strip.map(\.id))")
        #expect(board0b.card == nil)

        // 2. Day by day.
        let reviewDecisionDay = d("2030-04-15")
        var crossing: DayKey?
        var transitioned = false
        var expected: [DayKey: String] = [
            d("2030-01-07"): "gathering(first: 2030-01-21)",
            d("2030-01-14"): "gathering(first: 2030-01-21)",
            d("2030-01-21"): "confirming(below)",
            // Rule 5: rate +0.03 → (0.15 − 0.03) × 1,100 = 132 → 150.
            d("2030-01-28"): "proposal(150.0)",
            d("2030-02-04"): "gathering(first: 2030-02-11)",
            d("2030-02-11"): "confirming(above)",
            d("2030-02-18"): "hold",
            d("2030-02-25"): "hold",
            d("2030-03-04"): "proposal(-150.0)",
            d("2030-03-11"): "gathering(first: 2030-03-18)",
            d("2030-03-18"): "inRange",
        ]
        let last = 115
        for i in 0..<last {
            let day = start.adding(days: i, calendar: cal)
            let weekday = day.weekday(calendar: cal)
            // Tennis on Tue and Sat (flexible), set the evening before.
            if weekday == 2 || weekday == 6 { world.marks[day.rawValue] = "tennis" }

            // Morning weigh-in at 07:00 (day 0 has the import's 06:30 weight). Skip every 9th day.
            let early = day.date(minutes: 6 * 60 + 30, calendar: cal)
            if i > 0 {
                let before = world.board(day: day, today: day, now: early)
                if weekday == 1 || i % 9 != 4 {
                    #expect(before.strip.first?.id == "weighIn", "\(day): 'Weigh in' first before the cutoff, got \(before.strip.map(\.id))")
                }
                if weekday == 1 {
                    // F13 strip order on a check-in Monday before the weigh-in: weigh in, body, checks.
                    let ids = before.strip.map(\.id)
                    let kinds = before.strip.map(\.kind)
                    let firstCheck = kinds.firstIndex(of: .check) ?? kinds.count
                    let lastBody = kinds.lastIndex(of: .body) ?? -1
                    #expect(lastBody < firstCheck, "\(day): body items before checks \(ids)")
                    #expect(ids.contains("body.weekly") || ids.contains("body.full"), "\(day): waist/full due on the check-in day \(ids)")
                    #expect(before.card?.kind != .checkIn, "\(day): check-in card waits for the weigh-in before the cutoff")
                }
                if i % 9 != 4 || weekday == 1 {
                    var kg = ((CoachScenarioTests.trueWeight(i) + CoachScenarioTests.noise(i)) * 100).rounded() / 100
                    var text = ""
                    if i == 40 { kg += 1.4; text = WeightSignal.Tag.salty.token }
                    world.weights.append(WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: cal),
                                                              kilograms: kg, note: text))
                }
                // A later weigh-in sometimes (left out of everything).
                if i % 11 == 3 {
                    world.weights.append(WeightSignal.Reading(day: day, time: day.date(minutes: 19 * 60, calendar: cal),
                                                              kilograms: CoachScenarioTests.trueWeight(i) + 1.0))
                }
            }

            // Creatine from day 28 (2030-01-31), ticked at breakfast.
            if i >= 28 { world.checkStates[day, default: [:]]["creatine"] = .done }

            // Weekly waist on Mondays (07:10), full sets when due.
            let sched = world.schedule(today: day)
            let due = sched.dueItems(on: day, now: nil, hasMorningWeighIn: true, calendar: cal)
            let fullReason = due.first { $0.kind == .full }?.reason
            let waist = 84.0 + Double(i) * 0.012
            if due.contains(where: { $0.kind == .full }) {
                let full = due.first { $0.kind == .full }!
                note("\(day) full set due (\(full.reason.rawValue), assessment \(full.includesAssessment))")
                world.tape.append(BodyTapeRecord(day: day, time: day.date(minutes: 430, calendar: cal),
                                                 values: BodyValues([.waist: waist, .chest: 100.5, .arm: 35.3, .thigh: 56.3, .hip: 97.2]),
                                                 conditions: "morning,fasted"))
                if full.includesAssessment { world.assessmentDays.append(day) }
            } else if due.contains(where: { $0.kind == .weekly }) {
                world.tape.append(BodyTapeRecord(day: day, time: day.date(minutes: 430, calendar: cal),
                                                 values: BodyValues([.waist: waist]), conditions: "morning,fasted"))
            }
            if due.contains(where: { $0.kind == .assessment }) { world.assessmentDays.append(day) }

            // Meals near the day's targets (4 meals, protein spread).
            let t = world.plan.targets(on: day, marks: world.marks, fallback: world.legacyTargets(for: day), calendar: cal)
            let offset = [-40.0, 30, -10, 55, -60, 20, 0][i % 7]
            let energy = t.energy + offset
            let protein = t.protein + 4
            let fat = t.fat
            let carbs = (energy - protein * 4 - fat * 9) / 4
            var facts: [EntryFacts] = []
            for (index, meal) in ["breakfast", "lunch", "dinner", "snack"].enumerated() {
                let n = NutrientValues([.energy: energy / 4, .protein: protein / 4, .carbs: carbs / 4, .fat: fat / 4, .fiber: 8])
                facts.append(EntryFacts(day: day, meal: meal, nutrients: n, name: "Meal \(index)",
                                        time: day.date(minutes: 8 * 60 + index * 240, calendar: cal)))
            }
            world.facts[day] = facts
            world.water[day] = 2500

            // Today at 12:00: the board.
            let noon = day.date(minutes: 12 * 60, calendar: cal)
            let board = world.board(day: day, today: day, now: noon)
            let signal = world.signal()
            if crossing == nil, let c = signal.checkpointCrossing(in: world.plan, through: day) {
                crossing = c
                let avg = signal.average(on: c).value ?? 0
                let prev = signal.average(on: c.adding(days: -1, calendar: cal)).value ?? 0
                note("checkpoint crossed on \(c): avg7 \(avg) (day before \(prev)) card \(String(describing: board.card?.key))")
                #expect(avg >= 80.5 - 1e-9 && prev < 80.5, "F5: crossing is the first day the 7-day average reaches 80.5")
                #expect(board.card?.kind == .review, "F13: review card from the crossing day")
                // The full set was due that morning (and taken): due at the checkpoint, none in 14 days.
                note("full due at checkpoint: \(String(describing: fullReason))")
                #expect(c == day && fullReason == .checkpoint, "F5/F12: full set due at the checkpoint (none in 14 days)")
                #expect(world.tape.contains { $0.day == c && $0.values.sites.count > 2 })
            }

            if (weekday == 6 || weekday == 2) && i < 20 {
                note("\(day) chip \(String(describing: board.chip?.title)) manual \(String(describing: board.chip?.isManual)) quota \(String(describing: board.chip?.quotaText)) energy \(String(describing: board.chip?.energy)) week \(String(describing: board.weekAverageLine))")
            }
            // Week average line (F3) with 2+ finished logged days this week (today isn't over yet).
            if weekday == 3 && !transitioned {
                #expect(board.weekAverage?.eaten != nil, "\(day): week average after Monday and Tuesday")
                #expect(board.weekAverage?.loggedDays == 2, "\(day): today doesn't count yet")
            }

            // Check-in Mondays (after the phase start).
            if weekday == 1, i > 0, !transitioned {
                let card = board.card
                note("\(day) card: \(String(describing: card?.key)) strip \(board.strip.map(\.id))")
                let evaluation = world.evaluate(week: day, today: day)
                var rate: Double?
                let oracle = Oracle.outcome(world: world, day: day, rateOut: &rate)
                let r = evaluation.result
                note("\(day) CHECK-IN verdict \(r.verdict.rawValue) rule \(r.rule.rawValue) delta \(r.delta) step \(r.step) inARow \(r.outsideInARow) rate(engine) \(String(describing: evaluation.input.rate)) rate(oracle) \(String(describing: rate)) window \(evaluation.input.windowDays)d/\(evaluation.input.weighIns) start \(String(describing: evaluation.input.windowStart)) logged \(evaluation.window.loggedDays)/\(evaluation.window.days) intake \(Int(evaluation.window.averageIntake)) vs \(Int(evaluation.window.averageTarget)) status \(r.status.rawValue) | oracle \(oracle)")
                note("    reason: \(r.reason) notes: \(r.notes)")
                note("    week: days \(evaluation.week.days) logged \(evaluation.week.loggedDays) onPlan \(evaluation.week.onPlanDays) grade \(String(describing: evaluation.week.grade)) weekDays \(evaluation.input.weekDays(calendar: cal).first!)...")
                if day == d("2030-01-07") {
                    #expect(r.status != .offTrack, "first check-in: every day since the plan started was on plan, status \(r.status)")
                }
                // Engine vs oracle.
                let engine: String
                switch r.rule {
                case .gathering: engine = "gathering(first: \(r.firstAdjustmentCheck?.rawValue ?? "?"))"
                case .checkpoint: engine = "checkpoint"
                case .logging, .intake: engine = "gate"
                case .inRange: engine = "inRange"
                case .confirming: engine = "confirming(\(r.deviation == .above ? "above" : "below"))"
                case .locked: engine = "locked"
                case .weightCheckHold: engine = "hold"
                case .proposal: engine = "proposal(\(r.delta))"
                default: engine = r.rule.rawValue
                }
                #expect(engine == oracle.description, "\(day): engine \(engine) vs spec \(oracle)")
                if let want = expected[day] {
                    #expect(engine == want, "\(day): scenario expects \(want), got \(engine)")
                }
                if case .gathering(let first) = oracle {
                    let text = "\(Weekdays.shortNames[first.weekday(calendar: cal) - 1]) \(first.day) "
                    #expect(r.reason.contains(text), "\(day): gathering text names \(first): \(r.reason)")
                }
                if engine == "checkpoint" {
                    #expect(card?.kind == .review, "\(day): review card outranks the check-in card, got \(String(describing: card?.kind))")
                } else {
                    #expect(card?.kind == .checkIn, "\(day): check-in card after the weigh-in, got \(String(describing: card?.key))")
                }
                if r.verdict == .offTarget || r.rule == .weightCheckHold {
                    #expect(r.outsideInARow >= 2)
                }
                if r.rule == .weightCheckHold {
                    let devs: [CheckInEngine.Deviation?] = (world.checkIns.filter { $0.phaseID == "1" } + [evaluation.snapshot]).map(\.deviation)
                    let progressOff = WeightSignal.Status.isOffTrack(deviations: devs, inARow: 2)
                    note("    HOLD words: check-in verdict \(r.verdict.title) / status \(r.status.title); Body page header off track: \(progressOff)")
                    #expect(!(progressOff && r.status != .offTrack), "same words everywhere: Progress says Off track, the check-in says \(r.verdict.title) / \(r.status.title)")
                    #expect(r.notes.first?.contains("Creatine monohydrate started") == true, "creatine caveat line")
                }

                if engine == "checkpoint", day == d("2030-04-08") {
                    // Branch: a waist ceiling (+4 cm since the start) opened the review on 2030-03-18 and
                    // the person tapped "Keep gaining" (PhaseReviewSheet.keep -> review-keep).
                    var branch = world
                    let ceilingDay = d("2030-03-18")
                    let phase1 = branch.plan.activePhase(on: ceilingDay)!
                    let reached = BodyCeiling.reached(phase: phase1, waistChangeSinceStart: 4.2, waistToHeight: 85.6 / 176)
                    let early = branch.board(day: ceilingDay, today: ceilingDay, now: ceilingDay.date(minutes: 7 * 60 + 30, calendar: cal),
                                             ceilings: reached)
                    note("    CEILING branch \(ceilingDay): ceilings \(reached) card \(String(describing: early.card?.title))")
                    branch.phaseEvents.append((phaseID: "1", event: .reviewKeep, day: ceilingDay))
                    let later = branch.evaluate(week: day, today: day)
                    let laterBoard = branch.board(day: day, today: day, now: noon, ceilings: reached)
                    note("    CEILING branch \(day): check-in \(later.result.rule.rawValue) card \(String(describing: laterBoard.card?.key))")
                    #expect(later.result.rule == .checkpoint, "F5: the 7-day average reached the review weight after a ceiling review – the checkpoint review must still fire, got \(later.result.rule)")
                    #expect(laterBoard.card?.kind == .review, "F5: review card at the checkpoint after an earlier ceiling review, got \(String(describing: laterBoard.card?.key))")
                }

                // The person's decision.
                if r.hasProposal, r.rule == .proposal {
                    let before = world.plan.revision(on: day.adding(days: 1, calendar: cal))!
                    world.apply(evaluation, today: day)
                    let after = world.plan.revision(on: day.adding(days: 1, calendar: cal))!
                    #expect(after.from == day.adding(days: 1, calendar: cal), "F11: Apply from tomorrow")
                    #expect(world.plan.revision(on: day)?.from == before.from || world.plan.revision(on: day) == world.plan.phase(id: "1")?.revision(on: day),
                            "F11: today keeps its targets")
                    for type in ["gym", "tennis", "rest"] {
                        let b = before.byType[type]!, a = after.byType[type]!
                        note("    \(type): \(b.energy)/\(b.protein)/\(b.carbs)/\(b.fat) -> \(a.energy)/\(a.protein)/\(a.carbs)/\(a.fat)")
                        #expect(a.energy - b.energy == r.delta, "F11: same Δ for every day type (\(type))")
                        #expect(a.protein >= b.protein, "F11: protein never lowered")
                        #expect(a.fat == b.fat, "F11 gain: all of Δ in carbs (\(type))")
                        let carbs = ((r.delta / 4) / 5).rounded() * 5
                        #expect(a.carbs - b.carbs == carbs, "F11 gain: carbs Δ÷4 rounded to 5 g (\(type)): \(a.carbs - b.carbs)")
                    }
                    // Redo the same week right after Apply (CheckInSheet "Redo Check-in").
                    let redo = world.evaluate(week: day, today: day)
                    note("    REDO after apply: rule \(redo.result.rule.rawValue) verdict \(redo.result.verdict.rawValue) reason \(redo.result.reason)")
                    #expect(redo.result.rule == .locked, "redo after Apply should say targets changed today, got \(redo.result.rule): \(redo.result.reason)")
                    #expect(redo.result.delta == 0 && redo.result.verdict == r.verdict && redo.result.status == r.status)
                    let saved = world.checkIns.first { $0.day == evaluation.day }
                    var redone = redo.snapshot
                    redone.keepAppliedDecision(of: saved)
                    #expect(redone.decision == .applied && redone.deltaKcal == r.delta, "the redo keeps the applied change in the record")
                    #expect(redone.decisionText == saved?.decisionText)
                    world.save(redone)
                    let mirror = world.state.targets.energy
                    note("    mirror after apply (profile targets on \(day)): \(mirror)")
                    #expect(mirror == after.byType["rest"]?.energy, "the profile mirror follows the change from tomorrow")
                } else {
                    var snapshot = evaluation.snapshot
                    snapshot.decision = r.hasProposal ? .kept : nil
                    world.save(snapshot)
                }
            }

            // The review decision: C "Start fat loss now" (phase 2 moves to tomorrow).
            if day == reviewDecisionDay, let crossing, !transitioned {
                let board = world.board(day: day, today: day, now: noon)
                note("review day \(day) card \(String(describing: board.card?.key)) crossing \(crossing)")
                let tomorrow = day.adding(days: 1, calendar: cal)
                do {
                    // Branch A: keep gaining (review-keep): the check-in resumes next Monday.
                    var keep = world
                    keep.phaseEvents.append((phaseID: "1", event: .reviewKeep, day: day))
                    let again = keep.evaluate(week: day, today: day)
                    note("    KEEP branch same-day redo: \(again.result.rule.rawValue) \(again.result.reason)")
                    let boardK = keep.board(day: day, today: day, now: noon)
                    note("    KEEP branch board card \(String(describing: boardK.card?.key))")
                    #expect(boardK.card?.kind != .review)
                    // Branch B: hold (PhaseSheetPlan.holding): a maintain phase from tomorrow at maintenance.
                    var hold = world
                    let id = "3"
                    let nextStart = hold.plan.phase(id: "2")!.start!
                    let holdPhase = CoachPlan.Phase(id: id, name: "Maintenance", goal: .maintain, start: tomorrow,
                                                    end: nextStart.adding(days: -1, calendar: cal), endApprox: true)
                    var copy = hold.plan
                    copy.phases.insert(holdPhase, at: 1)
                    let startedH = copy.starting(phase: id, on: tomorrow, now: noon, calendar: cal)
                    let mH = hold.maintenance(on: day)
                    let propH = PhaseTransition.proposal(for: startedH.phase(id: id)!, in: startedH, on: tomorrow,
                                                         weightKg: hold.signal().bodyWeight(on: day)!.kilograms, maintenance: mH,
                                                         body: hold.body(today: day), fallback: hold.state.targets, calendar: cal)
                    let appliedH = propH.applied(to: startedH)
                    hold.savePlan(appliedH, on: day)
                    let revH = appliedH.phase(id: id)!.revision(on: tomorrow)!
                    note("    HOLD branch: maintenance \(String(describing: mH?.kilocalories)) energy \(propH.energy) shift \(propH.shift) week avg \(String(describing: appliedH.plannedWeekAverage(revH))) types \(revH.byType.mapValues(\.energy))")
                    #expect(abs((appliedH.plannedWeekAverage(revH) ?? 0) - (mH?.kilocalories ?? 0)) <= 10, "F5 hold: at maintenance")
                    let after = hold.evaluate(week: tomorrow.adding(days: 6, calendar: cal), today: tomorrow.adding(days: 6, calendar: cal))
                    note("    HOLD branch next check-in: \(after.result.rule.rawValue) \(after.result.reason)")
                }
                let signal = world.signal()
                let weight = signal.bodyWeight(on: day)!.kilograms
                let maintenance = world.maintenance(on: day)
                let next = world.plan.phase(id: "2")!
                let before = world.plan.revision(on: tomorrow)!
                // PhaseSheetPlan.starting(next.id, in: plan, on: tomorrow, context:)
                let started = world.plan.starting(phase: next.id, on: tomorrow, now: noon, calendar: cal)
                let proposal = PhaseTransition.proposal(for: started.phase(id: "2")!, in: started, on: tomorrow, weightKg: weight,
                                                        maintenance: maintenance, body: world.body(today: day),
                                                        fallback: world.state.targets, calendar: cal)
                let applied = proposal.applied(to: started)
                world.savePlan(applied, on: day)
                world.phaseEvents.append((phaseID: "1", event: .reviewCut, day: day))
                world.phaseEvents.append((phaseID: "2", event: .started, day: day))
                transitioned = true
                note("transition: weight \(weight) maintenance \(String(describing: maintenance?.kilocalories)) \(String(describing: maintenance?.confidence)) source \(proposal.source) rate \(proposal.rateMin)-\(proposal.rateMax) derived \(proposal.rateDerived) adjustment \(proposal.adjustment) energy \(proposal.energy) shift \(proposal.shift) notes \(proposal.notes)")
                let p2 = world.plan.phase(id: "2")!
                let after = p2.revision(on: tomorrow)!
                // F5 rate: (avg7 - target) / weeks, clamped to 0.25–1.0 % BW, ± 0.05.
                let weeks = Double(tomorrow.days(to: d("2030-08-31"), calendar: cal)) / 7
                let raw = (weight - 77) / weeks
                let pct = min(max(raw / weight * 100, 0.25), 1.0)
                let mid = pct * weight / 100
                note("    spec rate mid \(mid) (raw \(raw))")
                #expect(abs((p2.rateMin + p2.rateMax) / 2 - mid) < 0.006, "F5 derived rate midpoint")
                #expect(abs(p2.rateMax - p2.rateMin - 0.10) < 1e-6, "F5 ±0.05 range")
                let base = maintenance.map { ($0.confidence == .medium || $0.confidence == .high) ? $0.kilocalories : 0 } ?? 0
                if base > 0 {
                    let spec = base - ((((p2.rateMin + p2.rateMax) / 2) * 1100) / 50).rounded() * 50
                    #expect(abs(proposal.energy - spec) <= 10, "F5 kcal = maintenance − mid × 1,100: \(proposal.energy) vs \(spec)")
                }
                let newAvg = world.plan.plannedWeekAverage(after) ?? 0
                note("    planned week avg after: \(newAvg)")
                #expect(abs(newAvg - proposal.energy) <= 10, "F5: the new week averages the phase energy")
                var shifts: [Double] = []
                for type in ["gym", "tennis", "rest"] {
                    let b = before.byType[type]!, a = after.byType[type]!
                    note("    \(type): \(b.energy)/\(b.protein)/\(b.carbs)/\(b.fat) -> \(a.energy)/\(a.protein)/\(a.carbs)/\(a.fat)")
                    shifts.append(a.energy - b.energy)
                    #expect(a.protein >= (2.2 * weight - 1e-6).rounded(.up), "F5 cut: protein ≥ 2.2 g/kg (\(type))")
                    #expect(a.fat >= max(0.6 * weight, 0.2 * a.energy / 9) - 1e-6, "F5: fat ≥ max(0.6 g/kg, 20 % of kcal) (\(type))")
                    #expect(a.carbs >= 0)
                    #expect(abs(a.protein * 4 + a.carbs * 4 + a.fat * 9 - a.energy) <= 12, "macros add up (\(type))")
                }
                #expect(Set(shifts).count == 1, "F5: every day type shifted by the same kcal: \(shifts)")
                #expect(world.plan.activePhase(on: day)?.id == "1" && world.plan.activePhase(on: tomorrow)?.id == "2")
                let p1 = world.plan.phase(id: "1")!
                #expect(p1.status == .done && p1.end == day)
                // Tomorrow: targets of phase 2; no phase card; F12 full set at phase start covered.
                let boardT = world.board(day: tomorrow, today: tomorrow, now: tomorrow.date(minutes: 12 * 60, calendar: cal))
                note("    tomorrow card \(String(describing: boardT.card?.key)) strip \(boardT.strip.map(\.id)) chip \(String(describing: boardT.chip?.energy))")
                #expect(boardT.card?.kind != .phaseStart)
            }

            // After the transition: next check-in gathering from the phase-2 start.
            if transitioned, day == d("2030-04-22") {
                let evaluation = world.evaluate(week: day, today: day)
                note("\(day) phase-2 check-in: \(evaluation.result.rule.rawValue) \(evaluation.result.reason)")
                #expect(evaluation.result.rule == .gathering)
                #expect(evaluation.result.firstAdjustmentCheck == d("2030-04-29"), "first adjustment check 13 days after the phase-2 start, Monday")
                var snapshot = evaluation.snapshot
                snapshot.decision = nil
                world.save(snapshot)
            }
        }
        #expect(crossing != nil, "the checkpoint is reached in the scenario")
        #expect(transitioned)
        note("full set days: \(world.tape.filter { $0.values.sites.count > 2 }.map(\.day))")
        note("assessment days: \(world.assessmentDays)")
        let fullDays = world.tape.filter { $0.values.sites.count > 2 }.map(\.day)
        #expect(fullDays.contains(d("2030-02-25")), "F12: full set on the check-in day nearest to baseline + 56 days")
        let history = world.checkIns.map { "\($0.day) \($0.verdict?.rawValue ?? "-") \($0.deviation?.rawValue ?? "-") \($0.decisionText)" }
        note("history: \(history)")
    }
}
