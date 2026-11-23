import Foundation
import Testing
@testable import NinaCore

// Logging, food search and portions: quick add with German decimals and phrasings, portion texts,
// input fields that never change a value by showing it, and a faster search that ranks exactly
// like before. All data is made up or comes from the bundled catalog.

@Suite("Quick add: decimals and phrasings")
struct QuickAddPhrasingTests {
    @Test func germanDecimalCommasStayNumbers() throws {
        let milk = try #require(QuickParser.parse("1,5 l Milch").first)
        #expect(QuickParser.parse("1,5 l Milch").count == 1)
        #expect(milk.quantity == 1.5)
        #expect(milk.unit == .volume(1000))
        #expect(milk.query == "Milch")

        let two = QuickParser.parse("2 Eier, 1,5 dl Milch")
        #expect(two.count == 2)
        #expect(two[0].quantity == 2)
        #expect(two[1].quantity == 1.5)
        #expect(two[1].unit == .volume(100))

        let beer = QuickParser.parse("0,5 l Bier")
        #expect(beer.count == 1)
        #expect(beer.first?.quantity == 0.5)

        let yogurt = QuickParser.parse("200 g Joghurt 3,5%")
        #expect(yogurt.count == 1)
        #expect(yogurt.first?.query == "Joghurt 3,5%")
        #expect(yogurt.first?.quantity == 200)

        #expect(QuickParser.parse("Milch 1,5%").count == 1)
        #expect(QuickParser.parse("2,5 dag Butter").first?.quantity == 2.5)
        #expect(QuickParser.parse("2 Eier,1 Semmel").count == 2)
        #expect(QuickParser.parse("2 Eier,1 Semmel").map(\.query) == ["Eier", "Semmel"])
    }

    @Test func halvesAfterANumberWord() {
        #expect(QuickParser.parse("eine halbe Semmel").first?.quantity == 0.5)
        #expect(QuickParser.parse("eine halbe Semmel").first?.query == "Semmel")
        #expect(QuickParser.parse("ein halbes Brot").first?.quantity == 0.5)
        #expect(QuickParser.parse("ein halbes Brot").first?.query == "Brot")
        #expect(QuickParser.parse("zwei halbe Semmeln").first?.quantity == 1)
        #expect(QuickParser.parse("a half avocado").first?.quantity == 0.5)
        #expect(QuickParser.parse("a half avocado").first?.query == "avocado")
        #expect(QuickParser.parse("half a cup milk").first?.query == "milk")
        // Unchanged: a bare half and fractions.
        #expect(QuickParser.parse("halbe Semmel").first?.quantity == 0.5)
        #expect(QuickParser.parse("½ Semmel").first?.quantity == 0.5)
    }

    @Test func twoAmountsWithoutASeparatorSplit() {
        let items = QuickParser.parse("3 eggs 2 toast")
        #expect(items.count == 2)
        #expect(items.map(\.query) == ["eggs", "toast"])
        #expect(items.map(\.quantity) == [3, 2])
        #expect(QuickParser.parse("2 Eier 200 g Joghurt 1 Semmel").map(\.query) == ["Eier", "Joghurt", "Semmel"])
        #expect(QuickParser.parse("100 g Haferflocken 2 EL Honig").count == 2)
    }

    @Test func amountsInsideANameStayTogether() {
        #expect(QuickParser.parse("Cola 0,5 l").count == 1)
        #expect(QuickParser.parse("Cola 0,5 l").first?.quantity == 0.5)
        #expect(QuickParser.parse("Joghurt 3,5%").count == 1)
        #expect(QuickParser.parse("Rotwein 1 Achtel").count == 1)
        #expect(QuickParser.parse("chicken breast 200g").count == 1)
        #expect(QuickParser.parse("Pizza 4 Jahreszeiten").count == 1)
        #expect(QuickParser.parse("1 Glas Milch 3,5 %").count == 1)
        #expect(QuickParser.parse("2 Eier 2 Stück").count == 1)
        #expect(QuickParser.parse("1 Joghurt 0,1 % Fett").count == 1)
        #expect(QuickParser.parse("1 Joghurt 0,1% Fett").count == 1)
        #expect(QuickParser.parse("1 Joghurt 0,1 % Fett").first?.query == "Joghurt 0,1 % Fett")
    }

