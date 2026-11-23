import Foundation

/// The unit someone typed or dictated in quick add.
public enum QuickUnit: Equatable, Sendable {
    /// g, kg, dag, oz, lb – grams per unit.
    case mass(Double)
    /// ml, l, Achtel, Krügerl – millilitres per unit.
    case volume(Double)
    /// A household word that should match one of the food's portions ("slice", "Scheibe",
    /// "medium", "EL"). `fallback` is used when the food has no such portion (ml for spoons/cups,
    /// nil = the food's default portion).
    case portion(group: String, fallbackMilliliters: Double?)
    /// "350 kcal" – an entry without a food.
    case kilocalories
    case kilojoules
}

/// One thing in a quick-add line: "200 g chicken breast" → 200 × g, "chicken breast".
public struct QuickItem: Equatable, Sendable {
    public var original: String
    public var quantity: Double?
    public var unit: QuickUnit?
    /// What to search for ("chicken breast"); may be empty for "350 kcal".
    public var query: String

    public init(original: String, quantity: Double?, unit: QuickUnit?, query: String) {
        self.original = original
        self.quantity = quantity
        self.unit = unit
        self.query = query
    }

    /// "350 kcal" without a food: logged as a quick calorie entry.
    public var isEnergyOnly: Bool {
        switch unit {
        case .kilocalories?, .kilojoules?: true
        default: false
        }
    }

    public var kilocalories: Double? {
        guard let quantity else { return nil }
        switch unit {
        case .kilocalories?: return quantity
        case .kilojoules?: return quantity / EnergyUnit.kilojoulesPerKilocalorie
        default: return nil
        }
    }
}

/// How much of a food a quick item means.
public struct QuickAmount: Equatable, Sendable {
    /// In the food's base unit (g, ml or servings).
    public var amount: Double
    /// The household portion used, if any.
    public var serving: Serving?
    /// How many of `serving` (or of the base unit when `serving` is nil).
    public var count: Double

    public init(amount: Double, serving: Serving?, count: Double) {
        self.amount = amount
        self.serving = serving
        self.count = count
    }
}

/// Parses what people type or dictate: "200 g chicken breast, 2 eggs and 1 Semmel",
/// "Banane", "1/2 avocado", "Achtel Rotwein", "10 dag Extrawurst", "350 kcal snack".
/// English and German (incl. Austrian measures). Pure text work – the app resolves the
/// queries with `FoodSearchIndex` and shows a preview before anything is logged.
public enum QuickParser {
    public static func parse(_ text: String) -> [QuickItem] {
        chunks(text).compactMap(parseChunk)
    }

    // MARK: Splitting

