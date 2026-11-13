import Foundation

/// The small summary widgets and watch complications read from the shared App Group
/// (`<group>/Nina/today.json`). Only today's numbers – never the diary itself.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public static let fileName = "today.json"

    public var day: String
    public var energy: Double
    public var energyGoal: Double
    public var protein: Double
    public var proteinGoal: Double
    public var carbs: Double
    public var carbsGoal: Double
    public var fat: Double
    public var fatGoal: Double
    public var water: Double
    public var waterGoal: Double
    /// "Lunch · 12:30" – the next planned meal, if any.
    public var nextPlanned: String?
    public var energyUnit: String
    public var updatedAt: Date

    public init(day: String, energy: Double, energyGoal: Double, protein: Double, proteinGoal: Double, carbs: Double,
                carbsGoal: Double, fat: Double, fatGoal: Double, water: Double, waterGoal: Double,
                nextPlanned: String? = nil, energyUnit: String = "kcal", updatedAt: Date = Date()) {
        self.day = day
        self.energy = energy
        self.energyGoal = energyGoal
        self.protein = protein
        self.proteinGoal = proteinGoal
        self.carbs = carbs
        self.carbsGoal = carbsGoal
        self.fat = fat
        self.fatGoal = fatGoal
        self.water = water
        self.waterGoal = waterGoal
        self.nextPlanned = nextPlanned
        self.energyUnit = energyUnit
        self.updatedAt = updatedAt
    }

    public init(progress: DayProgress, nextPlanned: String? = nil, energyUnit: EnergyUnit = .kcal, now: Date = Date()) {
        self.init(day: progress.totals.day.rawValue,
                  energy: progress.energyEaten, energyGoal: progress.energyBudget,
                  protein: progress.totals.eaten.protein, proteinGoal: progress.targets.protein,
                  carbs: progress.totals.eaten.carbs, carbsGoal: progress.targets.carbs,
                  fat: progress.totals.eaten.fat, fatGoal: progress.targets.fat,
                  water: progress.totals.water, waterGoal: progress.targets.water,
                  nextPlanned: nextPlanned, energyUnit: energyUnit.rawValue, updatedAt: now)
    }

    public static let placeholder = TodaySnapshot(day: "2026-01-01", energy: 1240, energyGoal: 2100, protein: 82, proteinGoal: 140,
                                                  carbs: 130, carbsGoal: 230, fat: 41, fatGoal: 70, water: 1250, waterGoal: 2250,
                                                  nextPlanned: "Dinner · 18:30", updatedAt: Date(timeIntervalSince1970: 0))

    /// An empty day with the same goals (shown after midnight until the app writes a new snapshot).
    public func emptied(for day: DayKey) -> TodaySnapshot {
        TodaySnapshot(day: day.rawValue, energy: 0, energyGoal: energyGoal, protein: 0, proteinGoal: proteinGoal,
                      carbs: 0, carbsGoal: carbsGoal, fat: 0, fatGoal: fatGoal, water: 0, waterGoal: waterGoal,
                      nextPlanned: nil, energyUnit: energyUnit, updatedAt: updatedAt)
    }

    /// The snapshot for `today` – emptied when it is from an earlier day.
    public func current(today: DayKey) -> TodaySnapshot {
        day == today.rawValue ? self : emptied(for: today)
    }

    public var remaining: Double { energyGoal - energy }
    public var fraction: Double { energyGoal > 0 ? energy / energyGoal : 0 }

    public func hasSameContent(as other: TodaySnapshot?) -> Bool {
        guard let other else { return false }
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    public var unit: EnergyUnit { EnergyUnit(rawValue: energyUnit) ?? .kcal }
}

/// Which HealthKit quantity type each nutrient is written to (raw HKQuantityTypeIdentifier values),
/// and its unit. Trans fat and alcohol grams have no HealthKit type.
public enum HealthMapping {
    public struct Item: Sendable, Equatable {
        public let nutrient: Nutrient
        public let identifier: String
        /// "kcal", "g", "mg", "mcg"
        public let unit: String
    }

