import Foundation

/// The coach plan: day types for calorie cycling, dated phases with target revisions, the
/// long-term body goal, protein per meal, daily checks, the measuring routine, the adjustment
/// rules, pauses and plan notes. Stored as JSON in `NinaProfile.coachPlan` ("" = no plan),
/// synced, newest wins.
///
/// Decoding is lenient: every field falls back to its default when it is missing or has the wrong
/// type, unknown keys are ignored, a broken list item is dropped, and an empty or broken text is an
/// empty plan. Nothing in here switches or changes by itself: a phase counts only once it was
/// started (`startedAt`), and changed targets are new revisions that start on a given day, so past
/// days keep the targets they had.
public struct CoachPlan: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var v: Int
    public var dayTypes: [DayType]
    public var phases: [Phase]
    public var longTerm: LongTerm
    public var protein: Protein
    public var checks: [Check]
    public var routine: Routine
    public var adjust: Adjust
    public var pauses: [Pause]
    /// Plan notes (advice from the plan, shown in the plan editor).
    public var notes: [String]

    public init(dayTypes: [DayType] = [], phases: [Phase] = [], longTerm: LongTerm = LongTerm(),
                protein: Protein = Protein(), checks: [Check] = [], routine: Routine = Routine(),
                adjust: Adjust = Adjust(), pauses: [Pause] = [], notes: [String] = [], v: Int = CoachPlan.currentVersion) {
        self.v = v
        self.dayTypes = dayTypes
        self.phases = phases
        self.longTerm = longTerm
        self.protein = protein
        self.checks = checks
        self.routine = routine
        self.adjust = adjust
        self.pauses = pauses
        self.notes = notes
    }

    /// Nothing set at all (what "" decodes to).
    public var isEmpty: Bool { self == CoachPlan() }

    /// A plan has been set up: it has a phase or a day type. Without one, Nina behaves as before.
    public var isSetUp: Bool { !phases.isEmpty || !dayTypes.isEmpty }

    // MARK: Text encoding (NinaProfile.coachPlan)

    /// JSON with sorted keys; "" for an empty plan.
    public var encoded: String {
        guard !isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads `encoded`; an empty or broken text gives an empty plan.
    public init(encoded: String) {
        let text = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let plan = try? JSONDecoder().decode(CoachPlan.self, from: data) else {
            self.init()
            return
        }
        self = plan
    }

    enum CodingKeys: String, CodingKey {
        case v, dayTypes, phases, longTerm, protein, checks, routine, adjust, pauses, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = c.integer(.v, CoachPlan.currentVersion)
        dayTypes = c.list(.dayTypes)
        phases = c.list(.phases)
        longTerm = c.value(.longTerm, LongTerm())
        protein = c.value(.protein, Protein())
        checks = c.list(.checks)
        routine = c.value(.routine, Routine())
        adjust = c.value(.adjust, Adjust())
        pauses = c.list(.pauses)
        notes = c.texts(.notes, splitting: false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(dayTypes, forKey: .dayTypes)
        try c.encode(phases, forKey: .phases)
        try c.encode(longTerm, forKey: .longTerm)
        try c.encode(protein, forKey: .protein)
        try c.encode(checks, forKey: .checks)
        try c.encode(routine, forKey: .routine)
        try c.encode(adjust, forKey: .adjust)
        try c.encode(pauses, forKey: .pauses)
        try c.encode(notes, forKey: .notes)
    }
}

// MARK: - Day types

extension CoachPlan {
    /// How a day type is scheduled.
    public enum Schedule: String, Codable, Sendable, CaseIterable, Identifiable {
        /// On fixed ISO weekdays (Gym = Mon, Wed, Fri).
        case fixed
        /// Picked by hand, n per week as a hint (Tennis = 2).
        case flexible
        /// Every other day (exactly one type, e.g. Rest).
        case `default`

        public var id: String { rawValue }
    }

    /// A kind of day with its own targets (calorie cycling): "Gym", "Tennis", "Rest".
    public struct DayType: Codable, Equatable, Sendable, Identifiable {
        /// `[a-z0-9]+`, used in revisions (`byType`), day marks and check days.
        public var id: String
        public var name: String
        public var emoji: String
        public var schedule: Schedule
        /// `fixed`: the ISO weekdays it's on.
        public var weekdays: Weekdays
        /// `flexible`: days per week (a hint, never a nag).
        public var perWeek: Int
        /// Apple Health workout kinds that suggest this type ("strength", "tennis").
        public var workouts: [String]

        public init(id: String, name: String, emoji: String = "", schedule: Schedule, weekdays: Weekdays = Weekdays([]),
                    perWeek: Int = 0, workouts: [String] = []) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.schedule = schedule
            self.weekdays = weekdays
            self.perWeek = perWeek
            self.workouts = workouts
        }

        /// A fitting emoji for a type name: 🏋️ gym/training, 🎾 tennis, 🛋️ rest, … ("" when nothing fits).
        public static func suggestedEmoji(for name: String) -> String {
            let text = name.lowercased()
            let table: [(words: [String], emoji: String)] = [
                (["tennis", "padel", "squash", "badminton"], "🎾"),
                (["gym", "training", "strength", "kraft", "weights", "lift"], "🏋️"),
                (["rest", "off", "ruhe", "pause", "frei"], "🛋️"),
                (["run", "lauf", "jog"], "🏃"),
                (["swim", "schwimm"], "🏊"),
                (["bike", "cycl", "rad"], "🚴"),
                (["hike", "wander"], "🥾"),
                (["ski"], "⛷️"),
                (["football", "soccer", "fußball", "fussball"], "⚽️"),
            ]
            return table.first { entry in entry.words.contains { text.contains($0) } }?.emoji ?? ""
        }

        enum CodingKeys: String, CodingKey { case id, name, emoji, schedule, weekdays, perWeek, workouts }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id)
            guard !id.isEmpty else { throw CoachPlan.missing("dayType.id", decoder) }
            name = c.text(.name)
            emoji = c.text(.emoji)
            schedule = Schedule(rawValue: c.text(.schedule)) ?? .flexible
            weekdays = c.weekdays(.weekdays)
            perWeek = max(0, c.integer(.perWeek, 0))
            workouts = c.texts(.workouts, splitting: true)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(emoji, forKey: .emoji)
            try c.encode(schedule.rawValue, forKey: .schedule)
            try c.encode(weekdays.encoded, forKey: .weekdays)
            try c.encode(perWeek, forKey: .perWeek)
            try c.encode(workouts, forKey: .workouts)
        }
    }
}

// MARK: - Phases

extension CoachPlan {
    public enum PhaseStatus: String, Codable, Sendable, CaseIterable, Identifiable {
        case planned, active, done

        public var id: String { rawValue }
    }

    /// The targets of a phase from a day on. Adjustments and edits add a revision (usually from
    /// tomorrow), so earlier days keep their targets.
    public struct Revision: Codable, Equatable, Sendable {
        public var from: DayKey
        /// Targets for days without an own set (stored as `DailyTargets.encoded`).
        public var baseline: DailyTargets?
        /// Day type id → targets (stored as `DailyTargets.encoded`).
        public var byType: [String: DailyTargets]
        /// "import", "edit", "adjust:+100".
        public var reason: String

        public init(from: DayKey, baseline: DailyTargets? = nil, byType: [String: DailyTargets] = [:], reason: String = "edit") {
            self.from = from
            self.baseline = baseline
            self.byType = byType
            self.reason = reason
        }

        /// The type's own targets, else the baseline.
        public func targets(for typeID: String?) -> DailyTargets? {
            if let typeID, let own = byType[typeID] { return own }
            return baseline
        }

