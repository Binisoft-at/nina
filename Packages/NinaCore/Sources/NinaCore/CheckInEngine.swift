import Foundation

/// The weekly check-in's verdict (`DayMark` meta "verdict=…").
public enum CheckInVerdict: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The rate is inside the phase's range (with the tolerance).
    case inRange
    /// Outside the range, behind the plan (gaining too slowly, losing too slowly).
    case slower
    /// Outside the range, ahead of the plan (gaining or losing too fast; while maintaining,
    /// moving either way).
    case faster
    /// Outside the range in the same direction at enough check-ins in a row ("Off track").
    case offTarget
    /// Not enough data yet (or no active phase, or paused).
    case gathering
    /// The review weight was reached: the phase review decides, not the check-in.
    case checkpoint

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inRange: "In range"
        case .slower: "Slower than planned"
        case .faster: "Faster than planned"
        case .offTarget: "Off track"
        case .gathering: "Gathering data"
        case .checkpoint: "Review"
        }
    }
}

extension CheckInVerdict {
    /// The verdict for a weight status (Progress, widget and watch use the same words).
    public init(_ status: WeightSignal.Status) {
        switch status {
        case .inRange: self = .inRange
        case .slower: self = .slower
        case .faster: self = .faster
        case .gathering: self = .gathering
        }
    }
}

/// The one-word status line of a check-in.
public enum CheckInStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case onTrack
    /// One metric out: the rate outside the range once, or adherence 70–84 %, or the intake off target.
    case watch
    /// The rate out at enough check-ins in a row, or adherence below 70 %.
    case offTrack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onTrack: "On track"
        case .watch: "Watch"
        case .offTrack: "Off track"
        }
    }
}

/// What the person did with the proposal (`DayMark` meta "applied=yes|no|edited").
public enum CheckInDecision: String, Codable, Sendable, CaseIterable {
    /// "Apply from tomorrow".
    case applied = "yes"
    /// "Keep for now".
    case kept = "no"
    /// Applied with a changed Δ.
    case edited
}

/// Everything the check-in needs, as plain values. The weight numbers (rate, window, weigh-ins)
/// come from the weight signal and the adherence numbers from `Adherence.summary` over the same
/// window; tagged weigh-ins and paused days are already left out there.
public struct CheckInInput: Equatable, Sendable {
    /// The check-in day.
    public var day: DayKey
    public var plan: CoachPlan
    /// The profile's targets (used when the active phase has no revision yet).
    public var fallback: DailyTargets

    /// Decision rate in kg/week (least-squares slope of the morning weights × 7); nil while it
    /// can't be computed.
    public var rate: Double?
    /// Days the decision window spans, and the untagged morning weigh-ins in it.
    public var windowDays: Int
    public var weighIns: Int
    /// First day of the decision window; nil = `CheckInEngine.windowStart`.
    public var windowStart: DayKey?
    /// 7-day average weight in kg (0 = unknown): fat floor in g/kg.
    public var weightKg: Double

    /// Adherence over the decision window (not-paused days, logged days, average eaten and
    /// average resolved target over the logged days).
    public var countedDays: Int
    public var loggedDays: Int
    public var averageIntake: Double
    public var averageTarget: Double
    /// This week's adherence grade (for the status line).
    public var weekGrade: AdherenceGrade?

    /// Earlier check-ins (any order; later ones and other phases are ignored).
    public var history: [CheckInSnapshot]
    /// First day of the last applied change; nil = the newest "adjust" revision of the active phase.
    public var lastApplied: DayKey?
    /// The first tick of a check that affects weight (creatine), if any.
    public var weightCheck: CheckInEngine.WeightCheck?
    /// The 7-day average reached the review weight (F5 checkpoint).
    public var checkpointReached: Bool

    /// Measured maintenance (`Insights.maintenance`, 28-day window); the gain cap needs medium
    /// confidence or better.
    public var maintenance: Insights.Maintenance?
    /// Basal metabolic rate (kcal, 0 = unknown) and sex for the energy floor.
    public var bmr: Double
    public var sex: Sex

    public init(day: DayKey, plan: CoachPlan, fallback: DailyTargets = .standard, rate: Double? = nil, windowDays: Int = 0,
                weighIns: Int = 0, windowStart: DayKey? = nil, weightKg: Double = 0, countedDays: Int = 0, loggedDays: Int = 0,
                averageIntake: Double = 0, averageTarget: Double = 0, weekGrade: AdherenceGrade? = nil,
                history: [CheckInSnapshot] = [], lastApplied: DayKey? = nil, weightCheck: CheckInEngine.WeightCheck? = nil,
                checkpointReached: Bool = false, maintenance: Insights.Maintenance? = nil, bmr: Double = 0, sex: Sex = .unspecified) {
        self.day = day
        self.plan = plan
        self.fallback = fallback
        self.rate = rate
        self.windowDays = windowDays
        self.weighIns = weighIns
        self.windowStart = windowStart
        self.weightKg = weightKg
        self.countedDays = countedDays
        self.loggedDays = loggedDays
        self.averageIntake = averageIntake
        self.averageTarget = averageTarget
        self.weekGrade = weekGrade
        self.history = history
        self.lastApplied = lastApplied
        self.weightCheck = weightCheck
        self.checkpointReached = checkpointReached
        self.maintenance = maintenance
        self.bmr = bmr
        self.sex = sex
    }

    /// Takes the adherence numbers from a summary of the decision window (and this week's grade).
    public mutating func use(window: AdherenceSummary, week: AdherenceSummary? = nil) {
        countedDays = window.days
        loggedDays = window.loggedDays
        averageIntake = window.averageIntake
        averageTarget = window.averageTarget
        if let week { weekGrade = week.grade }
    }
}

/// The check-in's outcome: the verdict, one reason sentence and the proposal (Δ kcal per day,
/// the same for every day type; 0 = keep). Nothing is ever applied by itself.
public struct CheckInResult: Equatable, Sendable {
    public var verdict: CheckInVerdict
    /// Which side of the range the rate is on (nil when in range or without a rate).
    public var deviation: CheckInEngine.Deviation?
    public var status: CheckInStatus
    /// The rule that decided the outcome.
    public var rule: CheckInEngine.Rule
    /// One sentence: "Slower than planned two check-ins in a row – add 100 kcal a day."
    public var reason: String
    /// Extra lines: the creatine caveat, the cross-check, a capped step.
    public var notes: [String]
    /// The proposed change in kcal per day (0 = no change).
    public var delta: Double
    /// The step from the rate before the guardrails (0 inside the range or without data).
    public var step: Double
    /// Check-ins in a row (this one included) outside the range on the same side.
    public var outsideInARow: Int
    /// While gathering: the first check-in day that can judge the rate.
    public var firstAdjustmentCheck: DayKey?
    /// Cross-check: the rate the logged intake and measured maintenance predict (kg/week).
    public var expectedRate: Double?

