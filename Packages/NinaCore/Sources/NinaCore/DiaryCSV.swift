import Foundation
import BinisoftKitCore

/// One diary row as it travels through import and export.
public struct DiaryDraft: Equatable, Sendable {
    public var day: DayKey
    public var minutes: Int?
    /// The meal as written ("Frühstück", "lunch", "Jause"); matched to the meal slots in the app.
    public var meal: String
    public var name: String
    public var brand: String
    /// As written: 2 (slices), 150 (g).
    public var quantity: Double
    public var unitLabel: String
    /// Base amount in g/ml when known (grams column, or unit g/ml), else 0.
    public var amount: Double
    public var unit: BaseUnit
    /// Totals for the row. Empty energy → the app looks the food up by name.
    public var nutrients: NutrientValues
    public var note: String
    public var status: EntryStatus

    public init(day: DayKey, minutes: Int? = nil, meal: String, name: String, brand: String = "", quantity: Double = 1,
                unitLabel: String = "", amount: Double = 0, unit: BaseUnit = .gram, nutrients: NutrientValues = NutrientValues(),
                note: String = "", status: EntryStatus = .eaten) {
        self.day = day
        self.minutes = minutes
        self.meal = meal
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.unitLabel = unitLabel
        self.amount = amount
        self.unit = unit
        self.nutrients = nutrients
        self.note = note
        self.status = status
    }

    public var needsLookup: Bool { nutrients[.energy] == nil }

    /// Amount, unit, base amount and base unit are the same (the entry keeps its portion).
    public func sameAmount(as other: DiaryDraft) -> Bool {
        quantity == other.quantity && unitLabel == other.unitLabel && amount == other.amount && unit == other.unit
    }

    /// How the row is stored as an entry's amount. `lookedUp`: the base amount and unit of the food
    /// a lookup found (the row had no nutrition values).
    public func storedAmount(lookedUp: (amount: Double, unit: BaseUnit)? = nil) -> AmountText {
        ImportColumns.storedAmount(quantity: quantity, unitLabel: unitLabel, amount: lookedUp?.amount ?? amount,
                                   unit: lookedUp?.unit ?? unit)
    }
}

extension ImportColumns {
    /// g, ml, kg, l, serving … – a unit rather than a portion word like "slice" or "medium".
    static func isUnitWord(_ text: String) -> Bool {
        ["", "g", "gram", "grams", "gramm", "ml", "milliliter", "millilitre", "kg", "l", "liter", "litre", "cl", "dl",
         "serving", "servings", "portion", "portions"].contains(SearchText.normalize(text))
    }

    /// How an imported amount is stored: a portion word keeps its count ("2 × slice (64 g)"), a
    /// plain unit becomes the base amount ("150 g"), and without a base amount it is servings – with
    /// unit amount 0, like a quick entry, whose values don't scale.
    public static func storedAmount(quantity: Double, unitLabel: String, amount: Double, unit: BaseUnit) -> AmountText {
        let label = unitLabel.trimmingCharacters(in: .whitespaces)
        if amount > 0 {
            if !isUnitWord(label), quantity > 0 {
                return AmountText(quantity: quantity, unitLabel: label, unitAmount: amount / quantity, baseUnit: unit)
            }
            return AmountText(quantity: amount, unitLabel: unit.symbol, unitAmount: 1, baseUnit: unit)
        }
        return AmountText(quantity: quantity, unitLabel: label.isEmpty ? BaseUnit.serving.symbol : label, unitAmount: 0, baseUnit: .serving)
    }
}