        enum CodingKeys: String, CodingKey { case from, baseline, byType, reason }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let day = c.day(.from) else { throw CoachPlan.missing("revision.from", decoder) }
            from = day
            let base = c.text(.baseline)
            baseline = base.isEmpty ? nil : DailyTargets(encoded: base)
            let raw = c.value(.byType, [String: String]())
            byType = raw.reduce(into: [:]) { result, item in
                let key = item.key.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !item.value.isEmpty else { return }
                result[key] = DailyTargets(encoded: item.value)
            }
            reason = c.text(.reason)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(from, forKey: .from)
            try c.encode(baseline?.encoded ?? "", forKey: .baseline)
            try c.encode(byType.mapValues(\.encoded), forKey: .byType)
            try c.encode(reason, forKey: .reason)
        }
    }

    /// A stretch of weeks with one goal: "Lean gain, 7 Jan – ~26 May, +0.15 to +0.25 kg/week".
    /// A diet break is simply a short maintain phase.
    public struct Phase: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var goal: WeightGoal
        public var start: DayKey?
        /// The start is approximate ("~1 Apr"): planned phases only.
        public var startApprox: Bool
        /// Soft: only triggers prompts.
        public var end: DayKey?
        public var endApprox: Bool
        /// kg per week, positive for gain and loss alike (the goal gives the direction).
        public var rateMin: Double
        public var rateMax: Double
        /// Review checkpoint (kg), 0 = none.
        public var reviewMin: Double
        public var reviewMax: Double
        /// 0 = none.
        public var targetWeight: Double
        /// Percent, 0 = none.
        public var targetBodyFat: Double
        /// Waist gain since the phase start that opens the review (4 cm by default in a gain phase).
        public var maxWaistGainCm: Double
        /// Body fat (%) that opens the review in a gain phase (`BodyCeiling.bodyFat`), 0 = off (the
        /// default). Compared with the latest value of the tracking series.
        public var bodyFatCeiling: Double
        /// kg, 0 = taken from the weigh-ins.
        public var startWeight: Double
        /// When the person confirmed the start. Only started phases are active.
        public var startedAt: Date? {
            didSet { if let startedAt, startedAt != CoachPlan.wholeSeconds(startedAt) { self.startedAt = CoachPlan.wholeSeconds(startedAt) } }
        }
        public var status: PhaseStatus
        public var note: String
        /// Sorted by `from`.
        public var revisions: [Revision]

        public init(id: String, name: String = "", goal: WeightGoal = .maintain, start: DayKey? = nil, startApprox: Bool = false,
                    end: DayKey? = nil, endApprox: Bool = false, rateMin: Double = 0, rateMax: Double = 0,
                    reviewMin: Double = 0, reviewMax: Double = 0, targetWeight: Double = 0, targetBodyFat: Double = 0,
                    maxWaistGainCm: Double? = nil, startWeight: Double = 0, startedAt: Date? = nil,
                    status: PhaseStatus = .planned, note: String = "", revisions: [Revision] = [], bodyFatCeiling: Double = 0) {
            self.id = id
            self.name = name
            self.goal = goal
            self.start = start
            self.startApprox = startApprox
            self.end = end
            self.endApprox = endApprox
            self.rateMin = rateMin
            self.rateMax = rateMax
            self.reviewMin = reviewMin
            self.reviewMax = reviewMax
            self.targetWeight = targetWeight
            self.targetBodyFat = targetBodyFat
            self.maxWaistGainCm = maxWaistGainCm ?? Phase.defaultMaxWaistGain(for: goal)
            self.bodyFatCeiling = max(0, bodyFatCeiling)
            self.startWeight = startWeight
            self.startedAt = startedAt.map(CoachPlan.wholeSeconds)
            self.status = status
            self.note = note
            self.revisions = revisions
        }

        /// 4 cm in a gain phase, otherwise off (0).
        public static func defaultMaxWaistGain(for goal: WeightGoal) -> Double { goal == .gain ? 4 : 0 }

        /// "Weight gain", "Maintenance", "Weight loss".
        public static func defaultName(for goal: WeightGoal) -> String {
            switch goal {
            case .gain: "Weight gain"
            case .maintain: "Maintenance"
            case .lose: "Weight loss"
            }
        }

        /// Confirmed by the person (only then it can be active).
        public var isStarted: Bool { startedAt != nil }

        /// The rate range in kg/week as magnitudes, lower bound first.
        public var rateRange: ClosedRange<Double> {
            let low = max(0, min(rateMin, rateMax)), high = max(0, rateMin, rateMax)
            return low...high
        }

        /// The midpoint of the rate range (kg/week, positive); targets use it.
        public var rateMid: Double { (rateRange.lowerBound + rateRange.upperBound) / 2 }

        /// The rate range with its direction: gain +0.15…+0.25, loss −0.5…−0.3, maintain −max…+max.
        public var signedRateRange: ClosedRange<Double> {
            let range = rateRange
            switch goal {
            case .gain: return range
            case .lose: return -range.upperBound...(-range.lowerBound)
            case .maintain: return -range.upperBound...range.upperBound
            }
        }

        /// The midpoint with its direction (0 while maintaining).
        public var signedRateMid: Double {
            switch goal {
            case .gain: rateMid
            case .lose: -rateMid
            case .maintain: 0
            }
        }

        /// Daily surplus (+) or deficit (−) for the midpoint: kg/week × 7,700 ÷ 7 = × 1,100 kcal,
        /// rounded to 50 (0.15 → +150), as the transition proposal uses it.
        public var energyAdjustment: Double {
            let size = CheckInEngine.rounded50(rateMid * GoalCalculator.kilocaloriesPerKilogram / 7)
            switch goal {
            case .gain: return size
            case .lose: return -size
            case .maintain: return 0
            }
        }

        /// A gain of this much or less per week is labelled "Slow (lean) gain" (kg/week).
        public static let leanGainMax = 0.25
        /// A gain faster than this share of body weight per week gets a calm caution (%).
        public static let gainCautionPercent = 0.5
        /// A loss faster than this share of body weight per week gets a calm caution (%).
        public static let lossCautionPercent = 1.0

        /// "Slow (lean) gain" when the whole range of a gain is 0.25 kg/week or less; nil otherwise.
        /// Also for the single pace without a plan (`rate` = value...value).
        public static func rateLabel(goal: WeightGoal, rate: ClosedRange<Double>) -> String? {
            guard goal == .gain, rate.upperBound > 0, rate.upperBound <= leanGainMax + 1e-9 else { return nil }
            return "Slow (lean) gain"
        }

        /// A calm caution when the fastest pace of the range is more than 0.5 % of body weight a
        /// week while gaining, or more than 1 % while losing (% = kg ÷ the 7-day average × 100).
        /// nil without a weight, while maintaining or within the limits.
        public static func rateCaution(goal: WeightGoal, rate: ClosedRange<Double>, weightKg: Double) -> String? {
            guard let percent = WeightSignal.percent(rate.upperBound, of: weightKg) else { return nil }
            switch goal {
            case .gain where percent > gainCautionPercent + 1e-9:
                return "That's more than 0.5 % of your weight a week – a slower gain usually adds less fat."
            case .lose where percent > lossCautionPercent + 1e-9:
                return "That's more than 1 % of your weight a week – a slower loss makes it easier to keep muscle."
            default:
                return nil
            }
        }

        /// "Slow (lean) gain" for this phase's range (see `rateLabel(goal:rate:)`).
        public var rateLabel: String? { Phase.rateLabel(goal: goal, rate: rateRange) }

        /// The calm caution for this phase's range at a weight (see `rateCaution(goal:rate:weightKg:)`).
        public func rateCaution(weightKg: Double) -> String? {
            Phase.rateCaution(goal: goal, rate: rateRange, weightKg: weightKg)
        }

        /// Week of the phase a day falls in, 1 on the start day; nil before the start or without one.
        public func week(on day: DayKey, calendar: Calendar = .current) -> Int? {
            guard let start, day >= start else { return nil }
            return start.days(to: day, calendar: calendar) / 7 + 1
        }

        /// Whole weeks from start through end (rounded up); nil without both.
        public func weeks(calendar: Calendar = .current) -> Int? {
            guard let start, let end, end >= start else { return nil }
            let days = start.days(to: end, calendar: calendar) + 1
            return max(1, (days + 6) / 7)
        }

        /// The revision in force on a day: the newest one with `from <= day` (nil before the first).
        public func revision(on day: DayKey) -> Revision? {
            var best: Revision?
            for revision in revisions where revision.from <= day {
                if let current = best, revision.from < current.from { continue }
                best = revision
            }
            return best
        }

        enum CodingKeys: String, CodingKey {
            case id, name, goal, start, startApprox, end, endApprox, rateMin, rateMax, reviewMin, reviewMax, targetWeight,
                 targetBodyFat, maxWaistGainCm, bodyFatCeiling, startWeight, startedAt, status, note, revisions
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id)
            guard !id.isEmpty else { throw CoachPlan.missing("phase.id", decoder) }
            name = c.text(.name)
            goal = WeightGoal(rawValue: c.text(.goal)) ?? .maintain
            start = c.day(.start)
            startApprox = c.flag(.startApprox, false)
            end = c.day(.end)
            endApprox = c.flag(.endApprox, false)
            rateMin = c.number(.rateMin, 0)
            rateMax = c.number(.rateMax, 0)
            reviewMin = c.number(.reviewMin, 0)
            reviewMax = c.number(.reviewMax, 0)
            targetWeight = c.number(.targetWeight, 0)
            targetBodyFat = c.number(.targetBodyFat, 0)
            maxWaistGainCm = c.number(.maxWaistGainCm, Phase.defaultMaxWaistGain(for: goal))
            bodyFatCeiling = max(0, c.number(.bodyFatCeiling, 0))
            startWeight = c.number(.startWeight, 0)
            startedAt = c.moment(.startedAt)
            status = PhaseStatus(rawValue: c.text(.status)) ?? .planned
            note = c.text(.note)
            let revisions: [Revision] = c.list(.revisions)
            self.revisions = revisions.sorted { $0.from < $1.from }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(goal.rawValue, forKey: .goal)
            try c.encode(start?.rawValue ?? "", forKey: .start)
            try c.encode(startApprox, forKey: .startApprox)
            try c.encode(end?.rawValue ?? "", forKey: .end)
            try c.encode(endApprox, forKey: .endApprox)
            try c.encode(rateMin, forKey: .rateMin)
            try c.encode(rateMax, forKey: .rateMax)
            try c.encode(reviewMin, forKey: .reviewMin)
            try c.encode(reviewMax, forKey: .reviewMax)
            try c.encode(targetWeight, forKey: .targetWeight)
            try c.encode(targetBodyFat, forKey: .targetBodyFat)
            try c.encode(maxWaistGainCm, forKey: .maxWaistGainCm)
            // Written only when set, so plans without a ceiling keep their exact text.
            if bodyFatCeiling > 0 { try c.encode(bodyFatCeiling, forKey: .bodyFatCeiling) }
            try c.encode(startWeight, forKey: .startWeight)
            try c.encode(startedAt.map(CoachPlan.momentText) ?? "", forKey: .startedAt)
            try c.encode(status.rawValue, forKey: .status)
            try c.encode(note, forKey: .note)
            try c.encode(revisions, forKey: .revisions)
        }
    }
}