    public init(verdict: CheckInVerdict, deviation: CheckInEngine.Deviation? = nil, status: CheckInStatus = .onTrack,
                rule: CheckInEngine.Rule, reason: String, notes: [String] = [], delta: Double = 0, step: Double = 0,
                outsideInARow: Int = 0, firstAdjustmentCheck: DayKey? = nil, expectedRate: Double? = nil) {
        self.verdict = verdict
        self.deviation = deviation
        self.status = status
        self.rule = rule
        self.reason = reason
        self.notes = notes
        self.delta = delta
        self.step = step
        self.outsideInARow = outsideInARow
        self.firstAdjustmentCheck = firstAdjustmentCheck
        self.expectedRate = expectedRate
    }

    /// There is a change to apply.
    public var hasProposal: Bool { delta != 0 }

    /// "+100 kcal", "−150 kcal", "" without a proposal.
    public var deltaText: String { delta == 0 ? "" : CheckInFormat.signedKcal(delta) + " kcal" }
}

/// The weekly adjustment rules (F11), as pure functions.
///
/// 1. Window: at least `windowMinDays` days and 10 morning weigh-ins, else "gathering".
/// 2. Adherence gate: logged on at least 80 % of the window's days and the average intake
///    within ±`intakeTolerance` of the average resolved target, else no change.
/// 3. Inside the range (± `tolerance`): keep.
/// 4. Outside: a proposal only when the previous check-in(s) were outside on the same side.
/// 5. Step: sign × clamp(round to 50(|(mid − rate) × 1,100|), stepMin, stepMax).
/// 6. Macros: `CoachPlan.applyingDelta` (gain: carbs; loss: 70 % carbs / 30 % fat with the fat
///    floor; protein never lowered), the same Δ for every day type.
/// 7. Guardrails: the lock after an applied change, the 28-day hold of "faster" after the first
///    tick of a check that affects weight, the gain cap (maintenance + 500) and the energy floor
///    (max(1.1 × BMR, 1,500 men / 1,200 women)).
/// 8. Cross-check: expected rate from intake and measured maintenance vs. the scale.
public enum CheckInEngine {
    /// Morning weigh-ins the window needs.
    public static let minimumWeighIns = 10
    /// Share of the window's days that must be logged.
    public static let minimumLoggedShare = 0.8
    /// Days "faster than planned" is held after the first tick of a check that affects weight.
    public static let weightCheckHoldDays = 28
    /// Cross-check: expected and measured rate differ by more than this (kg/week).
    public static let crossCheckLimit = 0.15
    /// Daily kcal per kg/week (7,700 ÷ 7).
    public static let kcalPerKgWeek = GoalCalculator.kilocaloriesPerKilogram / 7

    /// Which side of the phase's (signed) range the rate is on.
    public enum Deviation: String, Codable, Sendable, CaseIterable {
        /// Below the range: gaining too little, or losing too much.
        case below
        /// Above the range: gaining too much, or losing too little.
        case above
    }

    /// The rule that decided a check-in.
    public enum Rule: String, Codable, Sendable, CaseIterable {
        case noPhase, paused, checkpoint
        /// The active phase has no weekly rate to compare with (a gain or loss phase without one).
        case noRate
        case gathering
        /// Adherence gate: too few logged days.
        case logging
        /// Adherence gate: the average intake is too far from the targets.
        case intake
        case inRange
        /// Outside the range, waiting for the next check-in to confirm.
        case confirming
        /// A change was applied less than `lockDays` ago.
        case locked
        /// "Faster" held after the first tick of a check that affects weight.
        case weightCheckHold
        /// The targets already reach measured maintenance + 500.
        case gainCap
        /// The targets are already at the safe minimum.
        case energyFloor
        case proposal
    }

    /// The first tick of a daily check that affects weight (creatine).
    public struct WeightCheck: Equatable, Sendable {
        public var name: String
        public var firstTick: DayKey

        public init(name: String, firstTick: DayKey) {
            self.name = name
            self.firstTick = firstTick
        }
    }

    // MARK: Evaluate