    @Test func joinersSplitOnSecondTry() throws {
        let line = try #require(QuickParser.parse("2 Semmeln mit Butter").first)
        #expect(QuickParser.parse("2 Semmeln mit Butter").count == 1)
        let retry = QuickParser.splitOnEveryJoiner(line)
        #expect(retry.map(\.query) == ["Semmeln", "Butter"])
        #expect(retry.first?.quantity == 2)
        #expect(retry.last?.quantity == nil)
        let single = try #require(QuickParser.parse("Banane").first)
        #expect(QuickParser.splitOnEveryJoiner(single).isEmpty)
    }

    @Test func newLinesAndOtherSeparators() {
        #expect(QuickParser.parse("2 Eier\n1 Semmel; Kaffee + Milch & Zucker").count == 5)
        #expect(QuickParser.parse("2 Eier\r\n1 Semmel").count == 2)
    }
}

@Suite("Portion texts")
struct PortionTextTests {
    @Test func bracketedAmountsAreNotShownTwice() {
        #expect(AmountText(quantity: 1, unitLabel: "glass (250 ml)", unitAmount: 250, baseUnit: .milliliter).text == "1 glass (250 ml)")
        #expect(AmountText(quantity: 2, unitLabel: "Glas (0,25 l)", unitAmount: 250, baseUnit: .milliliter).text == "2 × Glas (500 ml)")
        #expect(AmountText(quantity: 1, unitLabel: "Stamperl (2 cl)", unitAmount: 20, baseUnit: .milliliter).text == "1 Stamperl (20 ml)")
        #expect(AmountText(quantity: 1, unitLabel: "Portion (250 g)", unitAmount: 250, baseUnit: .gram).text == "1 Portion (250 g)")
        // Extra words in the bracket stay: they say something the total doesn't.
        #expect(AmountText(quantity: 1, unitLabel: "can (175 g drained)", unitAmount: 175, baseUnit: .gram).text == "1 can (175 g drained) (175 g)")
        #expect(AmountText(quantity: 1, unitLabel: "from 1 egg (M)", unitAmount: 33, baseUnit: .gram).text == "1 from 1 egg (M) (33 g)")
    }

    @Test func portionLabelDisplay() {
        #expect(PortionLabel.display("glass (250 ml)", baseUnit: .milliliter) == "glass")
        #expect(PortionLabel.display("Häferl (250 ml)", baseUnit: .milliliter) == "Häferl")
        #expect(PortionLabel.display("Doppelter (4 cl)", baseUnit: .milliliter) == "Doppelter")
        #expect(PortionLabel.display("slice (30g)", baseUnit: .gram) == "slice")
        #expect(PortionLabel.display("piece (15 cm)", baseUnit: .gram) == "piece (15 cm)")
        #expect(PortionLabel.display("slice", baseUnit: .gram) == "slice")
        #expect(PortionLabel.display("(250 ml)", baseUnit: .milliliter) == "(250 ml)")
        // A serving food shows no total, so its bracket is the only amount.
        #expect(PortionLabel.display("portion (250 g)", baseUnit: .serving) == "portion (250 g)")
    }

    @Test func gramsOfADrinkReadAsGrams() {
        let milk = AmountText(quantity: 200, unitLabel: "g", unitAmount: 1 / 1.031, baseUnit: .milliliter)
        #expect(milk.text == "200 g (194 ml)")
        let water = AmountText(quantity: 250, unitLabel: "g", unitAmount: 1, baseUnit: .milliliter)
        #expect(water.text == "250 g (250 ml)")
        #expect(AmountText(quantity: 250, unitLabel: "ml", unitAmount: 1, baseUnit: .milliliter).text == "250 ml")
        #expect(AmountText.isBaseLabel("g"))
        #expect(AmountText.isBaseLabel("ml"))
        #expect(!AmountText.isBaseLabel("slice"))
    }