// MARK: - Long-term goal, protein, checks, routine, adjustments, pauses

extension CoachPlan {
    /// The long-term body goal (separate from the active phase's target weight).
    public struct LongTerm: Codable, Equatable, Sendable {
        /// 0 = none.
        public var weightKg: Double
        /// Percent, 0 = none.
        public var bodyFat: Double
        /// 0 = none.
        public var waistCm: Double
        public var date: DayKey?
        public var note: String
        /// The day the weight or body-fat goal was set (F8: progress starts at the first value of
        /// the tracking series on or after it). nil = not known (the series' first value).
        public var since: DayKey?

        public init(weightKg: Double = 0, bodyFat: Double = 0, waistCm: Double = 0, date: DayKey? = nil, note: String = "",
                    since: DayKey? = nil) {
            self.weightKg = weightKg
            self.bodyFat = bodyFat
            self.waistCm = waistCm
            self.date = date
            self.note = note
            self.since = since
        }

        public var isSet: Bool { weightKg > 0 || bodyFat > 0 || waistCm > 0 }

        /// This goal as saved on `day` over `previous`: a new weight or body-fat goal counts from
        /// `day` (`since` = `day`); with both unchanged the goal keeps `previous.since`; without
        /// either goal there is nothing to count from (nil).
        public func stamped(after previous: LongTerm, on day: DayKey) -> LongTerm {
            var copy = self
            if weightKg <= 0, bodyFat <= 0 {
                copy.since = nil
            } else if abs(weightKg - previous.weightKg) > 1e-9 || abs(bodyFat - previous.bodyFat) > 1e-9 {
                copy.since = day
            } else {
                copy.since = previous.since
            }
            return copy
        }

