import Foundation

/// Which food a diary entry or recipe item came from.
///
/// - `usda:09003`, `nina:topfen-mager` – the bundled catalog
/// - `food:<uuid>` – one of the person's own foods
/// - `recipe:<uuid>` – a recipe or saved meal
/// - empty – a quick entry ("350 kcal") without a food
public struct FoodRef: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespaces)
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public enum Kind: Sendable { case catalog, food, recipe, none }

    public var kind: Kind {
        if rawValue.isEmpty { return .none }
        if rawValue.hasPrefix("food:") { return .food }
        if rawValue.hasPrefix("recipe:") { return .recipe }
        return .catalog
    }

    public static let none = FoodRef("")
    public static func food(_ id: UUID) -> FoodRef { FoodRef("food:" + id.uuidString) }
    public static func recipe(_ id: UUID) -> FoodRef { FoodRef("recipe:" + id.uuidString) }

    /// The UUID of an own food or recipe.
    public var uuid: UUID? {
        guard let colon = rawValue.firstIndex(of: ":") else { return nil }
        return UUID(uuidString: String(rawValue[rawValue.index(after: colon)...]))
    }

    public var isEmpty: Bool { rawValue.isEmpty }
    public var description: String { rawValue }
    public static func < (lhs: FoodRef, rhs: FoodRef) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The amount a food's nutrients refer to.
public enum BaseUnit: String, Codable, Sendable, CaseIterable {
    /// Per 100 g.
    case gram = "g"
    /// Per 100 ml (drinks).
    case milliliter = "ml"
    /// Per serving (recipes without a total weight).
    case serving

    public var symbol: String {
        switch self {
        case .gram: "g"
        case .milliliter: "ml"
        case .serving: "serving"
        }
    }

    /// 100 for g and ml, 1 for servings.
    public var basis: Double { self == .serving ? 1 : 100 }

    /// "ml", "100 ml", "per 100 ml", "l" → milliliter; "serving", "1 portion" → serving; anything else gram.
    public init(text: String) {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let liquid: Set<String> = ["ml", "milliliter", "millilitre", "milliliters", "millilitres", "l", "liter", "litre", "cl", "dl", "liquid"]
        let serving: Set<String> = ["serving", "servings", "portion", "portions"]
        if words.contains(where: liquid.contains) {
            self = .milliliter
        } else if words.contains(where: serving.contains) {
            self = .serving
        } else {
            self = .gram
        }
    }
}

/// Language of food names. The app UI is English; food names follow this setting.
public enum FoodLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    case german = "de"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        }
    }

    /// German for devices set to German, English otherwise.
    public static func preferred(languageCodes: [String]) -> FoodLanguage {
        guard let first = languageCodes.first?.lowercased() else { return .english }
        return first.hasPrefix("de") ? .german : .english
    }
}

/// A household portion: "medium" = 182 g, "slice" = 30 g, "glass" = 250 ml.
public struct Serving: Codable, Hashable, Sendable, Identifiable {
    public var en: String
    public var de: String
    /// In the food's base unit (g or ml; servings for per-serving recipes).
    public var amount: Double

    public init(en: String, de: String = "", amount: Double) {
        self.en = en.trimmingCharacters(in: .whitespaces)
        self.de = de.trimmingCharacters(in: .whitespaces)
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey { case en, de, amount }

    /// The German label is optional in files.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(en: try container.decode(String.self, forKey: .en),
                  de: try container.decodeIfPresent(String.self, forKey: .de) ?? "",
                  amount: try container.decode(Double.self, forKey: .amount))
    }

    public var id: String { en + "|" + NumberText.plain(amount) }

    public func label(_ language: FoodLanguage) -> String {
        language == .german && !de.isEmpty ? de : en
    }

    /// JSON array for a SwiftData string field.
    public static func encode(_ servings: [Serving]) -> String {
        guard !servings.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(servings) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> [Serving] {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Serving].self, from: data)) ?? []
    }

    /// "slice=30;pack=250" (CSV and AI import; "|" works too) → servings. Amounts may carry a unit ("slice=30g").
    public static func parseList(_ text: String) -> [Serving] {
        text.split(whereSeparator: { $0 == "|" || $0 == ";" }).compactMap { part in
            let pieces = part.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { return nil }
            let names = pieces[0].split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let amountText = pieces[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet.letters.union(.whitespaces))
            guard let first = names.first, !first.isEmpty, let amount = NumberText.parse(amountText), amount > 0 else { return nil }
            return Serving(en: first, de: names.count > 1 ? names[1] : "", amount: amount)
        }
    }

    public static func formatList(_ servings: [Serving]) -> String {
        servings.map { serving in
            let name = serving.de.isEmpty ? serving.en : serving.en + "/" + serving.de
            return name + "=" + NumberText.plain(serving.amount)
        }
        .joined(separator: ";")
    }
}

/// Where a food came from.
public enum FoodSource: String, Codable, Sendable {
    case catalog, custom, barcode, imported = "import", recipe
}

