import Foundation

/// Barcode lookups: one product at a time from Open Food Facts (open data, ODbL). The app does
/// the request; this turns the JSON into a food the person reviews before saving.
public enum OpenFoodFacts {
    /// `https://world.openfoodfacts.org/api/v2/product/<code>.json?fields=…`
    public static func productURL(barcode: String) -> URL? {
        let digits = barcode.filter(\.isNumber)
        guard digits.count >= 6 else { return nil }
        let fields = "code,product_name,product_name_en,product_name_de,generic_name,brands,quantity,serving_size,serving_quantity,nutriments,categories_tags,product_quantity_unit,nutrition_data_per"
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)")
    }

    /// Open Food Facts asks every app to identify itself.
    public static func userAgent(appName: String, version: String, platform: String) -> String {
        "\(appName)/\(version) (\(platform); https://github.com/Binisoft-at/nina)"
    }

    public enum LookupError: Error, Equatable, Sendable {
        case notFound
        case noNutrition(name: String)
        case unreadable
    }

    /// The product as a draft food (values per 100 g / 100 ml).
    public static func parse(_ data: Data, barcode: String) -> Result<FoodDraft, LookupError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.unreadable) }
        if let status = object["status"] as? Int, status == 0 { return .failure(.notFound) }
        guard let product = object["product"] as? [String: Any] else { return .failure(.notFound) }

        let nameEN = text(product["product_name_en"])
        let nameDE = text(product["product_name_de"])
        let generic = text(product["product_name"]) ?? text(product["generic_name"])
        let name = nameEN ?? generic ?? nameDE ?? "Product \(barcode)"
        let brand = text(product["brands"]).map { $0.split(separator: ",").first.map(String.init) ?? $0 }?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let categories = (product["categories_tags"] as? [String]) ?? []
        let quantityText = text(product["quantity"]) ?? ""
        let unitHint = (text(product["product_quantity_unit"]) ?? "").lowercased()
        let isLiquid = unitHint == "ml" || unitHint == "l" || containsVolume(quantityText) || categories.contains("en:beverages")

        let nutriments = (product["nutriments"] as? [String: Any]) ?? [:]
        var values = NutrientValues()
        if let kcal = number(nutriments["energy-kcal_100g"]) {
            values[.energy] = kcal
        } else if let kj = number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy_100g"]) {
            values[.energy] = kj / EnergyUnit.kilojoulesPerKilocalorie
        }
        let grams: [(String, Nutrient)] = [
            ("proteins_100g", .protein), ("carbohydrates_100g", .carbs), ("fat_100g", .fat), ("fiber_100g", .fiber),
            ("sugars_100g", .sugar), ("saturated-fat_100g", .saturatedFat), ("monounsaturated-fat_100g", .monoFat),
            ("polyunsaturated-fat_100g", .polyFat), ("trans-fat_100g", .transFat), ("alcohol_100g", .alcohol),
        ]
        for (key, nutrient) in grams {
            if let value = number(nutriments[key]) { values[nutrient] = value }
        }
        // Open Food Facts stores minerals and vitamins in grams.
        let scaled: [(String, Nutrient, Double)] = [
            ("cholesterol_100g", .cholesterol, 1000), ("potassium_100g", .potassium, 1000), ("calcium_100g", .calcium, 1000),
            ("iron_100g", .iron, 1000), ("magnesium_100g", .magnesium, 1000), ("zinc_100g", .zinc, 1000),
            ("vitamin-c_100g", .vitaminC, 1000), ("vitamin-a_100g", .vitaminA, 1_000_000), ("vitamin-d_100g", .vitaminD, 1_000_000),
            ("vitamin-b12_100g", .vitaminB12, 1_000_000), ("caffeine_100g", .caffeine, 1000),
        ]
        for (key, nutrient, factor) in scaled {
            if let value = number(nutriments[key]) { values[nutrient] = value * factor }
        }
        if let sodium = number(nutriments["sodium_100g"]) {
            values[.sodium] = sodium * 1000
        } else if let salt = number(nutriments["salt_100g"]) {
            values[.sodium] = NutrientValues.sodium(fromSalt: salt)
        }
        guard values[.energy] != nil else { return .failure(.noNutrition(name: name)) }
        for nutrient in [Nutrient.protein, .carbs, .fat] where values[nutrient] == nil { values[nutrient] = 0 }

        var servings: [Serving] = []
        if let serving = number(product["serving_quantity"]), serving > 0 {
            let label = text(product["serving_size"]) ?? "serving"
            servings.append(Serving(en: "serving (\(label))", de: "Portion (\(label))", amount: serving))
        }
        if let packageAmount = amount(in: quantityText), packageAmount > 0, packageAmount <= 3000 {
            servings.append(Serving(en: "package (\(quantityText))", de: "Packung (\(quantityText))", amount: packageAmount))
        }

        return .success(FoodDraft(
            name: name,
            nameDE: nameDE ?? (nameEN == nil ? "" : generic ?? ""),
            brand: brand,
            category: category(from: categories),
            unit: isLiquid ? .milliliter : .gram,
            nutrients: values,
            servings: servings,
            barcode: barcode.filter(\.isNumber),
            notes: "From Open Food Facts (ODbL). Check the values against the package."
        ))
    }

    static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? Double { return number.isFinite ? number : nil }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String { return ImportColumns.number(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    /// "330 ml", "1,5 l", "75cl" → true; "500 g", "1 kg" → false.
    static func containsVolume(_ text: String) -> Bool {
        let lowered = text.lowercased()
        var index = lowered.startIndex
        while index < lowered.endIndex {
            if lowered[index].isNumber {
                var cursor = index
                while cursor < lowered.endIndex, lowered[cursor].isNumber || lowered[cursor] == "." || lowered[cursor] == "," || lowered[cursor] == " " {
                    cursor = lowered.index(after: cursor)
                }
                let unit = lowered[cursor...].prefix(while: { $0.isLetter })
                if ["ml", "cl", "dl", "l", "liter", "litre", "liters", "litres"].contains(String(unit)) { return true }
                index = cursor
            } else {
                index = lowered.index(after: index)
            }
        }
        return false
    }

    /// "500 g" → 500, "1,5 l" → 1500, "330 ml" → 330.
    static func amount(in text: String) -> Double? {
        let lowered = text.lowercased().replacingOccurrences(of: ",", with: ".")
        var digits = ""
        var rest = Substring(lowered)
        while let first = rest.first, first == " " { rest = rest.dropFirst() }
        while let first = rest.first, first.isNumber || first == "." {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard let value = Double(digits) else { return nil }
        let unit = rest.trimmingCharacters(in: .whitespaces)
        if unit.hasPrefix("kg") { return value * 1000 }
        if unit.hasPrefix("ml") || unit.hasPrefix("g") { return value }
        if unit.hasPrefix("cl") { return value * 10 }
        if unit.hasPrefix("l") { return value * 1000 }
        return nil
    }

    static func category(from tags: [String]) -> FoodCategory {
        let checks: [(String, FoodCategory)] = [
            ("alcoholic-beverages", .alcohol), ("beers", .alcohol), ("wines", .alcohol),
            ("plant-based-milk", .beverages), ("beverages", .beverages),
            ("cheeses", .cheese), ("yogurts", .dairy), ("milks", .dairy), ("dairies", .dairy),
            ("eggs", .eggs), ("breakfast-cereals", .cereals), ("breads", .bread), ("pastas", .grains), ("rices", .grains),
            ("sausages", .sausages), ("hams", .sausages), ("meats", .meat), ("poultry", .poultry),
            ("fishes", .fish), ("seafood", .fish), ("tofu", .plantProtein), ("meat-analogues", .plantProtein),
            ("nuts", .nuts), ("seeds", .nuts), ("fats", .fats), ("vegetable-oils", .fats),
            ("chocolates", .sweets), ("biscuits", .sweets), ("cakes", .sweets), ("confectioneries", .sweets), ("desserts", .sweets),
            ("chips", .snacks), ("salty-snacks", .snacks), ("snacks", .snacks),
            ("sauces", .condiments), ("condiments", .condiments), ("spreads", .condiments), ("jams", .condiments), ("honeys", .condiments),
            ("spices", .spices), ("fruits", .fruit), ("vegetables", .vegetables), ("legumes", .legumes),
            ("meals", .dishes), ("pizzas", .dishes), ("soups", .dishes), ("sandwiches", .fastFood),
        ]
        for (fragment, category) in checks where tags.contains(where: { $0.hasPrefix("en:") && $0.contains(fragment) }) {
            return category
        }
        return .other
    }
}
