import Foundation

/// Protein per eating occasion (F9): grams per meal against the plan's minimum ("28 / 35 g" in the
/// meal header), protein meals per day ("Protein meals 3 of 4") and per week ("21 of 28"), the
/// search hint ("+18 g protein to reach 35") and protein per kg of body weight and lean mass.
/// Computed from the diary entries by meal; nothing new is stored per day.
public enum ProteinMeals {
    /// g per kg body weight per meal when the plan sets no minimum.
    public static let minimumPerKg = 0.4
    /// g per kg body weight: the optional maximum per meal when the plan sets no minimum.
    public static let maximumPerKg = 0.55

    /// What counts as a protein meal on a day.
    public struct Rule: Codable, Equatable, Sendable {
        /// g per meal; 0 = off.
        public var minimum: Double
        /// g per meal; above it the pill stays filled, with no warning.
        public var maximum: Double?
        /// Meal slot ids that count, in display order.
        public var meals: [String]
        /// Protein meals a day.
        public var count: Int

        public init(minimum: Double, maximum: Double? = nil, meals: [String], count: Int? = nil) {
            self.minimum = max(0, minimum)
            self.maximum = maximum.flatMap { $0 > 0 ? $0 : nil }
            self.meals = meals
            self.count = max(0, count ?? meals.count)
        }

        /// The plan's rule: its minimum, else 0.4 g/kg × `weightKg` (the 7-day average) with a
        /// maximum of 0.55 g/kg; its meals, else every meal slot; its count, else one per meal.
        public init(protein: CoachPlan.Protein, weightKg: Double, mealSlots: [String]) {
            let maximum: Double?
            if protein.mealMax > 0 {
                maximum = protein.mealMax
            } else if !protein.isSet, weightKg > 0 {
                maximum = (weightKg * ProteinMeals.maximumPerKg).rounded()
            } else {
                maximum = nil
            }
            let meals = protein.meals.isEmpty ? mealSlots : protein.meals
            self.init(minimum: protein.minimum(weightKg: weightKg), maximum: maximum, meals: meals,
                      count: protein.effectiveCount(mealSlots: mealSlots.count))
        }

        /// A minimum and a count are known.
        public var isActive: Bool { minimum > 0 && count > 0 && !meals.isEmpty }

        public func counts(_ meal: String) -> Bool { meals.contains(meal) }
    }

    /// How the meal header pill is drawn.
    public enum Fill: String, Codable, Sendable {
        /// Outlined: below the minimum.
        case below
        /// Filled: from the minimum on.
        case reached
        /// Above the maximum: still filled, no warning.
        case above
    }

    /// Protein of one meal.
    public struct Meal: Codable, Equatable, Sendable, Identifiable {
        /// Meal slot id.
        public var id: String
        /// g eaten.
        public var eaten: Double
        /// g still planned (count in the pill, drawn dimmed).
        public var planned: Double
        public var minimum: Double
        public var maximum: Double?

        public init(id: String, eaten: Double, planned: Double = 0, minimum: Double, maximum: Double? = nil) {
            self.id = id
            self.eaten = eaten
            self.planned = planned
            self.minimum = minimum
            self.maximum = maximum
        }

        /// Eaten plus planned: the pill's number ("28 / 35 g").
        public var total: Double { eaten + planned }

        public var fill: Fill { ProteinMeals.fill(total, minimum: minimum, maximum: maximum) }

        /// The eaten protein reaches the minimum (planned food doesn't count yet).
        public var isProteinMeal: Bool { ProteinMeals.reaches(eaten, minimum: minimum) }

        /// Whole grams still missing with planned food included (0 when reached): the search hint.
        public var missing: Double { ProteinMeals.missing(total, minimum: minimum) }
    }

    /// One day's protein meals.
    public struct Day: Codable, Equatable, Sendable {
        public var day: DayKey
        /// The meals that count, in the rule's order (also those without entries).
        public var meals: [Meal]
        /// Protein meals the plan wants.
        public var target: Int

        public init(day: DayKey, meals: [Meal], target: Int) {
            self.day = day
            self.meals = meals
            self.target = target
        }

        public func meal(_ id: String) -> Meal? { meals.first { $0.id == id } }

        /// Meals whose eaten protein reached the minimum.
        public var count: Int { meals.filter(\.isProteinMeal).count }
        /// The count, at most the target (for week sums).
        public var counted: Int { min(count, target) }
        /// The adherence rule: at least target − 1 protein meals.
        public var isEnough: Bool { target > 0 && count >= target - 1 }
        /// "3 of 4"
        public var text: String { "\(counted) of \(target)" }
    }

    /// A day's protein by meal from its diary entries: eaten and planned (skipped entries don't count).
    public static func day(_ day: DayKey, entries: [EntryFacts], rule: Rule) -> Day {
        var eaten: [String: Double] = [:]
        var planned: [String: Double] = [:]
        for entry in entries where entry.day == day {
            switch entry.status {
            case .eaten: eaten[entry.meal, default: 0] += entry.nutrients.value(.protein)
            case .planned: planned[entry.meal, default: 0] += entry.nutrients.value(.protein)
            case .skipped: break
            }
        }
        return make(day, eaten: eaten, planned: planned, rule: rule)
    }

