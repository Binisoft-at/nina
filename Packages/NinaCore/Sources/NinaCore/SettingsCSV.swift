import Foundation
import BinisoftKitCore

/// Everything the goals & settings import can change, in one value: the body data behind the goal
/// calculator, the daily targets and the preferences. The app converts its profile to this and back.
public struct SettingsState: Equatable, Sendable {
    public var sex: Sex
    /// 0 = unknown.
    public var birthYear: Int
    /// 0 = unknown.
    public var heightCm: Double
    /// The latest weight, 0 = unknown.
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: WeightGoal
    public var ratePerWeek: Double
    /// 0 = none.
    public var targetWeight: Double
    public var macroSplit: MacroSplit
    public var targets: DailyTargets
    public var trainingTargets: DailyTargets?
    public var trainingDays: Weekdays
    public var meals: [MealSlot]
    public var language: FoodLanguage
    public var energyUnit: EnergyUnit
    public var dayStartHour: Int
    public var waterGlass: Double
    public var activityBonusShare: Double
    public var focus: [Nutrient]
    /// The coach plan (nil or empty = no plan). With an active phase, goal, rate, target weight,
    /// targets and training days above mirror it (`CoachPlan.mirror(on:)`).
    public var plan: CoachPlan?

    public init(sex: Sex = .unspecified, birthYear: Int = 0, heightCm: Double = 0, weightKg: Double = 0,
                activity: ActivityLevel = .light, goal: WeightGoal = .maintain, ratePerWeek: Double = 0.5,
                targetWeight: Double = 0, macroSplit: MacroSplit = .balanced, targets: DailyTargets = .standard,
                trainingTargets: DailyTargets? = nil, trainingDays: Weekdays = Weekdays([]),
                meals: [MealSlot] = MealSlot.defaults, language: FoodLanguage = .english, energyUnit: EnergyUnit = .kcal,
                dayStartHour: Int = 0, waterGlass: Double = 250, activityBonusShare: Double = 0,
                focus: [Nutrient] = [.protein, .carbs, .fat], plan: CoachPlan? = nil) {
        self.sex = sex
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.ratePerWeek = ratePerWeek
        self.targetWeight = targetWeight
        self.macroSplit = macroSplit
        self.targets = targets
        self.trainingTargets = trainingTargets
        self.trainingDays = trainingDays
        self.meals = meals
        self.language = language
        self.energyUnit = energyUnit
        self.dayStartHour = dayStartHour
        self.waterGlass = waterGlass
        self.activityBonusShare = activityBonusShare
        self.focus = focus
        self.plan = plan
    }

    /// Extra calories on training days (0 when training targets are off).
    public var trainingExtra: Double {
        guard let trainingTargets else { return 0 }
        return max(0, trainingTargets.energy - targets.energy)
    }

    /// Training-day targets: the extra calories come 70 % from carbs and 30 % from protein.
    public static func training(_ targets: DailyTargets, extra: Double) -> DailyTargets {
        var copy = targets
        copy.energy += extra
        copy.carbs += (extra * 0.7 / 4).rounded()
        copy.protein += (extra * 0.3 / 4).rounded()
        return copy
    }
}

/// What a settings file says – only the settings it mentions are set.
public struct SettingsDraft: Equatable, Sendable {
    public var sex: Sex?
    public var birthYear: Int?
    public var age: Int?
    public var heightCm: Double?
    public var weightKg: Double?
    public var activity: ActivityLevel?
    public var goal: WeightGoal?
    /// The midpoint of `rateRange` (rounded to 0.001).
    public var ratePerWeek: Double?
    /// rate_kg_per_week as written: 0.2 or a range like 0.15-0.25 (the active phase takes the range).
    public var rateRange: ClosedRange<Double>?
    public var targetWeight: Double?
    public var macroSplit: MacroSplit?
    /// Percentages written as "30/40/30" (protein/carbs/fat).
    public var macroPercent: (protein: Double, carbs: Double, fat: Double)?
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var fiber: Double?
    public var sugarMax: Double?
    public var saturatedFatMax: Double?
    public var saltMax: Double?
    public var water: Double?
    public var trainingDays: Weekdays?
    public var trainingExtra: Double?
    public var meals: [MealSlot]?
    public var language: FoodLanguage?
    public var energyUnit: EnergyUnit?
    public var dayStartHour: Int?
    public var waterGlass: Double?
    public var activityBonusShare: Double?
    public var focus: [Nutrient]?
    /// The coach-plan rows and today's body values.
    public var plan = SettingsPlanDraft()
    /// Real wishes: what I want the app to do that no setting covers (rows with setting "not_supported").
    public var wishes: [String] = []
    /// Rows that couldn't be read, with the reason.
    public var skipped: [String] = []

    public init() {}

    public var isEmpty: Bool { self == SettingsDraft(skipped: skipped, wishes: wishes) }

    init(skipped: [String], wishes: [String]) {
        self.skipped = skipped
        self.wishes = wishes
    }

    public static func == (lhs: SettingsDraft, rhs: SettingsDraft) -> Bool {
        lhs.sex == rhs.sex && lhs.birthYear == rhs.birthYear && lhs.age == rhs.age && lhs.heightCm == rhs.heightCm
            && lhs.weightKg == rhs.weightKg && lhs.activity == rhs.activity && lhs.goal == rhs.goal
            && lhs.ratePerWeek == rhs.ratePerWeek && lhs.rateRange == rhs.rateRange && lhs.targetWeight == rhs.targetWeight
            && lhs.macroSplit == rhs.macroSplit && lhs.plan == rhs.plan
            && lhs.macroPercent?.protein == rhs.macroPercent?.protein && lhs.macroPercent?.carbs == rhs.macroPercent?.carbs
            && lhs.macroPercent?.fat == rhs.macroPercent?.fat && lhs.calories == rhs.calories && lhs.protein == rhs.protein
            && lhs.carbs == rhs.carbs && lhs.fat == rhs.fat && lhs.fiber == rhs.fiber && lhs.sugarMax == rhs.sugarMax
            && lhs.saturatedFatMax == rhs.saturatedFatMax && lhs.saltMax == rhs.saltMax && lhs.water == rhs.water
            && lhs.trainingDays == rhs.trainingDays && lhs.trainingExtra == rhs.trainingExtra && lhs.meals == rhs.meals
            && lhs.language == rhs.language && lhs.energyUnit == rhs.energyUnit && lhs.dayStartHour == rhs.dayStartHour
            && lhs.waterGlass == rhs.waterGlass && lhs.activityBonusShare == rhs.activityBonusShare && lhs.focus == rhs.focus
            && lhs.wishes == rhs.wishes && lhs.skipped == rhs.skipped
    }
}

/// One line of the preview: "Calories 2200 → 1900 kcal", in a group ("Targets").
public struct SettingsChange: Equatable, Sendable, Identifiable {
    /// Unique within a preview: the group, the key (the item's id for day types, phases and
    /// checks, so two items with the same name stay apart), the title and whether it's a removal.
    public var id: String { "\(group.rawValue):\(key):\(title)\(isRemoval ? ":removed" : "")" }
    public let title: String
    public let old: String
    public let new: String
    public let group: SettingsGroup
    /// Body lines: the value's key ("bodyFat", "waist" …) for `SettingsResult.removingBodyValues(_:)`.
    /// Day types, phases and checks: the item's id. Wishes: their position.
    public let key: String

