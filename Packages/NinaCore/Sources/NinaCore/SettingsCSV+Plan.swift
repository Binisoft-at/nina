import Foundation
import BinisoftKitCore

// The coach-plan part of the goals & settings file (docs/IMPORT.md, "Coach plan"): flat body rows
// (today's baseline), protein per meal, plan notes, the namespaces long_term.*, measure.* and
// checkin.*, and the groups day_type.<id>.*, phase.<n>.* and check.<id>.*. Keys are normalised like
// every setting ("phase.1.gym.calories" is read as phase_1_gym_calories); ids are [a-z0-9]+.

// MARK: - Preview groups and body records

/// The groups of the settings preview, in display order.
public enum SettingsGroup: String, CaseIterable, Sendable, Identifiable {
    case body, targets, dayTypes, phases, checks, measuring, checkIn, longTerm, notes, preferences, notSupported

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .body: "Body"
        case .targets: "Targets"
        case .dayTypes: "Day types"
        case .phases: "Phases"
        case .checks: "Daily checks"
        case .measuring: "Measuring"
        case .checkIn: "Check-in"
        case .longTerm: "Long-term goal"
        case .notes: "Notes"
        case .preferences: "Preferences"
        case .notSupported: "Not supported"
        }
    }
}

/// The preview lines of one group: "Day types (3)".
public struct SettingsSection: Equatable, Sendable, Identifiable {
    public let group: SettingsGroup
    /// The group's title; day types, phases and checks carry their number after the import.
    public let title: String
    public let changes: [SettingsChange]

    public var id: String { group.rawValue }
}

/// A body record the import adds for today (the baseline): the body-fat assessment with its method,
/// or the tape values. Each one is listed in the preview.
public struct SettingsBodyRecord: Equatable, Sendable, Identifiable {
    /// The conditions an imported tape baseline is stored with: a standard reading
    /// (`BodyProtocol.isStandard`), so trends, the tape estimate and "change since the start"
    /// use it like a morning measurement.
    public static let baselineConditions = BodyProtocol.encode([.morning, .fasted])

    public var day: DayKey
    public var kind: BodyRecordKind
    public var values: BodyValues
    /// Assessments: how the body fat was measured.
    public var method: BodyMethod?
    /// `BodyMeasurement.conditions`: tape records are the standard baseline, assessments have none.
    public var conditions: String

    public init(day: DayKey, kind: BodyRecordKind, values: BodyValues, method: BodyMethod? = nil, conditions: String? = nil) {
        self.day = day
        self.kind = kind
        self.values = values
        self.method = method
        self.conditions = conditions ?? (kind == .tape ? SettingsBodyRecord.baselineConditions : "")
    }

    /// The tape values as a record for the trends and the tape estimate (nil for an assessment).
    public var tapeRecord: BodyTapeRecord? {
        kind == .tape ? BodyTapeRecord(day: day, values: values, conditions: conditions) : nil
    }

    public var id: String { kind.rawValue }

    /// Importing the same file again on the same day updates the record instead of adding one.
    public var importKey: String { "settings:\(day.rawValue):\(kind.rawValue)" }
}

// MARK: - What the file says about the plan

/// The coach-plan rows of a settings file. nil (or empty) = not in the file. Groups (day types,
/// phases, checks, notes) replace the whole group; namespaces and protein change only their fields.
public struct SettingsPlanDraft: Equatable, Sendable {
    /// Daily targets written for a phase or a day type; missing fields come from the baseline.
    public struct Targets: Equatable, Sendable {
        public var calories: Double?
        public var protein: Double?
        public var carbs: Double?
        public var fat: Double?
        public var fiber: Double?
        public var water: Double?

        public init(calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil,
                    fiber: Double? = nil, water: Double? = nil) {
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.fiber = fiber
            self.water = water
        }

        public var isEmpty: Bool { self == Targets() }

        /// These fields over `base`. Calories without carbs: protein and fat stay, carbs take the
        /// rest; macros without calories: the calories follow the macros.
        public func filled(over base: DailyTargets) -> DailyTargets {
            var targets = base
            if let fiber { targets.fiber = fiber }
            if let water { targets.water = water }
            if let protein { targets.protein = protein }
            if let carbs { targets.carbs = carbs }
            if let fat { targets.fat = fat }
            if let calories {
                targets.energy = calories
                if carbs == nil { targets.carbs = max(0, ((calories - targets.protein * 4 - targets.fat * 9) / 4).rounded()) }
            } else if protein != nil || carbs != nil || fat != nil {
                targets.energy = ((targets.protein * 4 + targets.carbs * 4 + targets.fat * 9) / 10).rounded() * 10
            }
            return targets
        }

        /// "macros add up to 2,840 kcal, not 2,800" when calories and all three macros are given and
        /// differ by more than 5 %.
        public var macroProblem: String? {
            guard let calories, let protein, let carbs, let fat, calories > 0 else { return nil }
            return SettingsCSV.macroProblem(calories: calories, protein: protein, carbs: carbs, fat: fat)
        }
    }

    public struct DayType: Equatable, Sendable {
        public var id: String
        public var name: String?
        public var emoji: String?
        public var schedule: CoachPlan.Schedule?
        public var weekdays: Weekdays?
        public var perWeek: Int?
        public var workouts: [String]?

        public init(id: String) { self.id = id }
    }

    public struct Phase: Equatable, Sendable {
        public var id: String
        public var name: String?
        public var goal: WeightGoal?
        public var start: DayKey?
        public var startApprox = false
        public var end: DayKey?
        public var endApprox = false
        /// kg per week (magnitudes, 0...0 = none).
        public var rate: ClosedRange<Double>?
        /// % of body weight per week.
        public var ratePercent: ClosedRange<Double>?
        /// Review checkpoint, kg.
        public var review: ClosedRange<Double>?
        public var targetWeight: Double?
        public var targetBodyFat: Double?
        public var maxWaistGainCm: Double?
        public var note: String?
        /// phase.N.calories … (the phase's baseline).
        public var baseline = Targets()
        /// phase.N.<type>.calories … by day type id.
        public var byType: [String: Targets] = [:]
        /// Day type ids in the order of the file.
        public var typeOrder: [String] = []
        /// The first key written for each day type (for messages).
        var typeKeys: [String: String] = [:]

        public init(id: String) { self.id = id }

        public var hasTargets: Bool { !baseline.isEmpty || !byType.isEmpty }
    }

    public struct Check: Equatable, Sendable {
        public var id: String
        public var name: String?
        public var emoji: String?
        public var dose: String?
        /// A meal is kept as written and matched with the meals when applied.
        public var timing: CoachPlan.CheckTiming?
        public var days: CoachPlan.CheckDays?
        public var isOptional: Bool?
        public var remind: Bool?
        public var affectsWeight: Bool?
        /// The key of the days row (for messages).
        var daysKey = ""
        var whenKey = ""

        public init(id: String) { self.id = id }
    }

    public struct LongTerm: Equatable, Sendable {
        public var weightKg: Double?
        public var bodyFat: Double?
        public var waistCm: Double?
        public var date: DayKey?
        public var note: String?

        public init() {}

        public var isEmpty: Bool { self == LongTerm() }
    }

    public struct Measure: Equatable, Sendable {
        public var weighInMinutes: Int?
        public var morningCutoffMinutes: Int?
        public var weeklySites: [BodySite]?
        public var fullSites: [BodySite]?
        public var fullEveryWeeks: Int?
        public var bodyFatEveryWeeks: Int?
        /// .some(nil) = automatic (the most accurate method with 2 values).
        public var bodyFatMethod: BodyMethod??
        public var side: BodySide?
        public var thighMark: String?
        public var twoReadings: Bool?

        public init() {}

        public var isEmpty: Bool { self == Measure() }
    }

    public struct CheckIn: Equatable, Sendable {
        /// ISO weekday.
        public var weekday: Int?
        public var windowDays: ClosedRange<Int>?
        public var step: ClosedRange<Double>?
        public var lockDays: Int?

        public init() {}

        public var isEmpty: Bool { self == CheckIn() }
    }

    /// protein_meals: a count or meal names. (Not `ProteinMeals`, which is the per-meal protein logic.)
    public struct ProteinMealCount: Equatable, Sendable {
        /// 0 = one per listed meal.
        public var count: Int
        /// Meal names as written (matched with the meals when applied).
        public var names: [String]

        public init(count: Int, names: [String]) {
            self.count = count
            self.names = names
        }
    }

    // Today's body values (body_fat_percent, body_fat_method, *_cm).
    public var bodyFat: Double?
    public var bodyFatMethod: BodyMethod?
    public var tape: [BodySite: Double] = [:]

    /// meal_protein_g: "35-45" (a single value = minimum only).
    public var mealProtein: ClosedRange<Double>?
    public var proteinMeals: ProteinMealCount?
    /// note rows (nil = none in the file).
    public var notes: [String]?
    public var longTerm = LongTerm()
    public var measure = Measure()
    public var checkIn = CheckIn()
    /// Groups, in the order of first appearance (nil = not in the file).
    public var dayTypes: [DayType]?
    public var phases: [Phase]?
    public var checks: [Check]?

    public init() {}

    /// Rows that belong to the coach plan (body rows don't).
    public var hasPlanRows: Bool {
        mealProtein != nil || proteinMeals != nil || notes != nil || !longTerm.isEmpty || !measure.isEmpty || !checkIn.isEmpty
            || dayTypes != nil || phases != nil || checks != nil
    }

    /// Rows that set up a plan (phases or day types): a plan without them is created first.
    public var setsUpPlan: Bool { dayTypes != nil || phases != nil }

    public var hasBodyRows: Bool { bodyFat != nil || bodyFatMethod != nil || !tape.isEmpty }

    mutating func withDayType(_ id: String, _ change: (inout DayType) -> Void) {
        var list = dayTypes ?? []
        if let index = list.firstIndex(where: { $0.id == id }) {
            change(&list[index])
        } else {
            var item = DayType(id: id)
            change(&item)
            list.append(item)
        }
        dayTypes = list
    }

    mutating func withPhase(_ id: String, _ change: (inout Phase) -> Void) {
        var list = phases ?? []
        if let index = list.firstIndex(where: { $0.id == id }) {
            change(&list[index])
        } else {
            var item = Phase(id: id)
            change(&item)
            list.append(item)
        }
        phases = list
    }

    mutating func withCheck(_ id: String, _ change: (inout Check) -> Void) {
        var list = checks ?? []
        if let index = list.firstIndex(where: { $0.id == id }) {
            change(&list[index])
        } else {
            var item = Check(id: id)
            change(&item)
            list.append(item)
        }
        checks = list
    }
}

// MARK: - Reading plan rows

extension SettingsCSV {
    /// Where a normalised key of the plan goes.
    enum PlanRow: Equatable {
        case longTerm(String)
        case measure(String)
        case checkIn(String)
        case dayType(id: String, field: String)
        case phase(id: String, field: String)
        case phaseType(id: String, type: String, field: String)
        case check(id: String, field: String)
        /// A plan prefix with a field Nina doesn't know.
        case unknown
    }

    static func aliasMap(_ groups: [(String, [String])]) -> [String: String] {
        var map: [String: String] = [:]
        for (name, aliases) in groups {
            map[ImportColumns.normalize(name)] = name
            for alias in aliases { map[ImportColumns.normalize(alias)] = name }
        }
        return map
    }

    static let targetFieldList: [(String, [String])] = [
        ("calories", ["kcal", "calories_kcal", "energy", "kalorien"]),
        ("protein_g", ["protein", "eiweiss"]),
        ("carbs_g", ["carbs", "carbohydrates", "kohlenhydrate"]),
        ("fat_g", ["fat", "fett"]),
        ("macros_g", ["macros", "makros", "macros_pcf"]),
        ("fiber_g", ["fiber", "fibre", "ballaststoffe"]),
        ("water_ml", ["water", "wasser"]),
    ]

    static let targetFields = aliasMap(targetFieldList)