    public static func evaluate(_ input: CheckInInput, calendar: Calendar = .current) -> CheckInResult {
        let day = input.day
        let plan = input.plan
        let adjust = plan.adjust
        guard let phase = plan.activePhase(on: day) else {
            return CheckInResult(verdict: .gathering, rule: .noPhase, reason: "No active phase yet – start one to get weekly proposals.")
        }
        if plan.isPaused(on: day) {
            return CheckInResult(verdict: .gathering, rule: .paused, reason: "Coaching is paused – no check-in this week.")
        }
        let weekStatus: CheckInStatus = input.weekGrade == .off ? .offTrack : (input.weekGrade == .watch ? .watch : .onTrack)
        // Rule 1: a rate from a window that is too short (or has too few weigh-ins) is noise. It
        // never gives a side, so a check-in saved while gathering (or at the checkpoint) doesn't
        // count as "outside" at the next one.
        let windowValid = input.rate != nil && input.windowDays >= adjust.windowMinDays && input.weighIns >= minimumWeighIns
        let deviation = windowValid ? input.rate.flatMap { CheckInEngine.deviation(rate: $0, phase: phase, tolerance: adjust.tolerance) } : nil

        if input.checkpointReached {
            return CheckInResult(verdict: .checkpoint, deviation: deviation, status: weekStatus, rule: .checkpoint,
                                 reason: "Review weight reached – time to review your phase.")
        }
        guard WeightSignal.range(for: phase) != nil else {
            return CheckInResult(verdict: .gathering, status: weekStatus, rule: .noRate,
                                 reason: "This phase has no weekly rate yet – set one to get proposals.")
        }

        // A change that starts after the check-in day was applied at this very check-in ("Apply
        // from tomorrow", then Redo): the targets already changed, the next check-in judges them.
        // Never judged again here – the same step would be proposed and applied twice.
        let newest = input.lastApplied ?? lastAdjustment(in: plan, on: day)
        let pendingChange = newest.flatMap { $0 > day ? $0 : nil }
        let pendingReason = pendingChange.map {
            "Targets change from \(CheckInFormat.day($0, calendar: calendar)) – the next check-in judges them."
        }
        // The change in force on the check-in day: the history and the lock count from it.
        let lastApplied = pendingChange == nil ? newest : lastAdjustment(in: plan, on: day, inForce: true)

        // 1. Window.
        guard windowValid, let rate = input.rate else {
            if let pendingReason {
                return CheckInResult(verdict: .gathering, status: weekStatus, rule: .locked, reason: pendingReason)
            }
            let first = firstAdjustmentCheck(plan: plan, on: day, windowStart: input.windowStart, lastApplied: lastApplied, calendar: calendar)
            return CheckInResult(verdict: .gathering, status: weekStatus, rule: .gathering,
                                 reason: "Gathering data – first adjustment check on \(CheckInFormat.day(first, calendar: calendar)).",
                                 firstAdjustmentCheck: first)
        }

        // 8. Cross-check (display only).
        var notes: [String] = []
        var expectedRate: Double?
        if let maintenance = input.maintenance, isReliable(maintenance), input.loggedDays > 0 {
            let expected = (input.averageIntake - maintenance.kilocalories) * 7 / GoalCalculator.kilocaloriesPerKilogram
            expectedRate = expected
            if abs(expected - rate) > crossCheckLimit + 1e-9 {
                notes.append("Your logged intake points to \(CheckInFormat.rate(expected)) kg/week, the scale shows \(CheckInFormat.rate(rate)) – logging may be incomplete.")
            }
        }

        // 4. How many check-ins in a row (this one included) were outside on the same side. Only
        // check-ins of this phase since the last applied change count.
        var inARow = 0
        if let deviation {
            inARow = 1
            let earlier = input.history
                .filter { snapshot in snapshot.day < day && snapshot.phaseID == phase.id && (lastApplied.map { snapshot.day >= $0 } ?? true) }
                .sorted { $0.day > $1.day }
            for snapshot in earlier {
                guard snapshot.deviation == deviation else { break }
                inARow += 1
            }
        }
        let confirm = max(1, adjust.confirmChecks)
        let sideVerdict: CheckInVerdict = deviation.map { CheckInEngine.verdict(for: $0, goal: phase.goal) } ?? .inRange
        var verdict: CheckInVerdict = inARow >= confirm ? .offTarget : sideVerdict

        // 7. Creatine and the like: up to ~1 kg of water moves the scale up. "Faster" is held.
        var holdReason: String?
        if let check = input.weightCheck, deviation == .above {
            let since = check.firstTick.days(to: day, calendar: calendar)
            if since >= 0, since < weightCheckHoldDays {
                notes.insert("\(check.name) started \(CheckInFormat.daysAgo(since)) – up to ~1 kg may be water", at: 0)
                if sideVerdict == .faster {
                    verdict = .faster
                    holdReason = "Faster than planned, but \(check.name) started \(CheckInFormat.daysAgo(since)) – up to ~1 kg may be water, so keep it for now."
                }
            }
        }

        let rawStep = step(rate: rate, phase: phase, adjust: adjust)
        func result(_ rule: Rule, _ reason: String, delta: Double = 0) -> CheckInResult {
            var status = weekStatus
            // F11 status line: the rate out at enough check-ins in a row is "Off track", also
            // while the weight-check hold keeps the verdict at "Faster than planned" (Progress
            // and Today say the same).
            if verdict == .offTarget || inARow >= confirm { status = .offTrack }
            if status == .onTrack, verdict == .slower || verdict == .faster || rule == .logging || rule == .intake { status = .watch }
            return CheckInResult(verdict: verdict, deviation: deviation, status: status, rule: rule, reason: reason, notes: notes,
                                 delta: delta, step: rawStep, outsideInARow: inARow, expectedRate: expectedRate)
        }

        if let pendingReason { return result(.locked, pendingReason) }

        // 2. Adherence gate.
        let needed = Int((minimumLoggedShare * Double(input.countedDays) - 1e-9).rounded(.up))
        if input.countedDays <= 0 || input.loggedDays < needed {
            return result(.logging, "You logged \(input.loggedDays) of \(input.countedDays) days – log your meals this week first.")
        }
        let balance = input.averageIntake - input.averageTarget
        if abs(balance) > adjust.intakeTolerance + 1e-9 {
            let side = balance < 0 ? "under" : "over"
            return result(.intake, "You ate \(CheckInFormat.kcal(abs(balance))) kcal \(side) your targets – hit them this week first.")
        }

        // 3. Inside the range.
        guard deviation != nil else { return result(.inRange, "In range – keep it.") }

        // 4. Outside: only when confirmed by the check-in(s) before.
        let sideText = sideVerdict.title
        if inARow < confirm {
            return result(.confirming, "\(sideText) (\(CheckInFormat.rate(rate)) kg/week) – if next week is the same, Nina suggests a change.")
        }

        // 7. Guardrails: the lock after an applied change, then the hold.
        if let lastApplied {
            let since = lastApplied.days(to: day, calendar: calendar)
            if since < adjust.lockDays {
                let next = nextCheckIn(onOrAfter: lastApplied.adding(days: adjust.lockDays, calendar: calendar),
                                       weekday: plan.routine.checkInWeekday, calendar: calendar)
                return result(.locked, "Targets changed \(CheckInFormat.daysAgo(since)) – give them until \(CheckInFormat.day(next, calendar: calendar)) before the next change.")
            }
        }
        if let holdReason { return result(.weightCheckHold, holdReason) }

        // 5./6. The step, then the energy limits (the gain cap on the planned average, the floor
        // on the lowest day type).
        var delta = rawStep
        let energy = plannedEnergy(plan: plan, on: day, fallback: input.fallback)
        if delta > 0, let maintenance = input.maintenance, isReliable(maintenance) {
            let cap = maintenance.kilocalories + adjust.gainCapOverMaintenance
            if energy.average + delta > cap + 1e-9 {
                let allowed = roundedDown50(cap - energy.average)
                guard allowed > 0 else {
                    return result(.gainCap, "Your targets already reach your measured maintenance + \(CheckInFormat.kcal(adjust.gainCapOverMaintenance)) kcal – keep them.")
                }
                delta = allowed
                notes.append("Limited to your measured maintenance + \(CheckInFormat.kcal(adjust.gainCapOverMaintenance)) kcal.")
            }
        }
        if delta < 0 {
            let floor = energyFloor(bmr: input.bmr, sex: input.sex)
            if energy.lowest + delta < floor - 1e-9 {
                let allowed = roundedDown50(energy.lowest - floor)
                guard allowed > 0 else {
                    return result(.energyFloor, "Your targets are at the safe minimum of \(CheckInFormat.kcal(floor)) kcal – keep them.")
                }
                delta = -allowed
                notes.append("Limited by the safe minimum of \(CheckInFormat.kcal(floor)) kcal.")
            }
        }
        let change = delta > 0 ? "add \(CheckInFormat.kcal(delta)) kcal a day" : "eat \(CheckInFormat.kcal(-delta)) kcal less a day"
        return result(.proposal, "\(sideText) \(CheckInFormat.count(inARow)) check-ins in a row – \(change).", delta: delta)
    }

