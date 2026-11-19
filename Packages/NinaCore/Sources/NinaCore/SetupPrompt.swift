import Foundation
import BinisoftKitCore

/// What another AI writes back can hold several files at once – goals & settings, foods, meals &
/// recipes – as ```csv blocks or one after another. This splits it into its parts.
public enum ImportBundle {
    public struct Part: Equatable, Sendable {
        public let kind: ImportKind
        public let text: String
    }

    public static func parts(_ text: String) -> [Part] {
        let blocks = fencedBlocks(text) ?? headerBlocks(text)
        return blocks.compactMap { block in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let kind = ImportKind.detect(trimmed) else { return nil }
            return Part(kind: kind, text: trimmed + "\n")
        }
    }

    /// The contents of ``` code blocks, or nil when there are none.
    static func fencedBlocks(_ text: String) -> [String]? {
        guard text.contains("```") else { return nil }
        var blocks: [String] = []
        var current: [String]?
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = current {
                    blocks.append(open.joined(separator: "\n"))
                    current = nil
                } else {
                    current = []
                }
            } else {
                current?.append(line)
            }
        }
        if let open = current, !open.isEmpty { blocks.append(open.joined(separator: "\n")) }
        return blocks
    }

    /// Without code blocks: a new part starts at a header line that follows an empty line.
    static func headerBlocks(_ text: String) -> [String] {
        var blocks: [[String]] = [[]]
        var afterBlank = true
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                afterBlank = true
                continue
            }
            if afterBlank, !(blocks.last?.isEmpty ?? true), ImportKind.detect(trimmed) != nil {
                blocks.append([])
            }
            blocks[blocks.count - 1].append(line)
            afterBlank = false
        }
        return blocks.map { $0.joined(separator: "\n") }
    }
}

/// One prompt that sets Nina up from a few lines about me: goals & settings, my foods, and my
/// usual meals and recipes – three ```csv blocks that are pasted back in one go.
public enum SetupPrompt {
    public static func text(appName: String, currentSettings: String = "", existingTags: [String] = [],
                            existingRecipes: [String] = []) -> String {
        let foods = FoodCSV.prompt(appName: appName, existingTags: existingTags)
        let recipes = RecipeCSV.prompt(appName: appName, existingNames: existingRecipes)
        var lines: [String] = []
        lines.append("You set up my nutrition app \"\(appName)\" from what I tell you: about me (body, goal, training, habits, meal times, preferences), my plan if I have one (phases, calorie cycling, measurements, check-ins, supplements), the foods I eat (product names, label photos, my own dishes) and my usual meals and recipes.")
        lines.append("")
        lines.append("## Output rules")
        lines.append("- Answer with up to THREE csv code blocks and nothing else, in this order. Each block starts with its header line. Leave a block out when my notes have nothing for it.")
        lines.append("  1. Goals & settings – header: setting,value")
        lines.append("  2. My foods – header: \(foods.header)")
        lines.append("  3. My meals & recipes – header: \(recipes.header)")
        lines.append("- Comma separated, UTF-8. Put a value in \"double quotes\" if it contains a comma, a quote or a line break. Decimal point, not comma (4.5). No units inside number cells.")
        lines.append("- Never invent data; leave a cell empty when it doesn't apply and skip a row when it's unclear. Keep my own words and names as I wrote them.")
        lines.append("- \(appName) already knows about 1,000 basic foods (fruit, vegetables, bread, dairy, meat, fish, drinks …) in English and German. Put a food into block 2 only if it's a branded product, my own item, or I give label values. Ingredients of meals and recipes may be basic foods: leave their nutrient cells empty and \(appName) looks them up.")
        lines.append("")
        lines.append("## 1. Goals & settings (setting,value)")
        lines.append(contentsOf: SettingsCSV.settingsRules)
        lines.append("")
        lines.append(contentsOf: SettingsCSV.settingsTable.dropFirst())
        lines.append("")
        lines.append(contentsOf: SettingsCSV.planSection(heading: "### Coach plan (in block 1, only if my notes describe one)"))
        if !currentSettings.isEmpty {
            lines.append("")
            lines.append("My current settings (change only what my notes say):")
            lines.append("```csv")
            lines.append(currentSettings.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("```")
        }
        lines.append("")
        lines.append("## 2. My foods")
        lines.append(foods.task)
        lines.append(contentsOf: foods.rules.map { "- " + $0 })
        lines.append(contentsOf: table(foods.columns))
        lines.append("")
        lines.append("## 3. My meals & recipes")
        lines.append(recipes.task)
        lines.append(contentsOf: recipes.rules.map { "- " + $0 })
        lines.append(contentsOf: table(recipes.columns))
        let names = (foods.existingNames + recipes.existingNames).filter { !$0.1.isEmpty }
        if !names.isEmpty {
            lines.append("")
            lines.append("## Names that already exist in \(appName) (reuse them exactly)")
            for (kind, values) in names { lines.append("- \(kind): \(values.joined(separator: ", "))") }
        }
        lines.append("")
        lines.append("## Example answer")
        lines.append("```csv")
        lines.append("setting,value")
        lines.append("birth_year,1991")
        lines.append("height_cm,171")
        lines.append("weight_kg,67.3")
        lines.append("activity,moderate")
        lines.append("goal,lose")
        lines.append("rate_kg_per_week,0.5")
        lines.append("macro_split,high_protein")
        lines.append("training_days,mon;wed;fri")
        lines.append("meals,Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝")
        lines.append("not_supported,I'm lactose intolerant")
        lines.append("```")
        lines.append("```csv")
        lines.append(foods.header)
        for row in foods.exampleRows.prefix(1) { lines.append(row.map { CSV.escape($0) }.joined(separator: ",")) }
        lines.append("```")
        lines.append("```csv")
        lines.append(recipes.header)
        for row in recipes.exampleRows { lines.append(row.map { CSV.escape($0) }.joined(separator: ",")) }
        lines.append("```")
        lines.append("")
        lines.append("## About me and my foods")
        lines.append("(I write or paste it below – a few lines are enough.)")
        return lines.joined(separator: "\n")
    }

    static func table(_ columns: [AIImportPrompt.Column]) -> [String] {
        var lines = ["", "| column | meaning | required |", "|---|---|---|"]
        for column in columns {
            lines.append("| \(column.name) | \(column.meaning) | \(column.required ? "yes" : "no") |")
        }
        return lines
    }
}