/// Any food in a form Core can search, scale and show: a catalog food, an own food or a recipe.
public struct FoodRecord: Identifiable, Hashable, Sendable {
    /// Stable reference (own foods that personalise a catalog food keep the catalog reference).
    public var ref: FoodRef
    /// UUID of the SwiftData record behind it (own foods and recipes).
    public var recordID: UUID?
    public var name: String
    public var nameDE: String
    public var brand: String
    public var category: FoodCategory
    public var unit: BaseUnit
    /// g per ml for drinks (1 when unknown).
    public var density: Double
    /// Per 100 g / 100 ml, or per serving for `.serving`.
    public var nutrients: NutrientValues
    public var servings: [Serving]
    public var aliases: [String]
    public var barcode: String
    public var tags: [String]
    public var isFavorite: Bool
    public var source: FoodSource
    /// Amount used last time / the usual amount, in the base unit (0 = unknown).
    public var usualAmount: Double

    public init(ref: FoodRef, recordID: UUID? = nil, name: String, nameDE: String = "", brand: String = "",
                category: FoodCategory = .other, unit: BaseUnit = .gram, density: Double = 1,
                nutrients: NutrientValues, servings: [Serving] = [], aliases: [String] = [], barcode: String = "",
                tags: [String] = [], isFavorite: Bool = false, source: FoodSource = .custom, usualAmount: Double = 0) {
        self.ref = ref
        self.recordID = recordID
        self.name = name
        self.nameDE = nameDE
        self.brand = brand
        self.category = category
        self.unit = unit
        self.density = density > 0 ? density : 1
        self.nutrients = nutrients
        self.servings = servings
        self.aliases = aliases
        self.barcode = barcode
        self.tags = tags
        self.isFavorite = isFavorite
        self.source = source
        self.usualAmount = usualAmount
    }

    public var id: FoodRef { ref }

    public func displayName(_ language: FoodLanguage) -> String {
        switch language {
        case .german: nameDE.isEmpty ? name : nameDE
        case .english: name.isEmpty ? nameDE : name
        }
    }

    /// The other language's name, if it differs (shown small under the main name).
    public func secondaryName(_ language: FoodLanguage) -> String? {
        let other = language == .german ? name : nameDE
        guard !other.isEmpty, other != displayName(language) else { return nil }
        return other
    }

    /// Nutrients for an amount in the base unit (150 g, 250 ml, 1.5 servings).
    public func nutrients(forAmount amount: Double) -> NutrientValues {
        nutrients.scaled(by: amount / unit.basis)
    }

    /// The portion offered first: the usual amount, else the first household portion, else 100 g/ml or 1 serving.
    public var defaultAmount: Double {
        if usualAmount > 0 { return usualAmount }
        if let first = servings.first { return first.amount }
        return unit.basis
    }

    /// Energy density, for sorting ("lightest first").
    public var energyPer100: Double {
        unit == .serving ? nutrients.energy : nutrients.energy
    }

    /// Protein per 100 kcal – how "protein-rich" a food is, independent of portion size.
    public var proteinPer100kcal: Double {
        let energy = nutrients.energy
        guard energy > 0 else { return 0 }
        return nutrients.protein / energy * 100
    }

    /// Simple, explainable badges ("high protein", "high fiber"), EU claim thresholds.
    public var highlights: [FoodHighlight] {
        guard unit != .serving else { return [] }
        var result: [FoodHighlight] = []
        let energy = nutrients.energy
        if energy > 0, nutrients.protein * 4 / energy >= 0.20 { result.append(.highProtein) }
        if let fiber = nutrients[.fiber], fiber >= 6 { result.append(.highFiber) }
        if unit == .gram, energy <= 40 { result.append(.light) }
        if unit == .milliliter, energy <= 20 { result.append(.light) }
        if let sugar = nutrients[.sugar], sugar <= (unit == .milliliter ? 2.5 : 5), nutrients.carbs > 0 { result.append(.lowSugar) }
        if let sodium = nutrients[.sodium], sodium >= 600 { result.append(.salty) }
        return result
    }
}

/// Badges that follow the EU nutrition-claim thresholds (Regulation 1924/2006), simplified.
public enum FoodHighlight: String, CaseIterable, Sendable {
    case highProtein, highFiber, light, lowSugar, salty

    public var title: String {
        switch self {
        case .highProtein: "High protein"
        case .highFiber: "High fiber"
        case .light: "Light"
        case .lowSugar: "Low sugar"
        case .salty: "Salty"
        }
    }

    public var explanation: String {
        switch self {
        case .highProtein: "At least 20 % of the energy comes from protein."
        case .highFiber: "At least 6 g fiber per 100 g."
        case .light: "At most 40 kcal per 100 g (20 kcal per 100 ml)."
        case .lowSugar: "At most 5 g sugar per 100 g (2.5 g per 100 ml)."
        case .salty: "More than 1.5 g salt per 100 g."
        }
    }
}
