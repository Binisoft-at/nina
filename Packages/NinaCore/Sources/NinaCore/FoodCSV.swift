import Foundation
import BinisoftKitCore

/// One food as it travels through import and export.
public struct FoodDraft: Equatable, Sendable {
    public var name: String
    public var nameDE: String
    public var brand: String
    public var category: FoodCategory
    public var tags: [String]
    public var unit: BaseUnit
    /// Per 100 g or 100 ml.
    public var nutrients: NutrientValues
    public var servings: [Serving]
    public var barcode: String
    public var isFavorite: Bool
    public var notes: String

    public init(name: String, nameDE: String = "", brand: String = "", category: FoodCategory = .other, tags: [String] = [],
                unit: BaseUnit = .gram, nutrients: NutrientValues, servings: [Serving] = [], barcode: String = "",
                isFavorite: Bool = false, notes: String = "") {
        self.name = name
        self.nameDE = nameDE
        self.brand = brand
        self.category = category
        self.tags = tags
        self.unit = unit
        self.nutrients = nutrients
        self.servings = servings
        self.barcode = barcode
        self.isFavorite = isFavorite
        self.notes = notes
    }
}

/// Nina's food CSV: "Import my data", the AI import and Export use it. One row per food,
/// nutrition per 100 g (or 100 ml for drinks). See docs/IMPORT.md.
public enum FoodCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("id", "A stable id per food (1, 2, 3 …). Keep it when you edit the file so importing again updates instead of duplicating."),
        .init("name", "Food name in my words, short (\"Greek yogurt 2%\", \"Oat milk Barista\").", required: true),
        .init("name_de", "German name, if you know it (optional)."),
        .init("brand", "Brand or shop, empty for generic foods."),
        .init("category", "One of: \(FoodCategory.allCases.map(\.rawValue).joined(separator: ", "))."),
        .init("tags", "Optional labels separated by ; (e.g. breakfast;high-protein)."),
        .init("unit", "g if the values are per 100 g, ml if per 100 ml (drinks)."),
        .init("kcal", "Energy in kcal per 100 g/ml.", required: true),
        .init("protein", "Protein in g per 100 g/ml.", required: true),
        .init("carbs", "Carbohydrates in g per 100 g/ml.", required: true),
        .init("fat", "Fat in g per 100 g/ml.", required: true),
        .init("fiber", "Fiber in g per 100 g/ml."),
        .init("sugar", "Sugars in g per 100 g/ml."),
        .init("saturated_fat", "Saturated fat in g per 100 g/ml."),
        .init("salt", "Salt in g per 100 g/ml (as on EU labels)."),
        .init("portions", "Household portions as name=amount separated by ; – amount in g or ml, e.g. slice=30;pack=250;glass=250."),
        .init("barcode", "EAN/GTIN barcode digits, if known."),
        .init("favorite", "yes for foods I eat often."),
        .init("notes", "Anything else."),
    ]

    public static var header: [String] { columns.map(\.name) }

    public struct Parsed {
        public var rows: [(key: String, draft: FoodDraft)]
        public var skipped: [String]
    }

    public static func parse(_ text: String) -> Parsed {
        let (header, records) = ImportColumns.records(text)
        guard header.contains("name") || header.contains("food") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}name\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        var rows: [(key: String, draft: FoodDraft)] = []
        var skipped: [String] = []
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let name = (record["name"].flatMap { $0.isEmpty ? nil : $0 } ?? record["food"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                skipped.append("Row \(line): no name")
                continue
            }
            let nutrients = ImportColumns.nutrients(record)
            guard nutrients[.energy] != nil else {
                skipped.append("Row \(line) (\(name)): no kcal")
                continue
            }
            var values = nutrients
            for nutrient in [Nutrient.protein, .carbs, .fat] where values[nutrient] == nil { values[nutrient] = 0 }
            let draft = FoodDraft(
                name: name,
                nameDE: record["name_de"] ?? "",
                brand: record["brand"] ?? "",
                category: FoodCategory(text: record["category"] ?? ""),
                tags: ImportColumns.list(record["tags"]),
                unit: BaseUnit(text: record["unit"] ?? "g") == .milliliter ? .milliliter : .gram,
                nutrients: values,
                servings: Serving.parseList(record["portions"].flatMap { $0.isEmpty ? nil : $0 } ?? record["servings"] ?? ""),
                barcode: (record["barcode"] ?? "").filter(\.isNumber),
                isFavorite: ImportColumns.isYes(record["favorite"]),
                notes: record["notes"] ?? ""
            )
            let id = (record["id"] ?? "").trimmingCharacters(in: .whitespaces)
            let key = id.isEmpty ? ImportPlan<FoodDraft>.contentKey([draft.name, draft.brand]) : "id:" + id
            rows.append((key, draft))
        }
        return Parsed(rows: rows, skipped: skipped)
    }

    public static func plan(_ text: String, existing: [String: FoodDraft]) -> ImportPlan<FoodDraft> {
        let parsed = parse(text)
        return ImportPlan(incoming: parsed.rows.map { ($0.key, $0.draft) }, existing: existing, skipped: parsed.skipped)
    }

    public static func export(_ foods: [(key: String, draft: FoodDraft)]) -> String {
        var table = [header]
        for (key, draft) in foods {
            let n = draft.nutrients
            func cell(_ value: Double?) -> String { value.map { NumberText.plain($0, decimals: 2) } ?? "" }
            table.append([
                ImportColumns.exportID(forKey: key), draft.name, draft.nameDE, draft.brand, draft.category.rawValue,
                draft.tags.joined(separator: ";"), draft.unit == .milliliter ? "ml" : "g",
                cell(n[.energy]), cell(n[.protein]), cell(n[.carbs]), cell(n[.fat]), cell(n[.fiber]), cell(n[.sugar]),
                cell(n[.saturatedFat]), cell(n.salt), Serving.formatList(draft.servings), draft.barcode,
                draft.isFavorite ? "yes" : "", draft.notes,
            ])
        }
        return CSV.write(table)
    }

    public static func prompt(appName: String, existingTags: [String] = []) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn the foods I give you (photos of nutrition labels, product names, a spreadsheet or another app's export) into my food list. Values are per 100 g, or per 100 ml for drinks.",
            columns: columns,
            rules: [
                "One row per food. Use the values printed on the label (per 100 g / 100 ml). If I only give a product name, use the manufacturer's label values or a national food composition database (USDA, BLS, Swiss Food Composition Database) and never guess wildly; if you're unsure, leave the row out.",
                "kcal must match the macros roughly (4 kcal per g protein and carbs, 9 per g fat).",
                "Decimal point, not comma (4.5). No units inside the number cells.",
                "category must be one of the listed values.",
                "Number the id column 1, 2, 3 … unless my data already has ids.",
            ],
            existingNames: [("Tags", existingTags)],
            exampleRows: [
                ["1", "Greek yogurt 2%", "Griechisches Joghurt 2 %", "Fage", "dairy", "breakfast;high-protein", "g", "73", "10", "3.6", "2", "", "3.6", "1.3", "0.1", "pot=170", "5201054017197", "yes", ""],
                ["2", "Oat drink Barista", "Haferdrink Barista", "Oatly", "beverages", "", "ml", "59", "1", "6.6", "3", "0.8", "3.4", "0.3", "0.1", "glass=250", "", "", ""],
            ]
        )
    }
}