    static let phaseFields = aliasMap([
        ("name", ["title"]),
        ("goal", ["ziel"]),
        ("start", ["from", "start_date", "begin", "beginn"]),
        ("end", ["until", "end_date", "ende", "bis"]),
        ("rate_kg_per_week", ["rate", "pace", "kg_per_week", "rate_kg"]),
        ("rate_percent_per_week", ["rate_percent", "percent_per_week", "rate_pct_per_week"]),
        ("review_weight_kg", ["review_weight", "review_kg", "review"]),
        ("target_weight_kg", ["target_weight", "goal_weight", "zielgewicht"]),
        ("target_body_fat_percent", ["target_body_fat", "body_fat_percent", "body_fat_goal"]),
        ("max_waist_gain_cm", ["max_waist_gain", "waist_limit_cm"]),
        ("note", ["notes", "notiz"]),
    ] + targetFieldList)

    static let dayTypeFields = aliasMap([
        ("name", ["title"]),
        ("emoji", ["icon"]),
        ("days", ["schedule", "weekdays", "tage"]),
        ("per_week", ["times_per_week", "count"]),
        ("workouts", ["workout", "health_workouts"]),
    ])

    static let checkFields = aliasMap([
        ("name", ["title"]),
        ("emoji", ["icon"]),
        ("dose", ["amount", "dosis", "menge"]),
        ("when", ["timing", "time", "meal", "wann"]),
        ("days", ["schedule", "tage"]),
        ("optional", ["is_optional"]),
        ("remind", ["reminder", "notify", "erinnerung"]),
        ("affects_weight", ["affects_scale"]),
    ])

    static let longTermFields = aliasMap([
        ("weight_kg", ["weight", "gewicht"]),
        ("body_fat_percent", ["body_fat", "body_fat_pct", "korperfett", "kfa"]),
        ("waist_cm", ["waist", "taille", "bauchumfang"]),
        ("date", ["by", "datum", "target_date"]),
        ("note", ["notes", "notiz"]),
    ])

    static let measureFields = aliasMap([
        ("weigh_in", ["weighin", "weigh_in_time", "wiegen"]),
        ("morning_until", ["morning_cutoff", "morning_end"]),
        ("weekly", ["weekly_sites", "every_week"]),
        ("full", ["full_sites", "full_set"]),
        ("full_every_weeks", ["full_set_every_weeks", "full_weeks"]),
        ("body_fat_every_weeks", ["body_composition_every_weeks", "body_fat_weeks"]),
        ("body_fat_method", ["method", "tracking_method"]),
        ("side", ["seite"]),
        ("thigh_mark", ["thigh_landmark"]),
        ("two_readings", ["readings", "double_readings"]),
    ])

    static let checkInFields = aliasMap([
        ("day", ["weekday", "tag"]),
        ("adjust_after_weeks", ["window_weeks", "adjust_after"]),
        ("step_kcal", ["step", "adjust_kcal", "step_calories"]),
        ("lock_days", ["lock", "pause_days"]),
    ])

    /// The plan row a normalised key names, or nil when it isn't a plan key. `check_in_` and
    /// `checkin_` are matched before `check_`; `supplement_` is the same as `check_`.
    static func planRow(_ key: String) -> PlanRow? {
        func rest(after prefixes: [String]) -> String? {
            for prefix in prefixes where key.hasPrefix(prefix) { return String(key.dropFirst(prefix.count)) }
            return nil
        }
        if let field = rest(after: ["check_in_", "checkin_"]) { return checkInFields[field].map(PlanRow.checkIn) ?? .unknown }
        if let field = rest(after: ["long_term_goal_", "long_term_", "longterm_"]) { return longTermFields[field].map(PlanRow.longTerm) ?? .unknown }
        if let field = rest(after: ["measure_", "measuring_", "measurement_"]) { return measureFields[field].map(PlanRow.measure) ?? .unknown }
        if let tail = rest(after: ["day_type_", "daytype_"]) {
            guard let (id, field) = split(tail, fields: dayTypeFields) else { return .unknown }
            return .dayType(id: id, field: field)
        }
        if let tail = rest(after: ["phase_"]) {
            let parts = tail.split(separator: "_").map(String.init)
            guard parts.count >= 2 else { return .unknown }
            let remainder = parts.dropFirst().joined(separator: "_")
            if let field = phaseFields[remainder] { return .phase(id: parts[0], field: field) }
            if let (type, field) = split(remainder, fields: targetFields) { return .phaseType(id: parts[0], type: type, field: field) }
            return .unknown
        }
        if let tail = rest(after: ["check_", "checks_", "supplement_", "supplements_"]) {
            guard let (id, field) = split(tail, fields: checkFields) else { return .unknown }
            return .check(id: id, field: field)
        }
        return nil
    }