    @Test func oneServingOrLessIsSingular() {
        #expect(AmountText(quantity: 1, unitLabel: "serving", unitAmount: 1, baseUnit: .serving).text == "1 serving")
        #expect(AmountText(quantity: 0.5, unitLabel: "serving", unitAmount: 1, baseUnit: .serving).text == "½ serving")
        #expect(AmountText(quantity: 1.5, unitLabel: "serving", unitAmount: 1, baseUnit: .serving).text == "1½ servings")
        #expect(AmountText(quantity: 2, unitLabel: "serving", unitAmount: 1, baseUnit: .serving).text == "2 servings")
    }

    @Test func appFormattingKeepsTheShape() {
        let glass = AmountText(quantity: 2, unitLabel: "glass (250 ml)", unitAmount: 250, baseUnit: .milliliter)
        let text = glass.text(count: AmountText.quantity, measure: { "<\(Int($0))>" })
        #expect(text == "2 × glass (<500> ml)")
    }
}

@Suite("Input fields")
struct InputFieldTests {
    @Test func showingAValueNeverRoundsIt() {
        #expect(AmountText.fieldText(12.5) == "12.5")
        #expect(AmountText.fieldText(37.5) == "37.5")
        #expect(AmountText.fieldText(10.5) == "10.5")
        #expect(AmountText.fieldText(150) == "150")
        #expect(AmountText.fieldText(0.5) == "½")
        #expect(AmountText.fieldText(2.25) == "2¼")
        #expect(AmountText.fieldText(1.33) == "1.33")
        #expect(AmountText.fieldText(12.5, decimalSeparator: ",") == "12,5")
        for value in [12.5, 37.5, 10.5, 150, 0.5, 2.25, 1.33, 0.1, 99.75, 250] {
            #expect(NumberText.parse(AmountText.fieldText(value)) == value)
            #expect(NumberText.parse(AmountText.fieldText(value, decimalSeparator: ",")) == value)
        }
    }

    @Test func energyFieldRoundTripsInKilojoules() {
        for kcal in [0.0, 1, 52, 250, 389.4, 884, 2_000] {
            for unit in EnergyUnit.allCases {
                let text = NumberText.energyField(kilocalories: kcal, unit: unit)
                let back = NumberText.parse(text).map { unit.kilocalories(from: $0) }
                #expect(back != nil)
                #expect(abs((back ?? -99) - kcal) < 1)
            }
        }
        #expect(NumberText.energyField(kilocalories: 250, unit: .kJ) == "1046")
        #expect(NumberText.energyField(kilocalories: 250, unit: .kcal) == "250")
    }
}

@Suite("Food search speed and ranking")
struct FoodSearchSpeedTests {
    let catalog = FoodCatalog.bundled

    /// Queries people type: typos, umlauts, plurals, Austrian names, phrases, numbers.
    static let queries = [
        "h", "ha", "haf", "hafer", "haferflocken", "huhn", "hühnerbrust", "chicken breast", "chikcen brest",
        "joghurt natur", "vollkornbrot", "apfel", "äpfel", "aepfel", "proteinriegel", "xyzq", "banana", "banan",
        "paradeiser", "semmel", "eggs", "milch", "eierspeis", "tomaten", "2 eier", "kase", "käse", "brot mit butter",
        "vollmilch 3,5 %", "nudeln", "bananen", "reis", "chiken", "brokoli", "spagetti", "mozarella", "yoghurt",
        "olivenöl", "erdäpfel", "topfen", "kaiserschmarrn", "schnitzel", "orange juice", "peanutbutter", "almonds",
        "lachs", "thunfisch", "zucchini", "avocadoo", "mandeln geröstet", "kaffee", "bier", "wein rot", "oats",
    ]

