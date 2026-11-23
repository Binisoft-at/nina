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
    /// Applied on both sides, so it never prevents a match. One pass over the scalars (the three
    /// pairs can't overlap: each ends in "e" and none starts with it).
    static func umlautFold(_ token: String) -> String {
        guard token.count > 2 else { return token }
        let scalars = Array(token.unicodeScalars)
        var result = String.UnicodeScalarView()
        var changed = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if index + 1 < scalars.count, scalars[index + 1] == "e", scalar == "a" || scalar == "o" || scalar == "u" {
                result.append(scalar)
                index += 2
                changed = true
            } else {
                result.append(scalar)
                index += 1
            }
        }
        return changed ? String(result) : token
    }

    /// Damerau–Levenshtein distance (optimal string alignment) with an early exit above `limit`.
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

    /// Unicode scalars of a normalised token: the search compares these arrays (no `Character`
    /// work in the hot loop).
    static func scalars(_ text: String) -> [UInt32] {
        text.unicodeScalars.map(\.value)
    }

    /// True when `a` and `b[bStart..<bEnd]` are at most one edit apart (one substitution, insertion,
    /// deletion or swap of neighbours) – the same answer as `distance(…, limit: 1) <= 1`, in one pass.
    static func isWithinOneEdit(_ a: [UInt32], _ b: [UInt32], bEnd: Int? = nil) -> Bool {
        let n = a.count
        let m = bEnd ?? b.count
        if abs(n - m) > 1 { return false }
        var i = 0
        if n == m {
            while i < n, a[i] == b[i] { i += 1 }
            if i == n { return true }
            // One substitution at i …
            var j = i + 1
            while j < n, a[j] == b[j] { j += 1 }
            if j == n { return true }
            // … or neighbours i, i+1 swapped.
            guard i + 1 < n, a[i] == b[i + 1], a[i + 1] == b[i] else { return false }
            j = i + 2
            while j < n, a[j] == b[j] { j += 1 }
            return j == n
        }
        // One character more on one side.
        let shortCount = min(n, m)
        let aIsShort = n < m
        while i < shortCount, a[i] == b[i] { i += 1 }
        var short = i
        var long = i + 1
        while short < shortCount {
            let left = aIsShort ? a[short] : b[short]
            let right = aIsShort ? b[long] : a[long]
            if left != right { return false }
            short += 1
            long += 1
        }
        return true
    }

    /// `distance` on scalar arrays with reusable buffers (for limits above one).
    static func distance(_ a: [UInt32], _ b: [UInt32], limit: Int, buffers: inout DistanceBuffers) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        let width = b.count + 1
        buffers.prepare(width)
        for j in 0..<width {
            buffers.previous[j] = j
            buffers.previousPrevious[j] = 0
        }
        for i in 1...a.count {
            buffers.current[0] = i
            var rowMinimum = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(buffers.previous[j] + 1, buffers.current[j - 1] + 1, buffers.previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, buffers.previousPrevious[j - 2] + 1)
                }
                buffers.current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            buffers.rotate()
        }
        return buffers.previous[b.count]
    }

    /// The three rows of the distance table, kept between calls of one search.
    struct DistanceBuffers {
        var previousPrevious: [Int] = []
        var previous: [Int] = []
        var current: [Int] = []

        mutating func prepare(_ width: Int) {
            guard previous.count < width else { return }
            previousPrevious = [Int](repeating: 0, count: width)
            previous = [Int](repeating: 0, count: width)
            current = [Int](repeating: 0, count: width)
        }

        mutating func rotate() {
            swap(&previousPrevious, &previous)
            swap(&previous, &current)
        }
    }
}

/// How often and how recently a food was logged (from the diary), for ranking and "usual amount".
public struct FoodUsage: Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date?
    /// The amount (base unit) logged most recently.
    public var lastAmount: Double
    /// The same per meal id ("breakfast", "meal-1a2b3c4d"): the log sheet's Recent list puts the
    /// foods mostly logged at the meal being logged first (`RecentFoods`).
    public var meals: [String: FoodMealUse]

    public init(count: Int = 0, lastUsed: Date? = nil, lastAmount: Double = 0, meals: [String: FoodMealUse] = [:]) {
        self.count = count
        self.lastUsed = lastUsed
        self.lastAmount = lastAmount
        self.meals = meals
    }
}