    static func chunks(_ text: String) -> [String] {
        var pieces: [String] = []
        for line in separated(text) {
            for part in splitOnJoiners(line) {
                pieces.append(contentsOf: splitOnAmounts(part))
            }
        }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Splits on line breaks, ",", ";", "+" and "&" – but not on a comma between two digits, so
    /// German decimals stay whole ("1,5 l Milch", "Joghurt 3,5%").
    static func separated(_ text: String) -> [String] {
        let characters = Array(text)
        var parts: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let isSeparator: Bool
            switch character {
            case ";", "+", "&": isSeparator = true
            case ",":
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                isSeparator = !(before.isNumber && after.isNumber)
            default: isSeparator = character.isNewline
            }
            if isSeparator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    /// Splits on "and / und / with / mit / plus" only when the next part starts with an amount,
    /// so "fish and chips" and "Salz und Pfeffer" stay one food. `always` splits on every joiner
    /// between two words (the second try when a line found no food: "2 Semmeln mit Butter").
    static func splitOnJoiners(_ line: String, always: Bool = false) -> [String] {
        let words = line.split(separator: " ").map(String.init)
        guard words.count > 2 else { return [line] }
        var parts: [[String]] = [[]]
        var index = 0
        while index < words.count {
            let word = words[index]
            let lowered = SearchText.normalize(word)
            if joiners.contains(lowered), !(parts.last?.isEmpty ?? true), index + 1 < words.count,
               always || startsWithAmount(Array(words[(index + 1)...])) {
                parts.append([])
            } else {
                parts[parts.count - 1].append(word)
            }
            index += 1
        }
        return parts.filter { !$0.isEmpty }.map { $0.joined(separator: " ") }
    }

    /// Splits "3 eggs 2 toast" before a new number – only when the part starts with a number and
    /// both sides name a food, so "Cola 0,5 l", "Joghurt 3,5%" and "Rotwein 1 Achtel" stay whole.
    /// A percentage is part of a name ("1 Joghurt 0,1 % Fett").
    static func splitOnAmounts(_ part: String) -> [String] {
        let words = part.split(separator: " ").map(String.init)
        guard words.count >= 4, let first = words.first, leadingNumber(first) != nil || multiplierToken(first) != nil else {
            return [part]
        }
        func isPercent(_ index: Int) -> Bool {
            if let (_, rest) = leadingNumber(words[index]), rest.hasPrefix("%") { return true }
            return index + 1 < words.count && words[index + 1].hasPrefix("%")
        }
        var result: [String] = []
        var current: [String] = []
        for (index, word) in words.enumerated() {
            if index > 1, current.count > 1, leadingNumber(word) != nil, !isPercent(index),
               namesFood(current.joined(separator: " ")),
               namesFood(words[index...].joined(separator: " ")) {
                result.append(current.joined(separator: " "))
                current = [word]
            } else {
                current.append(word)
            }
        }
        result.append(current.joined(separator: " "))
        return result
    }

    /// True when a chunk leaves a food to search for: a word with a letter that isn't a unit
    /// ("2 toast" yes; "0,5 l" and "3,5%" no).
    static func namesFood(_ chunk: String) -> Bool {
        guard let item = parseChunk(chunk) else { return false }
        return item.query.split(separator: " ").contains { word in
            let normalized = SearchText.normalize(String(word))
            return normalized.contains(where: \.isLetter) && unit(for: normalized) == nil && leadingNumber(String(word)) == nil
        }
    }

    /// The items of a line that found no food, split on every joiner ("2 Semmeln mit Butter" →
    /// "2 Semmeln", "Butter"); empty when the line has no joiner between two words.
    public static func splitOnEveryJoiner(_ item: QuickItem) -> [QuickItem] {
        let parts = splitOnJoiners(item.original, always: true)
        guard parts.count > 1 else { return [] }
        return parts.compactMap(parseChunk)
    }

    static let joiners: Set<String> = ["and", "und", "with", "mit", "plus", "sowie"]

    static func startsWithAmount(_ words: [String]) -> Bool {
        guard let first = words.first else { return false }
        if leadingNumber(first) != nil { return true }
        let lowered = SearchText.normalize(first)
        return numberWords[lowered] != nil || unit(for: lowered) != nil
    }

    // MARK: One chunk

    static func parseChunk(_ chunk: String) -> QuickItem? {
        var words = chunk.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        var quantity: Double?
        var unit: QuickUnit?

        // Leading "2x" / "x2".
        if let multiplier = multiplierToken(words[0]) {
            quantity = multiplier
            words.removeFirst()
        }

        // Leading number, possibly glued to a unit ("200g", "1,5l", "½").
        if quantity == nil, let first = words.first {
            if let (number, rest) = leadingNumber(first) {
                quantity = number
                words.removeFirst()
                if !rest.isEmpty {
                    if let parsed = Self.unit(for: SearchText.normalize(rest)) {
                        unit = parsed
                    } else {
                        words.insert(rest, at: 0)
                    }
                }
            } else if let number = numberWords[SearchText.normalize(first)] {
                quantity = number
                words.removeFirst()
            }
            // "1 1/2", "2 ½"
            if let current = quantity, let next = words.first, let fraction = fractionOnly(next) {
                quantity = current + fraction
                words.removeFirst()
            }
            // "eine halbe Semmel", "ein halbes Brot", "zwei halbe" (= 1), "a half": the number counts halves.
            if let current = quantity, let next = words.first, halfWords.contains(SearchText.normalize(next)) {
                quantity = current * 0.5
                words.removeFirst()
            }
            // "half a cup"
            if quantity == 0.5, words.count > 1, let next = words.first, ["a", "an"].contains(SearchText.normalize(next)) {
                words.removeFirst()
            }
        }

        // Unit after the number ("200 g", "2 Scheiben", "1 Achtel"); also a unit without a number ("Achtel Rotwein").
        if unit == nil, let first = words.first {
            if let parsed = Self.unit(for: SearchText.normalize(first)), words.count > 1 || quantity != nil {
                unit = parsed
                words.removeFirst()
                if quantity == nil { quantity = 1 }
            } else if words.count > 1, let parsed = twoWordUnit(words[0], words[1]) {
                unit = parsed
                words.removeFirst(2)
            }
        }

        // Filler words: "of", "Stück", "von".
        while let first = words.first, fillers.contains(SearchText.normalize(first)) {
            words.removeFirst()
        }

        // Trailing amount: "chicken breast 200g", "Banane x2", "Rotwein 1 Achtel".
        if quantity == nil, words.count >= 2 {
            let last = words[words.count - 1]
            if let multiplier = multiplierToken(last) {
                quantity = multiplier
                words.removeLast()
            } else if let (number, rest) = leadingNumber(last) {
                if rest.isEmpty {
                    quantity = number
                    words.removeLast()
                } else if let parsed = Self.unit(for: SearchText.normalize(rest)) {
                    quantity = number
                    unit = parsed
                    words.removeLast()
                }
            } else if words.count >= 3, let parsed = Self.unit(for: SearchText.normalize(last)),
                      let (number, rest) = leadingNumber(words[words.count - 2]), rest.isEmpty {
                quantity = number
                unit = parsed
                words.removeLast(2)
            }
        }

        let query = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty, quantity == nil { return nil }
        if query.isEmpty, unit != .kilocalories, unit != .kilojoules { return nil }
        return QuickItem(original: chunk, quantity: quantity, unit: unit, query: query)
    }

    // MARK: Amount for a resolved food

    /// The amount of `food` an item means. Without a unit, a number counts the food's first
    /// portion ("2 eggs"), or grams when the number is large ("chicken 200").
    public static func amount(for item: QuickItem, food: FoodRecord) -> QuickAmount {
        let quantity = item.quantity ?? 1
        switch item.unit {
        case .mass(let grams)?:
            let total = quantity * grams
            switch food.unit {
            case .gram: return QuickAmount(amount: total, serving: nil, count: total)
            case .milliliter:
                let ml = total / food.density
                return QuickAmount(amount: ml, serving: nil, count: ml)
            case .serving: return defaultPortion(food, count: quantity)
            }
        case .volume(let milliliters)?:
            let total = quantity * milliliters
            switch food.unit {
            case .milliliter: return QuickAmount(amount: total, serving: nil, count: total)
            case .gram:
                let grams = total * food.density
                return QuickAmount(amount: grams, serving: nil, count: grams)
            case .serving: return defaultPortion(food, count: quantity)
            }
        case .portion(let group, let fallback)?:
            if let serving = matchingServing(food, group: group) {
                return QuickAmount(amount: serving.amount * quantity, serving: serving, count: quantity)
            }
            if let fallback, food.unit != .serving {
                let base = food.unit == .gram ? fallback * food.density : fallback
                return QuickAmount(amount: base * quantity, serving: nil, count: base * quantity)
            }
            return defaultPortion(food, count: quantity)
        case .kilocalories?, .kilojoules?:
            return defaultPortion(food, count: 1)
        case nil:
            if item.quantity == nil {
                if food.usualAmount > 0 {
                    return QuickAmount(amount: food.usualAmount, serving: nil, count: food.usualAmount)
                }
                return defaultPortion(food, count: 1)
            }
            // "2 eggs", "12 almonds", "1 Semmel": a count of pieces. "chicken 200": grams, because
            // nobody eats 200 fillets – a big bare number on a food with big portions is a weight.
            if let piece = countServing(food) {
                if quantity >= 10, piece.amount >= 20, food.unit != .serving {
                    return QuickAmount(amount: quantity, serving: nil, count: quantity)
                }
                return QuickAmount(amount: piece.amount * quantity, serving: piece, count: quantity)
            }
            if food.unit != .serving, quantity >= 10 {
                return QuickAmount(amount: quantity, serving: nil, count: quantity)
            }
            return defaultPortion(food, count: quantity)
        }
    }

    static func defaultPortion(_ food: FoodRecord, count: Double) -> QuickAmount {
        if let serving = food.servings.first {
            return QuickAmount(amount: serving.amount * count, serving: serving, count: count)
        }
        if food.unit == .serving {
            return QuickAmount(amount: count, serving: nil, count: count)
        }
        let amount = food.usualAmount > 0 ? food.usualAmount * count : food.unit.basis * count
        return QuickAmount(amount: amount, serving: nil, count: amount)
    }

    /// The portion a plain count refers to: a piece, an egg, a slice, a medium one …
    static func countServing(_ food: FoodRecord) -> Serving? {
        food.servings.first { serving in
            let tokens = SearchText.normalize(serving.en).split(separator: " ").map(String.init)
                + SearchText.normalize(serving.de).split(separator: " ").map(String.init)
            return tokens.contains { countWords.contains($0) }
        }
    }

    static let countWords: Set<String> = [
        "piece", "pieces", "stuck", "stk", "medium", "mittelgross", "mittel", "egg", "ei", "slice", "scheibe",
        "fillet", "filet", "half", "halfte", "clove", "zehe", "grape", "traube", "roll", "semmel", "bar", "riegel",
        "breast", "brust", "leg", "keule", "patty", "laberl", "sausage", "wurstel", "pod", "floret", "rosschen",
        "square", "fruit", "frucht", "cookie", "keks", "biscuit", "bun", "pretzel", "brezel", "dumpling", "knodel",
        "pancake", "tortilla", "wrap", "croissant", "muffin", "donut", "krapfen", "scoop", "kugel", "can", "dose",
        "bottle", "flasche", "glass", "glas", "cup", "tasse", "becher", "pot", "small", "klein", "large", "gross",
    ]

    static func matchingServing(_ food: FoodRecord, group: String) -> Serving? {
        let words = portionGroups[group] ?? [group]
        return food.servings.first { serving in
            let tokens = Set(SearchText.normalize(serving.en).split(separator: " ").map(String.init)
                + SearchText.normalize(serving.de).split(separator: " ").map(String.init))
            return words.contains { tokens.contains($0) }
        }
    }

    // MARK: Vocabulary

    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "ein": 1, "eine": 1, "einen": 1, "einem": 1, "einer": 1,
        "two": 2, "zwei": 2, "three": 3, "drei": 3, "four": 4, "vier": 4, "five": 5, "funf": 5,
        "six": 6, "sechs": 6, "seven": 7, "sieben": 7, "eight": 8, "acht": 8, "nine": 9, "neun": 9,
        "ten": 10, "zehn": 10, "half": 0.5, "halb": 0.5, "halbe": 0.5, "halben": 0.5, "halber": 0.5,
        "halbes": 0.5, "quarter": 0.25, "couple": 2, "paar": 2,
    ]

    static let fillers: Set<String> = ["of", "von", "vom", "der", "die", "das", "an", "stuck"]

    /// "halbe" after a number: "eine halbe Semmel" is half a Semmel.
    static let halfWords: Set<String> = ["half", "halb", "halbe", "halber", "halbes", "halben"]

    /// Portion groups: any of these words in a food's portion label counts as a match.
    static let portionGroups: [String: [String]] = [
        "piece": ["piece", "pieces", "pc", "pcs", "stuck", "stk", "whole", "item", "medium", "mittelgross", "mittel", "large", "gross"],
        "slice": ["slice", "slices", "scheibe", "scheiben"],
        "small": ["small", "klein", "kleine", "kleiner", "kleines"],
        "medium": ["medium", "mittel", "mittelgross", "mittelgrosse"],
        "large": ["large", "big", "gross", "grosse", "grosser", "groses"],
        "cup": ["cup", "cups", "tasse", "tassen"],
        "tbsp": ["tbsp", "tablespoon", "tablespoons", "el", "essloffel"],
        "tsp": ["tsp", "teaspoon", "teaspoons", "tl", "teeloffel"],
        "glass": ["glass", "glas"],
        "bottle": ["bottle", "flasche"],
        "can": ["can", "dose"],
        "serving": ["serving", "portion", "servings", "portionen"],
        "handful": ["handful", "handvoll"],
        "bowl": ["bowl", "schussel", "schale", "teller", "plate"],
        "roll": ["roll", "semmel", "brotchen", "weckerl", "bun"],
        "bar": ["bar", "riegel"],
        "scoop": ["scoop", "kugel", "messloffel"],
        "pack": ["pack", "package", "packung", "becher", "pot"],
    ]

    public static func unit(for word: String) -> QuickUnit? {
        switch word {
        case "g", "gr", "gram", "grams", "gramm", "grammes", "gramme": return .mass(1)
        case "kg", "kilo", "kilos", "kilogram", "kilograms", "kilogramm": return .mass(1000)
        case "dag", "deka", "dkg", "dekagramm", "decagram": return .mass(10)
        case "mg", "milligram", "milligramm": return .mass(0.001)
        case "oz", "ounce", "ounces", "unze": return .mass(28.35)
        case "lb", "lbs", "pound", "pounds", "pfund": return .mass(453.6)
        case "ml", "milliliter", "millilitre", "milliliters", "millilitres": return .volume(1)
        case "cl", "centiliter", "zentiliter": return .volume(10)
        case "dl", "deciliter", "deziliter": return .volume(100)
        case "l", "liter", "litre", "liters", "litres": return .volume(1000)
        case "achtel": return .volume(125)
        case "viertel", "vierterl": return .volume(250)
        case "krugerl", "kruegerl": return .volume(500)
        case "seidl", "seiterl": return .volume(300)
        case "pfiff": return .volume(200)
        case "stamperl", "shot", "shots", "schnapsglas": return .volume(20)
        case "espresso": return nil
        case "kcal", "kalorien", "calories", "cal", "kalorie", "calorie": return .kilocalories
        case "kj", "kilojoule", "kilojoules": return .kilojoules
        case "cup", "cups", "tasse", "tassen": return .portion(group: "cup", fallbackMilliliters: 240)
        case "tbsp", "tablespoon", "tablespoons", "el", "essloffel": return .portion(group: "tbsp", fallbackMilliliters: 15)
        case "tsp", "teaspoon", "teaspoons", "tl", "teeloffel": return .portion(group: "tsp", fallbackMilliliters: 5)
        case "glass", "glasses", "glas", "glaser": return .portion(group: "glass", fallbackMilliliters: 250)
        case "mug", "mugs", "haferl": return .portion(group: "cup", fallbackMilliliters: 250)
        case "bottle", "bottles", "flasche", "flaschen": return .portion(group: "bottle", fallbackMilliliters: 500)
        case "can", "cans", "dose", "dosen": return .portion(group: "can", fallbackMilliliters: 330)
        case "piece", "pieces", "pc", "pcs", "stuck", "stk", "stucke": return .portion(group: "piece", fallbackMilliliters: nil)
        case "slice", "slices", "scheibe", "scheiben", "scheibchen": return .portion(group: "slice", fallbackMilliliters: nil)
        case "small", "klein", "kleine", "kleiner", "kleines", "kleinen": return .portion(group: "small", fallbackMilliliters: nil)
        case "medium", "mittel", "mittelgross", "mittelgrosse", "mittelgrosser", "mittelgrosses": return .portion(group: "medium", fallbackMilliliters: nil)
        case "large", "big", "gross", "grosse", "grosser", "grosses", "grossen": return .portion(group: "large", fallbackMilliliters: nil)
        case "serving", "servings", "portion", "portionen": return .portion(group: "serving", fallbackMilliliters: nil)
        case "handful", "handfuls", "handvoll": return .portion(group: "handful", fallbackMilliliters: nil)
        case "bowl", "bowls", "schussel", "schusseln", "schale", "schalen", "teller", "plate": return .portion(group: "bowl", fallbackMilliliters: nil)
        case "bar", "bars", "riegel": return .portion(group: "bar", fallbackMilliliters: nil)
        case "scoop", "scoops", "kugel", "kugeln", "messloffel": return .portion(group: "scoop", fallbackMilliliters: nil)
        case "pack", "packs", "package", "packung", "packungen", "becher", "pot": return .portion(group: "pack", fallbackMilliliters: nil)
        default: return nil
        }
    }

    static func twoWordUnit(_ first: String, _ second: String) -> QuickUnit? {
        let pair = SearchText.normalize(first) + " " + SearchText.normalize(second)
        switch pair {
        case "fl oz": return .volume(29.57)
        default: return nil
        }
    }

    /// "2x", "x2", "2×" → 2
    static func multiplierToken(_ word: String) -> Double? {
        let lowered = word.lowercased()
        for marker in ["x", "×"] {
            if lowered.hasSuffix(marker), let value = NumberText.parse(String(lowered.dropLast())), value > 0 { return value }
            if lowered.hasPrefix(marker), let value = NumberText.parse(String(lowered.dropFirst())), value > 0 { return value }
        }
        return nil
    }

    /// A number at the start of a word and what follows it: "200g" → (200, "g"), "1,5" → (1.5, ""), "½" → (0.5, "").
    static func leadingNumber(_ word: String) -> (Double, String)? {
        var numberPart = ""
        var rest = Substring(word)
        let vulgar: Set<Character> = ["½", "¼", "¾", "⅓", "⅔", "⅛"]
        while let character = rest.first, character.isNumber || character == "." || character == "," || character == "/" || vulgar.contains(character) {
            numberPart.append(character)
            rest = rest.dropFirst()
        }
        guard !numberPart.isEmpty, numberPart.contains(where: { $0.isNumber || vulgar.contains($0) }) else { return nil }
        while let last = numberPart.last, last == "." || last == "," || last == "/" {
            numberPart.removeLast()
        }
        guard let value = NumberText.parse(numberPart), value > 0 else { return nil }
        return (value, String(rest))
    }

    static func fractionOnly(_ word: String) -> Double? {
        if word.count == 1, let value = NumberText.parse(word), value < 1 { return value }
        if word.contains("/"), let value = NumberText.parse(word), value < 1 { return value }
        return nil
    }
}