    /// Usage, favourites and an own food, so every bonus takes part in the ranking.
    func sample() -> (records: [FoodRecord], usage: [FoodRef: FoodUsage]) {
        var records = catalog.foods
        var usage: [FoodRef: FoodUsage] = [:]
        let now = Date()
        for (index, record) in records.enumerated() where index % 37 == 0 {
            usage[record.ref] = FoodUsage(count: index % 11 + 1, lastUsed: now.addingTimeInterval(-Double(index) * 3_600), lastAmount: 100)
        }
        for index in records.indices where index % 53 == 0 { records[index].isFavorite = true }
        records.append(FoodRecord(ref: FoodRef("food:00000000-0000-0000-0000-000000000001"), recordID: UUID(),
                                  name: "Oat bar, homemade", nameDE: "Haferriegel, selbst gemacht",
                                  nutrients: NutrientValues([.energy: 410, .protein: 9, .carbs: 60, .fat: 14]),
                                  aliases: ["Müsliriegel"], tags: ["snack"]))
        return (records, usage)
    }

    @Test func rankingIsUnchanged() {
        let (records, usage) = sample()
        let now = Date()
        for language in FoodLanguage.allCases {
            let index = FoodSearchIndex(records, language: language)
            let legacy = LegacySearchIndex(records, language: language)
            for query in Self.queries {
                let fast = index.scored(query, usage: usage, now: now, limit: 60)
                let slow = legacy.scored(query, usage: usage, now: now, limit: 60)
                #expect(fast.map(\.record.ref) == slow.map(\.record.ref), "\(language) \(query)")
                #expect(zip(fast, slow).allSatisfy { abs($0.score - $1.score) < 1e-9 }, "\(language) \(query)")
            }
        }
    }

    @Test func reusedEntriesGiveTheSameResults() {
        let (records, usage) = sample()
        let first = FoodSearchIndex(records, language: .german)
        var changed = records
        changed[3].name = "Something else entirely"
        changed[3].nameDE = "Etwas ganz anderes"
        changed.removeLast()
        let reused = FoodSearchIndex(changed, language: .german, reusing: first)
        let fresh = FoodSearchIndex(changed, language: .german)
        for query in Self.queries + ["etwas anderes", "haferriegel"] {
            #expect(reused.search(query, usage: usage).map(\.ref) == fresh.search(query, usage: usage).map(\.ref), "\(query)")
        }
        // Another language is never reused.
        let english = FoodSearchIndex(changed, language: .english, reusing: first)
        #expect(english.search("whole milk").map(\.ref) == FoodSearchIndex(changed, language: .english).search("whole milk").map(\.ref))
    }

