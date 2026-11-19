import Foundation
import SwiftData
import NinaCore

/// Everything the coach screens need for one day, gathered in one go: the plan and day-type
/// marks, the weigh-ins (typed in Nina, plus the ones read live from Apple Health – never
/// stored), the morning weight signal, the measuring schedule and what is due, Today's coach
/// board (chip, checks strip, card, week average), the protein-per-meal rule, the body records
/// and the saved check-ins. With `checkIn: true` also the week's check-in (`CheckInEvaluation`).
///
/// Cheap enough to rebuild on every data change: views build it in
/// `.task(id: "\(app.dataVersion)-\(day)")` and keep it in `@State`.
@MainActor
struct CoachContext {
    private let store: NinaStore
    /// The day it was built for (Today's selected day, or today).
    let day: DayKey
    let today: DayKey
    let now: Date
    /// The app's settings with `bodyWeightKg` from this signal (so `settings.body` is current).
    let settings: NinaSettings
    /// The weigh-ins typed in Nina (live, oldest first).
    let weights: [WeightEntry]
    /// The weigh-ins read live from Apple Health (not the ones Nina wrote). Never store them.
    let healthReadings: [WeightSignal.Reading]
    /// The morning weight signal over both.
    let signal: WeightSignal
    /// The weight card numbers on `day`: 7-day average, rate, status, corridor, checkpoint …
    let summary: WeightSignal.Summary
    /// When to measure: weekly sites, full sets, assessments.
    let schedule: BodySchedule
    /// The body items due on `day` (the weigh-in only on today, until the morning cutoff).
    let dueItems: [BodyDueItem]
    /// Today's coach parts for `day`: day-type chip, checks strip, coach card, week average.
    let board: CoachBoard
    /// Protein per meal on `day` (minimum from the plan, else 0.4 g/kg of the body weight).
    let proteinRule: ProteinMeals.Rule
    /// The phase in force on `day`.
    let activePhase: CoachPlan.Phase?
    /// Every live body measurement (tape and assessments), oldest first.
    let measurements: [BodyMeasurement]
    /// The tape measurements as Core reads them, oldest first.
    let tapeRecords: [BodyTapeRecord]
    /// Every body-fat value: assessments and the body fat typed with weigh-ins, oldest first.
    let bodyFatReadings: [BodyFatReading]
    /// The saved check-ins, one per week, oldest first.
    let checkIns: [CheckInSnapshot]
    /// Phases with a review decision (keep, hold or cut).
    let reviewedPhases: Set<String>
    /// `day`'s daily checks: check id → done or skipped (missing = open).
    let checkStates: [String: CheckState]
    /// Gain-phase ceilings reached today (waist gain, waist-to-height): they open the review.
    let ceilings: [BodyCeiling]
    /// The check-in of `day`'s week (only when loaded with `checkIn: true`).
    var checkIn: CheckInEvaluation?

    // MARK: Derived

    var calendar: Calendar { store.calendar }
    var plan: CoachPlan { settings.plan }
    /// A plan has been set up: it gates every coach part (except the protein pill when the plan
    /// sets a minimum per meal).
    var isSetUp: Bool { plan.isSetUp }
    /// DayKey raw value → day type id (the newest live mark per day).
    var dayTypeMarks: [String: String] { settings.dayTypeMarks }
    /// `day`'s day type (the mark, else the schedule).
    var dayType: CoachPlan.DayType? { settings.dayType(for: day, calendar: calendar) }
    /// `day`'s targets (day type in the active phase, else the profile's).
    var targets: DailyTargets { settings.targets(for: day, calendar: calendar) }
    var isPaused: Bool { plan.isPaused(on: day) }
    /// Every weigh-in the signal reads (typed and Health).
    var readings: [WeightSignal.Reading] { weights.map(\.reading) + healthReadings }
    /// The weight for body math today (7-day average, else trend, else latest).
    var bodyWeight: WeightSignal.Estimate? { signal.bodyWeight(on: today) }
    var latestWeight: WeightEntry? { weights.last }
    var tapeMeasurements: [BodyMeasurement] { measurements.filter { $0.recordKind == .tape } }
    var assessments: [BodyMeasurement] { measurements.filter { $0.recordKind == .assessment } }
    var latestTape: BodyMeasurement? { tapeMeasurements.last }
    var latestAssessment: BodyMeasurement? { assessments.last }
    var latestCheckIn: CheckInSnapshot? { checkIns.last }
    /// The next full set ("Next full measurement 11 Jan"); on or before today = due.
    var nextFull: BodySchedule.Due? { schedule.nextFull(today: today, calendar: calendar) }
    var nextAssessment: BodySchedule.Due? { schedule.nextAssessment(today: today, calendar: calendar) }
    /// The Monday of the latest check-in week: this week from the check-in weekday on, else last week.
    var currentCheckInWeek: DayKey {
        BodySchedule.onOrBefore(weekday: plan.routine.checkInWeekday, today, calendar: calendar).startOfWeek(calendar: calendar)
    }

