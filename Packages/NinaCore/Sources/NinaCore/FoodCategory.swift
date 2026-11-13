import Foundation

/// Food groups. Stored by raw value; unknown values from newer versions read as `.other`.
public enum FoodCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case fruit, vegetables, legumes, grains, bread, cereals
    case dairy, cheese, eggs, meat, poultry, sausages, fish, plantProtein
    case nuts, fats, sweets, snacks, beverages, alcohol, condiments, spices
    case dishes, fastFood, other

    public var id: String { rawValue }

    public init(text: String) {
        let key = text.trimmingCharacters(in: .whitespaces)
        if let exact = FoodCategory(rawValue: key) {
            self = exact
            return
        }
        let lowered = SearchText.normalize(key)
        if let match = FoodCategory.allCases.first(where: { SearchText.normalize($0.title) == lowered || $0.rawValue.lowercased() == lowered }) {
            self = match
            return
        }
        self = FoodCategory.synonyms[lowered] ?? .other
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodCategory(rawValue: raw) ?? .other
    }

    public var title: String {
        switch self {
        case .fruit: "Fruit"
        case .vegetables: "Vegetables"
        case .legumes: "Legumes"
        case .grains: "Grains, Rice & Pasta"
        case .bread: "Bread & Bakery"
        case .cereals: "Cereals & Oats"
        case .dairy: "Milk & Yogurt"
        case .cheese: "Cheese"
        case .eggs: "Eggs"
        case .meat: "Meat"
        case .poultry: "Poultry"
        case .sausages: "Sausages & Cold Cuts"
        case .fish: "Fish & Seafood"
        case .plantProtein: "Tofu & Plant Protein"
        case .nuts: "Nuts & Seeds"
        case .fats: "Fats & Oils"
        case .sweets: "Sweets & Desserts"
        case .snacks: "Snacks"
        case .beverages: "Drinks"
        case .alcohol: "Alcohol"
        case .condiments: "Sauces & Spreads"
        case .spices: "Spices & Herbs"
        case .dishes: "Dishes"
        case .fastFood: "Fast Food"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .fruit: "🍎"
        case .vegetables: "🥦"
        case .legumes: "🫘"
        case .grains: "🍝"
        case .bread: "🥖"
        case .cereals: "🥣"
        case .dairy: "🥛"
        case .cheese: "🧀"
        case .eggs: "🥚"
        case .meat: "🥩"
        case .poultry: "🍗"
        case .sausages: "🌭"
        case .fish: "🐟"
        case .plantProtein: "🌱"
        case .nuts: "🥜"
        case .fats: "🫒"
        case .sweets: "🍫"
        case .snacks: "🥨"
        case .beverages: "🧃"
        case .alcohol: "🍷"
        case .condiments: "🫙"
        case .spices: "🌿"
        case .dishes: "🍲"
        case .fastFood: "🍔"
        case .other: "🍽️"
        }
    }

    /// Hue (0…1) for the soft background behind the emoji, so groups are recognisable at a glance.
    public var hue: Double {
        switch self {
        case .fruit: 0.98
        case .vegetables: 0.33
        case .legumes: 0.08
        case .grains, .bread, .cereals: 0.11
        case .dairy, .cheese, .eggs: 0.14
        case .meat, .sausages: 0.01
        case .poultry: 0.06
        case .fish: 0.56
        case .plantProtein: 0.28
        case .nuts: 0.07
        case .fats: 0.20
        case .sweets, .snacks: 0.88
        case .beverages: 0.52
        case .alcohol: 0.80
        case .condiments, .spices: 0.25
        case .dishes, .fastFood: 0.04
        case .other: 0.62
        }
    }

    /// Words people (and AIs writing an import file) use for the groups.
    static let synonyms: [String: FoodCategory] = [
        "fruits": .fruit, "obst": .fruit, "fruchte": .fruit,
        "vegetable": .vegetables, "veggies": .vegetables, "gemuse": .vegetables, "salad": .vegetables, "salat": .vegetables,
        "legume": .legumes, "pulses": .legumes, "hulsenfruchte": .legumes, "beans": .legumes,
        "grain": .grains, "rice": .grains, "pasta": .grains, "getreide": .grains, "nudeln": .grains, "reis": .grains,
        "bakery": .bread, "brot": .bread, "geback": .bread, "backwaren": .bread,
        "cereal": .cereals, "muesli": .cereals, "musli": .cereals, "oats": .cereals, "breakfast": .cereals,
        "milk": .dairy, "yogurt": .dairy, "yoghurt": .dairy, "milchprodukte": .dairy, "milch": .dairy, "joghurt": .dairy,
        "kase": .cheese, "egg": .eggs, "eier": .eggs, "fleisch": .meat, "beef": .meat, "pork": .meat,
        "chicken": .poultry, "geflugel": .poultry, "turkey": .poultry,
        "wurst": .sausages, "cold cuts": .sausages, "deli": .sausages, "aufschnitt": .sausages,
        "seafood": .fish, "fisch": .fish, "meeresfruchte": .fish,
        "tofu": .plantProtein, "vegan": .plantProtein, "plant protein": .plantProtein,
        "nut": .nuts, "seeds": .nuts, "nusse": .nuts, "samen": .nuts,
        "oil": .fats, "oils": .fats, "fett": .fats, "ole": .fats, "butter": .fats,
        "sweet": .sweets, "dessert": .sweets, "desserts": .sweets, "candy": .sweets, "susses": .sweets, "sussigkeiten": .sweets, "kuchen": .sweets,
        "snack": .snacks, "chips": .snacks, "knabbereien": .snacks,
        "drinks": .beverages, "drink": .beverages, "beverage": .beverages, "getranke": .beverages,
        "alkohol": .alcohol, "beer": .alcohol, "wine": .alcohol,
        "sauce": .condiments, "sauces": .condiments, "spreads": .condiments, "condiment": .condiments, "sossen": .condiments, "aufstrich": .condiments,
        "spice": .spices, "herbs": .spices, "gewurze": .spices, "krauter": .spices,
        "dish": .dishes, "meals": .dishes, "meal": .dishes, "gerichte": .dishes, "soup": .dishes, "suppe": .dishes,
        "fast food": .fastFood, "fastfood": .fastFood, "takeaway": .fastFood,
        "supplements": .other, "sonstiges": .other,
    ]
}