        enum CodingKeys: String, CodingKey { case weightKg, bodyFat, waistCm, date, note, since }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weightKg = c.number(.weightKg, 0)
            bodyFat = c.number(.bodyFat, 0)
            waistCm = c.number(.waistCm, 0)
            date = c.day(.date)
            note = c.text(.note)
            since = c.day(.since)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(weightKg, forKey: .weightKg)
            try c.encode(bodyFat, forKey: .bodyFat)
            try c.encode(waistCm, forKey: .waistCm)
            try c.encode(date?.rawValue ?? "", forKey: .date)
            try c.encode(note, forKey: .note)
            // Written only when set, so goals without it keep their exact text.
            if let since { try c.encode(since.rawValue, forKey: .since) }
        }
    }

    /// Protein per eating occasion.
    public struct Protein: Codable, Equatable, Sendable {
        /// g per protein meal, 0 = not set (0.4 g/kg body weight is used then).
        public var mealMin: Double
        /// g, 0 = no maximum.
        public var mealMax: Double
        /// Protein meals per day, 0 = one per meal in `meals` (or per meal slot).
        public var count: Int
        /// Meal slot ids that count ("breakfast", "lunch", …); empty = all.
        public var meals: [String]

        public init(mealMin: Double = 0, mealMax: Double = 0, count: Int = 0, meals: [String] = []) {
            self.mealMin = mealMin
            self.mealMax = mealMax
            self.count = count
            self.meals = meals
        }

        /// A minimum per meal was set in the plan.
        public var isSet: Bool { mealMin > 0 }

        /// The minimum per meal: the set one, else 0.4 g per kg (rounded to 1 g; 0 without a weight).
        public func minimum(weightKg: Double) -> Double {
            if mealMin > 0 { return mealMin }
            return weightKg > 0 ? (weightKg * 0.4).rounded() : 0
        }

        /// Protein meals per day: the set count, else one per listed meal, else one per meal slot.
        public func effectiveCount(mealSlots: Int) -> Int {
            if count > 0 { return count }
            return meals.isEmpty ? mealSlots : meals.count
        }

        enum CodingKeys: String, CodingKey { case mealMin, mealMax, count, meals }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mealMin = c.number(.mealMin, 0)
            mealMax = c.number(.mealMax, 0)
            count = max(0, c.integer(.count, 0))
            meals = c.texts(.meals, splitting: true)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(mealMin, forKey: .mealMin)
            try c.encode(mealMax, forKey: .mealMax)
            try c.encode(count, forKey: .count)
            try c.encode(meals, forKey: .meals)
        }
    }

    /// When a daily check is due: "anytime", "meal:breakfast" or "time:08:00".
    public enum CheckTiming: Equatable, Hashable, Sendable {
        case anytime
        /// A meal slot id.
        case meal(String)
        /// Minutes after midnight.
        case time(Int)

        public var encoded: String {
            switch self {
            case .anytime: "anytime"
            case .meal(let id): "meal:\(id)"
            case .time(let minutes): "time:\(ClockTime.text(minutes))"
            }
        }

        /// Also reads a bare "08:00" or a bare meal id; "" is anytime.
        public init(encoded: String) {
            let text = encoded.trimmingCharacters(in: .whitespaces)
            let lower = text.lowercased()
            if lower.isEmpty || lower == "anytime" || lower == "any" {
                self = .anytime
            } else if lower.hasPrefix("meal:") {
                let id = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                self = id.isEmpty ? .anytime : .meal(id)
            } else if lower.hasPrefix("time:") {
                self = ClockTime.parse(String(text.dropFirst(5))).map(CheckTiming.time) ?? .anytime
            } else if lower.first?.isNumber == true, let minutes = ClockTime.parse(text) {
                self = .time(minutes)
            } else {
                self = .meal(text)
            }
        }
    }

    /// On which days a check is due: "daily", "weekdays:1,2,3,4,5" or "types:gym,tennis".
    public enum CheckDays: Equatable, Hashable, Sendable {
        case daily
        case weekdays(Weekdays)
        /// Day type ids.
        case dayTypes([String])

        public var encoded: String {
            switch self {
            case .daily: "daily"
            case .weekdays(let days): "weekdays:\(days.encoded)"
            case .dayTypes(let ids): "types:\(ids.joined(separator: ","))"
            }
        }

        /// Also reads bare weekday numbers ("1,3,5") or bare type ids ("gym,tennis"); "" is daily.
        public init(encoded: String) {
            let text = encoded.trimmingCharacters(in: .whitespaces)
            let lower = text.lowercased()
            func items(_ raw: Substring) -> [String] {
                raw.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if lower.isEmpty || lower == "daily" || lower == "every day" {
                self = .daily
            } else if lower.hasPrefix("weekdays:") {
                self = .weekdays(Weekdays(encoded: String(text.dropFirst(9))))
            } else if lower.hasPrefix("types:") {
                let ids = items(text.dropFirst(6))
                self = ids.isEmpty ? .daily : .dayTypes(ids)
            } else {
                let parts = items(Substring(text))
                if !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) {
                    self = .weekdays(Weekdays(encoded: parts.joined(separator: ",")))
                } else {
                    self = parts.isEmpty ? .daily : .dayTypes(parts)
                }
            }
        }
    }

    /// A daily check from the plan (a supplement): "Creatine · 3–5 g". Nina only shows what the
    /// plan says; checks have no nutrients and are never written to Health.
    public struct Check: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var emoji: String
        /// Text as written: "3–5 g".
        public var dose: String
        public var timing: CheckTiming
        public var days: CheckDays
        /// Optional checks never count as missed. (JSON key "optional".)
        public var isOptional: Bool
        public var remind: Bool
        /// Taking it can move the scale (creatine): holds "faster than planned" for 28 days.
        public var affectsWeight: Bool

        public init(id: String, name: String, emoji: String = "", dose: String = "", timing: CheckTiming = .anytime,
                    days: CheckDays = .daily, isOptional: Bool = false, remind: Bool = false, affectsWeight: Bool? = nil) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.dose = dose
            self.timing = timing
            self.days = days
            self.isOptional = isOptional
            self.remind = remind
            self.affectsWeight = affectsWeight ?? Check.affectsWeight(name: name)
        }

        /// Creatine binds water, so it is marked "affects weight" when its name says so.
        public static func affectsWeight(name: String) -> Bool {
            let text = name.lowercased()
            return text.contains("creatin") || text.contains("kreatin")
        }

        /// Due on a day with the given day type.
        public func isDue(on day: DayKey, dayTypeID: String?, calendar: Calendar = .current) -> Bool {
            switch days {
            case .daily: return true
            case .weekdays(let weekdays): return weekdays.contains(day, calendar: calendar)
            case .dayTypes(let ids): return dayTypeID.map(ids.contains) ?? false
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, emoji, dose, timing, days
            case isOptional = "optional"
            case remind, affectsWeight
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.text(.id)
            guard !id.isEmpty else { throw CoachPlan.missing("check.id", decoder) }
            name = c.text(.name)
            emoji = c.text(.emoji)
            dose = c.text(.dose)
            timing = CheckTiming(encoded: c.text(.timing))
            days = CheckDays(encoded: c.text(.days))
            isOptional = c.flag(.isOptional, false)
            remind = c.flag(.remind, false)
            affectsWeight = c.flag(.affectsWeight, Check.affectsWeight(name: name))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(emoji, forKey: .emoji)
            try c.encode(dose, forKey: .dose)
            try c.encode(timing.encoded, forKey: .timing)
            try c.encode(days.encoded, forKey: .days)
            try c.encode(isOptional, forKey: .isOptional)
            try c.encode(remind, forKey: .remind)
            try c.encode(affectsWeight, forKey: .affectsWeight)
        }
    }

    /// When and what to measure.
    public struct Routine: Codable, Equatable, Sendable {
        /// Weigh-in reminder, minutes after midnight (07:00).
        public var weighInMinutes: Int
        /// Weigh-ins before this count as morning weights (11:00).
        public var morningCutoffMinutes: Int
        public var weeklySites: [BodySite]
        public var fullSites: [BodySite]
        public var fullEveryWeeks: Int
        public var bodyFatEveryWeeks: Int
        /// The tracking method (nil = the most accurate one with at least 2 values).
        public var bodyFatMethod: BodyMethod?
        public var side: BodySide
        /// Where the thigh is measured, e.g. "20 cm above kneecap" ("" = halfway).
        public var thighMark: String
        /// Two readings per site in a full set.
        public var twoReadings: Bool
        /// ISO weekday of the weekly check-in (1 = Monday).
        public var checkInWeekday: Int

        public static let defaultWeeklySites: [BodySite] = [.waist]
        public static let defaultFullSites: [BodySite] = [.neck, .chest, .arm, .waist, .hip, .thigh]

        public init(weighInMinutes: Int = 420, morningCutoffMinutes: Int = 660, weeklySites: [BodySite] = Routine.defaultWeeklySites,
                    fullSites: [BodySite] = Routine.defaultFullSites, fullEveryWeeks: Int = 8, bodyFatEveryWeeks: Int = 8,
                    bodyFatMethod: BodyMethod? = nil, side: BodySide = .right, thighMark: String = "", twoReadings: Bool = true,
                    checkInWeekday: Int = 1) {
            self.weighInMinutes = weighInMinutes
            self.morningCutoffMinutes = morningCutoffMinutes
            self.weeklySites = weeklySites
            self.fullSites = fullSites
            self.fullEveryWeeks = fullEveryWeeks
            self.bodyFatEveryWeeks = bodyFatEveryWeeks
            self.bodyFatMethod = bodyFatMethod
            self.side = side
            self.thighMark = thighMark
            self.twoReadings = twoReadings
            self.checkInWeekday = checkInWeekday
        }

        /// The defaults, with the narrow waist instead of the navel waist for women (US Navy sites).
        public static func defaults(for sex: Sex) -> Routine {
            guard sex == .female else { return Routine() }
            func swap(_ sites: [BodySite]) -> [BodySite] { sites.map { $0 == .waist ? .waistNarrow : $0 } }
            return Routine(weeklySites: swap(defaultWeeklySites), fullSites: swap(defaultFullSites))
        }

        enum CodingKeys: String, CodingKey {
            case weighInMinutes, morningCutoffMinutes, weeklySites, fullSites, fullEveryWeeks, bodyFatEveryWeeks, bodyFatMethod,
                 side, thighMark, twoReadings, checkInWeekday
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Routine()
            weighInMinutes = c.integer(.weighInMinutes, defaults.weighInMinutes)
            morningCutoffMinutes = c.integer(.morningCutoffMinutes, defaults.morningCutoffMinutes)
            weeklySites = c.contains(.weeklySites) ? c.texts(.weeklySites, splitting: true).compactMap(BodySite.init(rawValue:)) : defaults.weeklySites
            fullSites = c.contains(.fullSites) ? c.texts(.fullSites, splitting: true).compactMap(BodySite.init(rawValue:)) : defaults.fullSites
            fullEveryWeeks = max(1, c.integer(.fullEveryWeeks, defaults.fullEveryWeeks))
            bodyFatEveryWeeks = max(1, c.integer(.bodyFatEveryWeeks, defaults.bodyFatEveryWeeks))
            bodyFatMethod = BodyMethod(rawValue: c.text(.bodyFatMethod))
            side = BodySide(rawValue: c.text(.side)) ?? defaults.side
            thighMark = c.text(.thighMark)
            twoReadings = c.flag(.twoReadings, defaults.twoReadings)
            let weekday = c.integer(.checkInWeekday, defaults.checkInWeekday)
            checkInWeekday = (1...7).contains(weekday) ? weekday : defaults.checkInWeekday
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(weighInMinutes, forKey: .weighInMinutes)
            try c.encode(morningCutoffMinutes, forKey: .morningCutoffMinutes)
            try c.encode(weeklySites.map(\.rawValue), forKey: .weeklySites)
            try c.encode(fullSites.map(\.rawValue), forKey: .fullSites)
            try c.encode(fullEveryWeeks, forKey: .fullEveryWeeks)
            try c.encode(bodyFatEveryWeeks, forKey: .bodyFatEveryWeeks)
            try c.encode(bodyFatMethod?.rawValue ?? "", forKey: .bodyFatMethod)
            try c.encode(side.rawValue, forKey: .side)
            try c.encode(thighMark, forKey: .thighMark)
            try c.encode(twoReadings, forKey: .twoReadings)
            try c.encode(checkInWeekday, forKey: .checkInWeekday)
        }
    }

    /// The rules for weekly adjustment proposals (F11).
    public struct Adjust: Codable, Equatable, Sendable {
        public var windowMinDays: Int
        public var windowMaxDays: Int
        /// kcal
        public var stepMin: Double
        /// kcal
        public var stepMax: Double
        /// ± kcal between average intake and average target for the adherence gate.
        public var intakeTolerance: Double
        /// No new proposal this many days after an applied change.
        public var lockDays: Int
        /// Check-ins in a row outside the range before a proposal.
        public var confirmChecks: Int
        /// kg/week of slack around the rate range.
        public var tolerance: Double
        /// A gain phase never goes above measured maintenance + this (kcal).
        public var gainCapOverMaintenance: Double

        public init(windowMinDays: Int = 14, windowMaxDays: Int = 21, stepMin: Double = 100, stepMax: Double = 150,
                    intakeTolerance: Double = 150, lockDays: Int = 14, confirmChecks: Int = 2, tolerance: Double = 0.03,
                    gainCapOverMaintenance: Double = 500) {
            self.windowMinDays = windowMinDays
            self.windowMaxDays = windowMaxDays
            self.stepMin = stepMin
            self.stepMax = stepMax
            self.intakeTolerance = intakeTolerance
            self.lockDays = lockDays
            self.confirmChecks = confirmChecks
            self.tolerance = tolerance
            self.gainCapOverMaintenance = gainCapOverMaintenance
        }

        enum CodingKeys: String, CodingKey {
            case windowMinDays, windowMaxDays, stepMin, stepMax, intakeTolerance, lockDays, confirmChecks, tolerance, gainCapOverMaintenance
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Adjust()
            windowMinDays = c.integer(.windowMinDays, d.windowMinDays)
            windowMaxDays = c.integer(.windowMaxDays, d.windowMaxDays)
            stepMin = c.number(.stepMin, d.stepMin)
            stepMax = c.number(.stepMax, d.stepMax)
            intakeTolerance = c.number(.intakeTolerance, d.intakeTolerance)
            lockDays = c.integer(.lockDays, d.lockDays)
            confirmChecks = c.integer(.confirmChecks, d.confirmChecks)
            tolerance = c.number(.tolerance, d.tolerance)
            gainCapOverMaintenance = c.number(.gainCapOverMaintenance, d.gainCapOverMaintenance)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(windowMinDays, forKey: .windowMinDays)
            try c.encode(windowMaxDays, forKey: .windowMaxDays)
            try c.encode(stepMin, forKey: .stepMin)
            try c.encode(stepMax, forKey: .stepMax)
            try c.encode(intakeTolerance, forKey: .intakeTolerance)
            try c.encode(lockDays, forKey: .lockDays)
            try c.encode(confirmChecks, forKey: .confirmChecks)
            try c.encode(tolerance, forKey: .tolerance)
            try c.encode(gainCapOverMaintenance, forKey: .gainCapOverMaintenance)
        }
    }

    public enum PauseReason: String, Codable, Sendable, CaseIterable, Identifiable {
        case holiday, sick, other

        public var id: String { rawValue }
    }

    /// Coaching paused (holiday, ill): no check-ins or check pills, paused days left out of windows.
    public struct Pause: Codable, Equatable, Sendable {
        public var start: DayKey
        /// nil = until resumed.
        public var end: DayKey?
        public var reason: PauseReason

        public init(start: DayKey, end: DayKey? = nil, reason: PauseReason = .other) {
            self.start = start
            self.end = end
            self.reason = reason
        }

        public func contains(_ day: DayKey) -> Bool {
            guard day >= start else { return false }
            guard let end else { return true }
            return day <= end
        }

        enum CodingKeys: String, CodingKey { case start, end, reason }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let day = c.day(.start) else { throw CoachPlan.missing("pause.start", decoder) }
            start = day
            end = c.day(.end)
            reason = PauseReason(rawValue: c.text(.reason)) ?? .other
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end?.rawValue ?? "", forKey: .end)
            try c.encode(reason.rawValue, forKey: .reason)
        }
    }
}

