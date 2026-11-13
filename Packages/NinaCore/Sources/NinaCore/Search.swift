import Foundation

/// Text normalisation for search: lower case, accents and umlauts folded (Äpfel → apfel, also
/// "aepfel" → apfel), punctuation removed. Applied to both the index and the query.
public enum SearchText {
    private static let folding: [Character: String] = {
        var map: [Character: String] = [:]
        let groups: [(String, String)] = [
            ("àáâãäåāăą", "a"), ("çćĉċč", "c"), ("ďđ", "d"), ("èéêëēĕėęě", "e"), ("ĝğġģ", "g"), ("ĥħ", "h"),
            ("ìíîïĩīĭįı", "i"), ("ĵ", "j"), ("ķ", "k"), ("ĺļľŀł", "l"), ("ñńņňŉ", "n"), ("òóôõöøōŏő", "o"),
            ("ŕŗř", "r"), ("śŝşšș", "s"), ("ţťŧț", "t"), ("ùúûüũūŭůűų", "u"), ("ŵ", "w"), ("ýÿŷ", "y"), ("źżž", "z"),
        ]
        for (letters, base) in groups {
            for letter in letters { map[letter] = base }
        }
        map["ß"] = "ss"
        map["æ"] = "ae"
        map["œ"] = "oe"
        map["þ"] = "th"
        return map
    }()

    /// "Äpfel, roh (100 g)" → "apfel roh 100 g"
    public static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var lastWasSpace = true
        for character in text.lowercased() {
            if let folded = folding[character] {
                result += folded
                lastWasSpace = false
            } else if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSpace = false
            } else if character == "%" {
                result += lastWasSpace ? "%" : " %"
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    /// Words of the normalised text, with German umlaut spellings folded ("aepfel" → "apfel").
    public static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map { umlautFold(String($0)) }
    }

    /// "ae" → "a", "oe" → "o", "ue" → "u": the way people type umlauts without a German keyboard.
    /// Applied on both sides, so it never prevents a match.
    static func umlautFold(_ token: String) -> String {
        guard token.count > 2 else { return token }
        return token
            .replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
    }

    /// Damerau–Levenshtein distance with an early exit above `limit`.
    static func distance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }
}

/// How often and how recently a food was logged (from the diary), for ranking and "usual amount".
public struct FoodUsage: Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date?
    /// The amount (base unit) logged most recently.
    public var lastAmount: Double

    public init(count: Int = 0, lastUsed: Date? = nil, lastAmount: Double = 0) {
        self.count = count
        self.lastUsed = lastUsed
        self.lastAmount = lastAmount
    }
}

/// Ranked food search over the catalog, own foods and recipes. Built once per data change;
/// a query over ~1,500 foods takes well under a millisecond per keystroke.
public struct FoodSearchIndex: Sendable {
    struct Entry: Sendable {
        let record: FoodRecord
        let primary: [String]
        /// Words after the first comma ("Tiefkühlpizza, Käse"): details of the main noun.
        let details: [String]
        /// Words after "mit"/"with" ("Cheeseburger mit Salat"): side items, matched at half weight.
        let sides: [String]
        let primaryJoined: String
        let secondary: [String]
        let aliases: [String]
        /// Each alias as one normalised phrase ("milch", "whole milk").
        let aliasPhrases: Set<String>
        let brand: [String]
        let tags: [String]
        let category: [String]
    }

    let entries: [Entry]
    public let language: FoodLanguage
    static let sideMarkers: Set<String> = ["mit", "with", "und", "and", "plus"]

    public init(_ records: [FoodRecord], language: FoodLanguage) {
        self.language = language
        entries = records.map { record in
            let primaryName = record.displayName(language)
            let primary = SearchText.tokens(primaryName)
            let otherName = language == .german ? record.name : record.nameDE
            let comma = primaryName.firstIndex(of: ",")
            let mainPart = comma.map { String(primaryName[..<$0]) } ?? primaryName
            let detailPart = comma.map { String(primaryName[primaryName.index(after: $0)...]) } ?? ""
            let main = SearchText.tokens(mainPart)
            let split = main.firstIndex { Self.sideMarkers.contains($0) } ?? main.count
            var sides = Array(main[split...])
            var details = SearchText.tokens(detailPart)
            if let detailSplit = details.firstIndex(where: { Self.sideMarkers.contains($0) }) {
                sides += details[detailSplit...]
                details = Array(details[..<detailSplit])
            }
            return Entry(
                record: record,
                primary: Array(main[..<split]),
                details: details,
                sides: sides.filter { !Self.sideMarkers.contains($0) },
                primaryJoined: primary.joined(separator: " "),
                secondary: SearchText.tokens(otherName),
                aliases: record.aliases.flatMap { SearchText.tokens($0) },
                aliasPhrases: Set(record.aliases.map { SearchText.tokens($0).joined(separator: " ") }),
                brand: SearchText.tokens(record.brand),
                tags: record.tags.flatMap { SearchText.tokens($0) },
                category: SearchText.tokens(record.category.title)
            )
        }
    }

    public var count: Int { entries.count }

    /// Best matches first. An empty query returns nothing (the app shows recents and favorites then).
    public func search(_ query: String, usage: [FoodRef: FoodUsage] = [:], now: Date = Date(), limit: Int = 60) -> [FoodRecord] {
        scored(query, usage: usage, now: now, limit: limit).map(\.record)
    }