    // MARK: Loading

    /// Builds the context of `day`. `settings`: the app's settings (`app.settings`); `health`:
    /// the live Health weigh-ins (`app.healthWeightReadings`); `dismissed`: this device's
    /// "Later" taps (`app.coachDismissals`).
    static func load(store: NinaStore, settings base: NinaSettings, health: [WeightSignal.Reading],
                     dismissed: [String: DayKey], day: DayKey, checkIn: Bool = false, now: Date = Date()) -> CoachContext {
        let calendar = store.calendar
        var settings = base
        let today = settings.today(now: now, calendar: calendar)
        let weights = store.weights()
        let signal = WeightSignal(weights.map(\.reading) + health, cutoffMinutes: settings.plan.routine.morningCutoffMinutes,
                                  dayStartHour: settings.dayStartHour, calendar: calendar)
        settings.bodyWeightKg = signal.bodyWeight(on: today)?.kilograms
        let plan = settings.plan
        let phase = plan.activePhase(on: day)
        let measurements = store.measurements()
        let tape = measurements.compactMap(\.tapeRecord)
        let fatReadings = (measurements.compactMap(\.bodyFatReading) + weights.compactMap(\.bodyFatReading))
            .sorted { $0.day < $1.day }
        let schedule = store.bodySchedule(plan: plan, signal: signal, today: today)
        let due = CoachBoard.bodyItems(schedule, on: day, today: today, now: now,
                                       hasMorningWeighIn: signal.morning(on: today) != nil, calendar: calendar)
        // The stored height, as the Body page uses it: a height without a birth year still counts.
        let heightCm = store.profile()?.heightCm ?? 0
        let ceilings = CoachContext.reachedCeilings(phase: plan.activePhase(on: today), tape: tape, settings: settings,
                                                    heightCm: heightCm)
        let board = store.coachBoard(for: day, settings: settings, signal: signal, now: now, dismissed: dismissed,
                                     ceilings: ceilings)
        let fallbackWeight = CoachContext.startWeightFallback(phase: phase, weights: weights, health: health)
        let summary = signal.summary(on: day, plan: plan, fallbackWeight: fallbackWeight)
        let rule = ProteinMeals.Rule(protein: plan.protein, weightKg: signal.bodyWeight(on: day)?.kilograms ?? 0,
                                     mealSlots: settings.meals.map(\.id))
        var context = CoachContext(
            store: store, day: day, today: today, now: now, settings: settings, weights: weights, healthReadings: health,
            signal: signal, summary: summary, schedule: schedule, dueItems: due, board: board, proteinRule: rule,
            activePhase: phase, measurements: measurements, tapeRecords: tape, bodyFatReadings: fatReadings,
            checkIns: store.checkIns(), reviewedPhases: store.reviewedPhaseIDs(), checkStates: store.checkStates(on: day),
            ceilings: ceilings, checkIn: nil)
        if checkIn { context.checkIn = context.evaluateCheckIn(week: day) }
        return context
    }

    // MARK: Check-in, maintenance, phase start

    /// The check-in of the week `week` falls in (any day of it), computed now.
    func evaluateCheckIn(week: DayKey) -> CheckInEvaluation {
        CheckInEvaluation.evaluate(store: store, settings: settings, signal: signal, week: week, today: today,
                                   checkIns: checkIns, reviewedPhases: reviewedPhases)
    }

    /// Measured maintenance over the 28 days ending on `day` (default today); nil without enough
    /// logged days and weigh-ins.
    func maintenance(on day: DayKey? = nil) -> Insights.Maintenance? {
        let end = day ?? today
        let totals = CoachContext.totals(store: store, from: end.adding(days: -27, calendar: calendar), through: end)
        return Insights.maintenance(totals: totals.values.sorted { $0.day < $1.day }, weights: signal.morningWeights,
                                    today: end, calendar: calendar)
    }

    /// The targets proposed for a phase without targets of its own if it started today (the
    /// "before → after" of the phase-start card); nil when it has targets or doesn't exist.
    func phaseProposal(for id: String) -> PhaseTransition.Proposal? {
        proposal(for: id, in: plan.starting(phase: id, on: today, now: now, calendar: calendar))
    }

    /// The plan after "Start" on a phase today: started (`CoachPlan.starting`), with the
    /// transition proposal's targets when it had none. nil for an unknown phase.
    func startingPlan(phase id: String) -> CoachPlan? {
        guard plan.phase(id: id) != nil else { return nil }
        let started = plan.starting(phase: id, on: today, now: now, calendar: calendar)
        guard let proposal = proposal(for: id, in: started) else { return started }
        return proposal.applied(to: started)
    }