/// Ranked food search over the catalog, own foods and recipes. Built once per data change (an
/// unchanged food keeps its prepared entry, see `init(_:language:reusing:)`). Every query word is
/// compared with every name word of every food, so a query costs a few milliseconds over ~1,500
/// foods: tokens are stored as scalar arrays, and the typo check only runs where it could still
/// raise a food's score.
public struct FoodSearchIndex: Sendable {
    /// One name word, as Unicode scalars.
    typealias Token = [UInt32]

    struct Entry: Sendable {
        let record: FoodRecord
        let primary: [Token]
        /// Words after the first comma ("Tiefkühlpizza, Käse"): details of the main noun.
        let details: [Token]
        /// Words after "mit"/"with" ("Cheeseburger mit Salat"): side items, matched at half weight.
        let sides: [Token]
        let secondary: [Token]
        let aliases: [Token]
        let brand: [Token]
        let tags: [Token]
        let category: [Token]
        let primaryJoined: Token
        /// `primaryJoined` in characters: shorter names win ties.
        let length: Int
        /// Each alias as one normalised phrase ("milch", "whole milk").
        let aliasPhrases: Set<String>
        /// Name words with a letter (primary and details): longer names rank a little lower.
        let nameWords: Int
        /// The display name, the last tie-breaker.
        let sortName: String
    }

    let entries: [Entry]
    public let language: FoodLanguage
    static let sideMarkers: Set<String> = ["mit", "with", "und", "and", "plus"]

    public init(_ records: [FoodRecord], language: FoodLanguage) {
        self.init(records, language: language, reusing: nil)
    }

    /// Like `init(_:language:)`, but a food whose record didn't change keeps the prepared entry of
    /// `previous` (same language): a rebuild after logging one food re-reads only what changed.
    public init(_ records: [FoodRecord], language: FoodLanguage, reusing previous: FoodSearchIndex?) {
        self.language = language
        var reusable: [FoodRef: Entry] = [:]
        if let previous, previous.language == language {
            reusable.reserveCapacity(previous.entries.count)
            for entry in previous.entries { reusable[entry.record.ref] = entry }
        }
        entries = records.map { record in
            if let old = reusable[record.ref], old.record == record { return old }
            return Self.entry(for: record, language: language)
        }
    }

    static func entry(for record: FoodRecord, language: FoodLanguage) -> Entry {
        let primaryName = record.displayName(language)
        let primary = SearchText.tokens(primaryName)
        let otherName = language == .german ? record.name : record.nameDE
        let comma = primaryName.firstIndex(of: ",")
        let mainPart = comma.map { String(primaryName[..<$0]) } ?? primaryName
        let detailPart = comma.map { String(primaryName[primaryName.index(after: $0)...]) } ?? ""
        let main = SearchText.tokens(mainPart)
        let split = main.firstIndex { sideMarkers.contains($0) } ?? main.count
        var sides = Array(main[split...])
        var details = SearchText.tokens(detailPart)
        if let detailSplit = details.firstIndex(where: { sideMarkers.contains($0) }) {
            sides += details[detailSplit...]
            details = Array(details[..<detailSplit])
        }
        let head = Array(main[..<split])
        let joined = primary.joined(separator: " ")
        func scalars(_ words: [String]) -> [Token] { words.map(SearchText.scalars) }
        return Entry(
            record: record,
            primary: scalars(head),
            details: scalars(details),
            sides: scalars(sides.filter { !sideMarkers.contains($0) }),
            secondary: scalars(SearchText.tokens(otherName)),
            aliases: scalars(record.aliases.flatMap { SearchText.tokens($0) }),
            brand: scalars(SearchText.tokens(record.brand)),
            tags: scalars(record.tags.flatMap { SearchText.tokens($0) }),
            category: scalars(SearchText.tokens(record.category.title)),
            primaryJoined: SearchText.scalars(joined),
            length: joined.count,
            aliasPhrases: Set(record.aliases.map { SearchText.tokens($0).joined(separator: " ") }),
            nameWords: (head + details).filter { $0.contains(where: \.isLetter) }.count,
            sortName: primaryName
        )
    }