// MARK: - Resolvers

extension CoachPlan {
    public func dayType(id: String) -> DayType? { dayTypes.first { $0.id == id } }
    public func phase(id: String) -> Phase? { phases.first { $0.id == id } }
    public func check(id: String) -> Check? { checks.first { $0.id == id } }

    /// The type for days nothing else claims (Rest).
    public var defaultDayType: DayType? { dayTypes.first { $0.schedule == .default } }

    /// The first fixed-weekday type on an ISO weekday (1 = Monday).
    public func fixedType(for weekday: Int) -> DayType? {
        dayTypes.first { $0.schedule == .fixed && $0.weekdays.days.contains(weekday) }
    }

    /// The phase in force on a day: of the started phases that began on or before it, the one that
    /// began last. End dates are soft, except that a phase marked done stops after its end.
    public func activePhase(on day: DayKey) -> Phase? {
        var best: Phase?
        for phase in phases where phase.isStarted {
            guard let start = phase.start, start <= day else { continue }
            if phase.status == .done, let end = phase.end, day > end { continue }
            if let current = best?.start, start < current { continue }
            best = phase
        }
        return best
    }

    /// The newest revision of a phase with `from <= day`.
    public func revision(of phase: Phase, on day: DayKey) -> Revision? { phase.revision(on: day) }

