import Foundation
import BinisoftKitCore

/// A saved meal is logged as its separate foods ("my usual breakfast"); a recipe is cooked once
/// and eaten in portions or by weight (one diary entry).
public enum RecipeKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case meal, recipe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .meal: "Meal"
        case .recipe: "Recipe"
        }
    }

    public init(text: String) {
        switch SearchText.normalize(text) {
        case "recipe", "rezept", "dish", "gericht": self = .recipe
        default: self = .meal
        }
    }
}

public struct RecipeItemDraft: Equatable, Sendable {
    public var name: String
    public var quantity: Double
    public var unitLabel: String
    /// g/ml (0 when unknown).
    public var amount: Double
    public var unit: BaseUnit
    /// Totals for this ingredient. Empty energy → the app looks it up by name.
    public var nutrients: NutrientValues

    public init(name: String, quantity: Double = 1, unitLabel: String = "", amount: Double = 0, unit: BaseUnit = .gram,
                nutrients: NutrientValues = NutrientValues()) {
        self.name = name
        self.quantity = quantity
        self.unitLabel = unitLabel
        self.amount = amount
        self.unit = unit
        self.nutrients = nutrients
    }

    public var needsLookup: Bool { nutrients[.energy] == nil }
}

public struct RecipeDraft: Equatable, Sendable {
    public var name: String
    public var kind: RecipeKind
    public var servings: Double
    /// Cooked weight in g (0 = sum of the ingredients).
    public var totalWeight: Double
    public var notes: String
    public var items: [RecipeItemDraft]

    public init(name: String, kind: RecipeKind = .meal, servings: Double = 1, totalWeight: Double = 0, notes: String = "",
                items: [RecipeItemDraft] = []) {
        self.name = name
        self.kind = kind
        self.servings = servings
        self.totalWeight = totalWeight
        self.notes = notes
        self.items = items
    }
}

/// Totals, portions and per-100 g values of a recipe.
public enum RecipeMath {
    public static func totals(_ items: [NutrientValues]) -> NutrientValues {
        NutrientValues.sum(items)
    }

    /// The weight the per-100 g values refer to: the cooked weight if known, else the raw ingredients' weight.
    public static func weight(items: [(amount: Double, unit: BaseUnit)], cookedWeight: Double) -> Double {
        if cookedWeight > 0 { return cookedWeight }
        return items.filter { $0.unit != .serving }.map(\.amount).reduce(0, +)
    }

    /// A recipe as a food: per 100 g when its weight is known, otherwise per serving.
    public static func record(ref: FoodRef, recordID: UUID?, name: String, totals: NutrientValues, servings: Double,
                              weight: Double, isFavorite: Bool = false, tags: [String] = []) -> FoodRecord {
        let portions = max(servings, 1)
        if weight > 0 {
            let per100 = totals.scaled(by: 100 / weight)
            let portion = Serving(en: "serving", de: "Portion", amount: weight / portions)
            return FoodRecord(ref: ref, recordID: recordID, name: name, category: .dishes, unit: .gram, nutrients: per100,
                              servings: [portion], tags: tags, isFavorite: isFavorite, source: .recipe)
        }
        return FoodRecord(ref: ref, recordID: recordID, name: name, category: .dishes, unit: .serving,
                          nutrients: totals.scaled(by: 1 / portions), servings: [], tags: tags, isFavorite: isFavorite, source: .recipe)
    }
}

