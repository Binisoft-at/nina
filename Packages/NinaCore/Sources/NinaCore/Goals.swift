import Foundation

public enum Sex: String, CaseIterable, Codable, Sendable, Identifiable {
    case female, male, unspecified

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .unspecified: "Prefer not to say"
        }
    }
}

public enum ActivityLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    public var id: String { rawValue }

    /// Physical activity level (PAL) factor applied to the basal metabolic rate.
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public var title: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Very active"
        case .veryActive: "Extremely active"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .light: "Exercise 1–3 days a week or a job on your feet"
        case .moderate: "Exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job plus hard training"
        }
    }
}

public enum WeightGoal: String, CaseIterable, Codable, Sendable, Identifiable {
    case lose, maintain, gain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Keep my weight"
        case .gain: "Gain weight"
        }
    }
}

/// What the goal calculator needs to know.
public struct BodyProfile: Equatable, Codable, Sendable {
    public var sex: Sex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: WeightGoal
    /// kg per week (positive), for lose and gain.
    public var ratePerWeek: Double

    public init(sex: Sex = .unspecified, age: Int = 35, heightCm: Double = 172, weightKg: Double = 72,
                activity: ActivityLevel = .light, goal: WeightGoal = .maintain, ratePerWeek: Double = 0.5) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.ratePerWeek = ratePerWeek
    }
}

/// How the energy is split between protein, carbs and fat (fractions that add up to 1).
public struct MacroSplit: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(id: String, name: String, protein: Double, carbs: Double, fat: Double) {
        self.id = id
        self.name = name
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let balanced = MacroSplit(id: "balanced", name: "Balanced", protein: 0.25, carbs: 0.45, fat: 0.30)
    public static let highProtein = MacroSplit(id: "highProtein", name: "High protein", protein: 0.30, carbs: 0.40, fat: 0.30)
    public static let lowCarb = MacroSplit(id: "lowCarb", name: "Low carb", protein: 0.30, carbs: 0.20, fat: 0.50)
    public static let endurance = MacroSplit(id: "endurance", name: "Endurance", protein: 0.20, carbs: 0.55, fat: 0.25)
    public static let keto = MacroSplit(id: "keto", name: "Keto", protein: 0.20, carbs: 0.05, fat: 0.75)
    public static let presets: [MacroSplit] = [.balanced, .highProtein, .lowCarb, .endurance, .keto]

    public var isValid: Bool { abs(protein + carbs + fat - 1) < 0.011 && min(protein, carbs, fat) >= 0 }
}

/// Daily targets. Energy, protein, carbs, fat, fiber and water are goals to reach; sugar,
/// saturated fat and sodium are limits.
public struct DailyTargets: Equatable, Codable, Sendable {
    public var energy: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double
    public var sugarMax: Double
    public var saturatedFatMax: Double
    /// mg (2000 mg sodium = 5 g salt).
    public var sodiumMax: Double
    /// ml
    public var water: Double

    public init(energy: Double, protein: Double, carbs: Double, fat: Double, fiber: Double = 30,
                sugarMax: Double = 50, saturatedFatMax: Double = 22, sodiumMax: Double = 2000, water: Double = 2000) {
        self.energy = energy
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugarMax = sugarMax
        self.saturatedFatMax = saturatedFatMax
        self.sodiumMax = sodiumMax
        self.water = water
    }

    public static let standard = DailyTargets(energy: 2000, protein: 125, carbs: 225, fat: 67, fiber: 30,
                                              sugarMax: 50, saturatedFatMax: 22, sodiumMax: 2000, water: 2000)

    /// The target (or limit) for a nutrient; reference intakes for the ones without an own target.
    public func target(for nutrient: Nutrient) -> Double? {
        switch nutrient {
        case .energy: energy
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        case .fiber: fiber
        case .sugar: sugarMax
        case .saturatedFat: saturatedFatMax
        case .sodium: sodiumMax
        case .water: water
        default: nutrient.referenceIntake
        }
    }

    /// Targets with energy changed and the macros following the same split.
    public func scaled(toEnergy newEnergy: Double) -> DailyTargets {
        guard energy > 0 else { return self }
        let factor = newEnergy / energy
        var copy = self
        copy.energy = newEnergy
        copy.protein = (protein * factor).rounded()
        copy.carbs = (carbs * factor).rounded()
        copy.fat = (fat * factor).rounded()
        return copy
    }

    /// The split these grams correspond to.
    public var split: MacroShares {
        NutrientValues([.protein: protein, .carbs: carbs, .fat: fat]).macroShares
    }

    /// "energy=2000;protein=125;…" for the SwiftData field.
    public var encoded: String {
        let values: [Nutrient: Double] = [.energy: energy, .protein: protein, .carbs: carbs, .fat: fat, .fiber: fiber,
                                          .sugar: sugarMax, .saturatedFat: saturatedFatMax, .sodium: sodiumMax, .water: water]
        return NutrientValues(values).encoded
    }

    public init(encoded: String) {
        let values = NutrientValues(encoded: encoded)
        let standard = DailyTargets.standard
        self.init(energy: values[.energy] ?? standard.energy,
                  protein: values[.protein] ?? standard.protein,
                  carbs: values[.carbs] ?? standard.carbs,
                  fat: values[.fat] ?? standard.fat,
                  fiber: values[.fiber] ?? standard.fiber,
                  sugarMax: values[.sugar] ?? standard.sugarMax,
                  saturatedFatMax: values[.saturatedFat] ?? standard.saturatedFatMax,
                  sodiumMax: values[.sodium] ?? standard.sodiumMax,
                  water: values[.water] ?? standard.water)
    }
}

