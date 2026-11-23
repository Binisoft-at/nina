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

    /// The key a food without an id is matched by: name and brand.
    public var contentKey: String { ImportPlan<FoodDraft>.contentKey([name, brand]) }
}

/// Nina's food CSV: "Import my data", the AI import and Export use it. One row per food,
/// nutrition per 100 g (or 100 ml for drinks). See docs/IMPORT.md.
public enum FoodCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("id", "Leave it empty for new foods. Nina writes an id when it exports; keep it when you edit that file, so importing again updates instead of duplicating."),
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

    /// How many own food names the prompts list ("Foods I already have").
    public static let promptNameLimit = 200

    public struct Parsed: Sendable {
        public var rows: [(key: String, draft: FoodDraft)]
        public var skipped: [String]
        /// Per row: the columns it speaks for (the file's columns, without a barcode Excel damaged).
        public var columns: [Set<String>] = []
        /// Per row: the nutrients its cells give (an empty cell keeps what Nina has).
        public var given: [Set<Nutrient>] = []
    }

    public static func parse(_ text: String) -> Parsed {
        let (header, records) = ImportColumns.records(text)
        guard header.contains("name") || header.contains("food") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}name\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        let fileColumns = Set(header)
        var parsed = Parsed(rows: [], skipped: [])
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let name = (record["name"].flatMap { $0.isEmpty ? nil : $0 } ?? record["food"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                parsed.skipped.append("Row \(line): no name")
                continue
            }
            let nutrients = ImportColumns.nutrients(record)
            guard nutrients[.energy] != nil else {
                parsed.skipped.append("Row \(line) (\(name)): no kcal")
                continue
            }
            var values = nutrients
            for nutrient in [Nutrient.protein, .carbs, .fat] where values[nutrient] == nil { values[nutrient] = 0 }
            var columns = fileColumns
            let rawBarcode = (record["barcode"] ?? "").trimmingCharacters(in: .whitespaces)
            var barcode = rawBarcode.filter(\.isNumber)
            if isDamagedBarcode(rawBarcode) {
                parsed.skipped.append("Row \(line) (\(name)): barcode \u{201C}\(rawBarcode)\u{201D} was shortened by a spreadsheet app – left out")
                barcode = ""
                columns.remove("barcode")
            }
            let draft = FoodDraft(
                name: name,
                nameDE: record["name_de"] ?? "",
                brand: record["brand"] ?? "",
                category: FoodCategory(text: record["category"] ?? ""),
                tags: ImportColumns.list(record["tags"]),
                unit: BaseUnit(text: record["unit"] ?? "g") == .milliliter ? .milliliter : .gram,
                nutrients: values,
                servings: Serving.parseList(record["portions"].flatMap { $0.isEmpty ? nil : $0 } ?? record["servings"] ?? ""),
                barcode: barcode,
                isFavorite: ImportColumns.isYes(record["favorite"]),
                notes: record["notes"] ?? ""
            )
            let key = ImportColumns.rowKey(id: record["id"] ?? "", content: [draft.name, draft.brand])
            if !key.hasPrefix("id:") {
                // Matched by name and brand (an AI's row, not one Nina exported): an empty cell
                // means "not known" there, so it keeps what Nina has – a favourite, tags, a barcode.
                columns = columns.filter { !(record[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            }
            parsed.rows.append((key, draft))
            parsed.columns.append(columns)
            parsed.given.append(Set(nutrients.known))
        }
        return parsed
    }

    /// "5.2E+12", "5,20105E+12": a barcode a spreadsheet turned into a rounded number.
    static func isDamagedBarcode(_ raw: String) -> Bool {
        let text = raw.uppercased()
        guard let e = text.firstIndex(of: "E") else { return false }
        let mantissa = text[..<e], exponent = text[text.index(after: e)...].drop { $0 == "+" }
        return !mantissa.isEmpty && !exponent.isEmpty && mantissa.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
            && exponent.allSatisfy(\.isNumber)
    }

    /// `existing`: the stored foods by every key they answer to (the stored values, not rounded).
    /// A row that matches one is merged over it (`merge`), so a file that only repeats what Nina
    /// has – an untouched export – plans as unchanged.
    public static func plan(_ text: String, existing: [String: FoodDraft]) -> ImportPlan<FoodDraft> {
        plan(parse(text), existing: existing)
    }

    public static func plan(_ parsed: Parsed, existing: [String: FoodDraft]) -> ImportPlan<FoodDraft> {
        let incoming = parsed.rows.enumerated().map { index, row -> (key: String, record: FoodDraft) in
            guard let stored = existing[row.key] else { return (row.key, row.draft) }
            let columns = index < parsed.columns.count ? parsed.columns[index] : Set(header)
            let given = index < parsed.given.count ? parsed.given[index] : Set(row.draft.nutrients.known)
            return (row.key, merge(row.draft, over: stored, columns: columns, given: given))
        }
        return ImportPlan(incoming: incoming, existing: existing, skipped: parsed.skipped)
    }

    /// The stored food as an export shows it once read back (rounded to the file's precision).
    public static func asExported(_ draft: FoodDraft) -> FoodDraft {
        parse(export([("", draft)])).rows.first?.draft ?? draft
    }

    /// What importing `incoming` makes of `stored`: a field changes only when the file has its
    /// column and its value differs from what an export of `stored` shows. Columns the file
    /// doesn't have, empty nutrient cells and rounding keep the stored value.
    public static func merge(_ incoming: FoodDraft, over stored: FoodDraft, columns: Set<String>, given: Set<Nutrient>) -> FoodDraft {
        let shown = asExported(stored)
        var result = stored
        if incoming.name != shown.name { result.name = incoming.name }
        if columns.contains("name_de"), incoming.nameDE != shown.nameDE { result.nameDE = incoming.nameDE }
        if columns.contains("brand"), incoming.brand != shown.brand { result.brand = incoming.brand }
        if columns.contains("category"), incoming.category != shown.category { result.category = incoming.category }
        if columns.contains("tags"), incoming.tags != shown.tags { result.tags = incoming.tags }
        if columns.contains("unit"), incoming.unit != shown.unit { result.unit = incoming.unit }
        if columns.contains("portions") || columns.contains("servings"), incoming.servings != shown.servings {
            result.servings = incoming.servings
        }
        if columns.contains("barcode"), incoming.barcode != shown.barcode { result.barcode = incoming.barcode }
        if columns.contains("favorite"), incoming.isFavorite != shown.isFavorite { result.isFavorite = incoming.isFavorite }
        if columns.contains("notes"), incoming.notes != shown.notes { result.notes = incoming.notes }
        result.nutrients = ImportColumns.mergeNutrients(incoming.nutrients, over: stored.nutrients, shown: shown.nutrients, given: given)
        return result
    }

    /// The file: the fixed columns, plus a column for every other nutrient some food has (and
    /// sodium_mg), values at up to 4 decimals. `key`: "id:<uuid>" writes the uuid as the row's id.
    public static func export(_ foods: [(key: String, draft: FoodDraft)]) -> String {
        let nutrientColumns = ImportColumns.exportColumns(foods.map(\.draft.nutrients))
        let before = Array(header.prefix { $0 != "kcal" })
        let after = Array(header.drop { $0 != "salt" }.dropFirst())
        var table = [before + nutrientColumns + after]
        for (key, draft) in foods {
            var row = [ImportColumns.exportID(forKey: key), draft.name, draft.nameDE, draft.brand, draft.category.rawValue,
                       draft.tags.joined(separator: ";"), draft.unit == .milliliter ? "ml" : "g"]
            row += ImportColumns.exportCells(draft.nutrients, columns: nutrientColumns)
            row += [Serving.formatList(draft.servings), draft.barcode, draft.isFavorite ? "yes" : "", draft.notes]
            table.append(row)
        }
        return CSV.write(table)
    }

    /// `existingFoods`: the names of the person's own foods, so the AI doesn't write them again
    /// (the first `promptNameLimit`).
    public static func prompt(appName: String, existingTags: [String] = [], existingFoods: [String] = []) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn the foods I give you (photos of nutrition labels, product names, a spreadsheet or another app's export) into my food list. Values are per 100 g, or per 100 ml for drinks.",
            columns: columns,
            rules: rules,
            existingNames: [("Tags", existingTags), ("Foods I already have (don't write them again unless I give new values)", Array(existingFoods.prefix(promptNameLimit)))],
            exampleRows: [
                ["", "Greek yogurt 2%", "Griechisches Joghurt 2 %", "Fage", "dairy", "breakfast;high-protein", "g", "73", "10", "3.6", "2", "", "3.6", "1.3", "0.1", "pot=170", "5201054017197", "yes", ""],
                ["", "Oat drink Barista", "Haferdrink Barista", "Oatly", "beverages", "", "ml", "59", "1", "6.6", "3", "0.8", "3.4", "0.3", "0.1", "glass=250", "", "", ""],
            ]
        )
    }

    static let rules: [String] = [
        "One row per food. Copy the values exactly as printed on the label (per 100 g / 100 ml). If I only give a product name, use the manufacturer's label values or a national food composition database (USDA, BLS, Swiss Food Composition Database) and never guess wildly; if you're unsure, leave the row out.",
        "If kcal and the macros clearly don't fit together (about 4 kcal per g protein and carbs, 9 per g fat), leave the row out instead of changing the label's numbers.",
        "Decimal point, not comma (4.5). No units inside the number cells.",
        "category must be one of the listed values.",
        "Leave the id column empty for new rows; keep ids that are already in my data (Nina writes them when it exports).",
    ]
}
