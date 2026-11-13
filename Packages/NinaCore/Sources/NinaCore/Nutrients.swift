import Foundation

/// Every nutrient Nina knows. Foods carry values per 100 g / 100 ml (or per serving for recipes
/// without a weight); diary entries carry the totals of what was eaten.
public enum Nutrient: String, CaseIterable, Codable, Sendable, Identifiable {
    case energy, protein, carbs, fat, fiber, sugar
    case saturatedFat, monoFat, polyFat, transFat, cholesterol
    case sodium, potassium, calcium, iron, magnesium, zinc
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminB12, folate
    case water, alcohol, caffeine

    public var id: String { rawValue }

    public enum Measure: String, Sendable {
        case kilocalories, grams, milligrams, micrograms

        public var symbol: String {
            switch self {
            case .kilocalories: "kcal"
            case .grams: "g"
            case .milligrams: "mg"
            case .micrograms: "µg"
            }
        }
    }

    public var measure: Measure {
        switch self {
        case .energy: .kilocalories
        case .protein, .carbs, .fat, .fiber, .sugar, .saturatedFat, .monoFat, .polyFat, .transFat, .water, .alcohol: .grams
        case .cholesterol, .sodium, .potassium, .calcium, .iron, .magnesium, .zinc, .vitaminC, .vitaminE, .caffeine: .milligrams
        case .vitaminA, .vitaminD, .vitaminB12, .folate: .micrograms
        }
    }

    public var title: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbohydrates"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .saturatedFat: "Saturated fat"
        case .monoFat: "Monounsaturated fat"
        case .polyFat: "Polyunsaturated fat"
        case .transFat: "Trans fat"
        case .cholesterol: "Cholesterol"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .magnesium: "Magnesium"
        case .zinc: "Zinc"
        case .vitaminA: "Vitamin A"
        case .vitaminC: "Vitamin C"
        case .vitaminD: "Vitamin D"
        case .vitaminE: "Vitamin E"
        case .vitaminB12: "Vitamin B12"
        case .folate: "Folate"
        case .water: "Water"
        case .alcohol: "Alcohol"
        case .caffeine: "Caffeine"
        }
    }

    /// Short label for chips, rings and the watch.
    public var shortTitle: String {
        switch self {
        case .energy: "Calories"
        case .carbs: "Carbs"
        case .saturatedFat: "Sat. fat"
        case .monoFat: "Mono fat"
        case .polyFat: "Poly fat"
        case .vitaminB12: "B12"
        default: title
        }
    }

    /// One letter for very small places (watch rings, widgets).
    public var letter: String {
        switch self {
        case .protein: "P"
        case .carbs: "C"
        case .fat: "F"
        case .fiber: "Fi"
        default: String(title.prefix(1))
        }
    }

    /// What a nutrition label shows, in EU label order (energy, fat, saturates, carbs, sugars, fiber, protein, salt).
    public static let label: [Nutrient] = [.energy, .fat, .saturatedFat, .carbs, .sugar, .fiber, .protein, .sodium]
    /// The big three besides energy.
    public static let macros: [Nutrient] = [.protein, .carbs, .fat]
    public static let fats: [Nutrient] = [.saturatedFat, .monoFat, .polyFat, .transFat, .cholesterol]
    public static let minerals: [Nutrient] = [.sodium, .potassium, .calcium, .iron, .magnesium, .zinc]
    public static let vitamins: [Nutrient] = [.vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminB12, .folate]
    public static let other: [Nutrient] = [.water, .alcohol, .caffeine]

    /// Reference intake for an average adult: EU Regulation 1169/2011 (energy, macros, salt,
    /// vitamins, minerals) and EFSA for fiber. Used for "% of reference" when no own target exists.
    public var referenceIntake: Double? {
        switch self {
        case .energy: 2000
        case .fat: 70
        case .saturatedFat: 20
        case .carbs: 260
        case .sugar: 90
        case .protein: 50
        case .fiber: 25
        case .sodium: 2400
        case .potassium: 2000
        case .calcium: 800
        case .iron: 14
        case .magnesium: 375
        case .zinc: 10
        case .vitaminA: 800
        case .vitaminC: 80
        case .vitaminD: 5
        case .vitaminE: 12
        case .vitaminB12: 2.5
        case .folate: 200
        case .cholesterol: 300
        case .caffeine: 400
        case .monoFat, .polyFat, .transFat, .water, .alcohol: nil
        }
    }

    /// For these, less is better: a target is a limit, not something to reach.
    public var isLimit: Bool {
        switch self {
        case .sugar, .saturatedFat, .transFat, .sodium, .cholesterol, .alcohol, .caffeine: true
        default: false
        }
    }

    /// kcal per gram (Atwater factors) for the nutrients that carry energy.
    public var kilocaloriesPerGram: Double? {
        switch self {
        case .protein, .carbs: 4
        case .fat: 9
        case .alcohol: 7
        default: nil
        }
    }
}