    // MARK: Pieces

    /// Which side of the phase's range (± tolerance) a rate is on; nil inside it, or when the
    /// phase has no range. The range is `WeightSignal.range(for:)` (a maintain phase without a
    /// rate of its own keeps ±0.1 kg/week), so Progress and the check-in always agree.
    public static func deviation(rate: Double, phase: CoachPlan.Phase, tolerance: Double = WeightSignal.defaultTolerance) -> Deviation? {
        guard let offset = WeightSignal.deviation(rate, phase: phase, tolerance: max(0, tolerance)), offset != 0 else { return nil }
        return offset > 0 ? .above : .below
    }

    /// "Slower" or "faster" for a side: gaining below the range is slower, losing below it (more
    /// than planned) is faster; while maintaining, moving either way is faster than planned.
    /// The same words as `WeightSignal.Status`.
    public static func verdict(for deviation: Deviation, goal: WeightGoal) -> CheckInVerdict {
        CheckInVerdict(WeightSignal.Status.outside(above: deviation == .above, goal: goal))
    }

    /// The step for a rate (rule 5): d = signed midpoint − rate, raw = d × 1,100 kcal,
    /// Δ = sign(raw) × clamp(round to 50(|raw|), stepMin, stepMax). 0 inside the range.
    public static func step(rate: Double, phase: CoachPlan.Phase, adjust: CoachPlan.Adjust = CoachPlan.Adjust()) -> Double {
        guard deviation(rate: rate, phase: phase, tolerance: adjust.tolerance) != nil else { return 0 }
        let raw = (phase.signedRateMid - rate) * kcalPerKgWeek
        guard raw != 0 else { return 0 }
        let low = max(0, min(adjust.stepMin, adjust.stepMax)), high = max(0, adjust.stepMin, adjust.stepMax)
        let size = min(max(rounded50(abs(raw)), low), high)
        return raw < 0 ? -size : size
    }

    /// The lowest a target may go: max(1.1 × BMR, 1,500 kcal men / 1,200 women / 1,350 unspecified),
    /// in whole kcal.
    public static func energyFloor(bmr: Double, sex: Sex) -> Double {
        max((1.1 * max(0, bmr)).rounded(), GoalCalculator.minimumEnergy(BodyProfile(sex: sex)))
    }

    /// The first day of the decision window ending on `day`: the last `windowMaxDays` days, never
    /// before the active phase's start, the last applied change or the day after a pause.
    public static func windowStart(plan: CoachPlan, on day: DayKey, lastApplied: DayKey? = nil, calendar: Calendar = .current) -> DayKey {
        var start = day.adding(days: -(max(1, plan.adjust.windowMaxDays) - 1), calendar: calendar)
        if let phaseStart = plan.activePhase(on: day)?.start { start = max(start, phaseStart) }
        if let applied = lastApplied ?? lastAdjustment(in: plan, on: day) { start = max(start, min(applied, day)) }
        for pause in plan.pauses where pause.start <= day {
            if let end = pause.end, end < day {
                start = max(start, end.adding(days: 1, calendar: calendar))
            } else {
                start = day
            }
        }
        return start
    }

    /// The first day of the newest applied adjustment ("adjust:…" revision) of the active phase,
    /// including one that starts after `day` (applied at this check-in, from tomorrow).
    public static func lastAdjustment(in plan: CoachPlan, on day: DayKey) -> DayKey? {
        lastAdjustment(in: plan, on: day, inForce: false)
    }

    /// The first day of the newest applied adjustment of the active phase; with `inForce` only
    /// one that has started by `day`.
    public static func lastAdjustment(in plan: CoachPlan, on day: DayKey, inForce: Bool) -> DayKey? {
        plan.activePhase(on: day)?.revisions
            .filter { $0.reason.hasPrefix("adjust") && (!inForce || $0.from <= day) }.map(\.from).max()
    }

    /// The first tick of a check that affects weight: `ticks` are (day, check id) of the done marks.
    public static func weightCheck(in plan: CoachPlan, ticks: [(day: DayKey, checkID: String)]) -> WeightCheck? {
        var first: WeightCheck?
        for tick in ticks {
            guard let check = plan.check(id: tick.checkID), check.affectsWeight else { continue }
            if let current = first, current.firstTick <= tick.day { continue }
            first = WeightCheck(name: check.name.isEmpty ? check.id : check.name, firstTick: tick.day)
        }
        return first
    }

    /// The first check-in day after `day` that can judge the rate: the rate is valid once the
    /// weigh-ins span `windowMinDays` days, the first and the last day included
    /// (`WeightSignal.firstRateDay`: window start + 13), so it is the first check-in weekday on or
    /// after that day (and after `day`). `windowStart` nil = `windowStart(plan:on:lastApplied:)`.
    public static func firstAdjustmentCheck(plan: CoachPlan, on day: DayKey, windowStart start: DayKey? = nil, lastApplied: DayKey? = nil,
                                            calendar: Calendar = .current) -> DayKey {
        let start = start ?? windowStart(plan: plan, on: day, lastApplied: lastApplied, calendar: calendar)
        let valid = WeightSignal.firstRateDay(from: start, minimumDays: plan.adjust.windowMinDays, calendar: calendar)
        let earliest = max(valid, day.adding(days: 1, calendar: calendar))
        return nextCheckIn(onOrAfter: earliest, weekday: plan.routine.checkInWeekday, calendar: calendar)
    }