    public static let items: [Item] = [
        Item(nutrient: .energy, identifier: "HKQuantityTypeIdentifierDietaryEnergyConsumed", unit: "kcal"),
        Item(nutrient: .protein, identifier: "HKQuantityTypeIdentifierDietaryProtein", unit: "g"),
        Item(nutrient: .carbs, identifier: "HKQuantityTypeIdentifierDietaryCarbohydrates", unit: "g"),
        Item(nutrient: .fat, identifier: "HKQuantityTypeIdentifierDietaryFatTotal", unit: "g"),
        Item(nutrient: .fiber, identifier: "HKQuantityTypeIdentifierDietaryFiber", unit: "g"),
        Item(nutrient: .sugar, identifier: "HKQuantityTypeIdentifierDietarySugar", unit: "g"),
        Item(nutrient: .saturatedFat, identifier: "HKQuantityTypeIdentifierDietaryFatSaturated", unit: "g"),
        Item(nutrient: .monoFat, identifier: "HKQuantityTypeIdentifierDietaryFatMonounsaturated", unit: "g"),
        Item(nutrient: .polyFat, identifier: "HKQuantityTypeIdentifierDietaryFatPolyunsaturated", unit: "g"),
        Item(nutrient: .cholesterol, identifier: "HKQuantityTypeIdentifierDietaryCholesterol", unit: "mg"),
        Item(nutrient: .sodium, identifier: "HKQuantityTypeIdentifierDietarySodium", unit: "mg"),
        Item(nutrient: .potassium, identifier: "HKQuantityTypeIdentifierDietaryPotassium", unit: "mg"),
        Item(nutrient: .calcium, identifier: "HKQuantityTypeIdentifierDietaryCalcium", unit: "mg"),
        Item(nutrient: .iron, identifier: "HKQuantityTypeIdentifierDietaryIron", unit: "mg"),
        Item(nutrient: .magnesium, identifier: "HKQuantityTypeIdentifierDietaryMagnesium", unit: "mg"),
        Item(nutrient: .zinc, identifier: "HKQuantityTypeIdentifierDietaryZinc", unit: "mg"),
        Item(nutrient: .vitaminA, identifier: "HKQuantityTypeIdentifierDietaryVitaminA", unit: "mcg"),
        Item(nutrient: .vitaminC, identifier: "HKQuantityTypeIdentifierDietaryVitaminC", unit: "mg"),
        Item(nutrient: .vitaminD, identifier: "HKQuantityTypeIdentifierDietaryVitaminD", unit: "mcg"),
        Item(nutrient: .vitaminE, identifier: "HKQuantityTypeIdentifierDietaryVitaminE", unit: "mg"),
        Item(nutrient: .vitaminB12, identifier: "HKQuantityTypeIdentifierDietaryVitaminB12", unit: "mcg"),
        Item(nutrient: .folate, identifier: "HKQuantityTypeIdentifierDietaryFolate", unit: "mcg"),
        Item(nutrient: .caffeine, identifier: "HKQuantityTypeIdentifierDietaryCaffeine", unit: "mg"),
    ]

    public static let waterIdentifier = "HKQuantityTypeIdentifierDietaryWater"

    /// Sync identifier for an entry's food correlation: HealthKit replaces the sample when the
    /// same identifier comes with a higher version, so edits never duplicate.
    public static func syncIdentifier(entry: UUID) -> String { "nina.entry.\(entry.uuidString)" }
    public static func syncIdentifier(water: UUID) -> String { "nina.water.\(water.uuidString)" }

    /// A version that grows with every edit (seconds since 2001 of the last change).
    public static func syncVersion(modifiedAt: Date) -> Int {
        max(1, Int(modifiedAt.timeIntervalSinceReferenceDate))
    }
}