/// Nina's meals & recipes CSV: one row per ingredient; rows with the same recipe name belong together.
public enum RecipeCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("recipe", "Name of the meal or recipe (the same on every row of it).", required: true),
        .init("kind", "meal (several foods logged together, e.g. my usual breakfast) or recipe (cooked once, eaten in portions)."),
        .init("servings", "How many portions the recipe makes (recipes only)."),
        .init("total_weight_g", "Cooked weight of the whole recipe in g, if known."),
        .init("ingredient", "One food of the meal or recipe.", required: true),
        .init("amount", "How many of unit."),
        .init("unit", "g, ml, or a portion word like piece, slice, tbsp."),
        .init("grams", "Weight in g (ml for liquids) of this ingredient."),
        .init("kcal", "Total kcal of this ingredient amount (not per 100 g). Leave empty if unknown – the app looks it up."),
        .init("protein", "Total protein in g."),
        .init("carbs", "Total carbohydrates in g."),
        .init("fat", "Total fat in g."),
        .init("fiber", "Total fiber in g."),
        .init("sugar", "Total sugar in g."),
        .init("saturated_fat", "Total saturated fat in g."),
        .init("salt", "Total salt in g."),
        .init("notes", "Notes for the recipe (preparation), on its first row."),
    ]

    public static var header: [String] { columns.map(\.name) }

    public struct Parsed {
        public var rows: [(key: String, draft: RecipeDraft)]
        public var skipped: [String]
    }

    public static func parse(_ text: String) -> Parsed {
        let (header, records) = ImportColumns.records(text)
        guard header.contains("recipe") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}recipe\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        var order: [String] = []
        var drafts: [String: RecipeDraft] = [:]
        var skipped: [String] = []
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let name = (record["recipe"] ?? "").trimmingCharacters(in: .whitespaces)
            let ingredient = (record["ingredient"] ?? record["food"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                skipped.append("Row \(line): no recipe name")
                continue
            }
            let key = "recipe:" + ImportPlan<RecipeDraft>.contentKey([name])
            var draft = drafts[key] ?? RecipeDraft(name: name)
            if drafts[key] == nil { order.append(key) }
            if let kind = record["kind"], !kind.isEmpty { draft.kind = RecipeKind(text: kind) }
            if let servings = ImportColumns.number(record["servings"]), servings > 0 { draft.servings = servings }
            if let weight = ImportColumns.number(record["total_weight_g"]), weight > 0 { draft.totalWeight = weight }
            if let notes = record["notes"], !notes.isEmpty, draft.notes.isEmpty { draft.notes = notes }
            if !ingredient.isEmpty {
                let unitText = (record["unit"] ?? "").trimmingCharacters(in: .whitespaces)
                let quantity = ImportColumns.number(record["amount"]) ?? 1
                var amount = ImportColumns.number(record["grams"]) ?? 0
                var unit = BaseUnit.gram
                switch SearchText.normalize(unitText) {
                case "g", "gram", "grams", "gramm": if amount == 0 { amount = quantity }
                case "ml": if amount == 0 { amount = quantity }; unit = .milliliter
                case "kg": if amount == 0 { amount = quantity * 1000 }
                case "l", "liter": if amount == 0 { amount = quantity * 1000 }; unit = .milliliter
                default: break
                }
                var values = ImportColumns.nutrients(record)
                if values[.energy] != nil {
                    for nutrient in [Nutrient.protein, .carbs, .fat] where values[nutrient] == nil { values[nutrient] = 0 }
                }
                draft.items.append(RecipeItemDraft(name: ingredient, quantity: quantity, unitLabel: unitText, amount: amount,
                                                   unit: unit, nutrients: values))
            }
            drafts[key] = draft
        }
        var rows: [(key: String, draft: RecipeDraft)] = []
        for key in order {
            guard let draft = drafts[key] else { continue }
            if draft.items.isEmpty {
                skipped.append("\(draft.name): no ingredients")
                continue
            }
            rows.append((key, draft))
        }
        return Parsed(rows: rows, skipped: skipped)
    }

    public static func plan(_ text: String, existing: [String: RecipeDraft]) -> ImportPlan<RecipeDraft> {
        let parsed = parse(text)
        return ImportPlan(incoming: parsed.rows.map { ($0.key, $0.draft) }, existing: existing, skipped: parsed.skipped)
    }

    public static func key(forName name: String) -> String {
        "recipe:" + ImportPlan<RecipeDraft>.contentKey([name])
    }

    public static func export(_ recipes: [RecipeDraft]) -> String {
        var table = [header]
        for recipe in recipes {
            for (index, item) in recipe.items.enumerated() {
                var row = [recipe.name, recipe.kind.rawValue,
                           recipe.kind == .recipe ? NumberText.plain(recipe.servings, decimals: 2) : "",
                           recipe.totalWeight > 0 ? NumberText.plain(recipe.totalWeight, decimals: 1) : "",
                           item.name, NumberText.plain(item.quantity, decimals: 2),
                           item.unitLabel.isEmpty ? item.unit.symbol : item.unitLabel,
                           item.amount > 0 ? NumberText.plain(item.amount, decimals: 1) : ""]
                row += ImportColumns.exportCells(item.nutrients)
                row.append(index == 0 ? recipe.notes : "")
                table.append(row)
            }
        }
        return CSV.write(table)
    }

    public static func prompt(appName: String, existingNames: [String]) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn my recipes and usual meals into rows: one row per ingredient, rows of the same recipe share its name. Nutrition values are the totals for the ingredient amount, not per 100 g.",
            columns: columns,
            rules: [
                "Use kind=meal for combinations I eat as they are (e.g. my usual breakfast) and kind=recipe for dishes cooked once and eaten in portions.",
                "Use reliable values (product labels, USDA, BLS). If you can't know an ingredient's values, leave its nutrient cells empty – the app looks it up.",
                "Decimal point, not comma. No units inside the number cells.",
            ],
            existingNames: [("Existing meals and recipes", existingNames)],
            exampleRows: [
                ["Usual breakfast", "meal", "", "", "Oats", "60", "g", "60", "233", "8.1", "40", "4.1", "6", "0.6", "0.7", "0", ""],
                ["Usual breakfast", "meal", "", "", "Milk 1.5%", "250", "ml", "250", "118", "8.5", "12", "3.8", "0", "12", "2.4", "0.3", ""],
            ]
        )
    }
}