    /// The next check-in weekday on or after a day.
    public static func nextCheckIn(onOrAfter day: DayKey, weekday: Int, calendar: Calendar = .current) -> DayKey {
        let target = (1...7).contains(weekday) ? weekday : 1
        let offset = (target - day.weekday(calendar: calendar) + 7) % 7
        return day.adding(days: offset, calendar: calendar)
    }

    // MARK: Proposal

    /// One day type before and after a change, for "Gym 2700 (+25 g carbs), Tennis 2900, Rest 2500".
    public struct TypeChange: Equatable, Sendable, Identifiable {
        /// The day type id ("" = the baseline, for plans without day types).
        public var typeID: String
        public var before: DailyTargets
        public var after: DailyTargets

        public var id: String { typeID }
        public var energyChange: Double { after.energy - before.energy }
        public var proteinChange: Double { after.protein - before.protein }
        public var carbsChange: Double { after.carbs - before.carbs }
        public var fatChange: Double { after.fat - before.fat }
    }

    /// The plan with the change applied from `day` on ("Apply from tomorrow": a new revision of
    /// the active phase, the same Δ for every day type; the macro rule follows the phase goal).
    public static func applying(_ delta: Double, to plan: CoachPlan, from day: DayKey, weightKg: Double = 0,
                                fallback: DailyTargets = .standard) -> CoachPlan {
        guard delta != 0 else { return plan }
        return plan.applyingDelta(delta, from: day, weightKg: weightKg, fallback: fallback)
    }

    /// Every day type before and after `delta` from `day` on, in plan order.
    public static func preview(_ delta: Double, plan: CoachPlan, from day: DayKey, weightKg: Double = 0,
                               fallback: DailyTargets = .standard) -> [TypeChange] {
        let changed = applying(delta, to: plan, from: day, weightKg: weightKg, fallback: fallback)
        let before = plan.revision(on: day), after = changed.revision(on: day)
        guard !plan.dayTypes.isEmpty else {
            return [TypeChange(typeID: "", before: before?.baseline ?? fallback, after: after?.baseline ?? fallback)]
        }
        return plan.dayTypes.map { type in
            TypeChange(typeID: type.id, before: before?.targets(for: type.id) ?? fallback, after: after?.targets(for: type.id) ?? fallback)
        }
    }

    // MARK: Helpers

    /// Average planned kcal per day (fixed, flexible and default types over a week) and the
    /// lowest day type's kcal, of the revision in force on `day`.
    static func plannedEnergy(plan: CoachPlan, on day: DayKey, fallback: DailyTargets) -> (average: Double, lowest: Double) {
        plannedEnergy(plan: plan, revision: plan.revision(on: day), fallback: fallback)
    }

    static func plannedEnergy(plan: CoachPlan, revision: CoachPlan.Revision?, fallback: DailyTargets) -> (average: Double, lowest: Double) {
        guard let revision else { return (fallback.energy, fallback.energy) }
        let energies = plan.dayTypes.isEmpty
            ? [(revision.baseline ?? fallback).energy]
            : plan.dayTypes.map { (revision.targets(for: $0.id) ?? fallback).energy }
        let mean = energies.reduce(0, +) / Double(max(1, energies.count))
        return (plan.plannedWeekAverage(revision) ?? mean, energies.min() ?? mean)
    }

    /// Measured maintenance with medium confidence or better.
    static func isReliable(_ maintenance: Insights.Maintenance) -> Bool {
        maintenance.confidence == .medium || maintenance.confidence == .high
    }

    static func rounded50(_ value: Double) -> Double { (value / 50).rounded() * 50 }

    static func roundedDown50(_ value: Double) -> Double { max(0, (value / 50 + 1e-9).rounded(.down) * 50) }
}

// MARK: - Phase transition (F5)

/// Targets for a phase that has none yet (the "phase starts today" card): maintenance (measured
/// when confident, else the calculator), the rate (from the target weight and end date when the
/// phase has none), kcal = maintenance ± midpoint × 1,100, and every day type shifted by the same
/// kcal so the differences between them stay. Protein keeps its grams (at least 2.2 g/kg in a
/// cut), fat stays at least max(0.6 g/kg, 20 % of kcal), carbs take the rest.
public enum PhaseTransition {
    /// Protein floor in a cut, g per kg.
    public static let cutProteinPerKg = 2.2
    /// Fat floor: g per kg, and share of kcal.
    public static let fatPerKg = 0.6
    public static let fatEnergyShare = 0.2
    /// A derived rate is kept within 0.25–1.0 % of body weight per week …
    public static let ratePercentRange: ClosedRange<Double> = 0.25...1.0
    /// … and given a ±0.05 kg range.
    public static let rateSpread = 0.05
    /// A maintenance bridge is offered after a gain phase longer than this (weeks).
    public static let bridgeAfterWeeks = 12

    public enum MaintenanceSource: String, Codable, Sendable {
        /// `Insights.maintenance` with medium confidence or better.
        case measured
        /// Mifflin-St Jeor × activity (`GoalCalculator`).
        case calculated
    }

    public struct Proposal: Equatable, Sendable {
        public var phaseID: String
        public var day: DayKey
        public var maintenance: Double
        public var source: MaintenanceSource
        /// The rate range (kg/week, magnitudes): the phase's own, or derived.
        public var rateMin: Double
        public var rateMax: Double
        /// The range was derived from the target weight and end date.
        public var rateDerived: Bool
        /// Surplus (+) or deficit (−) kcal per day: midpoint × 1,100, rounded to 50.
        public var adjustment: Double
        /// Average kcal per day the phase aims for: maintenance + adjustment.
        public var energy: Double
        /// kcal added to (or taken from) every day type, compared with the targets before.
        public var shift: Double
        /// The targets from `day` on.
        public var revision: CoachPlan.Revision
        public var notes: [String]

        /// The plan with the proposal: the revision added to the phase, and a derived rate stored.
        public func applied(to plan: CoachPlan) -> CoachPlan {
            var copy = plan.addingRevision(phase: phaseID, from: day, baseline: revision.baseline, byType: revision.byType,
                                           reason: revision.reason)
            if rateDerived, let index = copy.phases.firstIndex(where: { $0.id == phaseID }) {
                copy.phases[index].rateMin = rateMin
                copy.phases[index].rateMax = rateMax
            }
            return copy
        }
    }

