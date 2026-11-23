import Foundation
import BinisoftKitCore

/// What another AI writes back can hold several files at once – goals & settings, foods, meals &
/// recipes, weight & body history – as ```csv blocks or one after another. This splits it into its parts.
public enum ImportBundle {
    public struct Part: Equatable, Sendable {
        public let kind: ImportKind
        public let text: String
    }

    /// The parts of an answer, and a line for each block that wasn't recognised.
    public struct Split: Equatable, Sendable {
        public var parts: [Part]
        /// "Block 3, starting “…”, wasn't recognised – it was left out."
        public var unrecognised: [String]
    }

    public static func parts(_ text: String) -> [Part] {
        split(text).parts
    }

    /// Splits an answer into its parts. In each block, lines before the first header ("# 2. Foods",
    /// "csv", "Copy code", a label) are skipped, a blank line followed by another header starts a
    /// new part, and settings rows without a `setting,value` line count as settings.
    public static func split(_ text: String) -> Split {
        var result = Split(parts: [], unrecognised: [])
        var number = 0
        for block in fencedBlocks(text) ?? headerBlocks(text) {
            let lines = block.components(separatedBy: .newlines)
            guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
            number += 1
            let found = blockParts(lines)
            if found.isEmpty {
                let start = first.trimmingCharacters(in: .whitespaces)
                let shown = start.count > 40 ? String(start.prefix(40)) + "…" : start
                result.unrecognised.append("Block \(number), starting \u{201C}\(shown)\u{201D}, wasn't recognised – it was left out.")
            }
            result.parts += found
        }
        return result
    }

    /// What to read when no part is recognised: the code blocks' contents, else the whole text.
    public static func fallbackText(_ text: String) -> String {
        guard let blocks = fencedBlocks(text), !blocks.isEmpty else { return text }
        return blocks.joined(separator: "\n\n")
    }

    /// The parts of one block.
    static func blockParts(_ lines: [String]) -> [Part] {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let start = firstHeader(trimmed, from: 0, settingsWithoutHeader: true) else { return [] }
        var chunks: [Range<Int>] = []
        var chunkStart = start
        var afterBlank = false
        var index = start + 1
        while index < trimmed.count {
            if trimmed[index].isEmpty {
                afterBlank = true
                index += 1
                continue
            }
            if afterBlank, let next = firstHeader(trimmed, from: index, settingsWithoutHeader: false, look: 3) {
                // A blank line, maybe a title, then another header: a new part.
                chunks.append(chunkStart..<index)
                chunkStart = next
                index = next
            }
            afterBlank = false
            index += 1
        }
        chunks.append(chunkStart..<trimmed.count)
        return chunks.compactMap { range in
            let text = lines[range].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let kind = ImportKind.detect(text) else { return nil }
            return Part(kind: kind, text: text + "\n")
        }
    }

    /// The first line (of the next `look` non-empty ones from `from`) that starts a part: a header,
    /// or – with `settingsWithoutHeader` – settings rows without one.
    static func firstHeader(_ lines: [String], from: Int, settingsWithoutHeader: Bool, look: Int = 10) -> Int? {
        func nonEmpty(after start: Int, count: Int) -> [Int] {
            var found: [Int] = []
            var index = start
            while index < lines.count, found.count < count {
                if !lines[index].isEmpty { found.append(index) }
                index += 1
            }
            return found
        }
        for index in nonEmpty(after: from, count: look) {
            let next = nonEmpty(after: index + 1, count: 11).map { lines[$0] }
            if ImportKind.detectHeader(lines[index], following: Array(next.prefix(4))) != nil { return index }
            if settingsWithoutHeader, SettingsCSV.looksLikeSettings([lines[index]] + next) { return index }
        }
        return nil
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

/// One prompt that sets Nina up from a few lines about me: goals & settings, my foods, my usual
/// meals and recipes, and (optional) my weight and body history – up to four ```csv blocks that are
/// pasted back in one go.
public enum SetupPrompt {
    /// `existingFoods`: the names of the person's own foods (the AI doesn't write them again).
    public static func text(appName: String, currentSettings: String = "", existingTags: [String] = [],
                            existingRecipes: [String] = [], existingFoods: [String] = []) -> String {
        let foods = FoodCSV.prompt(appName: appName, existingTags: existingTags, existingFoods: existingFoods)
        let recipes = RecipeCSV.prompt(appName: appName, existingNames: existingRecipes)
        let history = BodyHistoryCSV.prompt(appName: appName)
        var lines: [String] = []
        lines.append("You set up my nutrition app \"\(appName)\" from what I tell you: about me (body, goal, training, habits, meal times, preferences), my plan if I have one (phases, calorie cycling, measurements, check-ins, supplements), the foods I eat (product names, label photos, my own dishes), my usual meals and recipes, and my weight and body history if I give one (weigh-ins, tape measurements, body-fat results).")
        lines.append("")
        lines.append("## Output rules")
        lines.append("- Answer with up to FOUR csv code blocks and nothing else, in this order. Each block starts with its header line. Leave a block out when my notes have nothing for it.")
        lines.append("  1. Goals & settings – header: setting,value")
        lines.append("  2. My foods – header: \(foods.header)")
        lines.append("  3. My meals & recipes – header: \(recipes.header)")
        lines.append("  4. My weight and body history – header: \(history.header)")
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
            lines.append("My current settings (change only what my notes say). \(SettingsCSV.currentSettingsNote)")
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
        lines.append("")
        lines.append("## 4. My weight and body history (only if I give dated weigh-ins, measurements or scan results)")
        lines.append(history.task)
        lines.append("- Dated values go here, not into block 1: block 1's body_fat_percent and *_cm rows are only for values I give without a date.")
        lines.append(contentsOf: history.rules.map { "- " + $0 })
        lines.append(contentsOf: table(history.columns))
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
        lines.append("```csv")
        lines.append(history.header)
        for row in history.exampleRows.prefix(1) { lines.append(row.map { CSV.escape($0) }.joined(separator: ",")) }
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
