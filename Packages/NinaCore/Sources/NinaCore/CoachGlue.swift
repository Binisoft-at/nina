import Foundation

/// The seams between the coach modules. The weight signal feeds the weekly check-in (its input
/// and its saved snapshot), body composition (the weight on an assessment day) and the review
/// checkpoint of the measuring schedule. Pure adapters over values the modules already compute;
/// nothing is stored.

// MARK: - Weight signal → body composition and schedule

extension WeightSignal {
    /// Every morning weight by day in kg (tagged ones included), for
    /// `BodyComposition.weight(on:morningWeights:…)` and `BodyComposition.points`.
    public var morningWeights: [DayKey: Double] { mornings.mapValues(\.kilograms) }

    /// The valid 7-day averages by day from `start` through `end`, for
    /// `BodySchedule.checkpointCrossed(avg7History:…)`.
    public func averageHistory(from start: DayKey, through end: DayKey) -> [DayKey: Double] {
        Dictionary(averages(from: start, through: end).map { ($0.day, $0.kilograms) }, uniquingKeysWith: { first, _ in first })
    }

    /// Body-fat values with their fat and lean mass, each weighed with these morning weights
    /// (mean of the morning weights around the day, else the trend, else the typed weight).
    public func compositionPoints(_ readings: [BodyFatReading], today: DayKey, typedWeight: Double? = nil) -> [BodyCompositionPoint] {
        BodyComposition.points(readings, morningWeights: morningWeights, today: today, typedWeight: typedWeight, calendar: calendar)
    }

    /// The first day the 7-day average reached the review checkpoint of the phase active on
    /// `day` (for `BodySchedule(plan:…, checkpoint:)` and the review card); nil without one.
    public func checkpointCrossing(in plan: CoachPlan, through day: DayKey) -> DayKey? {
        plan.activePhase(on: day).flatMap { checkpointCrossing(of: $0, through: day) }
    }
}

// MARK: - Weight signal → check-in

extension CheckInInput {
    /// Takes the decision rate from the weight signal: kg/week, the days its weigh-ins span, the
    /// untagged morning weigh-ins and the window start. The engine's "gathering" gate then matches
    /// `WeightSignal.Rate.isValid` (14 days, 10 weigh-ins).
    public mutating func use(rate: WeightSignal.Rate) {
        self.rate = rate.kilogramsPerWeek
        windowDays = rate.spanDays
        weighIns = rate.weighIns
        windowStart = rate.window.start
    }

    /// Everything the check-in needs from the weigh-ins on its day, with the plan's rules: the
    /// decision rate and its window (`WeightSignal.rate(on:plan:)`), the body weight for the fat
    /// floor (7-day average, else the trend) and whether the review checkpoint was reached.
    /// - Parameter reviewed: the person already decided on this phase's review (a phase
    ///   `DayMark` with event review-keep, review-hold or review-cut), so the checkpoint no
    ///   longer stops the check-in.
    public mutating func use(signal: WeightSignal, reviewed: Bool = false) {
        use(rate: signal.rate(on: day, plan: plan))
        if let weight = signal.bodyWeight(on: day)?.kilograms { weightKg = weight }
        checkpointReached = !reviewed && signal.checkpointCrossing(in: plan, through: day) != nil
    }

    /// The days the adherence gate looks at, oldest first: the decision window up to the day
    /// before the check-in (the check-in day itself is still being logged). Build a
    /// `DayAdherence` for each, sum them with `Adherence.summary` and hand that to `use(window:week:)`.
    public func adherenceDays(calendar: Calendar = .current) -> [DayKey] {
        let start = windowStart ?? CheckInEngine.windowStart(plan: plan, on: day, lastApplied: lastApplied, calendar: calendar)
        let end = day.adding(days: -1, calendar: calendar)
        guard start <= end else { return [] }
        return DayKey.range(start, through: end, calendar: calendar)
    }

    /// "How it went": the 7 days before the check-in day, oldest first.
    public func weekDays(calendar: Calendar = .current) -> [DayKey] {
        DayKey.range(day.adding(days: -7, calendar: calendar), through: day.adding(days: -1, calendar: calendar), calendar: calendar)
    }
}

extension CheckInSnapshot {
    /// Takes the weight numbers of the check-in day: the 7-day average and the one a week before
    /// (valid ones only), the decision rate (when valid) and its weigh-ins. When a Health weight
    /// is among them, `usesHealthWeights` is set and `values` leaves them out (they are
    /// recomputed live).
    public mutating func record(_ signal: WeightSignal, plan: CoachPlan) {
        let calendar = signal.calendar
        let rate = signal.rate(on: day, plan: plan)
        avg7 = signal.average(on: day).value
        prevAvg7 = signal.average(on: day.adding(days: -7, calendar: calendar)).value
        self.rate = rate.value
        weighIns = rate.weighIns
        let averages = signal.usesHealth(from: day.adding(days: -(2 * WeightSignal.averageDays - 1), calendar: calendar), through: day)
        usesHealthWeights = rate.usesHealth || averages
    }
}