    public func scored(_ query: String, usage: [FoodRef: FoodUsage] = [:], now: Date = Date(), limit: Int = 60) -> [(record: FoodRecord, score: Double)] {
        let words = SearchText.tokens(query)
        guard !words.isEmpty else { return [] }
        let joined = words.joined(separator: " ")
        var results: [(record: FoodRecord, score: Double, length: Int)] = []
        for entry in entries {
            guard var score = Self.score(words, joined: joined, entry: entry) else { continue }
            if let use = usage[entry.record.ref] {
                score += min(0.6, 0.15 * log2(1 + Double(use.count)))
                if let last = use.lastUsed, now.timeIntervalSince(last) < 7 * 86_400 { score += 0.1 }
            }
            if entry.record.isFavorite { score += 0.3 }
            if entry.record.recordID != nil { score += 0.1 }
            results.append((entry.record, score, entry.primaryJoined.count))
        }
        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.length != rhs.length { return lhs.length < rhs.length }
            return lhs.record.displayName(language) < rhs.record.displayName(language)
        }
        return results.prefix(limit).map { ($0.record, $0.score) }
    }

    static func score(_ words: [String], joined: String, entry: Entry) -> Double? {
        var total = 0.0
        for word in words {
            var best = 0.0
            best = max(best, 1.0 * bestMatch(word, in: entry.primary))
            if best < 0.75 { best = max(best, 0.75 * bestMatch(word, in: entry.details)) }
            if best < 0.5 { best = max(best, 0.5 * bestMatch(word, in: entry.sides)) }
            if best < 1 { best = max(best, 0.7 * bestMatch(word, in: entry.secondary)) }
            if best < 1 { best = max(best, 0.8 * bestMatch(word, in: entry.aliases)) }
            if best < 0.6 { best = max(best, 0.6 * bestMatch(word, in: entry.brand)) }
            if best < 0.5 { best = max(best, 0.5 * bestMatch(word, in: entry.tags)) }
            if best < 0.3 { best = max(best, 0.3 * bestMatch(word, in: entry.category)) }
            guard best > 0 else { return nil }
            total += best
        }
        var score = total / Double(words.count)
        if entry.primaryJoined == joined {
            score += 1.0
        } else if entry.aliasPhrases.contains(joined) {
            // A curated synonym typed exactly ("Milch" → whole milk, "Paradeiser" → tomato).
            score += 1.0
        } else if entry.primaryJoined.hasPrefix(joined), !(words.count == 1 && isCompoundStart(words[0], of: entry.primary.first)) {
            score += 0.5
        }
        if let first = words.first, let head = entry.primary.first,
           (head.hasPrefix(first) && !isCompoundStart(first, of: head)) || stems(first).contains(head) {
            score += 0.25
        }
        // Longer names rank a little lower; numbers and "%" ("Vollmilch 3,5 %") don't count.
        let nameWords = (entry.primary + entry.details).filter { $0.contains(where: \.isLetter) }.count
        score -= 0.03 * Double(max(0, nameWords - words.count))
        return score
    }

    /// Singular forms of a plural: "eggs" → egg, "tomatoes" → tomato, "Bananen" → banane, "Nudeln" → nudel.
    static func stems(_ word: String) -> [String] {
        guard word.count > 3 else { return [] }
        var result: [String] = []
        if word.hasSuffix("es") { result.append(String(word.dropLast(2))) }
        if word.hasSuffix("s") || word.hasSuffix("n") { result.append(String(word.dropLast())) }
        if word.hasSuffix("en") { result.append(String(word.dropLast(2))) }
        return result
    }

    /// A whole word typed that is only the first part of a longer compound: "käse" in "Käseflips"
    /// (German compounds name the last part: Käseflips are flips, Bergkäse is cheese).
    static func isCompoundStart(_ word: String, of token: String?) -> Bool {
        guard let token, word.count >= 4 else { return false }
        return token.count >= word.count + 3 && token.hasPrefix(word)
    }

    /// 1 exact · 0.98 plural · 0.8 end of a compound ("Vollmilch" for "milch") · 0.75–1 prefix
    /// (0.65 when a whole word starts a longer compound) · 0.45 inside the word · 0.35–0.4 one typo.
    static func bestMatch(_ word: String, in tokens: [String]) -> Double {
        var best = 0.0
        let singular = stems(word)
        for token in tokens {
            if token == word { return 1 }
            if singular.contains(token) {
                best = max(best, 0.98)
            } else if isCompoundStart(word, of: token) {
                best = max(best, 0.65)
            } else if token.hasPrefix(word) {
                best = max(best, 0.75 + 0.25 * Double(word.count) / Double(max(token.count, 1)))
            } else if word.count >= 4, token.hasSuffix(word) {
                best = max(best, 0.8)
            } else if word.count >= 3, token.contains(word) {
                best = max(best, 0.45)
            } else if word.count >= 4 {
                let limit = word.count >= 8 ? 2 : 1
                let a = Array(word)
                if SearchText.distance(a, Array(token), limit: limit) <= limit {
                    best = max(best, 0.4)
                } else if token.count > word.count,
                          SearchText.distance(a, Array(token.prefix(word.count)), limit: 1) <= 1 {
                    best = max(best, 0.35)
                }
            }
        }
        return best
    }
}
