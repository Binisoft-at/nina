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
}

/// Nina's diary CSV: one row per thing eaten, nutrition values are the totals for that row.
public enum DiaryCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("id", "A stable id per row (1, 2, 3 …)."),
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

    public struct Parsed {
        public var rows: [(key: String, draft: DiaryDraft)]
        public var skipped: [String]
    }

    public static func parse(_ text: String) -> Parsed {
        let (header, records) = ImportColumns.records(text)
        guard header.contains("date") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}date\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        var rows: [(key: String, draft: DiaryDraft)] = []
        var skipped: [String] = []
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let name = (record["food"].flatMap { $0.isEmpty ? nil : $0 } ?? record["name"] ?? "").trimmingCharacters(in: .whitespaces)
            guard let day = parseDate(record["date"] ?? "") else {
                skipped.append("Row \(line): date \u{201C}\(record["date"] ?? "")\u{201D} not understood (use YYYY-MM-DD)")
                continue
            }
            let nutrients = ImportColumns.nutrients(record)
            guard !name.isEmpty || nutrients[.energy] != nil else {
                skipped.append("Row \(line): no food")
                continue
            }
            let unitText = (record["unit"] ?? "").trimmingCharacters(in: .whitespaces)
            let quantity = ImportColumns.number(record["amount"]) ?? 1
            var amount = ImportColumns.number(record["grams"]) ?? 0
            var unit = BaseUnit.gram
            switch SearchText.normalize(unitText) {
            case "g", "gram", "grams", "gramm":
                if amount == 0 { amount = quantity }
            case "ml", "milliliter":
                if amount == 0 { amount = quantity }
                unit = .milliliter
            case "kg": if amount == 0 { amount = quantity * 1000 }
            case "l", "liter", "litre":
                if amount == 0 { amount = quantity * 1000 }
                unit = .milliliter
            default: break
            }
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
                amount: amount,
                unit: unit,
                nutrients: values,
                note: record["note"] ?? record["notes"] ?? "",
                status: EntryStatus(text: record["status"] ?? "")
            )
            let id = (record["id"] ?? "").trimmingCharacters(in: .whitespaces)
            let key = id.isEmpty
                ? ImportPlan<DiaryDraft>.contentKey([day.rawValue, draft.meal, draft.name, NumberText.plain(draft.quantity), draft.unitLabel])
                : "id:" + id
            rows.append((key, draft))
        }
        return Parsed(rows: rows, skipped: skipped)
    }

    public static func plan(_ text: String, existing: [String: DiaryDraft]) -> ImportPlan<DiaryDraft> {
        let parsed = parse(text)
        return ImportPlan(incoming: parsed.rows.map { ($0.key, $0.draft) }, existing: existing, skipped: parsed.skipped)
    }

    public static func export(_ rows: [(key: String, draft: DiaryDraft)]) -> String {
        var table = [header]
        for (key, draft) in rows {
            let unit = draft.unitLabel.isEmpty ? draft.unit.symbol : draft.unitLabel
            var row = [ImportColumns.exportID(forKey: key), draft.day.rawValue, draft.minutes.map(ClockTime.text) ?? "", draft.meal,
                       draft.name, draft.brand, NumberText.plain(draft.quantity, decimals: 2), unit,
                       draft.amount > 0 ? NumberText.plain(draft.amount, decimals: 1) : ""]
            row += ImportColumns.exportCells(draft.nutrients)
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
                "Number the id column 1, 2, 3 … unless my data already has ids.",
            ],
            existingNames: [("Meals", mealNames)],
            exampleRows: [
                ["1", "2026-11-12", "07:30", "breakfast", "Oats", "", "60", "g", "60", "233", "8.1", "40", "4.1", "6", "0.6", "0.7", "0", "", ""],
                ["2", "2026-11-12", "07:30", "breakfast", "Banana", "", "1", "piece", "118", "105", "1.3", "27", "0.4", "3.1", "14.4", "0.1", "0", "", ""],
            ]
        )
    }
}