    public init(title: String, old: String, new: String, group: SettingsGroup = .preferences, key: String = "") {
        self.title = title
        self.old = old
        self.new = new
        self.group = group
        self.key = key
    }

    /// A day type, phase, check or note the file no longer has.
    public var isRemoval: Bool { new == "removed" }
}

/// The result of applying a settings file to the current settings.
public struct SettingsResult: Equatable, Sendable {
    public var state: SettingsState
    public var changes: [SettingsChange]
    /// A weight to log today (when the file has one that differs from the latest).
    public var newWeight: Double?
    /// Settings the file gave that couldn't be used, and checks of what it says (orange in the preview).
    public var notes: [String]
    /// Today's body values from the file (baseline assessment and tape record).
    public var bodyRecords: [SettingsBodyRecord] = []
    /// Rows with setting not_supported.
    public var wishes: [String] = []

    /// The coach plan after the import (nil or empty = no plan).
    public var plan: CoachPlan? { state.plan }

    public var hasChanges: Bool { !changes.isEmpty || newWeight != nil || !bodyRecords.isEmpty }

    /// Without the body values the person unticked in the preview (the `key` of their lines).
    public func removingBodyValues(_ keys: Set<String>) -> SettingsResult {
        var copy = self
        copy.bodyRecords = bodyRecords.compactMap { record in
            var record = record
            for key in keys { record.values[key] = nil }
            if record.kind == .assessment, record.values.bodyFat == nil { return nil }
            return record.values.isEmpty ? nil : record
        }
        copy.changes.removeAll { $0.group == .body && !$0.key.isEmpty && keys.contains($0.key) }
        return copy
    }

    /// The preview lines by group (Body · Targets · Day types (3) · Phases (2) · …), wishes last.
    public var sections: [SettingsSection] {
        let plan = state.plan.flatMap { $0.isEmpty ? nil : $0 }
        var result: [SettingsSection] = []
        for group in SettingsGroup.allCases {
            let lines = group == .notSupported
                ? wishes.enumerated().map { SettingsChange(title: $0.element, old: "", new: "", group: .notSupported, key: String($0.offset)) }
                : changes.filter { $0.group == group }
            guard !lines.isEmpty else { continue }
            var title = group.title
            if let plan {
                switch group {
                case .dayTypes: title += " (\(plan.dayTypes.count))"
                case .phases: title += " (\(plan.phases.count))"
                case .checks: title += " (\(plan.checks.count))"
                default: break
                }
            }
            result.append(SettingsSection(group: group, title: title, changes: lines))
        }
        return result
    }
}

/// Nina's goals & settings file: two columns, `setting,value`, one row per setting – what another AI
/// writes from what I tell it about myself, and what Settings exports. Only the settings in the file
/// change. See docs/IMPORT.md.
public enum SettingsCSV {
    public struct Key: Sendable {
        public let name: String
        public let meaning: String
        public let example: String
        let aliases: [String]
    }

    /// Every setting, in the order of the prompt and the export.
    public static let keys: [Key] = [
        Key(name: "sex", meaning: "female, male or unspecified (only for the calorie formula)", example: "female", aliases: ["geschlecht", "gender"]),
        Key(name: "birth_year", meaning: "Year of birth, e.g. 1991 (or use age)", example: "1991", aliases: ["geburtsjahr", "year_of_birth", "born"]),
        Key(name: "age", meaning: "Age in years, if the birth year isn't known", example: "", aliases: ["alter"]),
        Key(name: "height_cm", meaning: "Height in cm", example: "171", aliases: ["height", "grosse", "korpergrosse"]),
        Key(name: "weight_kg", meaning: "Current weight in kg (logged as today's weight)", example: "67.3", aliases: ["weight", "gewicht", "current_weight"]),
        Key(name: "body_fat_percent", meaning: "Body fat in %, if I know it (saved as today's body-fat value)", example: "", aliases: ["body_fat", "korperfett", "kfa", "body_fat_pct", "bodyfat"]),
        Key(name: "body_fat_method", meaning: "How that body fat was measured: dexa, bodpod, bia_pro (InBody …), scan_3d (3D body scanner), scale, skinfold, navy (tape) or estimate (the default)", example: "", aliases: ["body_fat_source", "korperfett_methode"]),
        Key(name: "neck_cm", meaning: "Neck circumference in cm, just below the larynx (today's tape values; also chest_cm, arm_cm, waist_cm, hip_cm, thigh_cm, calf_cm)", example: "", aliases: ["neck", "hals", "halsumfang"]),
        Key(name: "chest_cm", meaning: "Chest at nipple height in cm", example: "", aliases: ["chest", "brust", "brustumfang"]),
        Key(name: "arm_cm", meaning: "Relaxed upper arm in cm", example: "", aliases: ["arm", "upper_arm_cm", "upper_arm", "oberarm", "oberarm_cm"]),
        Key(name: "waist_cm", meaning: "Waist at the navel in cm", example: "", aliases: ["waist", "bauchumfang", "taille", "bauchumfang_cm", "taille_cm"]),
        Key(name: "waist_narrow_cm", meaning: "Narrowest waist in cm (women's tape estimate)", example: "", aliases: ["narrow_waist_cm", "narrow_waist"]),
        Key(name: "hip_cm", meaning: "Hip at the widest point in cm", example: "", aliases: ["hip", "hips", "hufte", "huftumfang", "hufte_cm"]),
        Key(name: "thigh_cm", meaning: "Thigh halfway between hip crease and kneecap in cm", example: "", aliases: ["thigh", "oberschenkel", "oberschenkel_cm"]),
        Key(name: "calf_cm", meaning: "Calf at the widest point in cm", example: "", aliases: ["calf", "wade", "wade_cm", "wadenumfang"]),
        Key(name: "activity", meaning: "sedentary (desk job), light (exercise 1–3 days/week), moderate (3–5 days), active (6–7 days), very_active (physical job plus training)", example: "moderate", aliases: ["aktivitat", "activity_level"]),
        Key(name: "goal", meaning: "lose, maintain or gain (weight)", example: "lose", aliases: ["ziel", "weight_goal"]),
        Key(name: "rate_kg_per_week", meaning: "How fast to lose or gain, kg per week: 0.05–1; a range like 0.15-0.25 is fine", example: "0.5", aliases: ["rate", "pace", "tempo", "kg_per_week"]),
        Key(name: "target_weight_kg", meaning: "Target weight in kg (of the current phase, if my plan has phases)", example: "62", aliases: ["target_weight", "zielgewicht", "goal_weight"]),
        Key(name: "macro_split", meaning: "balanced, high_protein, low_carb, endurance or keto – or percent of calories as protein/carbs/fat, e.g. 30/40/30", example: "high_protein", aliases: ["macros", "makros", "split", "makroverteilung"]),
        Key(name: "calories", meaning: "Daily calories in kcal – only if I have a fixed number; otherwise leave it out and Nina calculates it from my body data", example: "", aliases: ["kcal", "calories_kcal", "kalorien", "energy", "daily_calories"]),
        Key(name: "protein_g", meaning: "Daily protein in g (only a fixed number)", example: "", aliases: ["protein", "eiweiss"]),
        Key(name: "carbs_g", meaning: "Daily carbohydrates in g (only a fixed number)", example: "", aliases: ["carbs", "kohlenhydrate", "carbohydrates"]),
        Key(name: "fat_g", meaning: "Daily fat in g (only a fixed number)", example: "", aliases: ["fat", "fett"]),
        Key(name: "fiber_g", meaning: "Daily fiber goal in g", example: "", aliases: ["fiber", "fibre", "ballaststoffe"]),
        Key(name: "sugar_max_g", meaning: "Most sugar per day in g", example: "", aliases: ["sugar", "sugar_g", "zucker", "zucker_max"]),
        Key(name: "saturated_fat_max_g", meaning: "Most saturated fat per day in g", example: "", aliases: ["saturated_fat", "gesattigte_fettsauren"]),
        Key(name: "salt_max_g", meaning: "Most salt per day in g", example: "", aliases: ["salt", "salz", "salt_g"]),
        Key(name: "water_ml", meaning: "Daily water goal in ml", example: "2500", aliases: ["water", "wasser", "water_goal"]),
        Key(name: "meal_protein_g", meaning: "Protein per protein meal in g, a range like 35-45 (or just a minimum)", example: "", aliases: ["protein_per_meal_g", "protein_per_meal", "eiweiss_pro_mahlzeit"]),
        Key(name: "protein_meals", meaning: "Protein meals per day (4) – or which meals, separated by ; (breakfast;lunch;snack;dinner)", example: "", aliases: ["protein_meals_per_day", "protein_meal_count"]),
        Key(name: "training_days", meaning: "Weekdays with more calories, e.g. mon;wed;fri – or none (with a coach plan use day_type rows instead)", example: "mon;wed;fri", aliases: ["trainingstage", "training", "workout_days"]),
        Key(name: "training_extra_kcal", meaning: "Extra kcal on training days (mostly carbs), e.g. 300", example: "300", aliases: ["training_kcal", "training_calories", "extra_kcal"]),
        Key(name: "meals", meaning: "My meals with their usual time and an emoji, separated by ;", example: "Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝", aliases: ["mahlzeiten", "meal_times"]),
        Key(name: "food_names", meaning: "english or german", example: "german", aliases: ["food_language", "language", "sprache"]),
        Key(name: "energy_unit", meaning: "kcal or kJ", example: "kcal", aliases: ["unit", "einheit"]),
        Key(name: "day_starts_at", meaning: "Hour the diary day starts, 0–6 (e.g. 3: a 2 am snack still counts for yesterday)", example: "", aliases: ["day_start", "tagesbeginn", "day_start_hour"]),
        Key(name: "water_glass_ml", meaning: "Size of one glass of water in ml", example: "300", aliases: ["glass", "glass_ml", "glas"]),
        Key(name: "add_burned_calories", meaning: "none, half or all – how much of the calories burned (Apple Health) is added to the day", example: "half", aliases: ["burned_calories", "activity_bonus"]),
        Key(name: "focus_nutrients", meaning: "Up to 4 nutrients shown first, separated by ; (protein, carbs, fat, fiber, sugar, saturated fat, salt, water …)", example: "protein;fiber;sugar", aliases: ["focus", "priorities", "prioritaten"]),
        Key(name: "note", meaning: "Advice from my plan that isn't a setting (training, recovery, timing) – one row each; Nina keeps it in my plan", example: "", aliases: ["plan_note", "notiz", "notes", "hinweis"]),
        Key(name: "not_supported", meaning: "Only a real wish: something I want the app to do that no row covers (one row each) – Nina lists it so I can ask for it", example: "", aliases: ["unsupported", "wish"]),
    ]

