import Foundation
import BinisoftKitCore

/// Which of Nina's three CSV formats a file is.
public enum ImportKind: String, CaseIterable, Sendable, Identifiable {
    case foods, diary, recipes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .foods: "Foods"
        case .diary: "Diary"
        case .recipes: "Meals & Recipes"
        }
    }

    public var subtitle: String {
        switch self {
        case .foods: "Your foods with their nutrition values – from labels, a spreadsheet or another app."
        case .diary: "What you ate on which day – e.g. an export from another app."
        case .recipes: "Saved meals (logged together) and recipes (cooked, then eaten in portions)."
        }
    }

    /// Guesses the format from the header line.
    public static func detect(_ text: String) -> ImportKind? {
        let header = CSV.records(text).header.map(ImportColumns.canonical)
        let set = Set(header)
        if set.contains("recipe") || set.contains("ingredient") { return .recipes }
        if set.contains("date") { return .diary }
        if set.contains("name") || set.contains("food") { return .foods }
        return nil
    }
}

/// Column names: canonical keys plus the variants people and AIs write ("Energy (kcal)",
/// "Kalorien", "Eiweiß", "davon Zucker").
public enum ImportColumns {
    /// "Energy (kcal)" → "energy_kcal", "Gesättigte Fettsäuren" → "gesattigte_fettsauren"
    public static func normalize(_ header: String) -> String {
        var text = header
        if let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            let unit = text[text.index(after: open)..<close]
            text = String(text[..<open]) + " " + unit
        }
        return SearchText.normalize(text).replacingOccurrences(of: " ", with: "_")
    }

    static let aliases: [String: String] = {
        var map: [String: String] = [:]
        let groups: [String: [String]] = [
            "id": ["id", "key", "nr", "number", "row_id"],
            "name": ["name", "food_name", "product", "product_name", "lebensmittel", "bezeichnung", "title"],
            "name_de": ["name_de", "german_name", "name_german", "deutsch", "name_deutsch"],
            "food": ["food", "item", "food_item", "speise"],
            "brand": ["brand", "brands", "marke", "hersteller", "manufacturer"],
            "category": ["category", "kategorie", "group", "food_group", "gruppe"],
            "tags": ["tags", "tag", "labels", "schlagworter"],
            "unit": ["unit", "einheit", "per", "basis", "base_unit"],
            "kcal": ["kcal", "energy_kcal", "calories", "kalorien", "energy", "energie", "calories_kcal", "kcal_100g", "energy_kcal_100g", "brennwert", "brennwert_kcal", "energie_kcal"],
            "kj": ["kj", "energy_kj", "kilojoule", "kilojoules", "brennwert_kj", "energie_kj"],
            "protein": ["protein", "proteins", "protein_g", "eiweiss", "eiweiss_g", "proteine"],
            "carbs": ["carbs", "carbohydrates", "carbohydrate", "carbs_g", "carbohydrates_g", "kohlenhydrate", "kh", "kohlenhydrate_g"],
            "fat": ["fat", "fat_g", "total_fat", "fett", "fett_g"],
            "fiber": ["fiber", "fibre", "fiber_g", "fibre_g", "ballaststoffe", "dietary_fiber", "ballaststoffe_g"],
            "sugar": ["sugar", "sugars", "sugar_g", "sugars_g", "zucker", "davon_zucker", "zucker_g"],
            "saturated_fat": ["saturated_fat", "saturates", "sat_fat", "saturated", "saturated_fat_g", "gesattigte_fettsauren", "davon_gesattigte_fettsauren", "gesattigte_fette"],
            "salt": ["salt", "salt_g", "salz", "salz_g"],
            "sodium_mg": ["sodium_mg", "sodium", "natrium", "natrium_mg"],
            "portions": ["portions", "portionen", "serving_sizes", "portion_sizes", "household_portions"],
            "barcode": ["barcode", "ean", "gtin", "upc", "code", "strichcode"],
            "favorite": ["favorite", "favourite", "fav", "favorit", "starred"],
            "notes": ["notes", "note", "notiz", "notizen", "comment", "kommentar"],
            "date": ["date", "datum", "day", "tag_datum"],
            "time": ["time", "uhrzeit", "zeit"],
            "meal": ["meal", "mahlzeit", "meal_type"],
            "amount": ["amount", "quantity", "menge", "anzahl", "qty"],
            "grams": ["grams", "gram", "g", "gramm", "weight", "weight_g", "gewicht", "amount_g", "ml"],
            "status": ["status", "state"],
            "recipe": ["recipe", "rezept", "meal_name", "recipe_name"],
            "kind": ["kind", "type", "art", "typ"],
            "servings": ["servings_count", "recipe_servings", "anzahl_portionen", "yield", "servings"],
            "total_weight_g": ["total_weight_g", "total_weight", "cooked_weight", "gesamtgewicht", "weight_cooked"],
            "ingredient": ["ingredient", "zutat", "ingredient_name"],
            "monounsaturated_fat": ["monounsaturated_fat", "mufa", "einfach_ungesattigte_fettsauren"],
            "polyunsaturated_fat": ["polyunsaturated_fat", "pufa", "mehrfach_ungesattigte_fettsauren"],
            "trans_fat": ["trans_fat", "transfett", "trans_fettsauren"],
            "cholesterol_mg": ["cholesterol_mg", "cholesterol", "cholesterin"],
            "potassium_mg": ["potassium_mg", "potassium", "kalium"],
            "calcium_mg": ["calcium_mg", "calcium", "kalzium"],
            "iron_mg": ["iron_mg", "iron", "eisen"],
            "magnesium_mg": ["magnesium_mg", "magnesium"],
            "zinc_mg": ["zinc_mg", "zinc", "zink"],
            "vitamin_a_ug": ["vitamin_a_ug", "vitamin_a", "vitamin_a_µg", "vitamin_a_mcg"],
            "vitamin_c_mg": ["vitamin_c_mg", "vitamin_c"],
            "vitamin_d_ug": ["vitamin_d_ug", "vitamin_d", "vitamin_d_µg", "vitamin_d_mcg"],
            "vitamin_e_mg": ["vitamin_e_mg", "vitamin_e"],
            "vitamin_b12_ug": ["vitamin_b12_ug", "vitamin_b12", "b12", "vitamin_b12_µg", "vitamin_b12_mcg"],
            "folate_ug": ["folate_ug", "folate", "folsaure", "folic_acid", "folate_µg", "folate_mcg"],
            "water_g": ["water_g", "water", "wasser"],
            "alcohol_g": ["alcohol_g", "alcohol", "alkohol"],
            "caffeine_mg": ["caffeine_mg", "caffeine", "koffein"],
        ]
        for (canonical, names) in groups {
            for name in names { map[normalize(name)] = canonical }
        }
        return map
    }()

    /// The canonical key for a header cell (unknown headers keep their normalised text).
    public static func canonical(_ header: String) -> String {
        let key = normalize(header)
        return aliases[key] ?? key
    }

    /// CSV rows with canonical keys.
    public static func records(_ text: String) -> (header: [String], rows: [[String: String]]) {
        let table = CSV.parse(text)
        guard let first = table.first else { return ([], []) }
        let keys = first.map(canonical)
        let rows = table.dropFirst().map { values -> [String: String] in
            var record: [String: String] = [:]
            for (index, key) in keys.enumerated() where index < values.count {
                let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                // The first non-empty column wins when two headers map to the same key.
                if record[key]?.isEmpty ?? true { record[key] = value }
            }
            return record
        }
        return (keys, Array(rows))
    }

    /// Nutrient columns shared by every format (energy handled separately: kcal or kJ).
    static let nutrientColumns: [(column: String, nutrient: Nutrient)] = [
        ("protein", .protein), ("carbs", .carbs), ("fat", .fat), ("fiber", .fiber), ("sugar", .sugar),
        ("saturated_fat", .saturatedFat), ("monounsaturated_fat", .monoFat), ("polyunsaturated_fat", .polyFat),
        ("trans_fat", .transFat), ("cholesterol_mg", .cholesterol), ("potassium_mg", .potassium),
        ("calcium_mg", .calcium), ("iron_mg", .iron), ("magnesium_mg", .magnesium), ("zinc_mg", .zinc),
        ("vitamin_a_ug", .vitaminA), ("vitamin_c_mg", .vitaminC), ("vitamin_d_ug", .vitaminD),
        ("vitamin_e_mg", .vitaminE), ("vitamin_b12_ug", .vitaminB12), ("folate_ug", .folate),
        ("water_g", .water), ("alcohol_g", .alcohol), ("caffeine_mg", .caffeine),
    ]

    /// Reads the nutrient columns of a row. Energy from kcal, else kJ; sodium from sodium_mg, else salt.
    static func nutrients(_ record: [String: String]) -> NutrientValues {
        var values = NutrientValues()
        if let kcal = number(record["kcal"]) {
            values[.energy] = kcal
        } else if let kj = number(record["kj"]) {
            values[.energy] = kj / EnergyUnit.kilojoulesPerKilocalorie
        }
        for (column, nutrient) in nutrientColumns {
            if let value = number(record[column]) { values[nutrient] = value }
        }
        if let sodium = number(record["sodium_mg"]) {
            values[.sodium] = sodium
        } else if let salt = number(record["salt"]) {
            values[.sodium] = NutrientValues.sodium(fromSalt: salt)
        }
        return values
    }

    /// The nutrient cells written by every export, in this order.
    static let exportNutrients: [(column: String, value: (NutrientValues) -> Double?)] = [
        ("kcal", { $0[.energy] }), ("protein", { $0[.protein] }), ("carbs", { $0[.carbs] }), ("fat", { $0[.fat] }),
        ("fiber", { $0[.fiber] }), ("sugar", { $0[.sugar] }), ("saturated_fat", { $0[.saturatedFat] }), ("salt", { $0.salt }),
    ]

    static func exportCells(_ values: NutrientValues) -> [String] {
        exportNutrients.map { item in item.value(values).map { NumberText.plain($0, decimals: 2) } ?? "" }
    }

    /// "1,5" and "1.5" and "1.234,5"; units glued to the number are ignored ("120 kcal", "4,5g").
    static func number(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        text = text.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "µ%")))
        guard !text.isEmpty, text != "-", text != "–" else { return nil }
        if text.contains(","), text.contains(".") {
            // 1.234,5 (German) or 1,234.5 (English)
            if let comma = text.lastIndex(of: ","), let dot = text.lastIndex(of: "."), comma > dot {
                text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        }
        guard let value = NumberText.parse(text), value >= 0 else { return nil }
        return value
    }

    static func isYes(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return ["yes", "y", "true", "1", "x", "ja", "j", "✓", "✔", "★", "fav", "favorite"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func list(_ raw: String?) -> [String] {
        (raw ?? "").split(whereSeparator: { $0 == "," || $0 == "|" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// "id:7" → "7"; content keys stay as they are.
    public static func exportID(forKey key: String) -> String {
        key.hasPrefix("id:") ? String(key.dropFirst(3)) : key
    }

    /// Every key a stored record answers to (its import key and the key its exported row comes back with).
    public static func lookupKeys(forKey key: String) -> [String] {
        let exported = "id:" + exportID(forKey: key)
        return exported == key ? [key] : [key, exported]
    }
}