    private func proposal(for id: String, in started: CoachPlan) -> PhaseTransition.Proposal? {
        guard let phase = started.phase(id: id), phase.revisions.isEmpty else { return nil }
        let weight = bodyWeight?.kilograms ?? settings.body.weightKg
        return PhaseTransition.proposal(for: phase, in: started, on: today, weightKg: weight, maintenance: maintenance(),
                                        body: settings.body, fallback: settings.targets, calendar: calendar)
    }

    // MARK: Helpers

    /// Diary totals (eaten, planned, water) of every day from `start` through `end`.
    static func totals(store: NinaStore, from start: DayKey, through end: DayKey) -> [DayKey: DayTotals] {
        guard start <= end else { return [:] }
        let calendar = store.calendar
        let factsByDay = Dictionary(grouping: store.entries(from: start, through: end).map(\.facts), by: \.day)
        var water: [DayKey: Double] = [:]
        for log in store.water(from: start, through: end) { water[log.dayKey, default: 0] += log.amount }
        var totals: [DayKey: DayTotals] = [:]
        for day in DayKey.range(start, through: end, calendar: calendar) {
            totals[day] = DayTotals(day: day, entries: factsByDay[day] ?? [], water: water[day] ?? 0)
        }
        return totals
    }

    /// The gain-phase ceilings reached (`BodyCeiling.reached`): standard waist readings since the
    /// phase start (against the last one on or before it, else the first after it) and the
    /// latest waist-to-height ratio. `heightCm`: the profile's stored height (0 = not entered);
    /// the ratio needs only the height, not the birth year.
    static func reachedCeilings(phase: CoachPlan.Phase?, tape: [BodyTapeRecord], settings: NinaSettings,
                                heightCm: Double) -> [BodyCeiling] {
        guard let phase, phase.goal == .gain, let start = phase.start else { return [] }
        let sex = settings.body.sex
        var waists: [(day: DayKey, cm: Double)] = []
        for record in tape where record.isStandard {
            if let cm = BodyComposition.waist(in: record.values, sex: sex) { waists.append((day: record.day, cm: cm)) }
        }
        waists.sort { $0.day < $1.day }
        guard let latest = waists.last else { return [] }
        let base = waists.last(where: { $0.day <= start }) ?? waists.first(where: { $0.day >= start })
        var change: Double?
        if let base, latest.day > base.day { change = latest.cm - base.cm }
        let ratio = heightCm > 0 ? BodyComposition.waistToHeight(waistCm: latest.cm, heightCm: heightCm) : nil
        return BodyCeiling.reached(phase: phase, waistChangeSinceStart: change, waistToHeight: ratio)
    }

    /// The typed or Health weight nearest the phase start (the summary's start weight when the
    /// weigh-ins around the start don't give a 7-day average).
    static func startWeightFallback(phase: CoachPlan.Phase?, weights: [WeightEntry],
                                    health: [WeightSignal.Reading]) -> Double? {
        let readings = (weights.map(\.reading) + health).sorted { $0.time < $1.time }
        guard let start = phase?.start else { return readings.last?.kilograms }
        let before = readings.last(where: { $0.day <= start })
        let after = readings.first(where: { $0.day >= start })
        return (before ?? after)?.kilograms
    }
}

/// One week's check-in, computed with the recipe in core-api.md: the input from the plan, the
/// weight signal and the saved check-ins, adherence over the decision window and the week, the
/// engine's result, and the snapshot to save.
@MainActor
struct CheckInEvaluation {
    /// Monday of the week.
    let week: DayKey
    /// Today when it was computed.
    let today: DayKey
    /// The check-in day: the plan's check-in weekday in that week (today while that is still ahead).
    let day: DayKey
    /// The check-in mark's key ("week-2030-01-07").
    let key: String
    /// The phase active on the check-in day.
    let phase: CoachPlan.Phase?
    let input: CheckInInput
    let result: CheckInResult
    /// The decision window (the adherence gate) and "How it went" (the 7 days before).
    let windowSummary: AdherenceSummary
    let weekSummary: AdherenceSummary
    /// The 7 days of "How it went", oldest first.
    let weekDays: [DayAdherence]
    /// Measured maintenance (28 days ending on the check-in day).
    let maintenance: Insights.Maintenance?
    /// Ready to save: the weight numbers, the week's adherence and the result (no decision yet;
    /// the sheet adds the waist, ratings and note). Save with `app.saveCheckIn` or apply with
    /// `app.applyCheckIn`.
    let snapshot: CheckInSnapshot
    /// The check-in already saved for this week, if any.
    let saved: CheckInSnapshot?