    static let canonical: [String: String] = {
        var map: [String: String] = [:]
        for key in keys {
            map[ImportColumns.normalize(key.name)] = key.name
            for alias in key.aliases { map[ImportColumns.normalize(alias)] = key.name }
        }
        return map
    }()

    /// A label with its unit ("Brustumfang (cm)" → brustumfang_cm, "KFA (%)" → kfa_%, "Gewicht (kg)")
    /// is the setting the bare name stands for, when that setting is in the same unit.
    static func unitKey(_ normalized: String) -> String? {
        let units: [(suffix: String, unit: String)] = [("_cm", "_cm"), ("_kg", "_kg"), ("_g", "_g"), ("_ml", "_ml"),
                                                        ("_%", "_percent"), ("_percent", "_percent"), ("_pct", "_percent"),
                                                        ("_prozent", "_percent")]
        for (suffix, unit) in units where normalized.hasSuffix(suffix) {
            if let key = canonical[String(normalized.dropLast(suffix.count))], key.hasSuffix(unit) { return key }
        }
        return nil
    }

    /// Is this the header of a settings file?
    public static func isHeader(_ cells: [String]) -> Bool {
        guard let first = cells.first else { return false }
        return ["setting", "settings", "einstellung", "option", "key_setting"].contains(ImportColumns.normalize(first))
    }

    /// Rows without a header line that are settings: at least 60 % of their first cells are
    /// settings or plan keys ("goal,lose", "phase.1.rest.calories,2300").
    public static func looksLikeSettings(_ lines: [String]) -> Bool {
        let rows = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func isKnown(_ line: String) -> Bool {
            guard line.contains(where: { $0 == "," || $0 == ";" || $0 == "\t" }) else { return false }
            let cell = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" }).first.map(String.init) ?? ""
            let key = ImportColumns.normalize(cell)
            if canonical[key] != nil || unitKey(key) != nil { return true }
            if let row = planRow(key), row != .unknown { return true }
            return false
        }
        guard let first = rows.first, isKnown(first) else { return false }
        return Double(rows.filter(isKnown).count) >= Double(rows.count) * 0.6
    }

    // MARK: Reading

    /// Reads `setting,value` rows (the header line is optional). With more columns (a comment or
    /// reason column), only the one named value is read.
    public static func parse(_ text: String) -> SettingsDraft {
        var draft = SettingsDraft()
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let delimiter: Character = firstLine.contains("\t") ? "\t" : (firstLine.contains(",") ? "," : (firstLine.contains(";") ? ";" : ","))
        var rows = CSV.parse(text, delimiter: delimiter)
        var valueColumn: Int?
        if let header = rows.first, isHeader(header) {
            rows.removeFirst()
            if header.count > 2 {
                valueColumn = header.firstIndex { ["value", "values", "wert", "werte"].contains(ImportColumns.normalize($0)) }
            }
        }
        for row in rows {
            guard let rawKey = row.first?.trimmingCharacters(in: .whitespaces), !rawKey.isEmpty else { continue }
            // A value with the delimiter in it that wasn't quoted: join the rest back together.
            let value = valueColumn.map { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : "" }
                ?? row.dropFirst().joined(separator: String(delimiter)).trimmingCharacters(in: .whitespaces)
            let normalized = ImportColumns.normalize(rawKey)
            let planKey = SettingsCSV.planRow(normalized)
            if let key = canonical[normalized] ?? (planKey == nil ? unitKey(normalized) : nil) {
                if value.isEmpty { continue }
                if let problem = read(key, value, into: &draft) {
                    draft.skipped.append("\(key): \(problem)")
                }
            } else if let planRow = planKey, planRow != .unknown {
                if value.isEmpty { continue }
                if let problem = readPlan(planRow, key: rawKey, value, into: &draft) {
                    draft.skipped.append("\(rawKey): \(problem)")
                }
            } else {
                draft.skipped.append("\(rawKey): not a setting Nina knows")
            }
        }
        // Second pass: day-type ids are checked once every row is read (day types may come last).
        validatePlan(&draft)
        return draft
    }