    /// A day's protein by meal from its totals (eaten only, `DayTotals.byMeal`).
    public static func day(_ totals: DayTotals, rule: Rule) -> Day {
        make(totals.day, eaten: totals.byMeal.mapValues { $0.value(.protein) }, planned: [:], rule: rule)
    }

    private static func make(_ day: DayKey, eaten: [String: Double], planned: [String: Double], rule: Rule) -> Day {
        var seen = Set<String>()
        let meals = rule.meals.filter { seen.insert($0).inserted }.map { id in
            Meal(id: id, eaten: eaten[id] ?? 0, planned: planned[id] ?? 0, minimum: rule.minimum, maximum: rule.maximum)
        }
        return Day(day: day, meals: rule.isActive ? meals : [], target: rule.isActive ? rule.count : 0)
    }

    /// Protein meals over several days ("Protein meals 21 of 28").
    public struct Period: Codable, Equatable, Sendable {
        public var days: Int
        /// Protein meals, at most the target per day.
        public var meals: Int
        public var target: Int
        /// Days with at least target − 1 protein meals.
        public var enoughDays: Int

        public init(days: Int, meals: Int, target: Int, enoughDays: Int) {
            self.days = days
            self.meals = meals
            self.target = target
            self.enoughDays = enoughDays
        }

        public var share: Double { target > 0 ? Double(meals) / Double(target) : 0 }
        /// "21 of 28"
        public var text: String { "\(meals) of \(target)" }
    }

    /// The days to sum (leave paused days out before).
    public static func period(_ days: [Day]) -> Period {
        Period(days: days.count, meals: days.map(\.counted).reduce(0, +), target: days.map(\.target).reduce(0, +),
               enoughDays: days.filter(\.isEnough).count)
    }

    // MARK: Pill and hint

    /// Compared in whole grams, as shown ("35 / 35 g" is reached).
    public static func reaches(_ grams: Double, minimum: Double) -> Bool {
        minimum > 0 && grams.rounded() >= minimum.rounded()
    }

    public static func fill(_ grams: Double, minimum: Double, maximum: Double? = nil) -> Fill {
        guard reaches(grams, minimum: minimum) else { return .below }
        if let maximum, maximum > 0, grams.rounded() > maximum.rounded() { return .above }
        return .reached
    }

    /// Whole grams to the minimum (rounded up), 0 when reached.
    public static func missing(_ grams: Double, minimum: Double) -> Double {
        guard minimum > 0, !reaches(grams, minimum: minimum) else { return 0 }
        return max(1, (minimum - grams).rounded(.up))
    }

    /// The search header when adding to a meal below the minimum: "+18 g protein to reach 35".
    public static func hint(_ grams: Double, minimum: Double) -> String? {
        let missing = ProteinMeals.missing(grams, minimum: minimum)
        guard missing > 0 else { return nil }
        return "+\(Int(missing)) g protein to reach \(Int(minimum.rounded()))"
    }

    // MARK: Ratios

    /// Protein per kg of body weight and per kg of lean mass.
    public struct Ratio: Codable, Equatable, Sendable {
        public var grams: Double
        /// g/kg body weight.
        public var perKg: Double
        /// g/kg lean mass, once a body-fat value (or lean mass) exists.
        public var perLeanKg: Double?

        public init(grams: Double, perKg: Double, perLeanKg: Double? = nil) {
            self.grams = grams
            self.perKg = perKg
            self.perLeanKg = perLeanKg
        }

        /// "2.0 g/kg · 2.5 g/kg lean mass" (one decimal).
        public var text: String {
            let body = ProteinMeals.oneDecimal(perKg) + " g/kg"
            guard let perLeanKg else { return body }
            return body + " · " + ProteinMeals.oneDecimal(perLeanKg) + " g/kg lean mass"
        }
    }

    /// `grams` per kg of `weightKg` (the 7-day average) and of lean mass: `leanKg` if known, else
    /// weight × (1 − body fat ÷ 100). nil without a weight.
    public static func ratio(grams: Double, weightKg: Double, leanKg: Double? = nil, bodyFat: Double? = nil) -> Ratio? {
        guard weightKg > 0, grams >= 0 else { return nil }
        var lean = leanKg.flatMap { $0 > 0 ? $0 : nil }
        if lean == nil, let bodyFat, bodyFat > 0, bodyFat < 100 {
            lean = weightKg * (1 - bodyFat / 100)
        }
        return Ratio(grams: grams, perKg: grams / weightKg, perLeanKg: lean.map { grams / $0 })
    }

    static func oneDecimal(_ value: Double) -> String {
        DisplayNumber.fixed((value * 10).rounded() / 10, decimals: 1)
    }
}