    var isSaved: Bool { saved != nil }

    /// The first day a change applies: tomorrow ("Apply from tomorrow").
    var applyFrom: DayKey { today.adding(days: 1) }

    /// Every day type before and after a change of `delta` kcal a day from tomorrow.
    func preview(_ delta: Double) -> [CheckInEngine.TypeChange] {
        CheckInEngine.preview(delta, plan: input.plan, from: applyFrom, weightKg: input.weightKg, fallback: input.fallback)
    }

    static func evaluate(store: NinaStore, settings: NinaSettings, signal: WeightSignal, week: DayKey, today: DayKey,
                         checkIns: [CheckInSnapshot], reviewedPhases: Set<String>) -> CheckInEvaluation {
        let calendar = store.calendar
        let plan = settings.plan
        let monday = week.startOfWeek(calendar: calendar)
        let scheduled = CheckInEngine.nextCheckIn(onOrAfter: monday, weekday: plan.routine.checkInWeekday, calendar: calendar)
        let day = scheduled <= today ? scheduled : max(today, monday)
        let key = DayMarks.checkInKey(week: day, calendar: calendar)
        let phase = plan.activePhase(on: day)
        let history = checkIns.filter { $0.key(calendar: calendar) != key }

        var input = CheckInInput(day: day, plan: plan, fallback: settings.targets, history: history,
                                 weightCheck: CheckInEngine.weightCheck(in: plan, ticks: store.checkTicks()),
                                 bmr: GoalCalculator.bmr(settings.body), sex: settings.body.sex)
        input.use(signal: signal, reviewed: phase.map { reviewedPhases.contains($0.id) } ?? false)

        // Diary totals for the decision window, the week and the 28-day maintenance window.
        let windowKeys = input.adherenceDays(calendar: calendar)
        let weekKeys = input.weekDays(calendar: calendar)
        let start = min(windowKeys.first ?? day, weekKeys.first ?? day, day.adding(days: -27, calendar: calendar))
        let totals = CoachContext.totals(store: store, from: start, through: day)
        let maintenance = Insights.maintenance(totals: totals.values.sorted { $0.day < $1.day }, weights: signal.morningWeights,
                                               today: day, calendar: calendar)
        input.maintenance = maintenance

        let done = store.doneChecks(from: start, through: day)
        let incomplete = Set(store.dayMarks(.event, from: start, through: day).filter { $0.key == "incompleteLog" }.map(\.dayKey))
        let marks = settings.dayTypeMarks
        let weightKg = input.weightKg
        let mealSlots = settings.meals.count
        func adherence(_ date: DayKey) -> DayAdherence {
            DayAdherence(plan: plan, totals: totals[date] ?? DayTotals(day: date, entries: []), marks: marks,
                         fallback: settings.legacyTargets(for: date, calendar: calendar), weightKg: weightKg,
                         mealSlots: mealSlots, doneChecks: done[date] ?? [], incomplete: incomplete.contains(date),
                         calendar: calendar)
        }
        let windowDays = windowKeys.map { adherence($0) }
        let weekDays = weekKeys.map { adherence($0) }
        let windowSummary = Adherence.summary(windowDays, plan: plan)
        let weekSummary = Adherence.summary(weekDays, plan: plan)
        input.use(window: windowSummary, week: weekSummary)

        let result = CheckInEngine.evaluate(input, calendar: calendar)
        var snapshot = CheckInSnapshot(day: day)
        snapshot.record(signal, plan: plan)
        snapshot.record(weekSummary)
        snapshot.record(result, phaseID: phase?.id ?? "")
        return CheckInEvaluation(week: monday, today: today, day: day, key: key, phase: phase, input: input, result: result,
                                 windowSummary: windowSummary, weekSummary: weekSummary, weekDays: weekDays,
                                 maintenance: maintenance, snapshot: snapshot,
                                 saved: store.checkInMark(week: day)?.checkInSnapshot)
    }
}

// MARK: - From the app

extension CoachContext {
    /// The live Apple Health weigh-ins as of the app's last refresh (`AppModel.refresh` sets it
    /// before rescheduling notifications), for code without an AppModel: notifications, intents.
    /// Memory only, never stored.
    static var latestHealthReadings: [WeightSignal.Reading] = []

    /// The context of `day` (default: the selected day) with the app's settings, the live
    /// Health weigh-ins and this device's "Later" taps. `checkIn`: also evaluate the check-in of
    /// `day`'s week.
    static func load(app: AppModel, day: DayKey? = nil, checkIn: Bool = false, now: Date = Date()) -> CoachContext {
        load(store: app.store, settings: app.settings, health: app.healthWeightReadings, dismissed: app.coachDismissals,
             day: day ?? app.selectedDay, checkIn: checkIn, now: now)
    }
}