    /// Reads one setting; returns what's wrong with the value, or nil.
    static func read(_ key: String, _ value: String, into draft: inout SettingsDraft) -> String? {
        let word = SearchText.normalize(value).replacingOccurrences(of: " ", with: "_")
        func number(_ range: ClosedRange<Double>) -> Double? {
            // "~20" or "about 20" (an estimate) is read as 20.
            guard let number = ImportColumns.number(withoutApprox(value).text), range.contains(number) else { return nil }
            return number
        }
        let invalid = "“\(value)” isn't a valid value"
        switch key {
        case "sex":
            let map: [String: Sex] = ["female": .female, "f": .female, "woman": .female, "weiblich": .female, "w": .female, "frau": .female,
                                      "male": .male, "m": .male, "man": .male, "mannlich": .male, "mann": .male,
                                      "unspecified": .unspecified, "divers": .unspecified, "other": .unspecified, "none": .unspecified]
            guard let sex = map[word] else { return invalid }
            draft.sex = sex
        case "birth_year":
            guard let year = number(1900...2100) else { return invalid }
            draft.birthYear = Int(year)
        case "age":
            guard let age = number(10...110) else { return invalid }
            draft.age = Int(age)
        case "height_cm":
            guard var height = number(0.5...250) else { return invalid }
            if height < 3 { height *= 100 } // 1.71 (m)
            guard height >= 100 else { return invalid }
            draft.heightCm = height
        case "weight_kg":
            guard let weight = number(25...300) else { return invalid }
            draft.weightKg = weight
        case "activity":
            let map: [String: ActivityLevel] = ["sedentary": .sedentary, "sitting": .sedentary, "sitzend": .sedentary, "low": .sedentary,
                                                "light": .light, "lightly_active": .light, "leicht": .light,
                                                "moderate": .moderate, "moderately_active": .moderate, "mittel": .moderate, "medium": .moderate,
                                                "active": .active, "very_active": .veryActive, "veryactive": .veryActive, "aktiv": .active,
                                                "extremely_active": .veryActive, "sehr_aktiv": .veryActive, "high": .active]
            guard let activity = map[word] ?? ActivityLevel(rawValue: value) else { return invalid }
            draft.activity = activity
        case "goal":
            let map: [String: WeightGoal] = ["lose": .lose, "lose_weight": .lose, "abnehmen": .lose, "cut": .lose, "loss": .lose,
                                             "maintain": .maintain, "keep": .maintain, "halten": .maintain, "keep_weight": .maintain,
                                             "gain": .gain, "gain_weight": .gain, "zunehmen": .gain, "bulk": .gain, "muscle": .gain]
            guard let goal = map[word] else { return invalid }
            draft.goal = goal
        case "rate_kg_per_week":
            guard let range = planRange(value, 0.05...1.0) else { return invalid + " (0.05–1 kg per week; a range like 0.15-0.25 is fine)" }
            draft.rateRange = range
            draft.ratePerWeek = ((range.lowerBound + range.upperBound) / 2 * 1000).rounded() / 1000
        case "target_weight_kg":
            guard let weight = number(25...300) else { return invalid }
            draft.targetWeight = weight
        case "macro_split":
            if let preset = MacroSplit.presets.first(where: { SearchText.normalize($0.id) == SearchText.normalize(word.replacingOccurrences(of: "_", with: ""))
                || SearchText.normalize($0.name).replacingOccurrences(of: " ", with: "_") == word }) {
                draft.macroSplit = preset
            } else {
                let parts = value.split(whereSeparator: { "/|:-".contains($0) }).compactMap { ImportColumns.number(String($0)) }
                guard parts.count == 3, abs(parts.reduce(0, +) - 100) <= 2 else { return invalid + " (use a name or protein/carbs/fat percent like 30/40/30)" }
                draft.macroPercent = (parts[0] / 100, parts[1] / 100, parts[2] / 100)
            }
        case "calories":
            guard var energy = number(800...6000) else {
                if let kj = ImportColumns.number(value), value.lowercased().contains("kj"), (3300...25000).contains(kj) {
                    draft.calories = (kj / EnergyUnit.kilojoulesPerKilocalorie).rounded()
                    return nil
                }
                return invalid
            }
            energy.round()
            draft.calories = energy
        case "protein_g":
            guard let grams = number(10...400) else { return invalid }
            draft.protein = grams
        case "carbs_g":
            guard let grams = number(0...900) else { return invalid }
            draft.carbs = grams
        case "fat_g":
            guard let grams = number(10...400) else { return invalid }
            draft.fat = grams
        case "fiber_g":
            guard let grams = number(5...100) else { return invalid }
            draft.fiber = grams
        case "sugar_max_g":
            guard let grams = number(0...300) else { return invalid }
            draft.sugarMax = grams
        case "saturated_fat_max_g":
            guard let grams = number(0...150) else { return invalid }
            draft.saturatedFatMax = grams
        case "salt_max_g":
            guard let grams = number(0.5...20) else { return invalid }
            draft.saltMax = grams
        case "water_ml":
            guard var ml = number(0.5...8000) else { return invalid }
            if ml < 10 { ml *= 1000 } // 2.5 (litres)
            guard ml >= 500 else { return invalid }
            draft.water = ml
        case "training_days":
            if ["none", "no", "keine", "nein", "0", "off"].contains(word) {
                draft.trainingDays = Weekdays([])
            } else {
                guard let days = weekdays(value) else { return invalid + " (use mon;wed;fri)" }
                draft.trainingDays = days
            }
        case "training_extra_kcal":
            guard let extra = number(0...2000) else { return invalid }
            draft.trainingExtra = extra
        case "meals":
            let meals = parseMeals(value)
            guard !meals.isEmpty else { return invalid + " (use Breakfast 07:30;Lunch 12:30)" }
            draft.meals = meals
        case "food_names":
            let map: [String: FoodLanguage] = ["english": .english, "en": .english, "englisch": .english,
                                               "german": .german, "de": .german, "deutsch": .german]
            guard let language = map[word] else { return invalid }
            draft.language = language
        case "energy_unit":
            let map: [String: EnergyUnit] = ["kcal": .kcal, "calories": .kcal, "kalorien": .kcal, "kj": .kJ, "kilojoule": .kJ, "kilojoules": .kJ]
            guard let unit = map[word] else { return invalid }
            draft.energyUnit = unit
        case "day_starts_at":
            let digits = value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            if ["midnight", "mitternacht"].contains(word) {
                draft.dayStartHour = 0
            } else {
                guard let hour = digits, (0...6).contains(hour) else { return invalid + " (an hour from 0 to 6)" }
                draft.dayStartHour = hour
            }
        case "water_glass_ml":
            guard let ml = number(50...1500) else { return invalid }
            draft.waterGlass = ml
        case "add_burned_calories":
            let map: [String: Double] = ["none": 0, "no": 0, "nein": 0, "keine": 0, "off": 0, "0": 0, "half": 0.5, "halb": 0.5, "50": 0.5,
                                         "all": 1, "full": 1, "alle": 1, "ja": 1, "yes": 1, "100": 1]
            if let share = map[word.replacingOccurrences(of: "%", with: "")] {
                draft.activityBonusShare = share
            } else if let percent = ImportColumns.number(value) {
                draft.activityBonusShare = percent >= 75 ? 1 : (percent >= 25 ? 0.5 : 0)
            } else {
                return invalid
            }
        case "focus_nutrients":
            var focus: [Nutrient] = []
            for part in ImportColumns.list(value) {
                guard let nutrient = nutrient(named: part) else { return "“\(part)” isn't a nutrient Nina knows" }
                if !focus.contains(nutrient), nutrient != .energy { focus.append(nutrient) }
            }
            guard !focus.isEmpty else { return invalid }
            draft.focus = Array(focus.prefix(4))
        case "body_fat_percent":
            guard let fat = number(3...60) else { return invalid + " (3–60 %)" }
            draft.plan.bodyFat = fat
        case "body_fat_method":
            guard let method = bodyMethod(named: value) else { return invalid + " (\(methodNames))" }
            draft.plan.bodyFatMethod = method
        case "neck_cm", "chest_cm", "arm_cm", "waist_cm", "waist_narrow_cm", "hip_cm", "thigh_cm", "calf_cm":
            guard let site = bodySite(named: key), let cm = number(0...1000), site.isPlausible(cm) else { return invalid }
            draft.plan.tape[site] = cm
        case "meal_protein_g":
            guard let range = planRange(value, 5...150) else { return invalid + " (grams like 35-45)" }
            draft.plan.mealProtein = range
        case "protein_meals":
            var count = 0
            var names: [String] = []
            for item in ImportColumns.list(value) {
                if item.first?.isNumber == true, let number = numbers(in: item).first {
                    guard (1...10).contains(number) else { return invalid + " (1–10 meals)" }
                    count = Int(number)
                } else {
                    names.append(item)
                }
            }
            guard count > 0 || !names.isEmpty else { return invalid }
            draft.plan.proteinMeals = SettingsPlanDraft.ProteinMealCount(count: count, names: names)
        case "note":
            draft.plan.notes = (draft.plan.notes ?? []) + [value]
        case "not_supported":
            draft.wishes.append(value)
        default:
            return "not a setting Nina knows"
        }
        return nil
    }