    public var count: Int { entries.count }

    /// Best matches first. An empty query returns nothing (the app shows recents and favorites then).
    public func search(_ query: String, usage: [FoodRef: FoodUsage] = [:], now: Date = Date(), limit: Int = 60) -> [FoodRecord] {
        scored(query, usage: usage, now: now, limit: limit).map(\.record)
    }

    /// One query word, prepared once per search.
    struct Word {
        let scalars: [UInt32]
        let stems: [[UInt32]]
        var count: Int { scalars.count }

        init(_ text: String) {
            scalars = SearchText.scalars(text)
            stems = FoodSearchIndex.stems(text).map(SearchText.scalars)
        }
    }

    /// The query, prepared once per search.
    struct Query {
        let words: [Word]
        let joined: [UInt32]
        let joinedText: String
        /// The first word, its plural stems, and whether it is a whole word long enough to be the
        /// start of a compound ("käse" in "Käseflips").
        let first: Word

        init?(_ text: String) {
            let tokens = SearchText.tokens(text)
            guard let firstText = tokens.first else { return nil }
            words = tokens.map(Word.init)
            joinedText = tokens.joined(separator: " ")
            joined = SearchText.scalars(joinedText)
            first = Word(firstText)
        }
    }

    public func scored(_ query: String, usage: [FoodRef: FoodUsage] = [:], now: Date = Date(), limit: Int = 60) -> [(record: FoodRecord, score: Double)] {
        guard let prepared = Query(query) else { return [] }
        var buffers = SearchText.DistanceBuffers()
        var results: [(entry: Entry, score: Double)] = []
        for entry in entries {
            guard var score = Self.score(prepared, entry: entry, buffers: &buffers) else { continue }
            if let use = usage[entry.record.ref] {
                score += min(0.6, 0.15 * log2(1 + Double(use.count)))
                if let last = use.lastUsed, now.timeIntervalSince(last) < 7 * 86_400 { score += 0.1 }
            }
            if entry.record.isFavorite { score += 0.3 }
            if entry.record.recordID != nil { score += 0.1 }
            results.append((entry, score))
        }
        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.length != rhs.entry.length { return lhs.entry.length < rhs.entry.length }
            return lhs.entry.sortName < rhs.entry.sortName
        }
        return results.prefix(limit).map { ($0.entry.record, $0.score) }
    }

    static func score(_ query: Query, entry: Entry, buffers: inout SearchText.DistanceBuffers) -> Double? {
        var total = 0.0
        for word in query.words {
            var best = bestMatch(word, in: entry.primary, floor: 0, buffers: &buffers)
            if best < 0.75 { best = max(best, 0.75 * bestMatch(word, in: entry.details, floor: best / 0.75, buffers: &buffers)) }
            if best < 0.5 { best = max(best, 0.5 * bestMatch(word, in: entry.sides, floor: best / 0.5, buffers: &buffers)) }
            if best < 1 { best = max(best, 0.7 * bestMatch(word, in: entry.secondary, floor: best / 0.7, buffers: &buffers)) }
            if best < 1 { best = max(best, 0.8 * bestMatch(word, in: entry.aliases, floor: best / 0.8, buffers: &buffers)) }
            if best < 0.6 { best = max(best, 0.6 * bestMatch(word, in: entry.brand, floor: best / 0.6, buffers: &buffers)) }
            if best < 0.5 { best = max(best, 0.5 * bestMatch(word, in: entry.tags, floor: best / 0.5, buffers: &buffers)) }
            if best < 0.3 { best = max(best, 0.3 * bestMatch(word, in: entry.category, floor: best / 0.3, buffers: &buffers)) }
            guard best > 0 else { return nil }
            total += best
        }
        let words = query.words
        var score = total / Double(words.count)
        if entry.primaryJoined == query.joined {
            score += 1.0
        } else if !entry.aliasPhrases.isEmpty, entry.aliasPhrases.contains(query.joinedText) {
            // A curated synonym typed exactly ("Milch" → whole milk, "Paradeiser" → tomato).
            score += 1.0
        } else if hasPrefix(entry.primaryJoined, query.joined),
                  !(words.count == 1 && isCompoundStart(words[0].scalars, of: entry.primary.first)) {
            score += 0.5
        }
        if let head = entry.primary.first {
            let first = query.first
            if (hasPrefix(head, first.scalars) && !isCompoundStart(first.scalars, of: head)) || first.stems.contains(head) {
                score += 0.25
            }
        }
        // Longer names rank a little lower; numbers and "%" ("Vollmilch 3,5 %") don't count.
        score -= 0.03 * Double(max(0, entry.nameWords - words.count))
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

    static func isCompoundStart(_ word: [UInt32], of token: [UInt32]?) -> Bool {
        guard let token, word.count >= 4 else { return false }
        return token.count >= word.count + 3 && hasPrefix(token, word)
    }

    @inline(__always)
    static func hasPrefix(_ token: [UInt32], _ prefix: [UInt32]) -> Bool {
        guard prefix.count <= token.count else { return false }
        var index = 0
        while index < prefix.count {
            if token[index] != prefix[index] { return false }
            index += 1
        }
        return true
    }

    @inline(__always)
    static func hasSuffix(_ token: [UInt32], _ suffix: [UInt32]) -> Bool {
        guard suffix.count <= token.count else { return false }
        let offset = token.count - suffix.count
        var index = 0
        while index < suffix.count {
            if token[offset + index] != suffix[index] { return false }
            index += 1
        }
        return true
    }

    static func contains(_ token: [UInt32], _ part: [UInt32]) -> Bool {
        guard !part.isEmpty else { return true }
        guard part.count <= token.count else { return false }
        let first = part[0]
        var start = 0
        while start <= token.count - part.count {
            if token[start] == first {
                var index = 1
                while index < part.count, token[start + index] == part[index] { index += 1 }
                if index == part.count { return true }
            }
            start += 1
        }
        return false
    }

    /// 1 exact · 0.98 plural · 0.8 end of a compound ("Vollmilch" for "milch") · 0.75–1 prefix
    /// (0.65 when a whole word starts a longer compound) · 0.45 inside the word · 0.35–0.4 one typo.
    /// `floor` is the score (in this list's terms) the word already has from another list: the
    /// typo check is skipped where it couldn't beat it, which never changes the result.
    static func bestMatch(_ word: Word, in tokens: [Token], floor: Double, buffers: inout SearchText.DistanceBuffers) -> Double {
        var best = 0.0
        let w = word.scalars
        let wordCount = w.count
        for token in tokens {
            let tokenCount = token.count
            if token == w { return 1 }
            if word.stems.contains(token) {
                best = max(best, 0.98)
            } else if wordCount >= 4, tokenCount >= wordCount + 3, hasPrefix(token, w) {
                best = max(best, 0.65)
            } else if hasPrefix(token, w) {
                best = max(best, 0.75 + 0.25 * Double(wordCount) / Double(max(tokenCount, 1)))
            } else if wordCount >= 4, hasSuffix(token, w) {
                best = max(best, 0.8)
            } else if wordCount >= 3, contains(token, w) {
                best = max(best, 0.45)
            } else if wordCount >= 4 {
                let reached = max(best, floor)
                guard reached < 0.4 else { continue }
                let limit = wordCount >= 8 ? 2 : 1
                let close = limit == 1
                    ? SearchText.isWithinOneEdit(w, token)
                    : SearchText.distance(w, token, limit: limit, buffers: &buffers) <= limit
                if close {
                    best = max(best, 0.4)
                } else if reached < 0.35, tokenCount > wordCount, SearchText.isWithinOneEdit(w, token, bEnd: wordCount) {
                    best = max(best, 0.35)
                }
            }
        }
        return best
    }
}