    /// The revision of the active phase on a day.
    public func revision(on day: DayKey) -> Revision? { activePhase(on: day).flatMap { $0.revision(on: day) } }

    /// A planned (not started) phase whose start has come: the "phase starts today" card. The
    /// running phase keeps going until the person taps Start.
    public func duePhase(on day: DayKey) -> Phase? {
        phases.filter { !$0.isStarted && $0.status != .done && ($0.start.map { $0 <= day } ?? false) }
            .min { ($0.start ?? day) < ($1.start ?? day) }
    }

    /// The day type of a day, first match wins: the live day-type mark (`marks`: DayKey raw value →
    /// type id, newest mark per day), the fixed-weekday type, the default type.
    public func dayType(on day: DayKey, marks: [String: String], calendar: Calendar = .current) -> DayType? {
        if let id = marks[day.rawValue], let marked = dayType(id: id) { return marked }
        return fixedType(for: day.weekday(calendar: calendar)) ?? defaultDayType
    }

    /// The day type was picked by hand (a filled chip) rather than coming from the schedule.
    public func isManualDayType(on day: DayKey, marks: [String: String]) -> Bool {
        guard let id = marks[day.rawValue] else { return false }
        return dayType(id: id) != nil
    }

    /// The targets of a day, first match wins: the day type's targets in the active revision, the
    /// revision's baseline, then `fallback` (the profile's targets).
    public func targets(on day: DayKey, marks: [String: String], fallback: DailyTargets, calendar: Calendar = .current) -> DailyTargets {
        guard let revision = revision(on: day) else { return fallback }
        let type = dayType(on: day, marks: marks, calendar: calendar)
        return revision.targets(for: type?.id) ?? fallback
    }

    /// The pause covering a day, if any.
    public func pause(on day: DayKey) -> Pause? { pauses.first { $0.contains(day) } }

    public func isPaused(on day: DayKey) -> Bool { pause(on: day) != nil }

    /// Days of a type in the ISO week (Mon–Sun) of `day`: "Tennis · 1 of 2 this week".
    public func flexibleCount(of typeID: String, inWeekOf day: DayKey, marks: [String: String], calendar: Calendar = .current) -> Int {
        let monday = day.startOfWeek(calendar: calendar)
        return (0..<7).filter { offset in
            dayType(on: monday.adding(days: offset, calendar: calendar), marks: marks, calendar: calendar)?.id == typeID
        }.count
    }

    /// Planned average kcal per day of a revision's week: fixed types on their weekdays, flexible
    /// types `perWeek` times, the default type (or the baseline) on the rest. nil when a needed
    /// set of targets is missing.
    public func plannedWeekAverage(_ revision: Revision) -> Double? {
        guard !dayTypes.isEmpty else { return revision.baseline?.energy }
        var total = 0.0, days = 0
        for type in dayTypes where type.schedule != .default {
            let count = type.schedule == .fixed ? type.weekdays.days.count : type.perWeek
            guard count > 0 else { continue }
            guard let energy = revision.targets(for: type.id)?.energy else { return nil }
            total += Double(count) * energy
            days += count
        }
        if days < 7 {
            guard let energy = revision.targets(for: defaultDayType?.id)?.energy else { return nil }
            total += Double(7 - days) * energy
            days = 7
        }
        return total / Double(days)
    }

    /// The planned week may differ from the phase's planned average (the revision's baseline) by
    /// this many kcal a day before the plan editor warns.
    public static let weekAverageTolerance = 50.0

    /// Plan editor warning: the day types' planned week averages more than 50 kcal a day away
    /// from the revision's baseline ("Your week averages 2,640 kcal a day, 60 more than the
    /// phase's 2,580."). nil without day types, a baseline or a full week.
    public func weekAverageWarning(_ revision: Revision) -> String? {
        guard !dayTypes.isEmpty, let planned = revision.baseline?.energy, planned > 0,
              let average = plannedWeekAverage(revision) else { return nil }
        let difference = average - planned
        guard abs(difference) > CoachPlan.weekAverageTolerance + 1e-9 else { return nil }
        return "Your week averages \(SettingsCSV.grouped(average)) kcal a day, \(SettingsCSV.grouped(abs(difference))) "
            + "\(difference > 0 ? "more" : "less") than the phase's \(SettingsCSV.grouped(planned))."
    }

    /// Plan editor warning for one set of targets: the macros add up to more than 5 % off the
    /// calories ("macros add up to 2,840 kcal, not 2,700"), as the import checks them.
    public static func macroWarning(_ targets: DailyTargets) -> String? {
        guard targets.energy > 0 else { return nil }
        return SettingsCSV.macroProblem(calories: targets.energy, protein: targets.protein, carbs: targets.carbs, fat: targets.fat)
    }
}

// MARK: - Compatibility mirror

extension CoachPlan {
    /// What every plan save also writes to the profile, so older builds and an un-updated watch
    /// show near-correct numbers.
    public struct Mirror: Equatable, Sendable {
        /// The default type's targets in the current revision (nil = keep the profile's).
        public var targets: DailyTargets?
        /// The first fixed-weekday type's targets (nil = training targets off).
        public var trainingTargets: DailyTargets?
        public var trainingDays: Weekdays
        public var goal: WeightGoal
        /// The midpoint of the rate range (nil = keep the profile's).
        public var ratePerWeek: Double?
        /// The active phase's target weight (0 = none).
        public var targetWeight: Double

        public init(targets: DailyTargets?, trainingTargets: DailyTargets?, trainingDays: Weekdays, goal: WeightGoal,
                    ratePerWeek: Double?, targetWeight: Double) {
            self.targets = targets
            self.trainingTargets = trainingTargets
            self.trainingDays = trainingDays
            self.goal = goal
            self.ratePerWeek = ratePerWeek
            self.targetWeight = targetWeight
        }

        /// The settings with the mirrored values written in.
        public func applied(to state: SettingsState) -> SettingsState {
            var copy = state
            if let targets { copy.targets = targets }
            copy.trainingTargets = trainingTargets
            copy.trainingDays = trainingTargets == nil ? Weekdays([]) : trainingDays
            copy.goal = goal
            if let ratePerWeek { copy.ratePerWeek = ratePerWeek }
            copy.targetWeight = targetWeight
            return copy
        }
    }

    /// The legacy profile values for a day (usually today); nil without an active phase (then the
    /// profile is left as it is).
    public func mirror(on day: DayKey) -> Mirror? {
        guard let phase = activePhase(on: day) else { return nil }
        let revision = phase.revision(on: day)
        let targets = revision?.targets(for: defaultDayType?.id)
        var training: DailyTargets?
        var trainingDays = Weekdays([])
        if let revision, let fixed = dayTypes.first(where: { $0.schedule == .fixed && !$0.weekdays.isEmpty }),
           let own = revision.targets(for: fixed.id), own != targets {
            training = own
            trainingDays = fixed.weekdays
        }
        return Mirror(targets: targets, trainingTargets: training, trainingDays: trainingDays, goal: phase.goal,
                      ratePerWeek: phase.rateMid > 0 ? phase.rateMid : nil, targetWeight: phase.targetWeight)
    }
}

// MARK: - Setting up and changing the plan

