import Foundation
import BinisoftKitCore

// Meals & recipes export and re-import without losses: the export writes every nutrient an
// ingredient has at full precision, and importing a file merges it over the stored recipes – an
// untouched export changes nothing, and an ingredient the file doesn't change keeps its food link,
// category, brand and portion.

extension RecipeCSV {
    /// The file: the fixed columns plus a column for every other nutrient some ingredient has (and
    /// sodium_mg), amounts and values at up to 4 decimals.
    public static func exportWithAllNutrients(_ recipes: [RecipeDraft]) -> String {
        let nutrientColumns = ImportColumns.exportColumns(recipes.flatMap { $0.items.map(\.nutrients) })
        var table = [Array(header.prefix { $0 != "kcal" }) + nutrientColumns + ["notes"]]
        for recipe in recipes {
            for (index, item) in recipe.items.enumerated() {
                var row = [recipe.name, recipe.kind.rawValue,
                           recipe.kind == .recipe ? NumberText.plain(recipe.servings, decimals: 4) : "",
                           recipe.totalWeight > 0 ? NumberText.plain(recipe.totalWeight, decimals: 4) : "",
                           item.name, NumberText.plain(item.quantity, decimals: 4),
                           item.unitLabel.isEmpty ? item.unit.symbol : item.unitLabel,
                           item.amount > 0 ? NumberText.plain(item.amount, decimals: 4) : ""]
                row += ImportColumns.exportCells(item.nutrients, columns: nutrientColumns)
                row.append(index == 0 ? recipe.notes : "")
                table.append(row)
            }
        }
        return CSV.write(table)
    }

    /// The stored recipe as the export shows it once read back.
    public static func importedView(of draft: RecipeDraft) -> RecipeDraft {
        parse(exportWithAllNutrients([draft])).rows.first?.draft ?? draft
    }

    /// `existing`: the stored recipes by `key(forName:)`. A recipe the file has is merged over the
    /// stored one (`mergeImported`), so an untouched export plans as unchanged.
    public static func planImport(_ text: String, existing: [String: RecipeDraft]) -> ImportPlan<RecipeDraft> {
        let parsed = parse(text)
        let columns = ImportColumns.headerColumns(text)
        let incoming = parsed.rows.map { row -> (key: String, record: RecipeDraft) in
            guard let stored = existing[row.key] else { return (row.key, row.draft) }
            return (row.key, mergeImported(row.draft, over: stored, columns: columns))
        }
        return ImportPlan(incoming: incoming, existing: existing, skipped: parsed.skipped)
    }

    /// What importing `incoming` makes of `stored`: a field changes only when the file has its
    /// column and its value differs from what the export shows. An ingredient that is the same as
    /// one of the stored ones (empty nutrient cells count as the same) stays the stored one.
    public static func mergeImported(_ incoming: RecipeDraft, over stored: RecipeDraft, columns: Set<String>) -> RecipeDraft {
        let shown = importedView(of: stored)
        var result = stored
        if incoming.name != shown.name { result.name = incoming.name }
        if columns.contains("kind"), incoming.kind != shown.kind { result.kind = incoming.kind }
        if columns.contains("servings"), !ImportColumns.sameValue(incoming.servings, shown.servings) { result.servings = incoming.servings }
        if columns.contains("total_weight_g"), !ImportColumns.sameValue(incoming.totalWeight, shown.totalWeight) {
            result.totalWeight = incoming.totalWeight
        }
        if columns.contains("notes"), incoming.notes != shown.notes { result.notes = incoming.notes }
        guard shown.items.count == stored.items.count else {
            result.items = incoming.items
            return result
        }
        var used = Set<Int>()
        result.items = incoming.items.map { item in
            guard let index = shown.items.indices.first(where: { !used.contains($0) && sameIngredient(item, shown.items[$0]) }) else {
                return item
            }
            used.insert(index)
            return stored.items[index]
        }
        return result
    }

    /// Same name, amount and unit, and every nutrient the row gives equal at the file's precision.
    static func sameIngredient(_ incoming: RecipeItemDraft, _ shown: RecipeItemDraft) -> Bool {
        guard incoming.name == shown.name, ImportColumns.sameValue(incoming.quantity, shown.quantity),
              incoming.unitLabel == shown.unitLabel, ImportColumns.sameValue(incoming.amount, shown.amount),
              incoming.unit == shown.unit else { return false }
        return incoming.nutrients.known.allSatisfy { ImportColumns.sameValue(incoming.nutrients[$0], shown.nutrients[$0]) }
    }

    /// For each ingredient of `merged`, the index of the stored ingredient it is (unchanged), or
    /// nil for a new or changed one – the app keeps those stored ingredients as they are.
    public static func keptIngredientIndices(of merged: RecipeDraft, in stored: RecipeDraft) -> [Int?] {
        var used = Set<Int>()
        return merged.items.map { item in
            guard let index = stored.items.indices.first(where: { !used.contains($0) && stored.items[$0] == item }) else { return nil }
            used.insert(index)
            return index
        }
    }
}

extension RecipeItemDraft {
    /// How the ingredient is stored as a recipe line's amount (see `ImportColumns.storedAmount`).
    /// `lookedUp`: the base amount and unit of the food a lookup found.
    public func storedAmount(lookedUp: (amount: Double, unit: BaseUnit)? = nil) -> AmountText {
        ImportColumns.storedAmount(quantity: quantity, unitLabel: unitLabel, amount: lookedUp?.amount ?? amount,
                                   unit: lookedUp?.unit ?? unit)
    }
}

extension ImportColumns {
    /// The canonical columns of a file's header line.
    public static func headerColumns(_ text: String) -> Set<String> {
        let lines = text.split(whereSeparator: \.isNewline).prefix(5).joined(separator: "\n")
        return Set((CSV.parse(lines).first ?? []).map(canonical))
    }
}
