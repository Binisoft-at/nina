import Foundation
import BinisoftKitCore

/// Which of Nina's CSV formats a file is.
public enum ImportKind: String, CaseIterable, Sendable, Identifiable {
    case settings, foods, recipes, diary, measurements

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .settings: "Goals & Settings"
        case .foods: "Foods"
        case .diary: "Diary"
        case .recipes: "Meals & Recipes"
        case .measurements: "Weight & Body"
        }
    }

    /// For the segmented picker.
    public var shortTitle: String {
        switch self {
        case .settings: "Goals"
        case .foods: "Foods"
        case .diary: "Diary"
        case .recipes: "Recipes"
        case .measurements: "Body"
        }
    }

    public var subtitle: String {
        switch self {
        case .settings: "Your body data, goal, daily targets, training days, meal times and preferences – from a few lines about you."
        case .foods: "Your foods with their nutrition values – from labels, a spreadsheet or another app."
        case .diary: "What you ate on which day – e.g. an export from another app."
        case .recipes: "Saved meals (logged together) and recipes (cooked, then eaten in portions)."
        case .measurements: "Past weigh-ins, tape measurements and body-fat results – from a DEXA, InBody or 3D-scan report, an old spreadsheet or another app."
        }
    }

    /// Guesses the format from the header line (or, for goals & settings, from rows without one).
    public static func detect(_ text: String) -> ImportKind? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return nil }
        if let kind = detectHeader(first, following: Array(lines.dropFirst().prefix(4))) { return kind }
        return SettingsCSV.looksLikeSettings(Array(lines.prefix(12))) ? .settings : nil
    }

    /// The format whose header this line is (`setting,value`, or a header with the columns of the
    /// other formats); nil for anything else. `following`: the next few lines, for the delimiter.
    public static func detectHeader(_ line: String, following: [String] = []) -> ImportKind? {
        let firstCell = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" }).first.map(String.init) ?? ""
        if SettingsCSV.isHeader([firstCell]) { return .settings }
        let cells = CSV.parse(([line] + following).joined(separator: "\n")).first ?? []
        let header = cells.map(ImportColumns.canonical)
        let set = Set(header)
        if set.contains("recipe") || set.contains("ingredient") { return .recipes }
        // Before the diary: a weight & body history has a date too.
        if BodyHistoryCSV.isHeader(cells) { return .measurements }
        if set.contains("date") { return .diary }
        if set.contains("name") || set.contains("food") { return .foods }
        return nil
    }
}