    /// The proposal for `phase` starting on `day`, from the targets before it
    /// (`targetsBefore(_:in:on:)`: the running phase's, or once `phase` has been started, those of
    /// the phase that ran before it; else `fallback`). It can be computed before or after
    /// `CoachPlan.starting(phase:on:)` and gives the same targets.
    /// - Parameters:
    ///   - weightKg: the 7-day average (0 = unknown: no derived rate, no g/kg floors).
    ///   - maintenance: measured maintenance (28-day window); used with medium confidence or better.
    ///   - body: for the calculator (its weight is replaced by `weightKg` when known).
    public static func proposal(for phase: CoachPlan.Phase, in plan: CoachPlan, on day: DayKey, weightKg: Double,
                                maintenance: Insights.Maintenance?, body: BodyProfile, fallback: DailyTargets,
                                calendar: Calendar = .current) -> Proposal {
        var notes: [String] = []
        var profile = body
        if weightKg > 0 { profile.weightKg = weightKg }
        let source: MaintenanceSource
        let base: Double
        if let maintenance, CheckInEngine.isReliable(maintenance) {
            source = .measured
            base = maintenance.kilocalories
        } else {
            source = .calculated
            base = (GoalCalculator.bmr(profile) * profile.activity.factor / 10).rounded() * 10
        }

        var rateMin = phase.rateRange.lowerBound, rateMax = phase.rateRange.upperBound
        var derived = false
        if phase.goal != .maintain, rateMax <= 0 {
            if let range = rate(for: phase, weightKg: weightKg, from: day, calendar: calendar) {
                rateMin = range.lowerBound
                rateMax = range.upperBound
                derived = true
            } else {
                notes.append("Set a rate for this phase to get a \(phase.goal == .lose ? "deficit" : "surplus").")
            }
        }
        let mid = phase.goal == .maintain ? 0 : (rateMin + rateMax) / 2
        let sign: Double = phase.goal == .lose ? -1 : 1
        let adjustment = sign * CheckInEngine.rounded50(mid * CheckInEngine.kcalPerKgWeek)
        let energy = ((base + adjustment) / 10).rounded() * 10

        let current = targetsBefore(phase, in: plan, on: day, calendar: calendar)
        let before = CheckInEngine.plannedEnergy(plan: plan, revision: current, fallback: fallback)
        var shift = ((energy - before.average) / 10).rounded() * 10
        if phase.goal == .lose {
            let floor = CheckInEngine.energyFloor(bmr: GoalCalculator.bmr(profile), sex: profile.sex)
            if before.lowest + shift < floor - 1e-9 {
                shift = ((floor - before.lowest) / 10).rounded(.up) * 10
                notes.append("Raised to the safe minimum of \(CheckInFormat.kcal(floor)) kcal on the lowest day.")
            }
        }
        let cut = phase.goal == .lose
        // Without targets so far the profile's become the baseline; a revision with types only keeps none.
        let baseSource = current == nil ? fallback : current?.baseline
        let baseline = baseSource.map { macros($0, energy: $0.energy + shift, weightKg: weightKg, cut: cut) }
        let byType = (current?.byType ?? [:]).mapValues { macros($0, energy: $0.energy + shift, weightKg: weightKg, cut: cut) }
        let revision = CoachPlan.Revision(from: day, baseline: baseline, byType: byType, reason: "transition")
        return Proposal(phaseID: phase.id, day: day, maintenance: base, source: source, rateMin: rateMin, rateMax: rateMax,
                        rateDerived: derived, adjustment: adjustment, energy: energy, shift: shift, revision: revision, notes: notes)
    }

    /// The targets a transition to `phase` starts from: while another phase is active on `day`,
    /// its revision in force that day; once `phase` itself has been started (Start, or an import
    /// that confirmed it), the targets of the phase that ran before it, as they were on the day
    /// before `phase` began. nil when no phase ran before (then the profile's targets are used).
    public static func targetsBefore(_ phase: CoachPlan.Phase, in plan: CoachPlan, on day: DayKey,
                                     calendar: Calendar = .current) -> CoachPlan.Revision? {
        if let active = plan.activePhase(on: day), active.id != phase.id { return active.revision(on: day) }
        let begin = min(phase.start ?? day, day)
        let previous = plan.phases.filter { other in
            guard other.id != phase.id, other.isStarted, let start = other.start else { return false }
            return start < begin
        }.max { ($0.start ?? begin) < ($1.start ?? begin) }
        guard let previous else { return nil }
        let lastDay = begin.adding(days: -1, calendar: calendar)
        return previous.revision(on: lastDay) ?? previous.revisions.last
    }

    /// A rate range from the target weight and end date: |weight − target| ÷ weeks left, kept
    /// within 0.25–1.0 % of body weight, rounded to 0.01 kg and given ±0.05 kg. nil without a
    /// weight, target, end date, or when the target lies the wrong way.
    public static func rate(for phase: CoachPlan.Phase, weightKg: Double, from day: DayKey, calendar: Calendar = .current) -> ClosedRange<Double>? {
        guard weightKg > 0, phase.targetWeight > 0, let end = phase.end, end > day else { return nil }
        let change = phase.targetWeight - weightKg
        switch phase.goal {
        case .gain: guard change > 0 else { return nil }
        case .lose: guard change < 0 else { return nil }
        case .maintain: return nil
        }
        let weeks = Double(day.days(to: end, calendar: calendar)) / 7
        let raw = abs(change) / max(weeks, 1)
        let percent = min(max(raw / weightKg * 100, ratePercentRange.lowerBound), ratePercentRange.upperBound)
        let mid = (percent * weightKg / 100 * 100).rounded() / 100
        let low = max(rateSpread, ((mid - rateSpread) * 100).rounded() / 100)
        return low...(((mid + rateSpread) * 100).rounded() / 100)
    }

    /// Targets at a new energy: protein keeps its grams (at least 2.2 g/kg in a cut), fat keeps
    /// its grams but at least max(0.6 g/kg, 20 % of kcal), carbs take the rest (5 g steps).
    public static func macros(_ targets: DailyTargets, energy: Double, weightKg: Double, cut: Bool) -> DailyTargets {
        var copy = targets
        copy.energy = max(0, energy)
        // Whole grams up (2.2 × 80 is 176.00000000000003 in binary).
        func gramsUp(_ value: Double) -> Double { (value - 1e-6).rounded(.up) }
        if cut, weightKg > 0 { copy.protein = max(targets.protein, gramsUp(cutProteinPerKg * weightKg)) }
        let fatFloor = max(fatPerKg * max(0, weightKg), fatEnergyShare * copy.energy / 9)
        copy.fat = max(targets.fat, gramsUp(fatFloor))
        let rest = (copy.energy - copy.protein * 4 - copy.fat * 9) / 4
        copy.carbs = max(0, (rest / 5).rounded() * 5)
        return copy
    }