/// Nina's diary CSV: one row per thing eaten, nutrition values are the totals for that row.
public enum DiaryCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("id", "Leave it empty for new rows. Nina writes an id when it exports; keep it when you edit that file."),
        .init("date", "Day in YYYY-MM-DD.", required: true),
        .init("time", "Time HH:MM (24 h), if known."),
        .init("meal", "breakfast, lunch, dinner or snack (or one of my own meal names).", required: true),
        .init("food", "What was eaten, short and in my words.", required: true),
        .init("brand", "Brand, if any."),
        .init("amount", "How many of unit (e.g. 2 for two slices, 150 for 150 g)."),
        .init("unit", "g, ml, or a portion word like slice, piece, cup, tbsp, glass."),
        .init("grams", "Total weight in g (or ml for drinks), if known."),
        .init("kcal", "Total kcal for this row (not per 100 g). Leave empty only if you can't know – the app then looks the food up."),
        .init("protein", "Total protein in g for this row."),
        .init("carbs", "Total carbohydrates in g for this row."),
        .init("fat", "Total fat in g for this row."),
        .init("fiber", "Total fiber in g."),
        .init("sugar", "Total sugar in g."),
        .init("saturated_fat", "Total saturated fat in g."),
        .init("salt", "Total salt in g."),
        .init("note", "Anything else."),
        .init("status", "eaten (default) or planned."),
    ]

    public static var header: [String] { columns.map(\.name) }

    public struct Parsed: Sendable {
        public var rows: [(key: String, draft: DiaryDraft)]
        public var skipped: [String]
        /// The file's columns (canonical keys).
        public var columns: Set<String> = []
        /// Per row: the nutrients its cells give (an empty cell keeps what Nina has).
        public var given: [Set<Nutrient>] = []
    }

    public static func parse(_ text: String) -> Parsed {
        let (header, records) = ImportColumns.records(text)
        guard header.contains("date") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}date\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        var parsed = Parsed(rows: [], skipped: [], columns: Set(header))
        // Two identical rows without an id (two coffees as snacks on one day) are two entries:
        // the second gets "#2" on its content key, the same each time the file is imported.
        var repeats: [String: Int] = [:]
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let name = (record["food"].flatMap { $0.isEmpty ? nil : $0 } ?? record["name"] ?? "").trimmingCharacters(in: .whitespaces)
            guard let day = parseDate(record["date"] ?? "") else {
                parsed.skipped.append("Row \(line): date \u{201C}\(record["date"] ?? "")\u{201D} not understood (use YYYY-MM-DD)")
                continue
            }
            let nutrients = ImportColumns.nutrients(record)
            guard !name.isEmpty || nutrients[.energy] != nil else {
                parsed.skipped.append("Row \(line): no food")
                continue
            }
            let unitText = (record["unit"] ?? "").trimmingCharacters(in: .whitespaces)
            let quantity = ImportColumns.number(record["amount"]) ?? 1
            let amount = baseAmount(quantity: quantity, unitText: unitText, grams: ImportColumns.number(record["grams"]) ?? 0,
                                    base: record["base"] ?? "")
            var values = nutrients
            if values[.energy] != nil {
                for nutrient in [Nutrient.protein, .carbs, .fat] where values[nutrient] == nil { values[nutrient] = 0 }
            }
            let draft = DiaryDraft(
                day: day,
                minutes: ClockTime.parse(record["time"] ?? ""),
                meal: (record["meal"] ?? "").trimmingCharacters(in: .whitespaces),
                name: name.isEmpty ? "Quick entry" : name,
                brand: record["brand"] ?? "",
                quantity: quantity,
                unitLabel: unitText,
                amount: amount.value,
                unit: amount.unit,
                nutrients: values,
                note: record["note"] ?? record["notes"] ?? "",
                status: EntryStatus(text: record["status"] ?? "")
            )
            var key = ImportColumns.rowKey(id: record["id"] ?? "",
                                           content: [day.rawValue, draft.meal, draft.name, NumberText.plain(draft.quantity), draft.unitLabel])
            if !key.hasPrefix("id:") {
                let count = (repeats[key] ?? 0) + 1
                repeats[key] = count
                if count > 1 { key += "#\(count)" }
            }
            parsed.rows.append((key, draft))
            parsed.given.append(Set(nutrients.known))
        }
        return parsed
    }

    /// The base amount and unit of a row: from the unit word (g, ml, kg, l, cl, dl), the grams
    /// column, the export's base column (ml or serving), or a serving word ("serving", "Portion")
    /// without grams.
    static func baseAmount(quantity: Double, unitText: String, grams: Double, base: String) -> (value: Double, unit: BaseUnit) {
        var amount = grams
        var unit = BaseUnit.gram
        var explicit = true
        switch SearchText.normalize(unitText) {
        case "g", "gram", "grams", "gramm":
            if amount == 0 { amount = quantity }
        case "ml", "milliliter", "millilitre":
            if amount == 0 { amount = quantity }
            unit = .milliliter
        case "kg": if amount == 0 { amount = quantity * 1000 }
        case "l", "liter", "litre":
            if amount == 0 { amount = quantity * 1000 }
            unit = .milliliter
        case "cl":
            if amount == 0 { amount = quantity * 10 }
            unit = .milliliter
        case "dl":
            if amount == 0 { amount = quantity * 100 }
            unit = .milliliter
        default:
            explicit = false
        }
        guard !explicit else { return (amount, unit) }
        let baseText = base.trimmingCharacters(in: .whitespaces)
        if !baseText.isEmpty {
            switch BaseUnit(text: baseText) {
            case .milliliter: unit = .milliliter
            case .serving: if amount == 0 { unit = .serving }
            case .gram: break
            }
        } else if amount == 0, BaseUnit(text: unitText) == .serving {
            unit = .serving
        }
        return (amount, unit)
    }

    /// `existing`: the stored entries by every key they answer to (their values as stored). A row
    /// that matches one is merged over it (`merge`), so an untouched export plans as unchanged.
    /// `meals`: the meal slots, to compare meals by slot ("Jause" and "meal-jause" are the same).
    public static func plan(_ text: String, existing: [String: DiaryDraft], meals: [MealSlot] = MealSlot.defaults) -> ImportPlan<DiaryDraft> {
        plan(parse(text), existing: existing, meals: meals)
    }

    public static func plan(_ parsed: Parsed, existing: [String: DiaryDraft], meals: [MealSlot] = MealSlot.defaults) -> ImportPlan<DiaryDraft> {
        let incoming = parsed.rows.enumerated().map { index, row -> (key: String, record: DiaryDraft) in
            guard let stored = existing[row.key] else { return (row.key, row.draft) }
            let given = index < parsed.given.count ? parsed.given[index] : Set(row.draft.nutrients.known)
            return (row.key, merge(row.draft, over: stored, columns: parsed.columns, given: given, meals: meals))
        }
        return ImportPlan(incoming: incoming, existing: existing, skipped: parsed.skipped)
    }

    /// The meal slot a row goes to: the meal it names (a slot's name, its id or a synonym like
    /// "Frühstück"), else – without a meal – the one nearest its time, else Snacks.
    public static func mealID(_ draft: DiaryDraft, in meals: [MealSlot]) -> String {
        let slots = meals.isEmpty ? MealSlot.defaults : meals
        if let slot = MealSlot.matching(draft.meal, in: slots) { return slot.id }
        if draft.meal.trimmingCharacters(in: .whitespaces).isEmpty, let minutes = draft.minutes {
            return MealSlot.suggested(atMinutes: minutes, in: slots).id
        }
        return MealSlot.snack.id
    }

    /// The stored entry as a file with these columns shows it once read back (rounded to the file's
    /// precision, without what the file has no column for).
    public static func asExported(_ draft: DiaryDraft, columns: Set<String>? = nil) -> DiaryDraft {
        var text = export([("", draft)])
        if let columns { text = restricted(text, to: columns.union(["date", "food", "name"])) }
        return parse(text).rows.first?.draft ?? draft
    }

    /// The CSV with only these (canonical) columns.
    static func restricted(_ text: String, to columns: Set<String>) -> String {
        let table = CSV.parse(text)
        guard let header = table.first else { return text }
        let keep = header.indices.filter { columns.contains(ImportColumns.canonical(header[$0])) }
        return CSV.write(table.map { row in keep.map { $0 < row.count ? row[$0] : "" } })
    }

    /// What importing `incoming` makes of `stored`: a field changes only when the file has its
    /// column and its value differs from what an export of `stored` with those columns shows.
    /// A changed amount scales the stored totals (or, when that isn't possible and the row has no
    /// kcal, leaves them empty so the app looks the food up); an unchanged one keeps the entry's
    /// portion.
    public static func merge(_ incoming: DiaryDraft, over stored: DiaryDraft, columns: Set<String>, given: Set<Nutrient>,
                             meals: [MealSlot] = MealSlot.defaults) -> DiaryDraft {
        let shown = asExported(stored, columns: columns)
        var result = stored
        if incoming.day != shown.day { result.day = incoming.day }
        if columns.contains("time"), incoming.minutes != shown.minutes { result.minutes = incoming.minutes }
        if columns.contains("meal"), mealID(incoming, in: meals) != mealID(stored, in: meals) { result.meal = incoming.meal }
        if incoming.name != shown.name { result.name = incoming.name }
        if columns.contains("brand"), incoming.brand != shown.brand { result.brand = incoming.brand }
        if columns.contains("notes"), incoming.note != shown.note { result.note = incoming.note }
        if columns.contains("status"), incoming.status != shown.status { result.status = incoming.status }
        let amountChanged = !ImportColumns.sameValue(incoming.quantity, shown.quantity) || incoming.unitLabel != shown.unitLabel
            || !ImportColumns.sameValue(incoming.amount, shown.amount) || incoming.unit != shown.unit
        var base = stored.nutrients
        if amountChanged {
            result.quantity = incoming.quantity
            result.unitLabel = incoming.unitLabel
            result.amount = incoming.amount
            result.unit = incoming.unit
            if let ratio = scale(from: stored, to: incoming) {
                base = stored.nutrients.scaled(by: ratio)
            } else if !given.contains(.energy) {
                base = NutrientValues()
            }
        }
        result.nutrients = ImportColumns.mergeNutrients(incoming.nutrients, over: base, shown: shown.nutrients, given: given)
        return result
    }

    /// How much more (or less) the new amount is: by weight in the same unit, else by count of the
    /// same portion word; nil when the two can't be compared.
    static func scale(from old: DiaryDraft, to new: DiaryDraft) -> Double? {
        if old.amount > 0, new.amount > 0, old.unit == new.unit { return new.amount / old.amount }
        if old.amount == 0, new.amount == 0, old.quantity > 0, new.quantity > 0, old.unitLabel == new.unitLabel {
            return new.quantity / old.quantity
        }
        return nil
    }

    /// The file: the fixed columns (a base column when an entry is in ml or servings), plus a
    /// column for every other nutrient some row has (and sodium_mg), values at up to 4 decimals.
    /// `meals`: the meal slots, so a row says "Jause" instead of the slot's id. `key`: "id:<uuid>"
    /// writes the uuid as the row's id.
    public static func export(_ rows: [(key: String, draft: DiaryDraft)], meals: [MealSlot] = []) -> String {
        let nutrientColumns = ImportColumns.exportColumns(rows.map(\.draft.nutrients))
        let withBase = rows.contains { $0.draft.unit != .gram }
        let before = Array(header.prefix { $0 != "kcal" }) + (withBase ? ["base"] : [])
        var table = [before + nutrientColumns + ["note", "status"]]
        for (key, draft) in rows {
            let unit = draft.unitLabel.isEmpty ? draft.unit.symbol : draft.unitLabel
            let meal = meals.first { $0.id == draft.meal }?.name ?? draft.meal
            var row = [ImportColumns.exportID(forKey: key), draft.day.rawValue, draft.minutes.map(ClockTime.text) ?? "", meal,
                       draft.name, draft.brand, NumberText.plain(draft.quantity, decimals: 4), unit,
                       draft.amount > 0 ? NumberText.plain(draft.amount, decimals: 4) : ""]
            if withBase { row.append(draft.unit.symbol) }
            row += ImportColumns.exportCells(draft.nutrients, columns: nutrientColumns)
            row += [draft.note, draft.status == .eaten ? "" : draft.status.rawValue]
            table.append(row)
        }
        return CSV.write(table)
    }

    /// "2026-11-13", "13.11.2026", "13.11.26", "13/11/2026", "11/13/2026".
    public static func parseDate(_ raw: String) -> DayKey? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let key = DayKey(String(text.prefix(10))) { return key }
        let separators: Set<Character> = [".", "/", "-"]
        let parts = text.split(whereSeparator: { separators.contains($0) }).map { String($0.prefix(4)) }
        guard parts.count >= 3, let a = Int(parts[0]), let b = Int(parts[1]), var year = Int(parts[2].prefix(4)) else { return nil }
        if year < 100 { year += 2000 }
        var day = a, month = b
        if b > 12, a <= 12 { day = b; month = a }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return DayKey(year: year, month: month, day: day)
    }

    public static func prompt(appName: String, mealNames: [String]) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn what I ate (notes, screenshots or an export from another nutrition app) into diary rows. Nutrition values are the TOTALS for each row, not per 100 g.",
            columns: columns,
            rules: [
                "One row per food eaten. A meal with several foods becomes several rows with the same date and meal.",
                "Use the values from my data. If you must estimate, use reliable sources (product labels, USDA, BLS) and say so in the note column.",
                "Decimal point, not comma. No units inside the number cells.",
                "Leave the id column empty for new rows; keep ids that are already in my data (Nina writes them when it exports).",
            ],
            existingNames: [("Meals", mealNames)],
            exampleRows: [
                ["", "2026-11-12", "07:30", "breakfast", "Oats", "", "60", "g", "60", "233", "8.1", "40", "4.1", "6", "0.6", "0.7", "0", "", ""],
                ["", "2026-11-12", "07:30", "breakfast", "Banana", "", "1", "piece", "118", "105", "1.3", "27", "0.4", "3.1", "14.4", "0.1", "0", "", ""],
            ]
        )
    }
}