    /// "mon;wed;fri", "Mo, Mi, Fr", "Mon–Fri", "weekdays", "every day".
    static func weekdays(_ text: String) -> Weekdays? {
        let key = SearchText.normalize(text)
        if ["every day", "daily", "taglich", "jeden tag", "all"].contains(key) { return .everyDay }
        if ["weekdays", "workdays", "werktags", "mon fri", "mo fr", "monday friday"].contains(key) { return .workdays }
        if ["weekend", "wochenende", "sat sun", "sa so"].contains(key) { return .weekend }
        let names: [String: Int] = [
            "mon": 1, "monday": 1, "mo": 1, "montag": 1, "tue": 2, "tues": 2, "tuesday": 2, "di": 2, "dienstag": 2,
            "wed": 3, "wednesday": 3, "mi": 3, "mittwoch": 3, "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "do": 4, "donnerstag": 4,
            "fri": 5, "friday": 5, "fr": 5, "freitag": 5, "sat": 6, "saturday": 6, "sa": 6, "samstag": 6,
            "sun": 7, "sunday": 7, "so": 7, "sonntag": 7,
        ]
        var days = Set<Int>()
        for part in key.split(separator: " ") {
            if let day = names[String(part)] {
                days.insert(day)
            } else if let number = Int(part), (1...7).contains(number) {
                days.insert(number)
            } else {
                return nil
            }
        }
        return days.isEmpty ? nil : Weekdays(days)
    }