/// A set of nutrient values. Missing means unknown (not zero): a food without a fiber value
/// shows "–", not "0 g".
public struct NutrientValues: Equatable, Hashable, Sendable {
    public private(set) var storage: [Nutrient: Double]

    public init(_ values: [Nutrient: Double] = [:]) {
        storage = values.filter { $0.value.isFinite }
    }

    public static let zero = NutrientValues([.energy: 0, .protein: 0, .carbs: 0, .fat: 0])

    public subscript(_ nutrient: Nutrient) -> Double? {
        get { storage[nutrient] }
        set {
            if let newValue, newValue.isFinite {
                storage[nutrient] = newValue
            } else {
                storage[nutrient] = nil
            }
        }
    }

    /// The value, or 0 when unknown.
    public func value(_ nutrient: Nutrient) -> Double { storage[nutrient] ?? 0 }

    public var energy: Double { value(.energy) }
    public var protein: Double { value(.protein) }
    public var carbs: Double { value(.carbs) }
    public var fat: Double { value(.fat) }

    public var isEmpty: Bool { storage.isEmpty }
    public var known: [Nutrient] { Nutrient.allCases.filter { storage[$0] != nil } }

    public func scaled(by factor: Double) -> NutrientValues {
        guard factor.isFinite else { return self }
        return NutrientValues(storage.mapValues { $0 * factor })
    }

    /// Sum: a nutrient known on either side is known in the result (unknown counts as 0 there).
    public static func + (lhs: NutrientValues, rhs: NutrientValues) -> NutrientValues {
        var result = lhs.storage
        for (key, value) in rhs.storage { result[key, default: 0] += value }
        return NutrientValues(result)
    }

    public static func += (lhs: inout NutrientValues, rhs: NutrientValues) {
        lhs = lhs + rhs
    }

    public static func sum<S: Sequence>(_ values: S) -> NutrientValues where S.Element == NutrientValues {
        values.reduce(NutrientValues()) { $0 + $1 }
    }

    // MARK: Salt (EU labels) and sodium (USDA)

    /// Salt in grams = sodium (mg) × 2.5 / 1000.
    public var salt: Double? { storage[.sodium].map { $0 * 2.5 / 1000 } }

    public static func sodium(fromSalt grams: Double) -> Double { grams / 2.5 * 1000 }

    // MARK: Energy from macros

    /// kcal from protein, carbs, fat and alcohol (4 / 4 / 9 / 7).
    public var energyFromMacros: Double {
        4 * protein + 4 * carbs + 9 * fat + 7 * value(.alcohol)
    }

    /// Share of the macro energy that comes from protein, carbs and fat (0…1 each, alcohol aside).
    public var macroShares: MacroShares {
        let p = 4 * protein, c = 4 * carbs, f = 9 * fat
        let total = p + c + f
        guard total > 0 else { return MacroShares(protein: 0, carbs: 0, fat: 0) }
        return MacroShares(protein: p / total, carbs: c / total, fat: f / total)
    }

    // MARK: Text encoding (SwiftData / CloudKit field, CSV)

    /// "energy=52;protein=0.26;carbs=13.81" – locale independent, unknown nutrients left out,
    /// unknown keys from newer versions ignored when decoding.
    public var encoded: String {
        Nutrient.allCases.compactMap { nutrient in
            storage[nutrient].map { "\(nutrient.rawValue)=\(NumberText.plain($0))" }
        }
        .joined(separator: ";")
    }

    public init(encoded: String) {
        var values: [Nutrient: Double] = [:]
        for pair in encoded.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let nutrient = Nutrient(rawValue: parts[0].trimmingCharacters(in: .whitespaces)),
                  let value = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            values[nutrient] = value
        }
        self.init(values)
    }
}

extension NutrientValues: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: Double].self)
        var values: [Nutrient: Double] = [:]
        for (key, value) in raw {
            if let nutrient = Nutrient(rawValue: key) { values[nutrient] = value }
        }
        self.init(values)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var raw: [String: Double] = [:]
        for (key, value) in storage { raw[key.rawValue] = value }
        try container.encode(raw)
    }
}

/// Where the energy comes from.
public struct MacroShares: Equatable, Sendable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(protein: Double, carbs: Double, fat: Double) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    /// "25 / 45 / 30"
    public var percentText: String {
        [protein, carbs, fat].map { String(Int(($0 * 100).rounded())) }.joined(separator: " / ")
    }
}

/// Energy unit for display. Stored values are always kcal.
public enum EnergyUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case kcal, kJ

    public var id: String { rawValue }
    public static let kilojoulesPerKilocalorie = 4.184

    public func value(fromKilocalories kcal: Double) -> Double {
        self == .kcal ? kcal : kcal * Self.kilojoulesPerKilocalorie
    }

    public func kilocalories(from value: Double) -> Double {
        self == .kcal ? value : value / Self.kilojoulesPerKilocalorie
    }

    public var symbol: String { rawValue }
}