    /// "gym_per_week" → ("gym", "per_week"); a longer id is joined ("gym_day_name" → "gymday").
    static func split(_ tail: String, fields: [String: String]) -> (String, String)? {
        let parts = tail.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return nil }
        for index in 1..<parts.count {
            if let field = fields[parts[index...].joined(separator: "_")] { return (parts[..<index].joined(), field) }
        }
        return nil
    }

    /// Reads one plan row; returns what's wrong with the value, or nil.
    static func readPlan(_ row: PlanRow, key: String, _ value: String, into draft: inout SettingsDraft) -> String? {
        let invalid = "“\(value)” isn't a valid value"
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch row {
        case .unknown:
            return "not a setting Nina knows"

        case .longTerm(let field):
            switch field {
            case "weight_kg":
                guard let weight = planNumber(value, 30...300) else { return invalid }
                draft.plan.longTerm.weightKg = weight
            case "body_fat_percent":
                guard let fat = planNumber(value, 3...50) else { return invalid + " (3–50 %)" }
                draft.plan.longTerm.bodyFat = fat
            case "waist_cm":
                guard let waist = planNumber(value, 40...200) else { return invalid }
                draft.plan.longTerm.waistCm = waist
            case "date":
                guard let date = planDate(value, end: true) else { return invalid + " (use YYYY-MM-DD or YYYY-MM)" }
                draft.plan.longTerm.date = date.day
            default:
                draft.plan.longTerm.note = text
            }

        case .measure(let field):
            switch field {
            case "weigh_in", "morning_until":
                guard let minutes = clockTime(in: value) else { return invalid + " (use a time like 07:00)" }
                if field == "weigh_in" { draft.plan.measure.weighInMinutes = minutes } else { draft.plan.measure.morningCutoffMinutes = minutes }
            case "weekly", "full":
                guard let sites = bodySites(value) else { return invalid + " (use sites like waist;chest;arm;thigh;hip)" }
                if field == "weekly" {
                    draft.plan.measure.weeklySites = sites
                } else {
                    guard !sites.isEmpty else { return invalid }
                    draft.plan.measure.fullSites = sites
                }
            case "full_every_weeks", "body_fat_every_weeks":
                guard let weeks = planNumber(value, 1...52) else { return invalid + " (1–52 weeks)" }
                if field == "full_every_weeks" { draft.plan.measure.fullEveryWeeks = Int(weeks.rounded()) } else { draft.plan.measure.bodyFatEveryWeeks = Int(weeks.rounded()) }
            case "body_fat_method":
                if ["auto", "automatic", "automatisch", "none", "best", "default"].contains(SearchText.normalize(value)) {
                    draft.plan.measure.bodyFatMethod = .some(nil)
                } else {
                    guard let method = bodyMethod(named: value) else { return invalid + " (\(methodNames))" }
                    draft.plan.measure.bodyFatMethod = .some(method)
                }
            case "side":
                let map: [String: BodySide] = ["right": .right, "rechts": .right, "r": .right, "left": .left, "links": .left, "l": .left,
                                               "both": .both, "beide": .both, "both sides": .both, "beidseitig": .both]
                guard let side = map[SearchText.normalize(value)] else { return invalid + " (right, left or both)" }
                draft.plan.measure.side = side
            case "thigh_mark":
                draft.plan.measure.thighMark = text
            default: // two_readings
                guard let flag = yesNo(value) else { return invalid + " (yes or no)" }
                draft.plan.measure.twoReadings = flag
            }

        case .checkIn(let field):
            switch field {
            case "day":
                guard let days = weekdays(value), days.days.count == 1, let day = days.days.first else { return invalid + " (a weekday like mon)" }
                draft.plan.checkIn.weekday = day
            case "adjust_after_weeks":
                guard let weeks = planRange(value, 1...8) else { return invalid + " (weeks like 2-3)" }
                draft.plan.checkIn.windowDays = Int((weeks.lowerBound * 7).rounded())...Int((weeks.upperBound * 7).rounded())
            case "step_kcal":
                guard let step = planRange(value, 25...500) else { return invalid + " (kcal like 100-150)" }
                draft.plan.checkIn.step = step
            default: // lock_days
                guard let days = planNumber(value, 0...90) else { return invalid + " (0–90 days)" }
                draft.plan.checkIn.lockDays = Int(days.rounded())
            }

        case .dayType(let id, let field):
            switch field {
            case "name":
                guard !text.isEmpty else { return invalid }
                draft.plan.withDayType(id) { $0.name = text }
            case "emoji":
                guard let emoji = firstEmoji(value) else { return invalid + " (one emoji)" }
                draft.plan.withDayType(id) { $0.emoji = emoji }
            case "days":
                let word = SearchText.normalize(value)
                if word.hasPrefix("flex") || word.contains("per week") || word.contains("pro woche") {
                    let count = numbers(in: value).first.map { Int($0) }
                    draft.plan.withDayType(id) { type in
                        type.schedule = .flexible
                        if type.perWeek == nil, let count, (0...7).contains(count) { type.perWeek = count }
                    }
                } else if ["default", "other days", "all other days", "remaining days", "the rest", "rest", "otherwise", "sonst",
                           "andere tage", "alle anderen tage", "restliche tage", "standard"].contains(word) {
                    draft.plan.withDayType(id) { $0.schedule = .default }
                } else if let days = weekdays(value) {
                    draft.plan.withDayType(id) { type in
                        type.schedule = .fixed
                        type.weekdays = days
                    }
                } else {
                    return invalid + " (use mon;wed;fri, flexible or default)"
                }
            case "per_week":
                guard let count = planNumber(value, 0...7) else { return invalid + " (0–7)" }
                draft.plan.withDayType(id) { $0.perWeek = Int(count.rounded()) }
            default: // workouts
                let workouts = ImportColumns.list(value).map { SearchText.normalize($0).replacingOccurrences(of: " ", with: "_") }.filter { !$0.isEmpty }
                draft.plan.withDayType(id) { $0.workouts = workouts }
            }

        case .phase(let id, let field):
            if targetFields.values.contains(field) {
                var targets = draft.plan.phases?.first { $0.id == id }?.baseline ?? SettingsPlanDraft.Targets()
                if let problem = readTarget(field, value, into: &targets) { return problem }
                draft.plan.withPhase(id) { $0.baseline = targets }
                return nil
            }
            switch field {
            case "name":
                guard !text.isEmpty else { return invalid }
                draft.plan.withPhase(id) { $0.name = text }
            case "goal":
                guard let goal = goal(named: value) else { return invalid + " (gain, maintain or lose)" }
                draft.plan.withPhase(id) { $0.goal = goal }
            case "start", "end":
                guard let date = planDate(value, end: field == "end") else { return invalid + " (use YYYY-MM-DD or YYYY-MM, ~ for about)" }
                draft.plan.withPhase(id) { phase in
                    if field == "start" {
                        phase.start = date.day
                        phase.startApprox = date.approx
                    } else {
                        phase.end = date.day
                        phase.endApprox = date.approx
                    }
                }
            case "rate_kg_per_week":
                if let zero = numbers(in: value).first, zero == 0, numbers(in: value).count == 1 {
                    draft.plan.withPhase(id) { $0.rate = 0...0 }
                } else {
                    guard let rate = planRange(value, 0.05...1.0) else { return invalid + " (0.05–1 kg per week, a range like 0.1-0.2 is fine)" }
                    draft.plan.withPhase(id) { $0.rate = rate }
                }
            case "rate_percent_per_week":
                guard let rate = planRange(value, 0.05...1.5) else { return invalid + " (0.05–1.5 % per week)" }
                draft.plan.withPhase(id) { $0.ratePercent = rate }
            case "review_weight_kg":
                guard let review = planRange(value, 25...300) else { return invalid + " (kg like 82-83)" }
                draft.plan.withPhase(id) { $0.review = review }
            case "target_weight_kg":
                guard let weight = planNumber(value, 25...300) else { return invalid }
                draft.plan.withPhase(id) { $0.targetWeight = weight }
            case "target_body_fat_percent":
                guard let fat = planNumber(value, 3...50) else { return invalid + " (3–50 %)" }
                draft.plan.withPhase(id) { $0.targetBodyFat = fat }
            case "max_waist_gain_cm":
                guard let cm = planNumber(value, 0...20) else { return invalid + " (0–20 cm)" }
                draft.plan.withPhase(id) { $0.maxWaistGainCm = cm }
            default: // note
                draft.plan.withPhase(id) { $0.note = text }
            }

        case .phaseType(let id, let type, let field):
            var targets = draft.plan.phases?.first { $0.id == id }?.byType[type] ?? SettingsPlanDraft.Targets()
            if let problem = readTarget(field, value, into: &targets) { return problem }
            draft.plan.withPhase(id) { phase in
                if phase.byType[type] == nil {
                    phase.typeOrder.append(type)
                    phase.typeKeys[type] = key
                }
                phase.byType[type] = targets
            }

        case .check(let id, let field):
            switch field {
            case "name":
                guard !text.isEmpty else { return invalid }
                draft.plan.withCheck(id) { $0.name = text }
            case "emoji":
                guard let emoji = firstEmoji(value) else { return invalid + " (one emoji)" }
                draft.plan.withCheck(id) { $0.emoji = emoji }
            case "dose":
                draft.plan.withCheck(id) { $0.dose = text }
            case "when":
                let timing = checkTiming(value)
                draft.plan.withCheck(id) { check in
                    check.timing = timing
                    check.whenKey = key
                }
            case "days":
                guard let days = checkDays(value) else { return invalid }
                draft.plan.withCheck(id) { check in
                    check.days = days
                    check.daysKey = key
                }
            default: // optional, remind, affects_weight
                guard let flag = yesNo(value) else { return invalid + " (yes or no)" }
                draft.plan.withCheck(id) { check in
                    switch field {
                    case "optional": check.isOptional = flag
                    case "remind": check.remind = flag
                    default: check.affectsWeight = flag
                    }
                }
            }
        }
        return nil
    }

    /// One target field (calories, protein_g, …, macros_g) into `targets`.
    static func readTarget(_ field: String, _ value: String, into targets: inout SettingsPlanDraft.Targets) -> String? {
        let invalid = "“\(value)” isn't a valid value"
        switch field {
        case "calories":
            guard let energy = planNumber(value, 800...6000) else { return invalid }
            targets.calories = energy.rounded()
        case "protein_g":
            guard let grams = planNumber(value, 10...400) else { return invalid }
            targets.protein = grams
        case "carbs_g":
            guard let grams = planNumber(value, 0...900) else { return invalid }
            targets.carbs = grams
        case "fat_g":
            guard let grams = planNumber(value, 10...400) else { return invalid }
            targets.fat = grams
        case "fiber_g":
            guard let grams = planNumber(value, 5...100) else { return invalid }
            targets.fiber = grams
        case "water_ml":
            guard var ml = planNumber(value, 0.5...8000) else { return invalid }
            if ml < 10 { ml *= 1000 } // litres
            guard ml >= 500 else { return invalid }
            targets.water = ml
        default: // macros_g
            let parts = numbers(in: value)
            guard parts.count == 3, (10...400).contains(parts[0]), (0...900).contains(parts[1]), (10...400).contains(parts[2]) else {
                return invalid + " (protein/carbs/fat in grams, like 160/328/72)"
            }
            targets.protein = parts[0]
            targets.carbs = parts[1]
            targets.fat = parts[2]
        }
        return nil
    }

    /// Unknown day-type ids in phases and checks (once every row is read, so day types may come
    /// after the phases that use them), and at most 4 day types.
    static func validatePlan(_ draft: inout SettingsDraft) {
        guard var types = draft.plan.dayTypes else { return }
        if types.count > 4 {
            for extra in types.dropFirst(4) { draft.skipped.append("day_type.\(extra.id): only 4 day types fit") }
            types = Array(types.prefix(4))
            draft.plan.dayTypes = types
        }
        let ids = Set(types.map(\.id))
        if var phases = draft.plan.phases {
            for index in phases.indices {
                for type in phases[index].typeOrder where !ids.contains(type) {
                    draft.skipped.append("\(phases[index].typeKeys[type] ?? "phase.\(phases[index].id).\(type)"): \(type) isn't a day type")
                    phases[index].byType[type] = nil
                }
                phases[index].typeOrder.removeAll { !ids.contains($0) }
                phases[index].typeKeys = phases[index].typeKeys.filter { ids.contains($0.key) }
            }
            draft.plan.phases = phases
        }
        if var checks = draft.plan.checks {
            for index in checks.indices {
                guard case .dayTypes(let list)? = checks[index].days else { continue }
                let unknown = list.filter { !ids.contains($0) }
                guard !unknown.isEmpty else { continue }
                draft.skipped.append("\(checks[index].daysKey): \(unknown.joined(separator: ", ")) isn't a day type")
                let known = list.filter { ids.contains($0) }
                checks[index].days = known.isEmpty ? nil : .dayTypes(known)
            }
            draft.plan.checks = checks
        }
    }

    // MARK: Value helpers

    /// The numbers in a text, signs ignored: "0.1 to 0.2" → [0.1, 0.2], "160/328/72" → 3 numbers.
    static func numbers(in text: String) -> [Double] {
        var result: [Double] = []
        var current = ""
        let characters = Array(text)
        func flush() {
            if let value = Double(current) { result.append(value) }
            current = ""
        }
        for (index, character) in characters.enumerated() {
            if character.isASCII, character.isNumber {
                current.append(character)
            } else if character == "." || character == ",", !current.isEmpty, !current.contains("."),
                      index + 1 < characters.count, characters[index + 1].isASCII, characters[index + 1].isNumber {
                current.append(".")
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// "0.15", "0.1-0.2", "0.1–0.2", "0.1 to 0.2" → a range within `bounds` (lower bound first).
    static func planRange(_ text: String, _ bounds: ClosedRange<Double>) -> ClosedRange<Double>? {
        let values = numbers(in: text)
        guard (1...2).contains(values.count), values.allSatisfy({ bounds.contains($0) }) else { return nil }
        return values.min()!...values.max()!
    }

    /// One number within `bounds`; "~83", "about 20", "ca. 82" are read as the number.
    static func planNumber(_ text: String, _ bounds: ClosedRange<Double>) -> Double? {
        guard let value = ImportColumns.number(withoutApprox(text).text), bounds.contains(value) else { return nil }
        return value
    }

    /// The text without a "~", "≈", "about", "ca." … in front, and whether there was one.
    static func withoutApprox(_ raw: String) -> (text: String, approx: Bool) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var approx = false
        var found = true
        while found {
            found = false
            let lower = text.lowercased()
            for prefix in approxPrefixes where lower.hasPrefix(prefix) {
                approx = true
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                found = true
                break
            }
        }
        return (text, approx)
    }

    static func yesNo(_ text: String) -> Bool? {
        if ImportColumns.isYes(text) { return true }
        let word = SearchText.normalize(text)
        if ["no", "n", "false", "0", "nein", "off", "aus", "none"].contains(word) || text.trimmingCharacters(in: .whitespaces) == "-" { return false }
        if ["on", "an", "ein", "optional"].contains(word) { return true }
        return nil
    }

    static func goal(named text: String) -> WeightGoal? {
        let word = SearchText.normalize(text).replacingOccurrences(of: " ", with: "_")
        let map: [String: WeightGoal] = ["lose": .lose, "lose_weight": .lose, "abnehmen": .lose, "cut": .lose, "loss": .lose, "fat_loss": .lose,
                                         "maintain": .maintain, "keep": .maintain, "halten": .maintain, "keep_weight": .maintain,
                                         "maintenance": .maintain, "hold": .maintain,
                                         "gain": .gain, "gain_weight": .gain, "zunehmen": .gain, "bulk": .gain, "muscle": .gain,
                                         "muscle_building": .gain, "lean_gain": .gain, "aufbau": .gain, "muskelaufbau": .gain]
        return map[word]
    }

    static let approxPrefixes = ["~", "≈", "approximately", "approx.", "approx", "about", "around", "circa", "ca.", "ca ",
                                 "etwa", "ungefähr", "ungefahr", "rund"]

    static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "januar": 1, "janner": 1, "feb": 2, "february": 2, "februar": 2, "feber": 2,
        "mar": 3, "march": 3, "marz": 3, "maerz": 3, "apr": 4, "april": 4, "may": 5, "mai": 5, "jun": 6, "june": 6, "juni": 6,
        "jul": 7, "july": 7, "juli": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "okt": 10, "oktober": 10, "nov": 11, "november": 11, "dec": 12, "december": 12, "dez": 12, "dezember": 12,
    ]

    /// "2030-01-07", "07.01.2030", "2030-04" (a start: the 1st, an end: the last day of the month),
    /// "April 2030"; "~" or "about" in front = approximate.
    static func planDate(_ raw: String, end: Bool) -> (day: DayKey, approx: Bool)? {
        let (text, approx) = withoutApprox(raw)
        guard !text.isEmpty else { return nil }
        if let day = DiaryCSV.parseDate(text) { return (day, approx) }
        var year: Int?
        var month: Int?
        for word in SearchText.normalize(text).split(separator: " ").map(String.init) {
            if let number = Int(word) {
                if (1900...2200).contains(number), year == nil {
                    year = number
                } else if (1...12).contains(number), month == nil {
                    month = number
                } else {
                    return nil
                }
            } else if let name = monthNames[word], month == nil {
                month = name
            } else {
                return nil
            }
        }
        guard let year, let month else { return nil }
        return (DayKey(year: year, month: month, day: end ? lastDay(year: year, month: month) : 1), approx)
    }

    static func lastDay(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// A clock time anywhere in a text: "daily 07:00", "7:30", "7am", "19h", "7" (a bare hour).
    /// `strict`: only what reads as a time – with ":" or "." and two-digit minutes, or am/pm/uhr/h
    /// ("7 am", "19 Uhr") – so "Snack 2" or "5 g" aren't 02:00 and 05:00.
    static func clockTime(in text: String, strict: Bool = false) -> Int? {
        let tokens = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).map(String.init)
        for (index, token) in tokens.enumerated() {
            var word = token
            var pm = false
            var marked = false
            let next = index + 1 < tokens.count ? tokens[index + 1] : ""
            if word.hasSuffix("pm") {
                pm = true
                marked = true
                word.removeLast(2)
            } else if word.hasSuffix("am") {
                marked = true
                word.removeLast(2)
            } else if word.hasSuffix("uhr") {
                marked = true
                word.removeLast(3)
            } else if next == "pm" {
                pm = true
                marked = true
            } else if ["am", "uhr", "h"].contains(next) {
                marked = true
            }
            guard word.first?.isNumber == true else { continue }
            if strict, !marked, word.range(of: #"^\d{1,2}([:.]\d{2}|h|h\d{2})$"#, options: .regularExpression) == nil { continue }
            guard var minutes = ClockTime.parse(word) else { continue }
            if pm, minutes < 12 * 60 { minutes += 12 * 60 }
            return minutes
        }
        return nil
    }

    static let siteAliases: [String: BodySite] = {
        let groups: [(BodySite, [String])] = [
            (.waist, ["navel", "bauch", "bauchumfang", "taille", "belly", "waist_navel"]),
            (.waistNarrow, ["narrow_waist", "natural_waist", "schmalste_taille"]),
            (.hip, ["hips", "hufte", "huften", "huftumfang", "gesass", "po"]),
            (.chest, ["brust", "brustumfang"]),
            (.arm, ["upper_arm", "oberarm", "arm_right", "right_arm", "arm_r"]),
            (.thigh, ["oberschenkel", "thigh_right", "right_thigh", "thigh_r", "leg"]),
            (.neck, ["hals", "halsumfang"]),
            (.calf, ["wade", "waden", "calves", "calf_right", "right_calf", "calf_r"]),
            (.armFlexed, ["flexed_arm", "biceps", "bizeps", "arm_flexed"]),
            (.armLeft, ["arm_left", "left_arm"]),
            (.thighLeft, ["thigh_left", "left_thigh"]),
            (.calfLeft, ["calf_left", "left_calf"]),
        ]
        var map: [String: BodySite] = [:]
        for site in BodySite.allCases { map[site.rawValue] = site }
        for (site, names) in groups {
            for name in names { map[ImportColumns.normalize(name)] = site }
        }
        return map
    }()

    /// "waist", "Taille", "upper_arm_cm", "arm_l" → the site.
    static func bodySite(named text: String) -> BodySite? {
        var key = ImportColumns.normalize(text)
        if key.hasSuffix("_cm") { key.removeLast(3) }
        return siteAliases[key]
    }

    /// "waist;chest;arm" → the sites in that order; "none" → []; nil when a name isn't a site.
    static func bodySites(_ text: String) -> [BodySite]? {
        if ["none", "no", "keine", "nothing", "-"].contains(SearchText.normalize(text)) || text.trimmingCharacters(in: .whitespaces) == "-" { return [] }
        var sites: [BodySite] = []
        for item in ImportColumns.list(text.replacingOccurrences(of: "/", with: ";")) {
            guard let site = bodySite(named: item) else { return nil }
            if !sites.contains(site) { sites.append(site) }
        }
        return sites.isEmpty ? nil : sites
    }

    static let methodNames = "dexa, bodpod, bia_pro, scale, skinfold, navy or estimate"

    static func bodyMethod(named text: String) -> BodyMethod? {
        let key = SearchText.normalize(text).replacingOccurrences(of: " ", with: "_")
        if let method = BodyMethod(rawValue: key) { return method }
        let map: [String: BodyMethod] = [
            "dxa": .dexa, "dexa_scan": .dexa, "bod_pod": .bodpod, "air_displacement": .bodpod,
            "bia": .biaPro, "inbody": .biaPro, "professional_bia": .biaPro, "bioimpedance": .biaPro, "tanita_pro": .biaPro,
            "smart_scale": .scale, "waage": .scale, "korperfettwaage": .scale, "bia_scale": .scale, "body_fat_scale": .scale,
            "calipers": .skinfold, "caliper": .skinfold, "skinfolds": .skinfold, "hautfalte": .skinfold, "hautfalten": .skinfold,
            "tape": .navy, "us_navy": .navy, "tape_estimate": .navy, "navy_tape": .navy, "massband": .navy,
            "estimated": .estimate, "guess": .estimate, "visual": .estimate, "schatzung": .estimate, "geschatzt": .estimate,
            "eyeball": .estimate, "ai_estimate": .estimate,
        ]
        return map[key]
    }

    /// The first character when it is an emoji.
    static func firstEmoji(_ text: String) -> String? {
        guard let first = text.trimmingCharacters(in: .whitespaces).first else { return nil }
        let scalars = first.unicodeScalars
        guard scalars.contains(where: { $0.properties.isEmojiPresentation }) || (scalars.count > 1 && scalars.first?.properties.isEmoji == true) else {
            return nil
        }
        return String(first)
    }

    /// "breakfast", "with breakfast", "5 g with breakfast", "Snack 2" (a meal), "08:00", "7 am",
    /// "anytime". Only a real time is a time (`clockTime(in:strict:)`); a meal name is matched
    /// with the meals when the plan is applied.
    static func checkTiming(_ text: String) -> CoachPlan.CheckTiming {
        let word = SearchText.normalize(text)
        if word.isEmpty || ["anytime", "any time", "any", "jederzeit", "egal", "whenever", "daily"].contains(word) { return .anytime }
        if let minutes = clockTime(in: text, strict: true) { return .time(minutes) }
        var name = text.trimmingCharacters(in: .whitespaces)
        let padded = " " + name
        let connectors = ["with", "at", "before", "after", "zum", "zur", "beim", "mit", "vor dem", "nach dem", "vor", "nach"]
        // "with breakfast", "5 g with breakfast": the meal is what follows the first connector
        // (the longer one where two start at the same place: "vor dem", not "vor").
        let found = connectors.compactMap { padded.range(of: " \($0) ", options: .caseInsensitive) }.min { a, b in
            a.lowerBound != b.lowerBound ? a.lowerBound < b.lowerBound : a.upperBound > b.upperBound
        }
        if let found {
            let rest = String(padded[found.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { name = rest }
        }
        return .meal(name)
    }

    /// "daily", "mon;wed;fri", "weekdays" or day-type ids "gym;tennis".
    static func checkDays(_ text: String) -> CoachPlan.CheckDays? {
        let word = SearchText.normalize(text)
        if ["daily", "every day", "everyday", "taglich", "jeden tag", "all days", "always", "immer"].contains(word) { return .daily }
        if let days = weekdays(text) { return .weekdays(days) }
        let ids = ImportColumns.list(text).map(planID).filter { !$0.isEmpty }
        return ids.isEmpty ? nil : .dayTypes(ids)
    }

    /// An id as Nina stores it: lowercase letters and digits.
    static func planID(_ text: String) -> String {
        ImportColumns.normalize(text).replacingOccurrences(of: "_", with: "")
    }

    static func macroProblem(calories: Double, protein: Double, carbs: Double, fat: Double) -> String? {
        let sum = protein * 4 + carbs * 4 + fat * 9
        guard abs(sum - calories) > calories * 0.05 else { return nil }
        return "macros add up to \(grouped(sum)) kcal, not \(grouped(calories))"
    }

    /// 2840 → "2,840".
    static func grouped(_ value: Double) -> String {
        let number = Int(value.rounded())
        var digits = String(abs(number))
        var parts: [String] = []
        while digits.count > 3 {
            parts.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        parts.insert(digits, at: 0)
        return (number < 0 ? "-" : "") + parts.joined(separator: ",")
    }
}

// MARK: - Applying the plan

extension SettingsCSV {
    /// The targets the flat calories, protein_g … rows stand for: the active phase's baseline, else
    /// the profile's targets.
    public static func flatTargets(_ state: SettingsState, today: DayKey) -> DailyTargets {
        state.plan?.revision(on: today)?.baseline ?? state.targets
    }

    /// The rate the flat rate_kg_per_week row stands for: the active phase's range, else the profile's.
    static func flatRate(_ state: SettingsState, today: DayKey) -> ClosedRange<Double> {
        if let phase = state.plan?.activePhase(on: today), phase.rateRange.upperBound > 0 { return phase.rateRange }
        return state.ratePerWeek...state.ratePerWeek
    }

    /// The revision a phase's targets are read from and compared with: the one in force today for a
    /// started phase, else the first.
    static func currentRevision(of phase: CoachPlan.Phase, today: DayKey) -> CoachPlan.Revision? {
        let day = phase.isStarted ? today : (phase.start ?? today)
        return phase.revision(on: day) ?? phase.revisions.first
    }

    struct PlanInput {
        var current: SettingsState
        var oldPlan: CoachPlan?
        var flatOld: DailyTargets
        var flatNew: DailyTargets
        var today: DayKey
        var now: Date
        var calendar: Calendar
    }

    /// The plan after the file, written into `state` with the compatibility mirror. The rules are in
    /// docs/IMPORT.md, "Coach plan" → "How an import changes the plan".
    static func applyPlan(_ draft: SettingsDraft, _ input: PlanInput, state: inout SettingsState, notes: inout [String]) {
        let rows = draft.plan
        let today = input.today
        let oldPlan = input.oldPlan
        var plan = oldPlan ?? CoachPlan(routine: CoachPlan.Routine.defaults(for: state.sex))

        // Setting up a plan (phases or day types in the file, none so far): the profile becomes the
        // first plan – training days a "Training" type, the goal one open-ended phase from today.
        let migrating = rows.setsUpPlan && !plan.isSetUp
        if migrating {
            var migrated = CoachPlan.migrated(from: state, on: today, now: input.now, reason: "import")
            if let oldPlan {
                migrated.longTerm = oldPlan.longTerm
                migrated.protein = oldPlan.protein
                migrated.checks = oldPlan.checks
                migrated.routine = oldPlan.routine
                migrated.adjust = oldPlan.adjust
                migrated.pauses = oldPlan.pauses
                migrated.notes = oldPlan.notes
            }
            plan = migrated
        }

        // Protein per meal.
        if let range = rows.mealProtein {
            plan.protein.mealMin = range.lowerBound
            plan.protein.mealMax = range.upperBound > range.lowerBound ? range.upperBound : 0
        }
        if let meals = rows.proteinMeals {
            var ids: [String] = []
            for name in meals.names {
                if let slot = MealSlot.matching(name, in: state.meals) {
                    if !ids.contains(slot.id) { ids.append(slot.id) }
                } else {
                    notes.append("protein_meals: “\(name)” isn't one of your meals")
                }
            }
            plan.protein.count = meals.count
            plan.protein.meals = ids
        }

        // Notes, long-term goal, measuring, check-in.
        if let list = rows.notes { plan.notes = list }
        let longTerm = rows.longTerm
        if let weight = longTerm.weightKg { plan.longTerm.weightKg = weight }
        if let fat = longTerm.bodyFat {
            plan.longTerm.bodyFat = fat
            if fat < (state.sex == .female ? 15 : 8) { notes.append("long_term.body_fat_percent: \(NumberText.plain(fat)) % is a contest-level target") }
        }
        if let waist = longTerm.waistCm { plan.longTerm.waistCm = waist }
        if let date = longTerm.date { plan.longTerm.date = date }
        if let note = longTerm.note { plan.longTerm.note = note }
        let measure = rows.measure
        if let minutes = measure.weighInMinutes { plan.routine.weighInMinutes = minutes }
        if let minutes = measure.morningCutoffMinutes { plan.routine.morningCutoffMinutes = minutes }
        if let sites = measure.weeklySites { plan.routine.weeklySites = sites }
        if let sites = measure.fullSites { plan.routine.fullSites = sites }
        if let weeks = measure.fullEveryWeeks { plan.routine.fullEveryWeeks = weeks }
        if let weeks = measure.bodyFatEveryWeeks { plan.routine.bodyFatEveryWeeks = weeks }
        if let method = measure.bodyFatMethod { plan.routine.bodyFatMethod = method }
        if let side = measure.side { plan.routine.side = side }
        if let mark = measure.thighMark { plan.routine.thighMark = mark }
        if let flag = measure.twoReadings { plan.routine.twoReadings = flag }
        let checkIn = rows.checkIn
        if let weekday = checkIn.weekday { plan.routine.checkInWeekday = weekday }
        if let window = checkIn.windowDays {
            plan.adjust.windowMinDays = window.lowerBound
            plan.adjust.windowMaxDays = window.upperBound
        }
        if let step = checkIn.step {
            plan.adjust.stepMin = step.lowerBound
            plan.adjust.stepMax = step.upperBound
        }
        if let lock = checkIn.lockDays { plan.adjust.lockDays = lock }

        // Day types (the group replaces all day types).
        if let types = rows.dayTypes {
            var built: [CoachPlan.DayType] = []
            for row in types {
                let name = row.name ?? row.id.prefix(1).uppercased() + row.id.dropFirst()
                var schedule = row.schedule ?? (row.weekdays != nil ? .fixed : .flexible)
                if schedule == .fixed, row.weekdays?.isEmpty ?? true { schedule = .flexible }
                if schedule == .default, built.contains(where: { $0.schedule == .default }) {
                    notes.append("day_type.\(row.id).days: only one day type can be the default – \(name) is flexible now")
                    schedule = .flexible
                }
                // Without an emoji row a day type that was there keeps its emoji (also none).
                let emoji = row.emoji ?? input.oldPlan?.dayType(id: row.id)?.emoji ?? {
                    let suggested = CoachPlan.DayType.suggestedEmoji(for: name)
                    return suggested.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: row.id) : suggested
                }()
                built.append(CoachPlan.DayType(id: row.id, name: name, emoji: emoji, schedule: schedule,
                                               weekdays: schedule == .fixed ? row.weekdays ?? Weekdays([]) : Weekdays([]),
                                               perWeek: schedule == .flexible ? row.perWeek ?? 0 : 0, workouts: row.workouts ?? []))
            }
            plan.dayTypes = built
        }
        let typeIDs = Set(plan.dayTypes.map(\.id))

        // Daily checks (the group replaces all checks).
        if let checks = rows.checks {
            plan.checks = checks.map { row in
                let name = row.name ?? row.id.prefix(1).uppercased() + row.id.dropFirst()
                var timing = row.timing ?? .anytime
                if case .meal(let meal) = timing {
                    if let slot = MealSlot.matching(meal, in: state.meals) {
                        timing = .meal(slot.id)
                    } else {
                        notes.append("\(row.whenKey): “\(meal)” isn't one of your meals – anytime instead")
                        timing = .anytime
                    }
                }
                var days = row.days ?? .daily
                if case .dayTypes(let ids) = days, rows.dayTypes == nil {
                    let unknown = ids.filter { !typeIDs.contains($0) }
                    if !unknown.isEmpty {
                        notes.append("\(row.daysKey): \(unknown.joined(separator: ", ")) isn't a day type")
                        let known = ids.filter { typeIDs.contains($0) }
                        days = known.isEmpty ? .daily : .dayTypes(known)
                    }
                }
                return CoachPlan.Check(id: row.id, name: name, emoji: row.emoji ?? input.oldPlan?.check(id: row.id)?.emoji ?? "💊",
                                       dose: row.dose ?? "", timing: timing, days: days,
                                       isOptional: row.isOptional ?? false, remind: row.remind ?? false, affectsWeight: row.affectsWeight)
            }
        }

        // Phases (the group replaces all phases; a phase that was there keeps its history).
        let flatChanged = input.flatNew != input.flatOld
        var filePhases = Set<String>()
        if let phaseRows = rows.phases {
            filePhases = Set(phaseRows.map(\.id))
            plan.phases = phases(phaseRows, draft: draft, input: input, plan: plan, typeIDs: typeIDs, state: state, notes: &notes)
        }

        // Flat goal, rate, target weight and targets go to the active phase when the file doesn't
        // have that phase's rows and they differ from what the flat rows stood for so far.
        if let active = plan.activePhase(on: today), !filePhases.contains(active.id), let index = plan.phases.firstIndex(where: { $0.id == active.id }) {
            if let goal = draft.goal, goal != input.current.goal { plan.phases[index].goal = goal }
            // A maintain phase has no pace: the profile's (flat) rate isn't its band.
            if let range = draft.rateRange, range != flatRate(input.current, today: today), plan.phases[index].goal != .maintain {
                plan.phases[index].rateMin = range.lowerBound
                plan.phases[index].rateMax = range.upperBound
            }
            if let target = draft.targetWeight, target != input.current.targetWeight { plan.phases[index].targetWeight = target }
            if flatChanged {
                let wasRunning = oldPlan?.phase(id: active.id)?.isStarted == true
                let byType = plan.phases[index].revision(on: today)?.byType ?? currentRevision(of: active, today: today)?.byType ?? [:]
                plan = addingImportRevision(to: plan, phase: active.id, from: wasRunning ? today : (active.start ?? today),
                                            baseline: input.flatNew, byType: byType, notes: &notes)
            }
        }

        // Legacy training days: a "Training" day type (fixed) plus "Rest" (default).
        if rows.dayTypes == nil, plan.isSetUp {
            let current = input.current
            let legacyDays: Weekdays? = draft.trainingDays
                ?? (migrating && rows.phases != nil && current.trainingTargets != nil && !current.trainingDays.isEmpty ? current.trainingDays : nil)
            if legacyDays == nil, draft.trainingExtra != nil, !notes.contains(where: { $0.hasPrefix("training_extra_kcal") }) {
                notes.append("training_extra_kcal: your plan's day types set the calories – use phase.N.<type>.calories rows")
            }
            if let days = legacyDays, days.isEmpty {
                if draft.trainingDays != nil, plan.dayTypes.contains(where: { $0.id != "rest" }) {
                    notes.append("training_days: your plan's day types stay – change them with day_type rows")
                }
            } else if let days = legacyDays {
                plan.dayTypes = [
                    CoachPlan.DayType(id: "training", name: "Training", emoji: "🏋️", schedule: .fixed, weekdays: days),
                    CoachPlan.DayType(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
                ]
                let ownRows = rows.phases?.contains { $0.id == plan.activePhase(on: today)?.id && !$0.byType.isEmpty } ?? false
                if let active = plan.activePhase(on: today), !ownRows {
                    let revision = active.revision(on: today)
                    let base = revision?.baseline ?? input.flatNew
                    let oldExtra = revision?.byType["training"].map { $0.energy - (revision?.byType["rest"] ?? base).energy }
                    let extra = draft.trainingExtra ?? oldExtra ?? (current.trainingTargets != nil ? current.trainingExtra : 300)
                    let byType = ["training": SettingsState.training(base, extra: extra), "rest": base]
                    if revision?.byType != byType || revision?.baseline != base {
                        let wasRunning = oldPlan?.phase(id: active.id)?.isStarted == true
                        plan = addingImportRevision(to: plan, phase: active.id, from: wasRunning ? today : (active.start ?? today),
                                                    baseline: base, byType: byType, notes: &notes)
                    }
                }
            }
        }

        // A plan that was set up by this import: types it no longer has are dropped from its first revision.
        if migrating, let index = plan.phases.firstIndex(where: { $0.id == "1" && !filePhases.contains($0.id) }) {
            let known = Set(plan.dayTypes.map(\.id))
            for revision in plan.phases[index].revisions.indices {
                let byType = plan.phases[index].revisions[revision].byType.filter { known.contains($0.key) }
                plan.phases[index].revisions[revision].byType = byType
            }
        }

        // The profile mirrors the active phase (older builds and the watch read it).
        if plan.isSetUp {
            state.trainingTargets = input.current.trainingTargets
            state.trainingDays = input.current.trainingDays
            if let mirror = plan.mirror(on: today) { state = mirror.applied(to: state) }
        }
        state.plan = plan
    }

    /// The phases of the file, matched by id with the ones there were (start confirmation, start
    /// weight and revisions are kept), with statuses, trimmed overlaps and their targets.
    static func phases(_ rows: [SettingsPlanDraft.Phase], draft: SettingsDraft, input: PlanInput, plan: CoachPlan, typeIDs: Set<String>,
                       state: SettingsState, notes: inout [String]) -> [CoachPlan.Phase] {
        let today = input.today
        let calendar = input.calendar
        let oldPlan = input.oldPlan
        var built: [CoachPlan.Phase] = rows.map { row in
            let old = oldPlan?.phase(id: row.id)
            var phase = CoachPlan.Phase(id: row.id, start: row.start, startApprox: row.startApprox, end: row.end, endApprox: row.endApprox,
                                        startWeight: old?.startWeight ?? 0, startedAt: old?.startedAt, status: old?.status ?? .planned,
                                        revisions: old?.revisions ?? [])
            if let end = phase.end, let start = phase.start, end < start {
                notes.append("phase.\(row.id).end: \(end.rawValue) is before the start")
                phase.end = nil
                phase.endApprox = false
            }
            // A start today or earlier counts as the confirmation – unless it's the same planned
            // start as before (then the "phase starts" card still asks).
            if old?.isStarted != true {
                let startChanged = old == nil || old?.start != row.start
                if let start = row.start, start <= today, startChanged {
                    phase.startedAt = input.now
                    phase.status = .active
                    phase.startApprox = false
                } else if old == nil {
                    phase.status = .planned
                }
            }
            return phase
        }

        // Overlapping dates are trimmed; of the running phases the one that started last is active.
        let order = built.indices.filter { built[$0].start != nil }.sorted { built[$0].start! < built[$1].start! }
        for (a, b) in zip(order, order.dropFirst()) {
            guard let end = built[a].end, let next = built[b].start, end >= next else { continue }
            let dayBefore = next.adding(days: -1, calendar: calendar)
            if let start = built[a].start, dayBefore >= start {
                built[a].end = dayBefore
                notes.append("phase.\(built[a].id) and phase.\(built[b].id) overlap – phase \(built[a].id) now ends \(dayBefore.rawValue)")
            } else {
                built[a].end = nil
                notes.append("phase.\(built[a].id) and phase.\(built[b].id) start on the same day")
            }
            built[a].endApprox = false
        }
        let running = order.filter { built[$0].isStarted && built[$0].status != .done }
        for (a, b) in zip(running, running.dropFirst()) {
            built[a].status = .done
            let dayBefore = built[b].start!.adding(days: -1, calendar: calendar)
            if built[a].end.map({ $0 > dayBefore }) ?? true {
                built[a].end = dayBefore
                built[a].endApprox = false
            }
        }
        var probe = plan
        probe.phases = built
        let activeID = probe.activePhase(on: today)?.id

        // The rest of each phase: rows, then (for the active phase) the flat rows, then defaults.
        let flatChanged = input.flatNew != input.flatOld
        for index in built.indices {
            let row = rows[index]
            let isActive = built[index].id == activeID
            let goal = row.goal ?? (isActive ? draft.goal : nil) ?? .maintain
            built[index].goal = goal
            built[index].name = row.name ?? CoachPlan.Phase.defaultName(for: goal)
            // The flat rate is the active phase's pace; a maintain phase has none (its band comes
            // from its own rate_kg_per_week row only).
            var rate = row.rate ?? (isActive && row.ratePercent == nil && goal != .maintain ? draft.rateRange : nil)
            if rate == nil, let percent = row.ratePercent {
                if state.weightKg > 0 {
                    func kg(_ value: Double) -> Double { (value / 100 * state.weightKg * 100).rounded() / 100 }
                    rate = kg(percent.lowerBound)...kg(percent.upperBound)
                } else {
                    notes.append("phase.\(row.id).rate_percent_per_week: needs your weight (weight_kg)")
                }
            }
            built[index].rateMin = rate?.lowerBound ?? 0
            built[index].rateMax = rate?.upperBound ?? 0
            built[index].reviewMin = row.review?.lowerBound ?? 0
            built[index].reviewMax = row.review?.upperBound ?? 0
            if let review = row.review, review.lowerBound == review.upperBound, let old = oldPlan?.phase(id: row.id),
               min(old.reviewMin, old.reviewMax) == 0, max(old.reviewMin, old.reviewMax) == review.lowerBound {
                // A single review weight stored with the other end empty reads back as it was.
                built[index].reviewMin = old.reviewMin
                built[index].reviewMax = old.reviewMax
            }
            built[index].targetWeight = row.targetWeight ?? (isActive ? draft.targetWeight : nil) ?? 0
            built[index].targetBodyFat = row.targetBodyFat ?? 0
            built[index].maxWaistGainCm = row.maxWaistGainCm ?? CoachPlan.Phase.defaultMaxWaistGain(for: goal)
            built[index].note = row.note ?? ""

            // Targets: the rows (missing fields from the baseline), the flat rows for the active phase.
            if let problem = row.baseline.macroProblem { notes.append("phase.\(row.id): \(problem)") }
            for type in row.typeOrder {
                if let problem = row.byType[type]?.macroProblem { notes.append("phase.\(row.id).\(type): \(problem)") }
            }
            var typeRows: [String: SettingsPlanDraft.Targets] = [:]
            for type in row.typeOrder {
                if typeIDs.contains(type) {
                    typeRows[type] = row.byType[type]
                } else if draft.plan.dayTypes == nil {
                    notes.append("\(row.typeKeys[type] ?? "phase.\(row.id).\(type)"): \(type) isn't a day type")
                }
            }
            let useFlat = isActive && flatChanged
            guard !row.baseline.isEmpty || !typeRows.isEmpty || useFlat else { continue }
            let current = currentRevision(of: built[index], today: today)
            let fillBase = useFlat ? input.flatNew : (current?.baseline ?? input.flatNew)
            let baseline: DailyTargets?
            if !row.baseline.isEmpty {
                baseline = row.baseline.filled(over: fillBase)
            } else if useFlat {
                baseline = input.flatNew
            } else {
                baseline = current?.baseline ?? (isActive ? input.flatNew : nil)
            }
            let byType = typeRows.isEmpty ? current?.byType ?? [:] : typeRows.mapValues { $0.filled(over: baseline ?? input.flatNew) }
            if let current, current.baseline == baseline,
               current.byType.filter({ typeIDs.contains($0.key) }) == byType.filter({ typeIDs.contains($0.key) }) { continue }
            let wasRunning = oldPlan?.phase(id: built[index].id)?.isStarted == true
            if wasRunning {
                addImportRevision(to: &built[index], from: today, baseline: baseline, byType: byType, notes: &notes)
            } else {
                built[index].revisions = [CoachPlan.Revision(from: built[index].start ?? today, baseline: baseline, byType: byType, reason: "import")]
            }
        }

        // A phase this import confirms with a start before today: the days up to yesterday keep the
        // targets they had (target history), its own targets start today.
        for index in built.indices {
            guard oldPlan?.phase(id: built[index].id)?.isStarted != true, built[index].isStarted,
                  let start = built[index].start, start < today else { continue }
            keepPastTargets(of: &built[index], from: start, input: input, typeIDs: typeIDs)
        }
        return built
    }

    /// The reason of the revisions that keep the targets days had before an import confirmed a
    /// phase with an earlier start.
    public static let keptRevisionReason = "kept"

    /// The plan with an import revision of a phase from `day` on. It replaces the revision dated
    /// that day and any dated later (an adjustment applied "from tomorrow" would otherwise take
    /// over again tomorrow); a note names the replaced ones.
    static func addingImportRevision(to plan: CoachPlan, phase id: String, from day: DayKey, baseline: DailyTargets?,
                                     byType: [String: DailyTargets], notes: inout [String]) -> CoachPlan {
        guard let index = plan.phases.firstIndex(where: { $0.id == id }) else { return plan }
        var copy = plan
        addImportRevision(to: &copy.phases[index], from: day, baseline: baseline, byType: byType, notes: &notes)
        return copy
    }

    static func addImportRevision(to phase: inout CoachPlan.Phase, from day: DayKey, baseline: DailyTargets?,
                                  byType: [String: DailyTargets], notes: inout [String]) {
        let later = phase.revisions.filter { $0.from > day }
        if !later.isEmpty {
            let days = later.map(\.from.rawValue).joined(separator: ", ")
            notes.append("phase.\(phase.id): these targets replace the change planned from \(days)")
        }
        var revisions = phase.revisions.filter { $0.from < day }
        revisions.append(CoachPlan.Revision(from: day, baseline: baseline, byType: byType, reason: "import"))
        phase.revisions = revisions.sorted { $0.from < $1.from }
    }

    /// For a phase this import confirms although it started before today: the days from its start
    /// up to yesterday get revisions with the targets they had before (`keptRevisions`), and its
    /// own targets start today – the newest one dated before today moves to today; without one,
    /// an empty revision from today leaves the phase without targets (the transition proposal).
    static func keepPastTargets(of phase: inout CoachPlan.Phase, from start: DayKey, input: PlanInput, typeIDs: Set<String>) {
        let today = input.today
        let kept = keptRevisions(from: start, before: today, input: input, typeIDs: typeIDs)
        guard !kept.isEmpty else { return }
        var own = phase.revisions.filter { $0.from >= today }
        if !own.contains(where: { $0.from == today }) {
            var moved = phase.revisions.filter { $0.from < today }.max { $0.from < $1.from }
                ?? CoachPlan.Revision(from: today, baseline: nil, byType: [:], reason: "import")
            moved.from = today
            own.append(moved)
        }
        phase.revisions = (kept + own).sorted { $0.from < $1.from }
    }

    /// What the days from `start` up to the day before `today` resolved to before the import, as
    /// revisions from `start` and from each later change: the old plan's revision in force on the
    /// day (missing targets filled with the profile's), else the profile's targets (with the
    /// training targets on a "training" day type, as before plans). Equal neighbours are merged.
    static func keptRevisions(from start: DayKey, before today: DayKey, input: PlanInput, typeIDs: Set<String>) -> [CoachPlan.Revision] {
        guard start < today else { return [] }
        let oldPlan = input.oldPlan
        let profile = input.current.targets
        var days: Set<DayKey> = [start]
        for phase in oldPlan?.phases ?? [] {
            var changes = phase.revisions.map(\.from)
            if let begin = phase.start { changes.append(begin) }
            if let end = phase.end { changes.append(end.adding(days: 1, calendar: input.calendar)) }
            for day in changes where day > start && day < today { days.insert(day) }
        }
        var legacy: [String: DailyTargets] = [:]
        if oldPlan?.isSetUp != true, typeIDs.contains("training"), let training = input.current.trainingTargets, !input.current.trainingDays.isEmpty {
            legacy["training"] = training
        }
        var result: [CoachPlan.Revision] = []
        for day in days.sorted() {
            let old = oldPlan?.revision(on: day)
            let revision = CoachPlan.Revision(from: day, baseline: old.map { $0.baseline ?? profile } ?? profile,
                                              byType: old?.byType ?? legacy, reason: keptRevisionReason)
            if let last = result.last, last.baseline == revision.baseline, last.byType == revision.byType { continue }
            result.append(revision)
        }
        return result
    }
}

// MARK: - Preview lines

extension SettingsCSV {
    static func g(_ value: Double) -> String { NumberText.plain(value.rounded(), decimals: 0) + " g" }

    static func rangeText(_ low: Double, _ high: Double, unit: String) -> String {
        guard high > 0 || low > 0 else { return "–" }
        let text = low == high || high == 0 ? NumberText.plain(low, decimals: 2) : "\(NumberText.plain(low, decimals: 2))–\(NumberText.plain(high, decimals: 2))"
        return text + unit
    }

    static func targetsText(_ targets: DailyTargets?, long: Bool) -> String {
        guard let targets else { return "–" }
        var text = "\(NumberText.plain(targets.energy, decimals: 0)) kcal · \(NumberText.plain(targets.protein.rounded(), decimals: 0))/\(NumberText.plain(targets.carbs.rounded(), decimals: 0))/\(NumberText.plain(targets.fat.rounded(), decimals: 0)) g"
        if long {
            text += " · fiber \(g(targets.fiber)) · water \(NumberText.plain(targets.water, decimals: 0)) ml"
            text += " · sugar ≤ \(g(targets.sugarMax)) · sat. fat ≤ \(g(targets.saturatedFatMax)) · salt ≤ \(NumberText.plain(targets.sodiumMax * 2.5 / 1000, decimals: 1)) g"
        }
        return text
    }

    static func dateText(_ day: DayKey?, approx: Bool) -> String {
        guard let day else { return "open" }
        return (approx ? "~" : "") + day.rawValue
    }

    static func describe(_ type: CoachPlan.DayType) -> String {
        let schedule: String
        switch type.schedule {
        case .fixed: schedule = type.weekdays.summary
        case .flexible: schedule = type.perWeek > 0 ? "flexible, \(type.perWeek) per week" : "flexible"
        case .default: schedule = "all other days"
        }
        let workouts = type.workouts.isEmpty ? "" : " · " + type.workouts.joined(separator: ", ")
        return "\(type.emoji.isEmpty ? "" : type.emoji + " ")\(type.name) · \(schedule)\(workouts)"
    }

    static func describe(_ check: CoachPlan.Check, plan: CoachPlan, meals: [MealSlot]) -> String {
        var parts = ["\(check.emoji.isEmpty ? "" : check.emoji + " ")\(check.name)"]
        if !check.dose.isEmpty { parts.append(check.dose) }
        switch check.timing {
        case .anytime: parts.append("anytime")
        case .meal(let id): parts.append(meals.first { $0.id == id }?.name ?? id)
        case .time(let minutes): parts.append(ClockTime.text(minutes))
        }
        switch check.days {
        case .daily: parts.append("daily")
        case .weekdays(let days): parts.append(days.summary)
        case .dayTypes(let ids): parts.append(ids.map { plan.dayType(id: $0)?.name ?? $0 }.joined(separator: ", ") + " days")
        }
        if check.isOptional { parts.append("optional") }
        if check.remind { parts.append("reminder") }
        if check.affectsWeight { parts.append("affects weight") }
        return parts.joined(separator: " · ")
    }

    static func proteinText(_ protein: CoachPlan.Protein?) -> String {
        guard let protein, protein.mealMin > 0 else { return "–" }
        return rangeText(protein.mealMin, protein.mealMax, unit: " g")
    }

    static func proteinMealsText(_ protein: CoachPlan.Protein?, meals: [MealSlot]) -> String {
        guard let protein, protein.count > 0 || !protein.meals.isEmpty else { return "–" }
        let names = protein.meals.map { id in meals.first { $0.id == id }?.name ?? id }.joined(separator: ", ")
        if protein.count > 0 { return names.isEmpty ? "\(protein.count) a day" : "\(protein.count) a day · \(names)" }
        return names
    }

    /// The plan lines of the preview: day types, phases, checks, measuring, check-in, long-term goal and notes.
    static func planChanges(from old: SettingsState, to new: SettingsState, today: DayKey) -> [SettingsChange] {
        let oldPlan = old.plan.flatMap { $0.isEmpty ? nil : $0 }
        let newPlan = new.plan.flatMap { $0.isEmpty ? nil : $0 }
        guard oldPlan != nil || newPlan != nil, oldPlan != newPlan else { return [] }
        let before = oldPlan ?? CoachPlan(routine: CoachPlan.Routine.defaults(for: new.sex))
        let after = newPlan ?? CoachPlan(routine: CoachPlan.Routine.defaults(for: new.sex))
        var result: [SettingsChange] = []
        func add(_ title: String, _ a: String, _ b: String, _ group: SettingsGroup, key: String = "") {
            if a != b { result.append(SettingsChange(title: title, old: a, new: b, group: group, key: key)) }
        }

        // Protein per meal (with the targets).
        add("Protein per meal", proteinText(oldPlan?.protein), proteinText(newPlan?.protein), .targets)
        add("Protein meals", proteinMealsText(oldPlan?.protein, meals: old.meals), proteinMealsText(newPlan?.protein, meals: new.meals), .targets)

        // Day types.
        for type in after.dayTypes {
            add(type.name, before.dayType(id: type.id).map(describe) ?? "–", describe(type), .dayTypes, key: type.id)
        }
        for type in before.dayTypes where after.dayType(id: type.id) == nil {
            add(type.name, describe(type), "removed", .dayTypes, key: type.id)
        }

        // Phases.
        let activeID = after.activePhase(on: today)?.id
        func status(_ phase: CoachPlan.Phase?) -> String {
            guard let phase else { return "–" }
            if phase.status == .done { return "done" }
            return phase.isStarted ? "running" : "planned"
        }
        for phase in after.phases {
            let was = before.phase(id: phase.id)
            let title = "Phase \(phase.id)"
            add("\(title) · Name", was?.name ?? "–", phase.name, .phases)
            add("\(title) · Goal", was?.goal.title ?? "–", phase.goal.title, .phases)
            add("\(title) · Dates", was.map { "\(dateText($0.start, approx: $0.startApprox)) – \(dateText($0.end, approx: $0.endApprox))" } ?? "–",
                "\(dateText(phase.start, approx: phase.startApprox)) – \(dateText(phase.end, approx: phase.endApprox))", .phases)
            add("\(title) · Status", status(was), status(phase), .phases)
            add("\(title) · Rate", was.map { rangeText($0.rateRange.lowerBound, $0.rateRange.upperBound, unit: " kg/week") } ?? "–",
                rangeText(phase.rateRange.lowerBound, phase.rateRange.upperBound, unit: " kg/week"), .phases)
            add("\(title) · Review at", was.map { rangeText($0.reviewMin, $0.reviewMax, unit: " kg") } ?? "–", rangeText(phase.reviewMin, phase.reviewMax, unit: " kg"), .phases)
            add("\(title) · Target weight", was.map { $0.targetWeight > 0 ? kg($0.targetWeight) : "–" } ?? "–", phase.targetWeight > 0 ? kg(phase.targetWeight) : "–", .phases)
            add("\(title) · Target body fat", was.map { $0.targetBodyFat > 0 ? NumberText.plain($0.targetBodyFat, decimals: 1) + " %" : "–" } ?? "–",
                phase.targetBodyFat > 0 ? NumberText.plain(phase.targetBodyFat, decimals: 1) + " %" : "–", .phases)
            add("\(title) · Waist limit", was.map { $0.maxWaistGainCm > 0 ? "+" + NumberText.plain($0.maxWaistGainCm, decimals: 1) + " cm" : "–" } ?? "–",
                phase.maxWaistGainCm > 0 ? "+" + NumberText.plain(phase.maxWaistGainCm, decimals: 1) + " cm" : "–", .phases)
            add("\(title) · Note", was.map { $0.note.isEmpty ? "–" : $0.note } ?? "–", phase.note.isEmpty ? "–" : phase.note, .phases)

            let oldRevision = was.flatMap { currentRevision(of: $0, today: today) }
            let newRevision = currentRevision(of: phase, today: today)
            func targetsLine(_ name: String, _ a: DailyTargets?, _ b: DailyTargets?, key: String = "") {
                guard a != b else { return }
                let short = (targetsText(a, long: false), targetsText(b, long: false))
                if short.0 != short.1 {
                    add(name, short.0, short.1, .phases, key: key)
                } else {
                    add(name, targetsText(a, long: true), targetsText(b, long: true), .phases, key: key)
                }
            }
            // The active phase's baseline is the flat targets (shown under Targets).
            if phase.id != activeID { targetsLine("\(title) · Targets", oldRevision?.baseline, newRevision?.baseline) }
            var typeIDs = after.dayTypes.map(\.id).filter { newRevision?.byType[$0] != nil || oldRevision?.byType[$0] != nil }
            typeIDs += (newRevision?.byType.keys.sorted() ?? []).filter { !typeIDs.contains($0) }
            for type in typeIDs {
                let name = after.dayType(id: type)?.name ?? before.dayType(id: type)?.name ?? type
                targetsLine("\(title) · \(name) days", oldRevision?.byType[type], newRevision?.byType[type], key: "\(phase.id).\(type)")
            }
        }
        for phase in before.phases where after.phase(id: phase.id) == nil {
            add("Phase \(phase.id) · Name", phase.name, "removed", .phases, key: phase.id)
        }

        // Daily checks.
        for check in after.checks {
            add(check.name, before.check(id: check.id).map { describe($0, plan: before, meals: old.meals) } ?? "–",
                describe(check, plan: after, meals: new.meals), .checks, key: check.id)
        }
        for check in before.checks where after.check(id: check.id) == nil {
            add(check.name, describe(check, plan: before, meals: old.meals), "removed", .checks, key: check.id)
        }

        // Measuring and check-in.
        let a = before.routine, b = after.routine
        func sites(_ list: [BodySite]) -> String { list.isEmpty ? "none" : list.map(\.title).joined(separator: ", ") }
        func weeks(_ count: Int) -> String { count == 1 ? "every week" : "every \(count) weeks" }
        add("Weigh-in", ClockTime.text(a.weighInMinutes), ClockTime.text(b.weighInMinutes), .measuring)
        add("Morning weigh-ins until", ClockTime.text(a.morningCutoffMinutes), ClockTime.text(b.morningCutoffMinutes), .measuring)
        add("Weekly sites", sites(a.weeklySites), sites(b.weeklySites), .measuring)
        add("Full set sites", sites(a.fullSites), sites(b.fullSites), .measuring)
        add("Full set", weeks(a.fullEveryWeeks), weeks(b.fullEveryWeeks), .measuring)
        add("Body-fat check", weeks(a.bodyFatEveryWeeks), weeks(b.bodyFatEveryWeeks), .measuring)
        add("Body-fat method", a.bodyFatMethod?.title ?? "Automatic", b.bodyFatMethod?.title ?? "Automatic", .measuring)
        add("Side", a.side.rawValue.capitalized, b.side.rawValue.capitalized, .measuring)
        add("Thigh mark", a.thighMark.isEmpty ? "halfway" : a.thighMark, b.thighMark.isEmpty ? "halfway" : b.thighMark, .measuring)
        add("Two readings per site", a.twoReadings ? "on" : "off", b.twoReadings ? "on" : "off", .measuring)
        func weekday(_ day: Int) -> String { Weekdays.shortNames[max(1, min(7, day)) - 1] }
        add("Check-in day", weekday(a.checkInWeekday), weekday(b.checkInWeekday), .checkIn)
        func window(_ adjust: CoachPlan.Adjust) -> String {
            rangeText(Double(adjust.windowMinDays) / 7, Double(adjust.windowMaxDays) / 7, unit: " weeks of data")
        }
        add("Adjust after", window(before.adjust), window(after.adjust), .checkIn)
        add("Calorie step", rangeText(before.adjust.stepMin, before.adjust.stepMax, unit: " kcal"), rangeText(after.adjust.stepMin, after.adjust.stepMax, unit: " kcal"), .checkIn)
        add("No new change for", "\(before.adjust.lockDays) days", "\(after.adjust.lockDays) days", .checkIn)

        // Long-term goal.
        let x = before.longTerm, y = after.longTerm
        add("Long-term weight", x.weightKg > 0 ? kg(x.weightKg) : "–", y.weightKg > 0 ? kg(y.weightKg) : "–", .longTerm)
        add("Long-term body fat", x.bodyFat > 0 ? NumberText.plain(x.bodyFat, decimals: 1) + " %" : "–", y.bodyFat > 0 ? NumberText.plain(y.bodyFat, decimals: 1) + " %" : "–", .longTerm)
        add("Long-term waist", x.waistCm > 0 ? NumberText.plain(x.waistCm, decimals: 1) + " cm" : "–", y.waistCm > 0 ? NumberText.plain(y.waistCm, decimals: 1) + " cm" : "–", .longTerm)
        add("Goal date", x.date?.rawValue ?? "–", y.date?.rawValue ?? "–", .longTerm)
        add("Long-term note", x.note.isEmpty ? "–" : x.note, y.note.isEmpty ? "–" : y.note, .longTerm)

        // Notes.
        if before.notes != after.notes {
            for (index, note) in after.notes.enumerated() where !before.notes.contains(note) {
                add("Note \(index + 1)", "–", note, .notes)
            }
            for (index, note) in before.notes.enumerated() where !after.notes.contains(note) {
                add("Removed note \(index + 1)", note, "removed", .notes)
            }
        }

        return result
    }
}

// MARK: - Writing the plan

extension SettingsCSV {
    static func rangeValue(_ low: Double, _ high: Double) -> String {
        low == high ? NumberText.plain(low) : "\(NumberText.plain(low))-\(NumberText.plain(high))"
    }

    static func dateValue(_ day: DayKey, approx: Bool) -> String { (approx ? "~" : "") + day.rawValue }

    static func flag(_ value: Bool) -> String { value ? "yes" : "no" }

    /// The plan rows of the export, in the dotted format the import reads.
    static func planRows(_ state: SettingsState, today: DayKey) -> [[String]] {
        guard let plan = state.plan, !plan.isEmpty else { return [] }
        var rows: [[String]] = []
        func add(_ key: String, _ value: String) { if !value.isEmpty { rows.append([key, value]) } }
        func mealName(_ id: String) -> String { state.meals.first { $0.id == id }?.name ?? id }

        if plan.protein.mealMin > 0 { add("meal_protein_g", rangeValue(plan.protein.mealMin, max(plan.protein.mealMin, plan.protein.mealMax))) }
        let names = plan.protein.meals.map(mealName)
        if plan.protein.count > 0 || !names.isEmpty {
            add("protein_meals", ((plan.protein.count > 0 ? [String(plan.protein.count)] : []) + names).joined(separator: ";"))
        }

        let longTerm = plan.longTerm
        if longTerm.weightKg > 0 { add("long_term.weight_kg", NumberText.plain(longTerm.weightKg)) }
        if longTerm.bodyFat > 0 { add("long_term.body_fat_percent", NumberText.plain(longTerm.bodyFat)) }
        if longTerm.waistCm > 0 { add("long_term.waist_cm", NumberText.plain(longTerm.waistCm)) }
        if let date = longTerm.date { add("long_term.date", date.rawValue) }
        add("long_term.note", longTerm.note)

        for type in plan.dayTypes {
            let prefix = "day_type.\(type.id)."
            add(prefix + "name", type.name)
            add(prefix + "emoji", type.emoji)
            switch type.schedule {
            case .fixed: add(prefix + "days", type.weekdays.days.sorted().map { Weekdays.shortNames[$0 - 1].lowercased() }.joined(separator: ";"))
            case .flexible: add(prefix + "days", "flexible")
            case .default: add(prefix + "days", "default")
            }
            if type.schedule == .flexible, type.perWeek > 0 { add(prefix + "per_week", String(type.perWeek)) }
            add(prefix + "workouts", type.workouts.joined(separator: ";"))
        }

        let activeID = plan.activePhase(on: today)?.id
        for phase in plan.phases {
            let prefix = "phase.\(phase.id)."
            add(prefix + "name", phase.name)
            add(prefix + "goal", phase.goal.rawValue)
            if let start = phase.start { add(prefix + "start", dateValue(start, approx: phase.startApprox)) }
            if let end = phase.end { add(prefix + "end", dateValue(end, approx: phase.endApprox)) }
            if phase.rateRange.upperBound > 0 {
                add(prefix + "rate_kg_per_week", rangeValue(phase.rateRange.lowerBound, phase.rateRange.upperBound))
            } else if phase.goal == .maintain || phase.id == activeID {
                // Written as 0, so the flat rate never fills it in on the way back.
                add(prefix + "rate_kg_per_week", "0")
            }
            let review = [phase.reviewMin, phase.reviewMax].filter { $0 > 0 }
            if let low = review.min(), let high = review.max() { add(prefix + "review_weight_kg", rangeValue(low, high)) }
            if phase.targetWeight > 0 { add(prefix + "target_weight_kg", NumberText.plain(phase.targetWeight)) }
            if phase.targetBodyFat > 0 { add(prefix + "target_body_fat_percent", NumberText.plain(phase.targetBodyFat)) }
            if phase.maxWaistGainCm != CoachPlan.Phase.defaultMaxWaistGain(for: phase.goal) {
                add(prefix + "max_waist_gain_cm", NumberText.plain(phase.maxWaistGainCm))
            }
            if let revision = currentRevision(of: phase, today: today) {
                // The active phase's baseline is the flat calories, protein_g … rows.
                if let baseline = revision.baseline, phase.id != activeID {
                    add(prefix + "calories", NumberText.plain(baseline.energy, decimals: 0))
                    add(prefix + "macros_g", "\(NumberText.plain(baseline.protein, decimals: 0))/\(NumberText.plain(baseline.carbs, decimals: 0))/\(NumberText.plain(baseline.fat, decimals: 0))")
                    add(prefix + "fiber_g", NumberText.plain(baseline.fiber, decimals: 0))
                    add(prefix + "water_ml", NumberText.plain(baseline.water, decimals: 0))
                }
                let base = revision.baseline
                for type in plan.dayTypes {
                    guard let targets = revision.byType[type.id] else { continue }
                    let typePrefix = prefix + type.id + "."
                    add(typePrefix + "calories", NumberText.plain(targets.energy, decimals: 0))
                    add(typePrefix + "macros_g", "\(NumberText.plain(targets.protein, decimals: 0))/\(NumberText.plain(targets.carbs, decimals: 0))/\(NumberText.plain(targets.fat, decimals: 0))")
                    if base == nil || targets.fiber != base?.fiber { add(typePrefix + "fiber_g", NumberText.plain(targets.fiber, decimals: 0)) }
                    if base == nil || targets.water != base?.water { add(typePrefix + "water_ml", NumberText.plain(targets.water, decimals: 0)) }
                }
            }
            add(prefix + "note", phase.note)
        }

        for check in plan.checks {
            let prefix = "check.\(check.id)."
            add(prefix + "name", check.name)
            add(prefix + "emoji", check.emoji)
            add(prefix + "dose", check.dose)
            switch check.timing {
            case .anytime: add(prefix + "when", "anytime")
            case .meal(let id): add(prefix + "when", mealName(id))
            case .time(let minutes): add(prefix + "when", ClockTime.text(minutes))
            }
            switch check.days {
            case .daily: add(prefix + "days", "daily")
            case .weekdays(let days): add(prefix + "days", days.days.sorted().map { Weekdays.shortNames[$0 - 1].lowercased() }.joined(separator: ";"))
            case .dayTypes(let ids): add(prefix + "days", ids.joined(separator: ";"))
            }
            add(prefix + "optional", flag(check.isOptional))
            add(prefix + "remind", flag(check.remind))
            add(prefix + "affects_weight", flag(check.affectsWeight))
        }

        let routine = plan.routine
        add("measure.weigh_in", "daily " + ClockTime.text(routine.weighInMinutes))
        add("measure.morning_until", ClockTime.text(routine.morningCutoffMinutes))
        add("measure.weekly", routine.weeklySites.isEmpty ? "none" : routine.weeklySites.map(\.rawValue).joined(separator: ";"))
        add("measure.full", routine.fullSites.map(\.rawValue).joined(separator: ";"))
        add("measure.full_every_weeks", String(routine.fullEveryWeeks))
        add("measure.body_fat_every_weeks", String(routine.bodyFatEveryWeeks))
        add("measure.body_fat_method", routine.bodyFatMethod?.rawValue ?? "auto")
        add("measure.side", routine.side.rawValue)
        add("measure.thigh_mark", routine.thighMark)
        add("measure.two_readings", flag(routine.twoReadings))

        add("checkin.day", Weekdays.shortNames[max(1, min(7, routine.checkInWeekday)) - 1].lowercased())
        add("checkin.adjust_after_weeks", rangeValue(Double(plan.adjust.windowMinDays) / 7, Double(plan.adjust.windowMaxDays) / 7))
        add("checkin.step_kcal", rangeValue(plan.adjust.stepMin, plan.adjust.stepMax))
        add("checkin.lock_days", String(plan.adjust.lockDays))

        for note in plan.notes { add("note", note) }
        return rows
    }
}

// MARK: - The prompt

extension SettingsCSV {
    /// The coach-plan keys, in the order of the prompt (N = phase number, ID = an id like gym).
    public static let planKeys: [Key] = [
        Key(name: "long_term.weight_kg", meaning: "Long-term goal weight in kg (separate from the current phase's target_weight_kg)", example: "78", aliases: []),
        Key(name: "long_term.body_fat_percent", meaning: "Long-term body-fat goal in %", example: "14", aliases: []),
        Key(name: "long_term.waist_cm", meaning: "Long-term waist goal in cm", example: "", aliases: []),
        Key(name: "long_term.date", meaning: "By when (YYYY-MM-DD or YYYY-MM), only if I said so", example: "", aliases: []),
        Key(name: "long_term.note", meaning: "The long-term goal in my words", example: "Leaner and stronger", aliases: []),
        Key(name: "day_type.ID.name", meaning: "A kind of day with its own calories (calorie cycling). ID: lowercase letters and digits like gym, tennis, rest; at most 4 day types", example: "Gym", aliases: []),
        Key(name: "day_type.ID.emoji", meaning: "One emoji (optional; gym, tennis and rest get one by themselves)", example: "🏋️", aliases: []),
        Key(name: "day_type.ID.days", meaning: "Fixed weekdays (mon;wed;fri), flexible (picked by hand on the day) or default (all other days – exactly one day type)", example: "mon;wed;fri", aliases: []),
        Key(name: "day_type.ID.per_week", meaning: "Flexible day types: how many per week (a hint)", example: "2", aliases: []),
        Key(name: "day_type.ID.workouts", meaning: "Apple Health workouts that suggest this day: strength, tennis, running, cycling …, separated by ;", example: "strength", aliases: []),
        Key(name: "phase.N.name", meaning: "A dated phase of my plan. N = 1, 2, 3 … in date order", example: "Lean gain", aliases: []),
        Key(name: "phase.N.goal", meaning: "gain, maintain or lose", example: "gain", aliases: []),
        Key(name: "phase.N.start", meaning: "Start date YYYY-MM-DD or YYYY-MM; ~ in front = approximate. A start today or earlier means the phase is running", example: "2030-01-07", aliases: []),
        Key(name: "phase.N.end", meaning: "End date, same format", example: "~2030-05-31", aliases: []),
        Key(name: "phase.N.rate_kg_per_week", meaning: "kg per week, 0.05–1; a range like 0.1-0.2 is fine", example: "0.1-0.2", aliases: []),
        Key(name: "phase.N.rate_percent_per_week", meaning: "Or the rate in % of body weight per week (0.05–1.5)", example: "", aliases: []),
        Key(name: "phase.N.review_weight_kg", meaning: "Weight (range) at which to review the phase", example: "82-83", aliases: []),
        Key(name: "phase.N.target_weight_kg", meaning: "Target weight of the phase in kg", example: "83", aliases: []),
        Key(name: "phase.N.target_body_fat_percent", meaning: "Target body fat of the phase in %", example: "", aliases: []),
        Key(name: "phase.N.max_waist_gain_cm", meaning: "Review the phase when the waist grew this much (gain phases: 4 by default)", example: "", aliases: []),
        Key(name: "phase.N.calories", meaning: "A later phase's daily calories (also phase.N.protein_g, carbs_g, fat_g, fiber_g, water_ml, or macros_g). Leave it out for the current phase: the flat calories, protein_g … rows are its numbers", example: "", aliases: []),
        Key(name: "phase.N.macros_g", meaning: "Protein/carbs/fat in grams in one cell", example: "160/278/72", aliases: []),
        Key(name: "phase.N.ID.calories", meaning: "Calories on that day type in this phase (also phase.N.ID.protein_g, carbs_g, fat_g, fiber_g, water_ml)", example: "2600", aliases: []),
        Key(name: "phase.N.ID.macros_g", meaning: "Protein/carbs/fat in grams on that day type", example: "160/328/72", aliases: []),
        Key(name: "phase.N.note", meaning: "A note about the phase", example: "", aliases: []),
        Key(name: "check.ID.name", meaning: "A daily check my plan names (a supplement). ID like creatine", example: "Creatine monohydrate", aliases: []),
        Key(name: "check.ID.emoji", meaning: "One emoji (optional)", example: "", aliases: []),
        Key(name: "check.ID.dose", meaning: "The dose as written in my plan", example: "3-5 g", aliases: []),
        Key(name: "check.ID.when", meaning: "A meal (breakfast, lunch, snack, dinner or my own), a time (08:00) or anytime", example: "breakfast", aliases: []),
        Key(name: "check.ID.days", meaning: "daily, weekdays (mon;wed;fri) or day-type ids (gym;tennis)", example: "daily", aliases: []),
        Key(name: "check.ID.optional", meaning: "yes when a day without it is fine", example: "yes", aliases: []),
        Key(name: "check.ID.remind", meaning: "yes for a reminder", example: "", aliases: []),
        Key(name: "check.ID.affects_weight", meaning: "yes when it can move the scale (creatine – set by itself for creatine)", example: "", aliases: []),
        Key(name: "measure.weigh_in", meaning: "When I weigh myself", example: "daily 07:00", aliases: []),
        Key(name: "measure.morning_until", meaning: "Weigh-ins before this time count as morning weights", example: "11:00", aliases: []),
        Key(name: "measure.weekly", meaning: "Tape sites every week, separated by ; (waist, waist_narrow, hip, chest, arm, thigh, neck, calf)", example: "waist", aliases: []),
        Key(name: "measure.full", meaning: "Tape sites of the full set", example: "waist;chest;arm;thigh;hip", aliases: []),
        Key(name: "measure.full_every_weeks", meaning: "Full set every n weeks", example: "8", aliases: []),
        Key(name: "measure.body_fat_every_weeks", meaning: "Body-fat check every n weeks", example: "8", aliases: []),
        Key(name: "measure.body_fat_method", meaning: "The body-fat method I'll repeat: \(methodNames)", example: "", aliases: []),
        Key(name: "measure.side", meaning: "right, left or both (arm, thigh, calf)", example: "", aliases: []),
        Key(name: "measure.thigh_mark", meaning: "Where the thigh is measured, e.g. 20 cm above the kneecap", example: "", aliases: []),
        Key(name: "measure.two_readings", meaning: "yes: two readings per site in a full set", example: "", aliases: []),
        Key(name: "checkin.day", meaning: "Weekday of the weekly check-in", example: "mon", aliases: []),
        Key(name: "checkin.adjust_after_weeks", meaning: "Weeks of weigh-ins before calories are adjusted", example: "2-3", aliases: []),
        Key(name: "checkin.step_kcal", meaning: "Size of one calorie adjustment in kcal", example: "100-150", aliases: []),
        Key(name: "checkin.lock_days", meaning: "Days without a new adjustment after a change", example: "14", aliases: []),
    ]

    static let planRules: [String] = [
        "Same block, same two columns. Use these rows only when my notes describe a plan: dated phases, calorie cycling, body measurements, weekly check-ins or supplements.",
        "- Dated phases (muscle building, fat loss, maintenance with dates) → phase.N.* rows, N = 1, 2, 3 … in date order. Dates YYYY-MM-DD or YYYY-MM; put ~ in front of an approximate date.",
        "- Calorie cycling (different calories on different kinds of days) → one day_type.ID.* group per kind of day plus phase.N.ID.* targets in each phase that has numbers. IDs are lowercase letters and digits (gym, tennis, rest); at most 4 day types, exactly one with days default.",
        "- The flat goal, rate_kg_per_week, target_weight_kg, calories, protein_g, carbs_g, fat_g, fiber_g and water_ml rows are the current phase's. Without day_type rows, training_days still works.",
        "- Body fat and tape measurements I have now → body_fat_percent, body_fat_method and the *_cm rows (saved as today's values).",
        "- Supplements my plan names → check.ID.* (only what my plan says; never add one).",
        "- Advice that isn't a setting (training, recovery, timing tips) → one note row each. not_supported is only for real wishes: something I want the app to do that no row covers.",
        "- Ranges are written 0.1-0.2, 82-83, 35-45; macros_g is protein/carbs/fat in grams like 160/328/72.",
        "- A group you write replaces that whole group: if you change a day type, a phase or a check, write all day_type.*, phase.N.* and check.* rows again (copy the unchanged ones from my current settings). Leave the groups out when nothing in them changes.",
    ]

    /// A made-up example of a coach plan (no real person's numbers).
    static let planExample: [String] = [
        "setting,value",
        "weight_kg,80",
        "goal,gain",
        "rate_kg_per_week,0.1-0.2",
        "target_weight_kg,83",
        "calories,2600",
        "protein_g,160",
        "carbs_g,328",
        "fat_g,72",
        "fiber_g,30",
        "water_ml,2500",
        "body_fat_percent,20",
        "body_fat_method,estimate",
        "waist_cm,88",
        "meal_protein_g,35-45",
        "protein_meals,4",
        "long_term.weight_kg,78",
        "long_term.body_fat_percent,14",
        "long_term.note,Leaner and stronger",
        "day_type.gym.name,Gym",
        "day_type.gym.days,mon;wed;fri",
        "day_type.gym.workouts,strength",
        "day_type.tennis.name,Tennis",
        "day_type.tennis.days,flexible",
        "day_type.tennis.per_week,2",
        "day_type.tennis.workouts,tennis",
        "day_type.rest.name,Rest",
        "day_type.rest.days,default",
        "phase.1.name,Lean gain",
        "phase.1.goal,gain",
        "phase.1.start,2030-01-07",
        "phase.1.end,~2030-05-31",
        "phase.1.rate_kg_per_week,0.1-0.2",
        "phase.1.review_weight_kg,82-83",
        "phase.1.target_weight_kg,83",
        "phase.1.gym.calories,2600",
        "phase.1.gym.macros_g,160/328/72",
        "phase.1.tennis.calories,2800",
        "phase.1.tennis.macros_g,160/378/72",
        "phase.1.rest.calories,2400",
        "phase.1.rest.macros_g,160/278/72",
        "phase.2.name,Fat loss",
        "phase.2.goal,lose",
        "phase.2.start,~2030-06",
        "phase.2.end,~2030-08",
        "phase.2.target_weight_kg,78",
        "phase.2.target_body_fat_percent,14",
        "check.creatine.name,Creatine monohydrate",
        "check.creatine.dose,3-5 g",
        "check.creatine.when,breakfast",
        "check.creatine.optional,yes",
        "measure.weigh_in,daily 07:00",
        "measure.weekly,waist",
        "measure.full,waist;chest;arm;thigh;hip",
        "measure.full_every_weeks,8",
        "measure.body_fat_every_weeks,8",
        "checkin.day,mon",
        "checkin.adjust_after_weeks,2-3",
        "checkin.step_kcal,100-150",
        "note,An extra gym session counts as a gym day: pick Gym on that day.",
        "note,The fat-loss start depends on progress.",
    ]

    /// The "Coach plan" part of the prompts: rules, key table and the made-up example.
    static func planSection(heading: String) -> [String] {
        var lines = [heading]
        lines.append(contentsOf: planRules)
        lines.append("")
        lines.append("| setting | value |")
        lines.append("|---|---|")
        for key in planKeys {
            lines.append("| \(key.name) | \(key.meaning)\(key.example.isEmpty ? "" : " – e.g. \(key.example)") |")
        }
        lines.append("")
        lines.append("Example with a coach plan (made-up numbers):")
        lines.append("```csv")
        lines.append(contentsOf: planExample)
        lines.append("```")
        return lines
    }
}