extension CoachPlan {
    /// A plan built from the settings people had before plans existed: training targets and days
    /// become a fixed "Training" type plus a default "Rest" type, and one open-ended phase follows
    /// the profile goal, started on `day`.
    public static func migrated(from state: SettingsState, on day: DayKey, now: Date = Date(), reason: String = "edit") -> CoachPlan {
        var types: [DayType] = []
        var byType: [String: DailyTargets] = [:]
        if let training = state.trainingTargets, !state.trainingDays.isEmpty {
            types = [
                DayType(id: "training", name: "Training", emoji: "🏋️", schedule: .fixed, weekdays: state.trainingDays),
                DayType(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
            ]
            byType = ["training": training, "rest": state.targets]
        }
        let rate = state.goal == .maintain ? 0 : max(0, state.ratePerWeek)
        let phase = Phase(id: "1", name: Phase.defaultName(for: state.goal), goal: state.goal, start: day,
                          rateMin: rate, rateMax: rate, targetWeight: state.targetWeight, startedAt: now, status: .active,
                          revisions: [Revision(from: day, baseline: state.targets, byType: byType, reason: reason)])
        return CoachPlan(dayTypes: types, phases: [phase], routine: Routine.defaults(for: state.sex))
    }

    /// The plan with a new revision of a phase from `day` on. A revision with the same `from` is
    /// replaced (so several edits on one day stay one revision). Unknown phase: unchanged.
    public func addingRevision(phase id: String, from day: DayKey, baseline: DailyTargets?, byType: [String: DailyTargets],
                               reason: String) -> CoachPlan {
        guard let index = phases.firstIndex(where: { $0.id == id }) else { return self }
        var plan = self
        var revisions = plan.phases[index].revisions.filter { $0.from != day }
        revisions.append(Revision(from: day, baseline: baseline, byType: byType, reason: reason))
        plan.phases[index].revisions = revisions.sorted { $0.from < $1.from }
        return plan
    }

    /// How a calorie change is split over the macros (F11 step 6). Protein is never lowered.
    public enum MacroRule: String, Codable, Sendable, CaseIterable {
        /// All of it in carbs (gain and maintain phases).
        case carbs
        /// 70 % carbs, 30 % fat, fat kept at max(0.6 g/kg, 20 % of kcal), the rest from carbs (loss phases).
        case carbsAndFat

        /// The rule for a phase goal: carbs and fat while losing, carbs otherwise.
        public init(goal: WeightGoal) { self = goal == .lose ? .carbsAndFat : .carbs }
    }

    /// Targets with `kcal` more (or fewer) calories, split by the rule. Carbs move in 5 g steps,
    /// fat in whole grams; energy changes by exactly `kcal`.
    public static func shifted(_ targets: DailyTargets, by kcal: Double, macros rule: MacroRule, weightKg: Double = 0) -> DailyTargets {
        var copy = targets
        copy.energy = max(0, targets.energy + kcal)
        func fiveGrams(_ value: Double) -> Double { (value / 5).rounded() * 5 }
        switch rule {
        case .carbs:
            copy.carbs = max(0, targets.carbs + fiveGrams(kcal / 4))
        case .carbsAndFat:
            let floor = max(0.6 * max(0, weightKg), 0.2 * copy.energy / 9)
            var fat = targets.fat + (kcal * 0.3 / 9).rounded()
            if fat < floor { fat = max(fat, min(targets.fat, floor.rounded(.up))) }
            fat = max(0, fat)
            copy.fat = fat
            let rest = kcal - (fat - targets.fat) * 9
            copy.carbs = max(0, targets.carbs + fiveGrams(rest / 4))
        }
        return copy
    }

    /// The plan with every day type of the active phase moved by the same `kcal` from `day` on, so
    /// the differences between day types stay (+100: Gym 2600 → 2700, Rest 2400 → 2500). Adds a
    /// revision; without a revision so far the change starts from `fallback` (the profile's
    /// targets). No active phase on `day`: unchanged.
    public func applyingDelta(_ kcal: Double, macros rule: MacroRule? = nil, from day: DayKey, weightKg: Double = 0,
                              fallback: DailyTargets = .standard, reason: String? = nil) -> CoachPlan {
        guard let phase = activePhase(on: day) else { return self }
        let rule = rule ?? MacroRule(goal: phase.goal)
        let current = phase.revision(on: day)
        let baseline = CoachPlan.shifted(current?.baseline ?? fallback, by: kcal, macros: rule, weightKg: weightKg)
        let byType = (current?.byType ?? [:]).mapValues { CoachPlan.shifted($0, by: kcal, macros: rule, weightKg: weightKg) }
        let rounded = Int(kcal.rounded())
        let reason = reason ?? "adjust:\(rounded >= 0 ? "+" : "")\(rounded)"
        return addingRevision(phase: phase.id, from: day, baseline: baseline, byType: byType, reason: reason)
    }

    /// The plan after the person tapped Start on a phase: it starts on `day` (confirmed now), a
    /// running phase that began earlier is marked done and ends the day before (it kept running
    /// until now, whatever its planned end said), and when the
    /// phase's first revision was planned for a later day it now starts on `day`.
    public func starting(phase id: String, on day: DayKey, now: Date = Date(), calendar: Calendar = .current) -> CoachPlan {
        guard let index = phases.firstIndex(where: { $0.id == id }) else { return self }
        var plan = self
        let dayBefore = day.adding(days: -1, calendar: calendar)
        for other in plan.phases.indices where other != index && plan.phases[other].isStarted && plan.phases[other].status != .done {
            guard let start = plan.phases[other].start, start < day else { continue }
            plan.phases[other].status = .done
            plan.phases[other].end = dayBefore
            plan.phases[other].endApprox = false
        }
        plan.phases[index].start = day
        plan.phases[index].startApprox = false
        plan.phases[index].startedAt = now
        plan.phases[index].status = .active
        if let first = plan.phases[index].revisions.first, first.from > day {
            plan.phases[index].revisions[0].from = day
        }
        return plan
    }
}

// MARK: - Calorie changes

extension CoachPlan {
    /// The first day of new calorie targets in a phase: the pace, the check-in's window, its lock
    /// and its "in a row" count all restart there, however the targets changed (Apply in a
    /// check-in, My Plan, Calculate in the phase sheet, an import).
    public struct CalorieChange: Equatable, Sendable {
        public var from: DayKey
        /// Applied in a check-in ("adjust…" revision, from the day after it). Other changes start
        /// on the day they were made.
        public var isAdjustment: Bool

        public init(from: DayKey, isAdjustment: Bool) {
            self.from = from
            self.isAdjustment = isAdjustment
        }

        /// A check-in saved on `day` judged these targets: on or after an adjustment's first day;
        /// after any other change (an edit or import made on a check-in day comes after that
        /// day's check-in, which judged the targets before it).
        public func covers(checkInOn day: DayKey) -> Bool {
            isAdjustment ? day >= from : day > from
        }
    }

    /// kcal a day the planned week average has to move for an edit, a calculation or an import
    /// to count as a calorie change (protein-only edits and an import of the same targets don't).
    public static let calorieChangeMinimum = 50.0

    /// The calorie changes of a phase, oldest first: every applied adjustment ("adjust…", even
    /// without targets of its own), and every other revision (an edit, a calculation, an import –
    /// not the "kept" history an import writes) whose planned week average moved by 50 kcal or
    /// more from the revision in force the day before. A phase's first targets count only when
    /// they start after the phase did (the days before ran on other targets).
    public func calorieChanges(of phase: Phase) -> [CalorieChange] {
        var changes: [CalorieChange] = []
        var previous: Revision?
        for from in Set(phase.revisions.map(\.from)).sorted() {
            guard let revision = phase.revision(on: from) else { continue }
            defer { previous = revision }
            if revision.reason.hasPrefix("adjust") {
                changes.append(CalorieChange(from: from, isAdjustment: true))
                continue
            }
            guard revision.reason != SettingsCSV.keptRevisionReason else { continue }
            if let previous {
                if movesCalories(from: previous, to: revision) { changes.append(CalorieChange(from: from, isAdjustment: false)) }
            } else if let start = phase.start, from > start {
                changes.append(CalorieChange(from: from, isAdjustment: false))
            }
        }
        return changes
    }