/// One line of the "how is this calculated" explainer.
public struct GoalStep: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let formula: String
    public let value: Double
    public let unit: String
}

/// The calculator's result, with every step shown in the app's explainer.
public struct GoalPlan: Equatable, Sendable {
    public var bmr: Double
    public var maintenance: Double
    public var adjustment: Double
    public var targets: DailyTargets
    public var steps: [GoalStep]
    /// True when the energy was raised to the safe minimum.
    public var hitFloor: Bool
}

/// The standard method nutritionists use: Mifflin–St Jeor for the basal metabolic rate, times
/// an activity factor for maintenance, ±7,700 kcal per kg of body weight for the weekly goal,
/// then the macro split; fiber 14 g per 1,000 kcal (at least 25 g), sugar and saturated fat at
/// most 10 % of energy (WHO), sodium 2 g (5 g salt, WHO), water 30 ml per kg.
public enum GoalCalculator {
    public static let kilocaloriesPerKilogram = 7700.0

    public static func bmr(_ profile: BodyProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    public static func minimumEnergy(_ profile: BodyProfile) -> Double {
        switch profile.sex {
        case .male: 1500
        case .female: 1200
        case .unspecified: 1350
        }
    }

    public static func plan(_ profile: BodyProfile, split: MacroSplit = .balanced) -> GoalPlan {
        let basal = bmr(profile)
        let maintenance = basal * profile.activity.factor
        let dailyChange = profile.ratePerWeek * kilocaloriesPerKilogram / 7
        let adjustment: Double
        switch profile.goal {
        case .lose: adjustment = -dailyChange
        case .maintain: adjustment = 0
        case .gain: adjustment = dailyChange
        }
        var energy = maintenance + adjustment
        let floor = max(minimumEnergy(profile), profile.goal == .lose ? basal : 0)
        let hitFloor = energy < floor
        if hitFloor { energy = floor }
        energy = (energy / 10).rounded() * 10

        let protein = (energy * split.protein / 4).rounded()
        let carbs = (energy * split.carbs / 4).rounded()
        let fat = (energy * split.fat / 9).rounded()
        let fiber = max(25, (energy / 1000 * 14).rounded())
        let sugar = (energy * 0.10 / 4).rounded()
        let saturated = (energy * 0.10 / 9).rounded()
        let water = min(3500, max(1500, (profile.weightKg * 30 / 250).rounded() * 250))
        let targets = DailyTargets(energy: energy, protein: protein, carbs: carbs, fat: fat, fiber: fiber,
                                   sugarMax: sugar, saturatedFatMax: saturated, sodiumMax: 2000, water: water)

        let sexTerm: String
        switch profile.sex {
        case .male: sexTerm = "+ 5"
        case .female: sexTerm = "− 161"
        case .unspecified: sexTerm = "− 78"
        }
        let w = DisplayNumber.plain(profile.weightKg, decimals: 1)
        let h = DisplayNumber.plain(profile.heightCm, decimals: 0)
        var steps = [
            GoalStep(title: "Basal metabolic rate", formula: "10 × \(w) kg + 6.25 × \(h) cm − 5 × \(profile.age) years \(sexTerm)", value: basal.rounded(), unit: "kcal"),
            GoalStep(title: "Maintenance", formula: "BMR × \(DisplayNumber.plain(profile.activity.factor, decimals: 4)) (\(profile.activity.title.lowercased()))", value: maintenance.rounded(), unit: "kcal"),
        ]
        if profile.goal != .maintain {
            let sign = profile.goal == .lose ? "−" : "+"
            steps.append(GoalStep(title: profile.goal == .lose ? "Deficit" : "Surplus",
                                  formula: "\(sign) \(DisplayNumber.plain(profile.ratePerWeek, decimals: 4)) kg/week × \(DisplayNumber.grouped(7700)) kcal ÷ 7 days",
                                  value: adjustment.rounded(), unit: "kcal"))
        }
        steps.append(GoalStep(title: "Daily calories", formula: hitFloor ? "raised to the safe minimum" : "rounded to 10 kcal", value: energy, unit: "kcal"))
        steps.append(GoalStep(title: "Protein", formula: "\(Int(split.protein * 100)) % of calories ÷ 4 kcal/g (\(DisplayNumber.plain(protein / max(profile.weightKg, 1), decimals: 1)) g per kg)", value: protein, unit: "g"))
        steps.append(GoalStep(title: "Carbohydrates", formula: "\(Int(split.carbs * 100)) % of calories ÷ 4 kcal/g", value: carbs, unit: "g"))
        steps.append(GoalStep(title: "Fat", formula: "\(Int(split.fat * 100)) % of calories ÷ 9 kcal/g", value: fat, unit: "g"))
        steps.append(GoalStep(title: "Fiber", formula: "14 g per \(DisplayNumber.grouped(1000)) kcal, at least 25 g", value: fiber, unit: "g"))
        steps.append(GoalStep(title: "Water", formula: "30 ml × \(w) kg", value: water, unit: "ml"))
        return GoalPlan(bmr: basal, maintenance: maintenance, adjustment: adjustment, targets: targets, steps: steps, hitFloor: hitFloor)
    }

    /// Age from a birth year.
    public static func age(birthYear: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.component(.year, from: now) - birthYear)
    }
}