    /// A 1–2 week maintenance bridge is worth offering after a gain phase longer than 12 weeks.
    public static func suggestsBridge(after phase: CoachPlan.Phase, on day: DayKey, calendar: Calendar = .current) -> Bool {
        guard phase.goal == .gain, let start = phase.start else { return false }
        return start.days(to: day, calendar: calendar) > bridgeAfterWeeks * 7
    }
}

// MARK: - Snapshot (DayMark kind checkIn)

/// The 1–5 feelings of a check-in (all optional).
public struct CheckInRatings: Equatable, Hashable, Codable, Sendable {
    public static let keys = ["hunger", "energy", "sleep", "performance", "digestion", "stress", "mood"]

    public var hunger: Int?
    public var energy: Int?
    public var sleep: Int?
    /// Training performance (rated, never programmed).
    public var performance: Int?
    public var digestion: Int?
    public var stress: Int?
    public var mood: Int?

    public init(hunger: Int? = nil, energy: Int? = nil, sleep: Int? = nil, performance: Int? = nil, digestion: Int? = nil,
                stress: Int? = nil, mood: Int? = nil) {
        self.hunger = CheckInRatings.clamped(hunger)
        self.energy = CheckInRatings.clamped(energy)
        self.sleep = CheckInRatings.clamped(sleep)
        self.performance = CheckInRatings.clamped(performance)
        self.digestion = CheckInRatings.clamped(digestion)
        self.stress = CheckInRatings.clamped(stress)
        self.mood = CheckInRatings.clamped(mood)
    }

    public var isEmpty: Bool { self == CheckInRatings() }

    /// By key ("hunger", …); values are kept within 1–5.
    public subscript(_ key: String) -> Int? {
        get {
            switch key {
            case "hunger": hunger
            case "energy": energy
            case "sleep": sleep
            case "performance": performance
            case "digestion": digestion
            case "stress": stress
            case "mood": mood
            default: nil
            }
        }
        set {
            let value = CheckInRatings.clamped(newValue)
            switch key {
            case "hunger": hunger = value
            case "energy": energy = value
            case "sleep": sleep = value
            case "performance": performance = value
            case "digestion": digestion = value
            case "stress": stress = value
            case "mood": mood = value
            default: break
            }
        }
    }

    static func clamped(_ value: Int?) -> Int? { value.map { min(max($0, 1), 5) } }
}

/// What a check-in keeps in its `DayMark(kind: checkIn, key: "week-<Monday>")`: numbers in
/// `values`, the verdict and decision in `meta`. The weight numbers (avg7, prevAvg7, rate,
/// weighIns) are stored only when every weight in the window was typed in Nina; with Health
/// weights they are left out (`source=health`) and recomputed live.
public struct CheckInSnapshot: Equatable, Sendable, Identifiable {
    /// The check-in day (`DayMark.day`).
    public var day: DayKey
    // Weight
    public var avg7: Double?
    public var prevAvg7: Double?
    public var rate: Double?
    public var weighIns: Int?
    /// Health weights were used: the weight numbers aren't stored.
    public var usesHealthWeights: Bool
    // Adherence
    /// Counted (not paused) days, logged ones, on plan.
    public var days: Int?
    public var logged: Int?
    public var onPlan: Int?
    public var kcalAvg: Double?
    public var kcalTarget: Double?
    public var proteinDays: Int?
    public var proteinMeals: Int?
    public var proteinMealsTarget: Int?
    public var waist: Double?
    /// The proposed (or applied, or edited) change in kcal per day.
    public var deltaKcal: Double?
    public var ratings: CheckInRatings
    // Meta
    public var verdict: CheckInVerdict?
    public var deviation: CheckInEngine.Deviation?
    public var decision: CheckInDecision?
    public var phaseID: String

    public var id: String { day.rawValue }

    public init(day: DayKey, avg7: Double? = nil, prevAvg7: Double? = nil, rate: Double? = nil, weighIns: Int? = nil,
                usesHealthWeights: Bool = false, days: Int? = nil, logged: Int? = nil, onPlan: Int? = nil, kcalAvg: Double? = nil,
                kcalTarget: Double? = nil, proteinDays: Int? = nil, proteinMeals: Int? = nil, proteinMealsTarget: Int? = nil,
                waist: Double? = nil, deltaKcal: Double? = nil, ratings: CheckInRatings = CheckInRatings(),
                verdict: CheckInVerdict? = nil, deviation: CheckInEngine.Deviation? = nil, decision: CheckInDecision? = nil,
                phaseID: String = "") {
        self.day = day
        self.avg7 = avg7
        self.prevAvg7 = prevAvg7
        self.rate = rate
        self.weighIns = weighIns
        self.usesHealthWeights = usesHealthWeights
        self.days = days
        self.logged = logged
        self.onPlan = onPlan
        self.kcalAvg = kcalAvg
        self.kcalTarget = kcalTarget
        self.proteinDays = proteinDays
        self.proteinMeals = proteinMeals
        self.proteinMealsTarget = proteinMealsTarget
        self.waist = waist
        self.deltaKcal = deltaKcal
        self.ratings = ratings
        self.verdict = verdict
        self.deviation = deviation
        self.decision = decision
        self.phaseID = phaseID
    }