    /// The newest calorie change of the phase active on `day`; with `inForce` only one that has
    /// started by `day`, else also one that starts later (applied at this check-in, from tomorrow).
    public func lastCalorieChange(on day: DayKey, inForce: Bool) -> CalorieChange? {
        guard let phase = activePhase(on: day) else { return nil }
        return calorieChanges(of: phase).last { !inForce || $0.from <= day }
    }

    /// The planned kcal a day of a revision: its planned week average, else its baseline, else
    /// the mean of its day types; nil without any targets.
    func plannedEnergy(_ revision: Revision) -> Double? {
        if let average = plannedWeekAverage(revision) { return average }
        if let baseline = revision.baseline { return baseline.energy }
        let energies = revision.byType.values.map(\.energy)
        return energies.isEmpty ? nil : energies.reduce(0, +) / Double(energies.count)
    }

    func movesCalories(from old: Revision, to new: Revision) -> Bool {
        switch (plannedEnergy(old), plannedEnergy(new)) {
        case let (before?, after?): return abs(after - before) >= CoachPlan.calorieChangeMinimum - 1e-9
        case (nil, nil): return false
        default: return true
        }
    }
}

// MARK: - Day marks

/// What a `DayMark` record holds (its `kind`).
public enum DayMarkKind: String, Codable, Sendable, CaseIterable {
    /// key = day type id (the newest live mark per day wins).
    case dayType
    /// key = check id, meta "state=done|skipped".
    case check
    /// key = "week-<Monday>", values = the snapshot, meta = verdict and decision.
    case checkIn
    /// key = phase id, meta "event=…".
    case phase
    /// key = "ill", "travel", "period", "incompleteLog".
    case event
}

/// A daily check's mark (`DayMark.meta` "state=…"). Any live "done" mark means done.
public enum CheckState: String, Codable, Sendable, CaseIterable {
    case done, skipped
}

/// A phase decision (`DayMark.meta` "event=…").
public enum PhaseEvent: String, Codable, Sendable, CaseIterable {
    case started, postponed
    case reviewKeep = "review-keep"
    case reviewHold = "review-hold"
    case reviewCut = "review-cut"
    case ended
}

public enum DayMarks {
    /// The day-type marks as the resolvers want them (DayKey raw value → type id): for each day
    /// the mark changed last wins, so two devices that disagree converge.
    public static func dayTypes(_ marks: [(day: String, key: String, modifiedAt: Date)]) -> [String: String] {
        var newest: [String: (key: String, modifiedAt: Date)] = [:]
        for mark in marks where !mark.day.isEmpty && !mark.key.isEmpty {
            if let current = newest[mark.day], current.modifiedAt >= mark.modifiedAt { continue }
            newest[mark.day] = (mark.key, mark.modifiedAt)
        }
        return newest.mapValues(\.key)
    }

    /// "week-2030-01-07": the check-in key of the ISO week a day falls in (its Monday).
    public static func checkInKey(week day: DayKey, calendar: Calendar = .current) -> String {
        "week-\(day.startOfWeek(calendar: calendar).rawValue)"
    }
}

// MARK: - Key=value text

/// Small key=value lists in one text field: `DayMark.meta` ("state=done;verdict=slower") and
/// number lists ("waist=84.0;chest=101.5"). Keys sorted when encoded, numbers with "." decimals,
/// unknown keys kept. ";" in a value becomes ",", line breaks become spaces.
public struct KeyValueText: Equatable, Hashable, Sendable {
    public private(set) var storage: [String: String]

    public init(_ values: [String: String] = [:]) {
        storage = [:]
        for (key, value) in values { self[key] = value }
    }

    public init(encoded: String) {
        storage = [:]
        for pair in encoded.split(whereSeparator: { $0 == ";" || $0 == "\n" }) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            self[String(parts[0])] = String(parts[1])
        }
    }

    public var encoded: String {
        storage.keys.sorted().compactMap { key in storage[key].map { "\(key)=\($0)" } }.joined(separator: ";")
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var keys: [String] { storage.keys.sorted() }

    public subscript(_ key: String) -> String? {
        get { storage[KeyValueText.clean(key: key)] }
        set {
            let key = KeyValueText.clean(key: key)
            guard !key.isEmpty else { return }
            let value = newValue.map(KeyValueText.clean(value:)) ?? ""
            storage[key] = value.isEmpty ? nil : value
        }
    }

    /// A number value ("." decimals); nil when missing or not a number.
    public func number(_ key: String) -> Double? {
        guard let text = self[key], let value = Double(text), value.isFinite else { return nil }
        return value
    }

    public mutating func setNumber(_ value: Double?, for key: String) {
        self[key] = value.flatMap { $0.isFinite ? NumberText.plain($0) : nil }
    }

    static func clean(key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0 != "=" && $0 != ";" && !$0.isNewline }
    }

    static func clean(value: String) -> String {
        String(value.map { $0 == ";" ? "," : ($0.isNewline ? " " : $0) }).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Helpers

extension CoachPlan {
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// "2030-01-07T08:00:00Z"
    static func momentText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func moment(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return wholeSeconds(date) }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return wholeSeconds(date) }
        return DayKey(text).map { $0.date() }
    }

    static func missing(_ field: String, _ decoder: Decoder) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\(field) missing"))
    }
}

/// Decodes a list item or nothing, so one broken item doesn't lose the whole list.
private struct LossyItem<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Lenient reads: the fallback when a value is missing or has the wrong type.
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    func text(_ key: Key) -> String {
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return NumberText.plain(number) }
        return ""
    }

    func number(_ key: Key, _ fallback: Double) -> Double {
        if let number = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return number.isFinite ? number : fallback }
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil, let number = NumberText.parse(text) { return number }
        return fallback
    }

    func integer(_ key: Key, _ fallback: Int) -> Int {
        if let number = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return number }
        let number = self.number(key, .nan)
        guard number.isFinite, abs(number) < 1e9 else { return fallback }
        return Int(number.rounded())
    }

    func flag(_ key: Key, _ fallback: Bool) -> Bool {
        if let flag = (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil { return flag }
        if let number = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return number != 0 }
        switch text(key).lowercased() {
        case "true", "yes", "y", "1", "on", "ja": return true
        case "false", "no", "n", "0", "off", "nein": return false
        default: return fallback
        }
    }

    func day(_ key: Key) -> DayKey? { DayKey(text(key)) }

    func moment(_ key: Key) -> Date? {
        if let seconds = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil, seconds.isFinite, seconds > 0 {
            return CoachPlan.wholeSeconds(Date(timeIntervalSince1970: seconds))
        }
        let raw = text(key)
        return raw.isEmpty ? nil : CoachPlan.moment(from: raw)
    }

    func weekdays(_ key: Key) -> Weekdays {
        if let numbers = (try? decodeIfPresent([Int].self, forKey: key)) ?? nil { return Weekdays(Set(numbers)) }
        return Weekdays(encoded: text(key).replacingOccurrences(of: ";", with: ","))
    }

    func list<T: Decodable>(_ key: Key) -> [T] {
        guard let items = (try? decodeIfPresent([LossyItem<T>].self, forKey: key)) ?? nil else { return [] }
        return items.compactMap(\.value)
    }

    /// A list of texts; a single text is split at ";" and "," when `splitting` (else kept whole).
    func texts(_ key: Key, splitting: Bool) -> [String] {
        let trimmed: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let items = (try? decodeIfPresent([LossyItem<String>].self, forKey: key)) ?? nil {
            return items.compactMap(\.value).map(trimmed).filter { !$0.isEmpty }
        }
        let single = text(key)
        guard !single.isEmpty else { return [] }
        guard splitting else { return [single] }
        return single.split(whereSeparator: { $0 == ";" || $0 == "," }).map { trimmed(String($0)) }.filter { !$0.isEmpty }
    }
}