    /// "Breakfast 07:30 🥐;Lunch 12:30 🥗" → meal slots; the standard meals keep their ids
    /// ("Frühstück" is breakfast), others get an id from their name.
    static func parseMeals(_ text: String) -> [MealSlot] {
        var slots: [MealSlot] = []
        for part in text.split(whereSeparator: { $0 == ";" || $0 == "|" || $0.isNewline }) {
            var item = String(part).trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            let emoji = String(item.filter { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } || ($0.unicodeScalars.count > 1 && $0.unicodeScalars.first?.properties.isEmoji == true) })
            item = String(item.filter { !emoji.contains($0) })
            var minutes: Int?
            if let match = item.range(of: #"\b(\d{1,2})[:.h](\d{2})\b"#, options: .regularExpression) {
                let digits = item[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if digits.count == 2, digits[0] < 24, digits[1] < 60 { minutes = digits[0] * 60 + digits[1] }
                item.removeSubrange(match)
            } else if let match = item.range(of: #"\b(\d{1,2})\s*(am|pm|uhr|h)\b"#, options: [.regularExpression, .caseInsensitive]) {
                let text = item[match].lowercased()
                if var hour = text.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }), hour < 24 {
                    if text.contains("pm"), hour < 12 { hour += 12 }
                    minutes = hour * 60
                }
                item.removeSubrange(match)
            }
            let name = item.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
            guard !name.isEmpty else { continue }
            // "Frühstück" is breakfast, "Jause" the snack – unless that meal is already taken ("Jause" and "Snack").
            let builtIn = MealSlot.matching(name, in: MealSlot.defaults).flatMap { match in
                slots.contains { $0.id == match.id } ? nil : match
            }
            let id = builtIn?.id ?? "meal-" + SearchText.normalize(name).replacingOccurrences(of: " ", with: "-")
            guard !slots.contains(where: { $0.id == id }) else { continue }
            slots.append(MealSlot(id: id, name: name, emoji: emoji.isEmpty ? (builtIn?.emoji ?? "🍽️") : String(emoji.prefix(1)),
                                  minutes: minutes ?? builtIn?.minutes ?? 12 * 60))
        }
        return slots.sorted { $0.minutes < $1.minutes }
    }

    static func nutrient(named text: String) -> Nutrient? {
        let key = SearchText.normalize(text)
        let extra: [String: Nutrient] = ["salt": .sodium, "salz": .sodium, "carbohydrates": .carbs, "kohlenhydrate": .carbs,
                                         "eiweiss": .protein, "fett": .fat, "ballaststoffe": .fiber, "fibre": .fiber, "zucker": .sugar,
                                         "saturates": .saturatedFat, "gesattigte fettsauren": .saturatedFat, "wasser": .water,
                                         "calories": .energy, "kcal": .energy]
        if let nutrient = extra[key] { return nutrient }
        return Nutrient.allCases.first { SearchText.normalize($0.title) == key || SearchText.normalize($0.rawValue) == key
            || SearchText.normalize($0.shortTitle) == key }
    }

    // MARK: Applying

    /// The settings after the file, what changes, a weight to log and today's body values. Body data
    /// recalculates the targets with the goal calculator (as Settings → Goals & Plan does); fixed numbers in
    /// the file win. With a coach plan (one there was, or plan rows in the file) the flat goal, rate,
    /// target weight and targets are the active phase's, and the profile mirrors the plan. `today`
    /// and `now` date the body records and a phase start the file confirms.
    public static func apply(_ draft: SettingsDraft, to current: SettingsState, year: Int, today: DayKey = DayKey.today(),
                             now: Date = Date(), calendar: Calendar = .current) -> SettingsResult {
        var state = current
        var notes: [String] = []
        let oldPlan = current.plan.flatMap { $0.isEmpty ? nil : $0 }
        let planMode = oldPlan != nil || draft.plan.hasPlanRows
        let flatOld = flatTargets(current, today: today)
        if let sex = draft.sex { state.sex = sex }
        if let birthYear = draft.birthYear {
            state.birthYear = birthYear
        } else if let age = draft.age {
            state.birthYear = year - age
        }
        if let height = draft.heightCm { state.heightCm = height }
        if let weight = draft.weightKg { state.weightKg = weight }
        if let activity = draft.activity { state.activity = activity }
        if let goal = draft.goal { state.goal = goal }
        if let rate = draft.ratePerWeek { state.ratePerWeek = rate }
        if let target = draft.targetWeight { state.targetWeight = target }
        if let split = draft.macroSplit { state.macroSplit = split }
        if let percent = draft.macroPercent {
            // The closest preset is remembered; the grams follow the exact percentages below.
            state.macroSplit = MacroSplit.presets.min { a, b in
                abs(a.protein - percent.protein) + abs(a.carbs - percent.carbs) + abs(a.fat - percent.fat)
                    < abs(b.protein - percent.protein) + abs(b.carbs - percent.carbs) + abs(b.fat - percent.fat)
            } ?? state.macroSplit
        }

        // Daily targets (with a plan: the active phase's baseline).
        let bodyGiven = draft.sex != nil || draft.birthYear != nil || draft.age != nil || draft.heightCm != nil || draft.weightKg != nil
            || draft.activity != nil || draft.goal != nil || draft.ratePerWeek != nil || draft.macroSplit != nil || draft.macroPercent != nil
        let canCalculate = state.birthYear > 0 && state.heightCm > 0 && state.weightKg > 0
        // A whole settings file copied back with a new goal, pace or body value: the calories and
        // grams it repeats are the old calculation, not fixed numbers – they are calculated again.
        var draft = draft
        let echoed = bodyGiven && canCalculate && repeatsTargets(draft, flatOld) && bodyInputsChanged(draft, state: state, current: current, today: today)
        if echoed {
            draft.calories = nil
            draft.protein = nil
            draft.carbs = nil
            draft.fat = nil
        }
        var targets = flatOld
        if bodyGiven {
            if canCalculate {
                let body = BodyProfile(sex: state.sex, age: max(10, year - state.birthYear), heightCm: state.heightCm, weightKg: state.weightKg,
                                       activity: state.activity, goal: state.goal, ratePerWeek: state.ratePerWeek)
                targets = GoalCalculator.plan(body, split: state.macroSplit).targets
            } else if draft.calories == nil {
                notes.append("Calories not calculated: Nina needs birth year (or age), height and weight for that.")
            }
        }
        if echoed, targets.energy != flatOld.energy {
            let old = grouped(flatOld.energy), new = grouped(targets.energy)
            notes.append("Calories recalculated for your new numbers (\(old) → \(new) kcal) – the file repeated your current calories and grams. To keep \(old) kcal, import calories on its own.")
        }
        let percent: (Double, Double, Double)? = draft.macroPercent.map { ($0.protein, $0.carbs, $0.fat) }
            ?? draft.macroSplit.map { ($0.protein, $0.carbs, $0.fat) }
        if let calories = draft.calories {
            if let percent {
                targets.energy = calories
                targets.protein = (calories * percent.0 / 4).rounded()
                targets.carbs = (calories * percent.1 / 4).rounded()
                targets.fat = (calories * percent.2 / 9).rounded()
            } else {
                targets = targets.scaled(toEnergy: calories)
            }
        } else if let percent, !bodyGiven || !canCalculate || draft.macroPercent != nil {
            targets.protein = (targets.energy * percent.0 / 4).rounded()
            targets.carbs = (targets.energy * percent.1 / 4).rounded()
            targets.fat = (targets.energy * percent.2 / 9).rounded()
        }
        if let protein = draft.protein { targets.protein = protein }
        if let carbs = draft.carbs { targets.carbs = carbs }
        if let fat = draft.fat { targets.fat = fat }
        if let fiber = draft.fiber { targets.fiber = fiber }
        if let sugar = draft.sugarMax { targets.sugarMax = sugar }
        if let saturated = draft.saturatedFatMax { targets.saturatedFatMax = saturated }
        if let salt = draft.saltMax { targets.sodiumMax = NutrientValues.sodium(fromSalt: salt) }
        if let water = draft.water { targets.water = water }
        if draft.calories == nil, draft.protein != nil || draft.carbs != nil || draft.fat != nil {
            // Fixed macros without fixed calories: the calories follow the macros.
            targets.energy = ((targets.protein * 4 + targets.carbs * 4 + targets.fat * 9) / 10).rounded() * 10
        }
        if let calories = draft.calories, let protein = draft.protein, let carbs = draft.carbs, let fat = draft.fat,
           let problem = macroProblem(calories: calories, protein: protein, carbs: carbs, fat: fat) {
            notes.append("calories: \(problem)")
        }
        state.targets = targets

        // Training days (with day_type rows the day types replace them).
        let typeRows = planMode && draft.plan.dayTypes != nil
        if typeRows, draft.trainingDays != nil || draft.trainingExtra != nil {
            notes.append("training_days: skipped – the day_type rows set the day types")
        }
        let trainingDays = typeRows ? nil : draft.trainingDays
        let trainingExtra = typeRows ? nil : draft.trainingExtra
        let extra = trainingExtra ?? (current.trainingTargets != nil ? current.trainingExtra : 300)
        if let days = trainingDays {
            state.trainingDays = days
            state.trainingTargets = days.isEmpty ? nil : SettingsState.training(targets, extra: extra)
        } else if current.trainingTargets != nil {
            state.trainingTargets = SettingsState.training(targets, extra: extra)
        } else if trainingExtra != nil {
            notes.append("training_extra_kcal needs training_days (e.g. mon;wed;fri).")
        }

        // Preferences.
        if let meals = draft.meals {
            // Imported meals replace the own ones; the four standard meals always stay (renamed if the file renames them).
            var merged = meals
            for builtIn in MealSlot.defaults where !merged.contains(where: { $0.id == builtIn.id }) {
                merged.append(current.meals.first { $0.id == builtIn.id } ?? builtIn)
            }
            state.meals = merged.sorted { $0.minutes < $1.minutes }
        }
        if let language = draft.language { state.language = language }
        if let unit = draft.energyUnit { state.energyUnit = unit }
        if let hour = draft.dayStartHour { state.dayStartHour = hour }
        if let glass = draft.waterGlass { state.waterGlass = glass }
        if let share = draft.activityBonusShare { state.activityBonusShare = share }
        if let focus = draft.focus { state.focus = focus }

        // The coach plan.
        if planMode {
            let input = PlanInput(current: current, oldPlan: oldPlan, flatOld: flatOld, flatNew: targets, today: today, now: now, calendar: calendar)
            applyPlan(draft, input, state: &state, notes: &notes)
        }

        // Today's body values: the baseline assessment and tape record.
        var records: [SettingsBodyRecord] = []
        if let fat = draft.plan.bodyFat {
            records.append(SettingsBodyRecord(day: today, kind: .assessment, values: BodyValues([BodyValues.bodyFatKey: fat]),
                                              method: draft.plan.bodyFatMethod ?? .estimate))
        } else if draft.plan.bodyFatMethod != nil {
            notes.append("body_fat_method needs body_fat_percent.")
        }
        if !draft.plan.tape.isEmpty {
            records.append(SettingsBodyRecord(day: today, kind: .tape, values: BodyValues(draft.plan.tape)))
        }

        var newWeight: Double?
        if let weight = draft.weightKg, abs(weight - current.weightKg) >= 0.05 { newWeight = weight }
        var changes = changes(from: current, to: state, today: today)
        if let newWeight {
            changes.removeAll { $0.title == "Weight" && $0.group == .body }
            changes.insert(SettingsChange(title: "Weight (logged today)", old: current.weightKg > 0 ? kg(current.weightKg) : "–", new: kg(newWeight), group: .body), at: 0)
        }
        var bodyLines: [SettingsChange] = []
        for record in records {
            if record.kind == .assessment, let fat = record.values.bodyFat {
                bodyLines.append(SettingsChange(title: "Body fat (today)", old: "–",
                                                new: NumberText.plain(fat, decimals: 1) + " % · " + (record.method ?? .estimate).title,
                                                group: .body, key: BodyValues.bodyFatKey))
            } else {
                let sites = record.values.sites
                for site in BodySite.allCases {
                    guard let cm = sites[site] else { continue }
                    bodyLines.append(SettingsChange(title: "\(site.title) (today)", old: "–", new: NumberText.plain(cm, decimals: 1) + " cm",
                                                    group: .body, key: site.rawValue))
                }
            }
        }
        let insertAt = changes.firstIndex { $0.group != .body } ?? changes.count
        changes.insert(contentsOf: bodyLines, at: insertAt)
        return SettingsResult(state: state, changes: changes, newWeight: newWeight, notes: notes, bodyRecords: records, wishes: draft.wishes)
    }

    static func kg(_ value: Double) -> String { NumberText.plain(value, decimals: 1) + " kg" }

    /// The file's calories (and the grams it has) are the current targets, as the export writes them.
    static func repeatsTargets(_ draft: SettingsDraft, _ targets: DailyTargets) -> Bool {
        func same(_ value: Double?, _ target: Double) -> Bool { value.map { abs($0 - target) < 0.5 } ?? true }
        guard let calories = draft.calories, abs(calories - targets.energy) < 0.5 else { return false }
        return same(draft.protein, targets.protein) && same(draft.carbs, targets.carbs) && same(draft.fat, targets.fat)
    }

    /// Something the calorie calculation uses changed: goal, pace, sex, birth year, height,
    /// activity or weight.
    static func bodyInputsChanged(_ draft: SettingsDraft, state: SettingsState, current: SettingsState, today: DayKey) -> Bool {
        if let goal = draft.goal, goal != current.goal { return true }
        if let range = draft.rateRange, range != flatRate(current, today: today) { return true }
        return state.sex != current.sex || state.birthYear != current.birthYear || abs(state.heightCm - current.heightCm) >= 0.05
            || state.activity != current.activity || abs(state.weightKg - current.weightKg) >= 0.05
    }

    /// Every setting that differs, in plain words and by group. With an active phase its goal, rate
    /// and target weight are listed under Phases; the flat targets are the active phase's baseline.
    public static func changes(from old: SettingsState, to new: SettingsState, today: DayKey = DayKey.today()) -> [SettingsChange] {
        var result: [SettingsChange] = []
        func add(_ title: String, _ a: String, _ b: String, _ group: SettingsGroup) {
            if a != b { result.append(SettingsChange(title: title, old: a, new: b, group: group)) }
        }
        let newPlan = new.plan.flatMap { $0.isEmpty ? nil : $0 }
        let phaseRules = newPlan?.activePhase(on: today) != nil
        let typesRule = newPlan?.isSetUp == true
        add("Sex", old.sex.title, new.sex.title, .body)
        add("Born", old.birthYear > 0 ? String(old.birthYear) : "–", new.birthYear > 0 ? String(new.birthYear) : "–", .body)
        add("Height", old.heightCm > 0 ? NumberText.plain(old.heightCm, decimals: 0) + " cm" : "–", new.heightCm > 0 ? NumberText.plain(new.heightCm, decimals: 0) + " cm" : "–", .body)
        add("Weight", old.weightKg > 0 ? kg(old.weightKg) : "–", new.weightKg > 0 ? kg(new.weightKg) : "–", .body)
        add("Activity", old.activity.title, new.activity.title, .body)
        if !phaseRules {
            add("Goal", old.goal.title, new.goal.title, .targets)
            if new.goal != .maintain { add("Pace", NumberText.plain(old.ratePerWeek) + " kg/week", NumberText.plain(new.ratePerWeek) + " kg/week", .targets) }
            add("Target weight", old.targetWeight > 0 ? kg(old.targetWeight) : "–", new.targetWeight > 0 ? kg(new.targetWeight) : "–", .targets)
        }
        add("Macro split", old.macroSplit.name, new.macroSplit.name, .targets)
        let a = flatTargets(old, today: today), b = flatTargets(new, today: today)
        add("Calories", NumberText.plain(a.energy, decimals: 0) + " kcal", NumberText.plain(b.energy, decimals: 0) + " kcal", .targets)
        add("Protein", g(a.protein), g(b.protein), .targets)
        add("Carbohydrates", g(a.carbs), g(b.carbs), .targets)
        add("Fat", g(a.fat), g(b.fat), .targets)
        add("Fiber", g(a.fiber), g(b.fiber), .targets)
        add("Sugar (max)", g(a.sugarMax), g(b.sugarMax), .targets)
        add("Saturated fat (max)", g(a.saturatedFatMax), g(b.saturatedFatMax), .targets)
        add("Salt (max)", NumberText.plain(a.sodiumMax * 2.5 / 1000, decimals: 1) + " g", NumberText.plain(b.sodiumMax * 2.5 / 1000, decimals: 1) + " g", .targets)
        add("Water", NumberText.plain(a.water, decimals: 0) + " ml", NumberText.plain(b.water, decimals: 0) + " ml", .targets)
        if !typesRule {
            func training(_ state: SettingsState) -> String {
                guard state.trainingTargets != nil, !state.trainingDays.isEmpty else { return "off" }
                return "\(state.trainingDays.summary), +\(NumberText.plain(state.trainingExtra, decimals: 0)) kcal"
            }
            add("Training days", training(old), training(new), .targets)
        }
        result += planChanges(from: old, to: new, today: today)
        func meals(_ slots: [MealSlot]) -> String {
            slots.sorted { $0.minutes < $1.minutes }.map { "\($0.emoji) \($0.name) \(ClockTime.text($0.minutes))" }.joined(separator: ", ")
        }
        add("Meals", meals(old.meals), meals(new.meals), .preferences)
        add("Food names", old.language.title, new.language.title, .preferences)
        add("Energy unit", old.energyUnit.rawValue, new.energyUnit.rawValue, .preferences)
        add("Day starts at", "\(old.dayStartHour):00", "\(new.dayStartHour):00", .preferences)
        add("Glass of water", NumberText.plain(old.waterGlass, decimals: 0) + " ml", NumberText.plain(new.waterGlass, decimals: 0) + " ml", .preferences)
        func bonus(_ share: Double) -> String { share >= 1 ? "all" : (share > 0 ? "half" : "none") }
        add("Burned calories added", bonus(old.activityBonusShare), bonus(new.activityBonusShare), .preferences)
        add("Shown first", old.focus.map(\.title).joined(separator: ", "), new.focus.map(\.title).joined(separator: ", "), .preferences)
        if result.isEmpty, old.plan.flatMap({ $0.isEmpty ? nil : $0 }) != newPlan {
            // A plan change no line describes (e.g. the order of the day types).
            result.append(SettingsChange(title: "Coach plan", old: "", new: "updated", group: .phases))
        }
        return result
    }

    // MARK: Writing

    /// The current settings as a file (export, and what the AI can start from). With a coach plan the
    /// flat goal, rate, target weight and targets are the active phase's on `today`, and the whole
    /// plan follows in the dotted format (day_type.*, phase.N.*, check.*, measure.*, checkin.*, note).
    public static func export(_ state: SettingsState, today: DayKey = DayKey.today()) -> String {
        let plan = state.plan.flatMap { $0.isEmpty ? nil : $0 }
        var rows: [[String]] = [["setting", "value"]]
        func add(_ key: String, _ value: String) { if !value.isEmpty { rows.append([key, value]) } }
        add("sex", state.sex.rawValue)
        if state.birthYear > 0 { add("birth_year", String(state.birthYear)) }
        if state.heightCm > 0 { add("height_cm", NumberText.plain(state.heightCm, decimals: 1)) }
        if state.weightKg > 0 { add("weight_kg", NumberText.plain(state.weightKg, decimals: 1)) }
        add("activity", state.activity == .veryActive ? "very_active" : state.activity.rawValue)
        add("goal", state.goal.rawValue)
        // The active phase's pace; a phase without one (maintain) writes its own rate row (0), and
        // the profile's old pace would be read back into it.
        if let active = plan?.activePhase(on: today) {
            if active.rateRange.upperBound > 0 { add("rate_kg_per_week", rangeValue(active.rateRange.lowerBound, active.rateRange.upperBound)) }
        } else {
            let rate = plan != nil ? flatRate(state, today: today) : state.ratePerWeek...state.ratePerWeek
            add("rate_kg_per_week", rangeValue(rate.lowerBound, rate.upperBound))
        }
        if state.targetWeight > 0 { add("target_weight_kg", NumberText.plain(state.targetWeight, decimals: 1)) }
        add("macro_split", splitName(state.macroSplit))
        let targets = flatTargets(state, today: today)
        add("calories", NumberText.plain(targets.energy, decimals: 0))
        add("protein_g", NumberText.plain(targets.protein, decimals: 0))
        add("carbs_g", NumberText.plain(targets.carbs, decimals: 0))
        add("fat_g", NumberText.plain(targets.fat, decimals: 0))
        add("fiber_g", NumberText.plain(targets.fiber, decimals: 0))
        add("sugar_max_g", NumberText.plain(targets.sugarMax, decimals: 0))
        add("saturated_fat_max_g", NumberText.plain(targets.saturatedFatMax, decimals: 0))
        add("salt_max_g", NumberText.plain(targets.sodiumMax * 2.5 / 1000, decimals: 1))
        add("water_ml", NumberText.plain(targets.water, decimals: 0))
        if plan?.isSetUp != true {
            if state.trainingTargets != nil, !state.trainingDays.isEmpty {
                add("training_days", state.trainingDays.days.sorted().map { Weekdays.shortNames[$0 - 1].lowercased() }.joined(separator: ";"))
                add("training_extra_kcal", NumberText.plain(state.trainingExtra, decimals: 0))
            } else {
                add("training_days", "none")
            }
        }
        add("meals", state.meals.map { "\($0.name) \(ClockTime.text($0.minutes)) \($0.emoji)" }.joined(separator: ";"))
        add("food_names", state.language == .german ? "german" : "english")
        add("energy_unit", state.energyUnit.rawValue)
        add("day_starts_at", String(state.dayStartHour))
        add("water_glass_ml", NumberText.plain(state.waterGlass, decimals: 0))
        add("add_burned_calories", state.activityBonusShare >= 1 ? "all" : (state.activityBonusShare > 0 ? "half" : "none"))
        add("focus_nutrients", state.focus.map { $0 == .sodium ? "salt" : $0.title.lowercased() }.joined(separator: ";"))
        rows += planRows(state, today: today)
        return CSV.write(rows)
    }

    static func splitName(_ split: MacroSplit) -> String {
        switch split.id {
        case "highProtein": "high_protein"
        case "lowCarb": "low_carb"
        default: split.id
        }
    }

    // MARK: The prompt

    /// The prompt for another AI: everything I tell it about me becomes this file.
    public static func prompt(appName: String, current: String? = nil) -> String {
        var lines: [String] = []
        lines.append("You set up my nutrition app \"\(appName)\" from what I tell you about myself (body, goal, training, habits, my meals and their times, preferences) and from my plan if I have one (phases, calorie cycling, measurements, check-ins, supplements). Write the settings as a CSV with two columns.")
        lines.append("")
        lines.append("## Output rules")
        lines.append("- Answer with ONE csv code block and nothing else. The first line is exactly this header:")
        lines.append("setting,value")
        lines.append(contentsOf: settingsRules)
        lines.append("")
        lines.append(contentsOf: settingsTable)
        lines.append("")
        lines.append(contentsOf: planSection(heading: "## Coach plan (only if my notes describe one)"))
        if let current, !current.isEmpty {
            lines.append("")
            lines.append("## My current settings in \(appName) (change only what my notes say)")
            lines.append(currentSettingsNote)
            lines.append("```csv")
            lines.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("```")
        }
        lines.append("")
        lines.append("## My notes")
        lines.append("(I paste or describe them below.)")
        return lines.joined(separator: "\n")
    }

    /// Above the current settings in every prompt: the numbers in them aren't fixed ones.
    static let currentSettingsNote = "Write only the rows that change. Don't copy the calories and grams below into your answer unless I give new fixed numbers – Nina calculates them again from my body data and goal."

    static let settingsRules: [String] = [
        "- One row per setting. Leave out every setting my notes don't say anything about – only the rows in the file change.",
        "- Prefer my body data (birth_year or age, height_cm, weight_kg, activity, goal, rate_kg_per_week) over fixed numbers: Nina calculates calories and macros from them with the Mifflin–St Jeor formula. Write calories or grams only if I give fixed numbers (e.g. from a dietitian).",
        "- Put a value in \"double quotes\" if it contains a comma. Decimal point, not comma (67.5). No units inside number cells.",
        "- Advice from my plan that isn't a setting (training, recovery, timing tips): one row each with setting note – Nina keeps it in my plan.",
        "- Only a real wish that no row covers (e.g. allergies, a diet I follow, a medication, a reminder I want): one row each with setting not_supported – the app shows the list.",
    ]

    static var settingsTable: [String] {
        var lines = ["## Settings", "| setting | value |", "|---|---|"]
        for key in keys {
            lines.append("| \(key.name) | \(key.meaning)\(key.example.isEmpty ? "" : " – e.g. \(key.example)") |")
        }
        return lines
    }
}