    @Test func oneEditCheckMatchesTheDistance() {
        var generator = SeededGenerator(seed: 42)
        let alphabet: [Character] = ["a", "b", "c", "e"]
        for _ in 0..<4_000 {
            let a = String((0..<Int.random(in: 0...6, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! })
            let b = String((0..<Int.random(in: 0...6, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! })
            let expected = SearchText.distance(Array(a), Array(b), limit: 1) <= 1
            #expect(SearchText.isWithinOneEdit(SearchText.scalars(a), SearchText.scalars(b)) == expected, "\(a) \(b)")
            var buffers = SearchText.DistanceBuffers()
            for limit in 1...2 {
                #expect(SearchText.distance(SearchText.scalars(a), SearchText.scalars(b), limit: limit, buffers: &buffers)
                    == SearchText.distance(Array(a), Array(b), limit: limit), "\(a) \(b) \(limit)")
            }
        }
    }

    @Test func umlautFoldMatchesTheThreeReplacements() {
        var generator = SeededGenerator(seed: 7)
        let alphabet: [Character] = ["a", "o", "u", "e", "x"]
        for _ in 0..<3_000 {
            let token = String((0..<Int.random(in: 0...8, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! })
            let expected = token.count > 2
                ? token.replacingOccurrences(of: "ae", with: "a").replacingOccurrences(of: "oe", with: "o").replacingOccurrences(of: "ue", with: "u")
                : token
            #expect(SearchText.umlautFold(token) == expected, "\(token)")
        }
    }

    @Test func searchIsFast() {
        let (records, usage) = sample()
        let index = FoodSearchIndex(records, language: .german)
        let started = Date()
        var found = 0
        let phrase = "haferflocken mit milch"
        for length in 1...phrase.count { found += index.search(String(phrase.prefix(length)), usage: usage).count }
        let elapsed = Date().timeIntervalSince(started)
        #expect(found > 0)
        // Typing a 22-letter phrase used to cost ~470 ms of search on the CI machine; generous bound.
        #expect(elapsed < 2.5, "typing took \(elapsed) s")
    }

    @Test func emojiIsTheSameFromTheCache() {
        let banana = catalog[FoodRef("usda:09040")]
        let first = banana?.emoji
        #expect(first == "🍌")
        #expect(banana?.emoji == first)
        #expect(FoodEmoji.emoji(for: ["Vollmilch"], category: .dairy) == FoodEmoji.emoji(for: ["Vollmilch"], category: .dairy))
    }
}

/// Deterministic random numbers for the property checks.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The search as it was before it was made faster (string tokens, a full distance per token),
/// kept here to prove the ranking didn't change.
struct LegacySearchIndex {
    struct Entry {
        let record: FoodRecord
        let primary: [String]
        let details: [String]
        let sides: [String]
        let primaryJoined: String
        let secondary: [String]
        let aliases: [String]
        let aliasPhrases: Set<String>
        let brand: [String]
        let tags: [String]
        let category: [String]
    }

    let entries: [Entry]
    let language: FoodLanguage
    static let sideMarkers: Set<String> = ["mit", "with", "und", "and", "plus"]

    init(_ records: [FoodRecord], language: FoodLanguage) {
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
            return Entry(record: record, primary: Array(main[..<split]), details: details,
                         sides: sides.filter { !Self.sideMarkers.contains($0) }, primaryJoined: primary.joined(separator: " "),
                         secondary: SearchText.tokens(otherName), aliases: record.aliases.flatMap { SearchText.tokens($0) },
                         aliasPhrases: Set(record.aliases.map { SearchText.tokens($0).joined(separator: " ") }),
                         brand: SearchText.tokens(record.brand), tags: record.tags.flatMap { SearchText.tokens($0) },
                         category: SearchText.tokens(record.category.title))
        }
    }

    func scored(_ query: String, usage: [FoodRef: FoodUsage], now: Date, limit: Int) -> [(record: FoodRecord, score: Double)] {
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
            score += 1.0
        } else if entry.primaryJoined.hasPrefix(joined), !(words.count == 1 && FoodSearchIndex.isCompoundStart(words[0], of: entry.primary.first)) {
            score += 0.5
        }
        if let first = words.first, let head = entry.primary.first,
           (head.hasPrefix(first) && !FoodSearchIndex.isCompoundStart(first, of: head)) || FoodSearchIndex.stems(first).contains(head) {
            score += 0.25
        }
        let nameWords = (entry.primary + entry.details).filter { $0.contains(where: \.isLetter) }.count
        score -= 0.03 * Double(max(0, nameWords - words.count))
        return score
    }

    static func bestMatch(_ word: String, in tokens: [String]) -> Double {
        var best = 0.0
        let singular = FoodSearchIndex.stems(word)
        for token in tokens {
            if token == word { return 1 }
            if singular.contains(token) {
                best = max(best, 0.98)
            } else if FoodSearchIndex.isCompoundStart(word, of: token) {
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