/// Column names: canonical keys plus the variants people and AIs write ("Energy (kcal)",
/// "Kalorien", "Eiweiß", "davon Zucker").
public enum ImportColumns {
    /// "Energy (kcal)" → "energy_kcal", "Gesättigte Fettsäuren" → "gesattigte_fettsauren"
    public static func normalize(_ header: String) -> String {
        var text = header
        if let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            let unit = text[text.index(after: open)..<close]
            text = String(text[..<open]) + " " + unit
        }
        return SearchText.normalize(text).replacingOccurrences(of: " ", with: "_")
    }

    static let aliases: [String: String] = {
        var map: [String: String] = [:]
        let groups: [String: [String]] = [
            "id": ["id", "key", "nr", "number", "row_id"],
            "name": ["name", "food_name", "product", "product_name", "lebensmittel", "bezeichnung", "title", "produkt", "artikel",
                     "lebensmittelname", "nahrungsmittel", "produktname"],
            "name_de": ["name_de", "german_name", "name_german", "deutsch", "name_deutsch"],
            "food": ["food", "item", "food_item", "speise"],
            "brand": ["brand", "brands", "marke", "hersteller", "manufacturer"],
            "category": ["category", "kategorie", "group", "food_group", "gruppe"],
            "tags": ["tags", "tag", "labels", "schlagworter"],
            "unit": ["unit", "einheit", "per", "basis", "base_unit"],
            "kcal": ["kcal", "energy_kcal", "calories", "kalorien", "energy", "energie", "calories_kcal", "kcal_100g", "energy_kcal_100g", "brennwert", "brennwert_kcal", "energie_kcal"],
            "kj": ["kj", "energy_kj", "kilojoule", "kilojoules", "brennwert_kj", "energie_kj"],
            "protein": ["protein", "proteins", "protein_g", "eiweiss", "eiweiss_g", "proteine"],
            "carbs": ["carbs", "carbohydrates", "carbohydrate", "carbs_g", "carbohydrates_g", "kohlenhydrate", "kh", "kohlenhydrate_g"],
            "fat": ["fat", "fat_g", "total_fat", "fett", "fett_g"],
            "fiber": ["fiber", "fibre", "fiber_g", "fibre_g", "ballaststoffe", "dietary_fiber", "ballaststoffe_g"],
            "sugar": ["sugar", "sugars", "sugar_g", "sugars_g", "zucker", "davon_zucker", "zucker_g"],
            "saturated_fat": ["saturated_fat", "saturates", "sat_fat", "saturated", "saturated_fat_g", "gesattigte_fettsauren", "davon_gesattigte_fettsauren", "gesattigte_fette"],
            "salt": ["salt", "salt_g", "salz", "salz_g"],
            "sodium_mg": ["sodium_mg", "sodium", "natrium", "natrium_mg"],
            "portions": ["portions", "portionen", "serving_sizes", "portion_sizes", "household_portions"],
            "barcode": ["barcode", "ean", "gtin", "upc", "code", "strichcode"],
            "favorite": ["favorite", "favourite", "fav", "favorit", "starred"],
            "notes": ["notes", "note", "notiz", "notizen", "comment", "kommentar"],
            "date": ["date", "datum", "day", "tag_datum"],
            "time": ["time", "uhrzeit", "zeit"],
            "meal": ["meal", "mahlzeit", "meal_type"],
            "amount": ["amount", "quantity", "menge", "anzahl", "qty"],
            "grams": ["grams", "gram", "g", "gramm", "weight", "weight_g", "gewicht", "amount_g", "ml"],
            "status": ["status", "state"],
            "recipe": ["recipe", "rezept", "meal_name", "recipe_name"],
            "kind": ["kind", "type", "art", "typ"],
            "servings": ["servings_count", "recipe_servings", "anzahl_portionen", "yield", "servings"],
            "total_weight_g": ["total_weight_g", "total_weight", "cooked_weight", "gesamtgewicht", "weight_cooked"],
            "ingredient": ["ingredient", "zutat", "ingredient_name"],
            "monounsaturated_fat": ["monounsaturated_fat", "mufa", "einfach_ungesattigte_fettsauren"],
            "polyunsaturated_fat": ["polyunsaturated_fat", "pufa", "mehrfach_ungesattigte_fettsauren"],
            "trans_fat": ["trans_fat", "transfett", "trans_fettsauren"],
            "cholesterol_mg": ["cholesterol_mg", "cholesterol", "cholesterin"],
            "potassium_mg": ["potassium_mg", "potassium", "kalium"],
            "calcium_mg": ["calcium_mg", "calcium", "kalzium"],
            "iron_mg": ["iron_mg", "iron", "eisen"],
            "magnesium_mg": ["magnesium_mg", "magnesium"],
            "zinc_mg": ["zinc_mg", "zinc", "zink"],
            "vitamin_a_ug": ["vitamin_a_ug", "vitamin_a", "vitamin_a_µg", "vitamin_a_mcg"],
            "vitamin_c_mg": ["vitamin_c_mg", "vitamin_c"],
            "vitamin_d_ug": ["vitamin_d_ug", "vitamin_d", "vitamin_d_µg", "vitamin_d_mcg"],
            "vitamin_e_mg": ["vitamin_e_mg", "vitamin_e"],
            "vitamin_b12_ug": ["vitamin_b12_ug", "vitamin_b12", "b12", "vitamin_b12_µg", "vitamin_b12_mcg"],
            "folate_ug": ["folate_ug", "folate", "folsaure", "folic_acid", "folate_µg", "folate_mcg"],
            "water_g": ["water_g", "water", "wasser"],
            "alcohol_g": ["alcohol_g", "alcohol", "alkohol"],
            "caffeine_mg": ["caffeine_mg", "caffeine", "koffein"],
        ]
        for (canonical, names) in groups {
            for name in names { map[normalize(name)] = canonical }
        }
        return map
    }()

    /// The canonical key for a header cell (unknown headers keep their normalised text).
    public static func canonical(_ header: String) -> String {
        let key = normalize(header)
        return aliases[key] ?? key
    }

    /// CSV rows with canonical keys. An amount with its unit glued on ("40.00 g", "2 slices") is
    /// split into amount and unit when the row's unit cell is empty.
    public static func records(_ text: String) -> (header: [String], rows: [[String: String]]) {
        let table = CSV.parse(text)
        guard let first = table.first else { return ([], []) }
        let keys = first.map(canonical)
        let rows = table.dropFirst().map { values -> [String: String] in
            var record: [String: String] = [:]
            for (index, key) in keys.enumerated() where index < values.count {
                let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                // The first non-empty column wins when two headers map to the same key.
                if record[key]?.isEmpty ?? true { record[key] = value }
            }
            if (record["unit"] ?? "").isEmpty, let amount = record["amount"], let split = splitAmount(amount) {
                record["amount"] = split.number
                record["unit"] = split.unit
            }
            return record
        }
        return (keys, Array(rows))
    }

    /// "40.00 g" → ("40.00", "g"), "2 slices" → ("2", "slices"); nil without a number or a unit.
    static func splitAmount(_ raw: String) -> (number: String, unit: String)? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let index = text.firstIndex(where: { $0.isLetter }), index > text.startIndex else { return nil }
        let number = String(text[..<index]).trimmingCharacters(in: .whitespaces)
        let unit = String(text[index...]).trimmingCharacters(in: .whitespaces)
        guard !unit.isEmpty, self.number(number) != nil else { return nil }
        return (number, unit)
    }

    /// Nutrient columns shared by every format (energy handled separately: kcal or kJ).
    static let nutrientColumns: [(column: String, nutrient: Nutrient)] = [
        ("protein", .protein), ("carbs", .carbs), ("fat", .fat), ("fiber", .fiber), ("sugar", .sugar),
        ("saturated_fat", .saturatedFat), ("monounsaturated_fat", .monoFat), ("polyunsaturated_fat", .polyFat),
        ("trans_fat", .transFat), ("cholesterol_mg", .cholesterol), ("potassium_mg", .potassium),
        ("calcium_mg", .calcium), ("iron_mg", .iron), ("magnesium_mg", .magnesium), ("zinc_mg", .zinc),
        ("vitamin_a_ug", .vitaminA), ("vitamin_c_mg", .vitaminC), ("vitamin_d_ug", .vitaminD),
        ("vitamin_e_mg", .vitaminE), ("vitamin_b12_ug", .vitaminB12), ("folate_ug", .folate),
        ("water_g", .water), ("alcohol_g", .alcohol), ("caffeine_mg", .caffeine),
    ]

    /// Reads the nutrient columns of a row. Energy from kcal, else kJ; sodium from sodium_mg, else salt.
    static func nutrients(_ record: [String: String]) -> NutrientValues {
        var values = NutrientValues()
        if let kcal = number(record["kcal"]) {
            values[.energy] = kcal
        } else if let kj = number(record["kj"]) {
            values[.energy] = kj / EnergyUnit.kilojoulesPerKilocalorie
        }
        for (column, nutrient) in nutrientColumns {
            if let value = number(record[column]) { values[nutrient] = value }
        }
        if let sodium = number(record["sodium_mg"]) {
            values[.sodium] = sodium
        } else if let salt = number(record["salt"]) {
            values[.sodium] = NutrientValues.sodium(fromSalt: salt)
        }
        return values
    }

    /// The eight nutrient cells of the fixed-header exports, in this order.
    static let exportNutrients: [(column: String, value: (NutrientValues) -> Double?)] = [
        ("kcal", { $0[.energy] }), ("protein", { $0[.protein] }), ("carbs", { $0[.carbs] }), ("fat", { $0[.fat] }),
        ("fiber", { $0[.fiber] }), ("sugar", { $0[.sugar] }), ("saturated_fat", { $0[.saturatedFat] }), ("salt", { $0.salt }),
    ]

    static func exportCells(_ values: NutrientValues) -> [String] {
        exportNutrients.map { item in item.value(values).map { NumberText.plain($0, decimals: 4) } ?? "" }
    }

    /// Every nutrient column an export can write, in order: kcal and the seven label columns, the
    /// other nutrients, sodium_mg.
    static let allExportColumns: [String] = exportNutrients.map(\.column)
        + nutrientColumns.map(\.column).filter { !["protein", "carbs", "fat", "fiber", "sugar", "saturated_fat"].contains($0) }
        + ["sodium_mg"]

    /// The nutrient columns of an export: kcal, protein, carbs, fat, fiber, sugar, saturated fat and
    /// salt always, every other nutrient (and sodium_mg) when a row has it – so nothing a record
    /// stores is lost, and importing the file again changes nothing.
    public static func exportColumns(_ rows: [NutrientValues]) -> [String] {
        let fixed = Set(exportNutrients.map(\.column))
        return allExportColumns.filter { column in
            fixed.contains(column) || rows.contains { exportValue(column, $0) != nil }
        }
    }

    /// The value an export writes in a nutrient column.
    static func exportValue(_ column: String, _ values: NutrientValues) -> Double? {
        switch column {
        case "kcal": return values[.energy]
        case "salt": return values.salt
        case "sodium_mg": return values[.sodium]
        default: return nutrientColumns.first { $0.column == column }.flatMap { values[$0.nutrient] }
        }
    }

    /// The cells of these columns, at up to 4 decimals (the precision Nina stores).
    public static func exportCells(_ values: NutrientValues, columns: [String]) -> [String] {
        columns.map { column in exportValue(column, values).map { NumberText.plain($0, decimals: 4) } ?? "" }
    }

    /// The nutrients a row's cells give (energy from kcal or kJ, sodium from sodium_mg or salt). An
    /// empty cell gives nothing, so importing keeps the value Nina has.
    static func givenNutrients(_ record: [String: String]) -> Set<Nutrient> {
        Set(nutrients(record).known)
    }

    /// Whether two values are the same once written to a file: equal at 4 decimals, or within the
    /// 2-decimal rounding of files exported by earlier versions.
    static func sameValue(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 0.0051
        default: return false
        }
    }

    /// `incoming` over `stored`: a nutrient the row gives replaces the stored value when it differs
    /// from what the export shows (`shown`); everything else keeps the stored value.
    static func mergeNutrients(_ incoming: NutrientValues, over stored: NutrientValues, shown: NutrientValues,
                               given: Set<Nutrient>) -> NutrientValues {
        var result = stored
        for nutrient in given where !sameValue(incoming[nutrient], shown[nutrient]) {
            result[nutrient] = incoming[nutrient]
        }
        return result
    }

    /// "1,5" and "1.5" and "1.234,5" and "1 234"; units glued to the number are ignored ("120 kcal",
    /// "4,5g"), and so are approximations, limits and footnotes ("~52", "ca. 52", "<0.5",
    /// "12.5 (est.)", "3*").
    static func number(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        // A remark in brackets after the number: "12.5 (est.)", "52 (approx)".
        if text.hasSuffix(")"), let open = text.lastIndex(of: "("), open > text.startIndex {
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        }
        text = withoutApproximation(text)
        text = text.trimmingCharacters(in: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "µ%*")))
        guard !text.isEmpty, text != "-", text != "–" else { return nil }
        text = withoutThousandsSpaces(text)
        if text.contains(","), text.contains(".") {
            // 1.234,5 (German) or 1,234.5 (English)
            if let comma = text.lastIndex(of: ","), let dot = text.lastIndex(of: "."), comma > dot {
                text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        }
        guard let value = NumberText.parse(text), value >= 0 else { return nil }
        return value
    }

    /// What people and AIs put in front of a number they aren't sure of, or of a value under or
    /// over a limit (EU labels print "<0.5 g").
    static let approximationPrefixes = ["~", "≈", "<", "≤", ">", "≥", "*", "ca.", "ca", "circa", "approx.", "approx", "about", "etwa", "rund"]

    /// The text without an approximation in front ("~52" → "52", "ca. 80" → "80", "< 0.5" → "0.5").
    /// A word ("ca", "about") counts only when no letter follows it.
    static func withoutApproximation(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for prefix in approximationPrefixes where text.lowercased().hasPrefix(prefix) {
                let rest = text.dropFirst(prefix.count)
                if prefix.last?.isLetter == true, let next = rest.first, next.isLetter { continue }
                text = String(rest).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return text
    }

    /// "1 234" and "12 345,5" (a space before each group of exactly three digits) → "1234", "12345,5".
    static func withoutThousandsSpaces(_ text: String) -> String {
        let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}"]
        let parts = text.split(whereSeparator: { spaces.contains($0) }).map(String.init)
        guard parts.count > 1, let head = parts.first, (1...3).contains(head.count), head.allSatisfy(\.isNumber) else { return text }
        for (index, part) in parts.enumerated().dropFirst() {
            let isLast = index == parts.count - 1
            let digits = isLast ? String(part.prefix { $0.isNumber }) : part
            guard digits.count == 3, digits.allSatisfy(\.isNumber) else { return text }
            if isLast, let next = part.dropFirst(3).first, next != ",", next != "." { return text }
        }
        return parts.joined()
    }

    static func isYes(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return ["yes", "y", "true", "1", "x", "ja", "j", "✓", "✔", "★", "fav", "favorite"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func list(_ raw: String?) -> [String] {
        (raw ?? "").split(whereSeparator: { $0 == "," || $0 == "|" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// "id:7" → "7"; content keys stay as they are.
    public static func exportID(forKey key: String) -> String {
        key.hasPrefix("id:") ? String(key.dropFirst(3)) : key
    }

    /// Every key a stored record answers to (its import key and the key its exported row comes back with).
    public static func lookupKeys(forKey key: String) -> [String] {
        let exported = "id:" + exportID(forKey: key)
        return exported == key ? [key] : [key, exported]
    }

    /// Every key a stored record answers to: "id:<uuid>" (what the exports write) and the key it
    /// was imported with.
    public static func lookupKeys(uuid: UUID, importKey: String) -> [String] {
        let own = idKey(uuid)
        return importKey.isEmpty || importKey == own ? [own] : [own, importKey]
    }

    /// "id:<UUID>" – the key of an exported row.
    public static func idKey(_ uuid: UUID) -> String {
        "id:" + uuid.uuidString
    }

    /// The key a row is matched by: its id when that is one of Nina's own (a UUID, which the exports
    /// write), else the content key. Ids an AI numbers 1, 2, 3 … start again in every conversation,
    /// so they never match anything by themselves.
    public static func rowKey(id: String, content: [String]) -> String {
        if let uuid = UUID(uuidString: id.trimmingCharacters(in: .whitespaces)) { return idKey(uuid) }
        return ImportPlan<String>.contentKey(content)
    }
}