    /// Reads a check-in mark (`DayMark.values` and `.meta`); unknown keys are ignored.
    public init(day: DayKey, values: String, meta: String) {
        let numbers = KeyValueText(encoded: values)
        let text = KeyValueText(encoded: meta)
        func int(_ key: String) -> Int? {
            numbers.number(key).flatMap { abs($0) < 1e9 ? Int($0.rounded()) : nil }
        }
        let health = text["source"]?.lowercased() == "health"
        var ratings = CheckInRatings()
        for key in CheckInRatings.keys { ratings[key] = int(key) }
        self.init(day: day,
                  avg7: health ? nil : numbers.number("avg7"),
                  prevAvg7: health ? nil : numbers.number("prevAvg7"),
                  rate: health ? nil : numbers.number("rate"),
                  weighIns: health ? nil : int("weighIns"),
                  usesHealthWeights: health,
                  days: int("days"), logged: int("logged"), onPlan: int("onPlan"),
                  kcalAvg: numbers.number("kcalAvg"), kcalTarget: numbers.number("kcalTarget"),
                  proteinDays: int("proteinDays"), proteinMeals: int("proteinMeals"), proteinMealsTarget: int("proteinMealsTarget"),
                  waist: numbers.number("waist"), deltaKcal: numbers.number("deltaKcal"), ratings: ratings,
                  verdict: text["verdict"].flatMap(CheckInVerdict.init(rawValue:)),
                  deviation: text["deviation"].flatMap(CheckInEngine.Deviation.init(rawValue:)),
                  decision: text["applied"].flatMap(CheckInDecision.init(rawValue:)),
                  phaseID: text["phase"] ?? "")
    }

    /// `DayMark.key`: "week-<Monday>".
    public func key(calendar: Calendar = .current) -> String { DayMarks.checkInKey(week: day, calendar: calendar) }

    /// `DayMark.values`: the numbers (without the weight numbers when Health weights were used).
    public var values: String {
        var numbers = KeyValueText()
        if !usesHealthWeights {
            numbers.setNumber(avg7, for: "avg7")
            numbers.setNumber(prevAvg7, for: "prevAvg7")
            numbers.setNumber(rate, for: "rate")
            numbers.setNumber(weighIns.map(Double.init), for: "weighIns")
        }
        numbers.setNumber(days.map(Double.init), for: "days")
        numbers.setNumber(logged.map(Double.init), for: "logged")
        numbers.setNumber(onPlan.map(Double.init), for: "onPlan")
        numbers.setNumber(kcalAvg, for: "kcalAvg")
        numbers.setNumber(kcalTarget, for: "kcalTarget")
        numbers.setNumber(proteinDays.map(Double.init), for: "proteinDays")
        numbers.setNumber(proteinMeals.map(Double.init), for: "proteinMeals")
        numbers.setNumber(proteinMealsTarget.map(Double.init), for: "proteinMealsTarget")
        numbers.setNumber(waist, for: "waist")
        numbers.setNumber(deltaKcal, for: "deltaKcal")
        for key in CheckInRatings.keys { numbers.setNumber(ratings[key].map(Double.init), for: key) }
        return numbers.encoded
    }

    /// `DayMark.meta`: "applied=yes;deviation=below;phase=1;verdict=offTarget" (+ "source=health").
    public var meta: String {
        var text = KeyValueText()
        text["verdict"] = verdict?.rawValue
        text["deviation"] = deviation?.rawValue
        text["applied"] = decision?.rawValue
        text["phase"] = phaseID
        if usesHealthWeights { text["source"] = "health" }
        return text.encoded
    }

    /// Takes the adherence numbers of the week.
    public mutating func record(_ week: AdherenceSummary) {
        days = week.days
        logged = week.loggedDays
        onPlan = week.onPlanDays
        kcalAvg = week.loggedDays > 0 ? week.averageIntake.rounded() : nil
        kcalTarget = week.loggedDays > 0 ? week.averageTarget.rounded() : nil
        proteinDays = week.proteinDays
        proteinMeals = week.proteinMealsTarget > 0 ? week.proteinMeals : nil
        proteinMealsTarget = week.proteinMealsTarget > 0 ? week.proteinMealsTarget : nil
        if !week.ratings.isEmpty { ratings = week.ratings }
    }

    /// Takes the verdict, side and proposal of a result (the decision is set when the person taps).
    public mutating func record(_ result: CheckInResult, phaseID: String) {
        verdict = result.verdict
        deviation = result.deviation
        deltaKcal = result.delta == 0 ? nil : result.delta
        self.phaseID = phaseID
    }

    /// A redo of a week whose change was applied (`saved.decision` applied or edited) that has
    /// no decision of its own keeps the saved decision, Δ, verdict and side: the plan keeps that
    /// change, so the record does too. Only the weight numbers, adherence, ratings, waist and
    /// note are new. Anything else is left as it is.
    public mutating func keepAppliedDecision(of saved: CheckInSnapshot?) {
        guard decision == nil, let saved, saved.decision == .applied || saved.decision == .edited else { return }
        decision = saved.decision
        deltaKcal = saved.deltaKcal
        verdict = saved.verdict
        deviation = saved.deviation
    }

    /// For the history list: "+100 kcal", "Kept", "In range", "Gathering data".
    public var decisionText: String {
        if let deltaKcal, deltaKcal != 0, decision == .applied || decision == .edited {
            return CheckInFormat.signedKcal(deltaKcal) + " kcal"
        }
        if decision == .kept, deltaKcal != nil { return "Kept" }
        return verdict?.title ?? ""
    }
}

// MARK: - Text

/// English display pieces for the reason sentences (the app formats numbers with the locale
/// everywhere else).
private enum CheckInFormat {
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Mon 28 Jan"
    static func day(_ day: DayKey, calendar: Calendar) -> String {
        "\(Weekdays.shortNames[day.weekday(calendar: calendar) - 1]) \(day.day) \(months[max(1, min(12, day.month)) - 1])"
    }

    /// "1,500"
    static func kcal(_ value: Double) -> String {
        let number = Int(value.rounded())
        let digits = String(abs(number))
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped += "," }
            grouped.append(character)
        }
        return (number < 0 ? "−" : "") + grouped
    }

    /// "+100", "−150"
    static func signedKcal(_ value: Double) -> String {
        value < 0 ? "−" + kcal(-value) : "+" + kcal(value)
    }

    /// "+0.05", "−0.30", "0.00"
    static func rate(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let text = String(format: "%.2f", abs(rounded))
        if rounded > 0 { return "+" + text }
        if rounded < 0 { return "−" + text }
        return text
    }

    /// "today", "1 day ago", "9 days ago"
    static func daysAgo(_ days: Int) -> String {
        switch days {
        case ...0: "today"
        case 1: "1 day ago"
        default: "\(days) days ago"
        }
    }

    /// "two", "three", … for check-ins in a row.
    static func count(_ number: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six"]
        return number >= 0 && number < words.count ? words[number] : "\(number)"
    }
}
