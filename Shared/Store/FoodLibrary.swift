import Foundation
import SwiftData
import Observation
import BinisoftKit
import NinaCore

/// One line of a quick-add preview: what was typed, the food it matched and how much.
struct QuickMatch: Identifiable {
    let id = UUID()
    var item: QuickItem
    var food: FoodRecord?
    var alternatives: [FoodRecord]
    var amount: QuickAmount?
    /// The food language when the line was matched: the portion word follows it, like the
    /// portion picker ("2 × Scheibe" next to "Vollkornbrot").
    var language: FoodLanguage = .english

    /// Totals for the line (a calorie-only item has just energy).
    var nutrients: NutrientValues {
        if item.isEnergyOnly, let kcal = item.kilocalories {
            return NutrientValues([.energy: kcal, .protein: 0, .carbs: 0, .fat: 0])
        }
        guard let food, let amount else { return NutrientValues() }
        return food.nutrients(forAmount: amount.amount)
    }

    var amountText: AmountText? {
        guard let food, let amount else { return nil }
        if let serving = amount.serving {
            return AmountText(quantity: amount.count, unitLabel: serving.label(language), unitAmount: serving.amount, baseUnit: food.unit)
        }
        return AmountText(quantity: amount.amount, unitLabel: food.unit.symbol, unitAmount: 1, baseUnit: food.unit)
    }

    var isResolved: Bool { item.isEnergyOnly || food != nil }
}

/// Every food Nina can log, in one place: the bundled catalog, the person's own foods (and
/// personal versions of catalog foods), their recipes and saved meals – with search and the
/// usage that ranks it. Searching is in memory and takes about a millisecond.
///
/// `rebuild` runs after every save and sync, but most saves (water, weigh-ins, ticks, check-ins)
/// can't change the library: a cheap change token (counts and the latest change of foods,
/// recipes and diary entries) skips those, and an unchanged food keeps its prepared search entry,
/// so only what changed is read again.
@MainActor
@Observable
final class FoodLibrary {
    let catalog: FoodCatalog
    private(set) var language: FoodLanguage = .english
    private(set) var records: [FoodRecord] = []
    private(set) var byRef: [FoodRef: FoodRecord] = [:]
    private(set) var usage: [FoodRef: FoodUsage] = [:]
    /// Grows with every rebuild that changed something, so views can refresh.
    private(set) var version = 0
    @ObservationIgnored private var index = FoodSearchIndex([], language: .english)
    /// What the last rebuild read (nil before the first one).
    @ObservationIgnored private var token: LibraryToken?
    /// Catalog, own foods and recipes before the usage is applied (reused when only usage changed).
    @ObservationIgnored private var base: [FoodRef: FoodRecord] = [:]
    /// The last time everything was read, whatever the token said: a safety net for changes that
    /// don't move a count or a change date (an Undo that puts a value back without a new date).
    @ObservationIgnored private var lastFullRead = Date.distantPast
    @ObservationIgnored private var nameOrderCache: (version: Int, order: [FoodRef: Int])?

    /// The last index built per language, shared by every library in the process (the app, the
    /// Siri intent, the watch): its catalog entries are reused instead of being prepared again.
    private static var sharedIndexes: [FoodLanguage: FoodSearchIndex] = [:]

    init(catalog: FoodCatalog = .bundled) {
        self.catalog = catalog
    }

    func rebuild(context: ModelContext, language: FoodLanguage, usageDays: Int = 180) {
        let started = Date()
        let since = DayKey.today().adding(days: -usageDays).rawValue
        let next = LibraryToken.read(context: context, language: language, since: since)
        let previous = token
        let isStale = started.timeIntervalSince(lastFullRead) > 300
        if let previous, previous == next, !isStale { return }

        let usageChanged = isStale || previous?.usage != next.usage
        // A new diary entry can carry a new usual amount for an own food (saved without a change date).
        let foodsChanged = isStale || usageChanged || previous?.foods != next.foods || previous?.language != language
        if foodsChanged { base = readBase(context: context) }
        let counts = usageChanged ? readUsage(context: context, since: since) : usage

        var merged = base
        for (ref, use) in counts {
            guard var record = merged[ref], record.unit != .serving || record.ref.kind != .recipe else { continue }
            if record.usualAmount <= 0, use.lastAmount > 0 { record.usualAmount = use.lastAmount }
            merged[ref] = record
        }
        let sorted = merged.values.sorted { $0.displayName(language) < $1.displayName(language) }
        token = next
        if usageChanged { lastFullRead = started }

        // Assign only what changed: every assignment re-renders the views that read the library.
        let indexIsCurrent = index.language == language && sorted == records
        let changed = !indexIsCurrent || counts != usage || language != self.language
        guard changed else { return }
        if language != self.language { self.language = language }
        if !indexIsCurrent {
            let reusable = index.language == language && index.count > 0 ? index : Self.sharedIndexes[language]
            index = FoodSearchIndex(sorted, language: language, reusing: reusable)
            Self.sharedIndexes[language] = index
            records = sorted
            byRef = merged
        }
        if counts != usage { usage = counts }
        version += 1
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.debug("Food library: \(records.count) foods, \(counts.count) used, \(elapsed) ms", category: "foods")
    }

    /// The catalog with the person's foods (hidden ones removed) and recipes.
    private func readBase(context: ModelContext) -> [FoodRef: FoodRecord] {
        var merged = catalog.byRef
        let foods = (try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.deletedAt == nil }))) ?? []
        var hidden = Set<FoodRef>()
        for food in foods {
            let record = food.record
            if food.isHidden {
                hidden.insert(record.ref)
                continue
            }
            merged[record.ref] = record
        }
        for ref in hidden { merged[ref] = nil }

        let recipes = (try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.deletedAt == nil }))) ?? []
        for recipe in recipes {
            let record = recipe.record
            merged[record.ref] = record
        }
        return merged
    }

    /// Usage from the diary: how often, how recently and how much – overall and per meal (the
    /// log sheet's Recent list leads with the foods mostly logged at the meal being logged).
    private func readUsage(context: ModelContext, since: String) -> [FoodRef: FoodUsage] {
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day >= since && $0.deletedAt == nil && $0.foodRef != "" },
            sortBy: [SortDescriptor(\.time)]
        )
        var counts: [FoodRef: FoodUsage] = [:]
        for entry in (try? context.fetch(descriptor)) ?? [] where entry.isEaten {
            var use = counts[entry.ref] ?? FoodUsage()
            use.record(meal: entry.meal, at: entry.time, amount: entry.totalAmount)
            counts[entry.ref] = use
        }
        return counts
    }

    func record(_ ref: FoodRef) -> FoodRecord? { byRef[ref] }

    func search(_ text: String, limit: Int = 60) -> [FoodRecord] {
        index.search(text, usage: usage, limit: limit)
    }

    func bestMatch(_ text: String) -> FoodRecord? {
        index.search(text, usage: usage, limit: 1).first
    }

    var favorites: [FoodRecord] {
        records.filter(\.isFavorite)
    }

    /// Logged most recently first.
    func recents(limit: Int = 25) -> [FoodRecord] {
        usage.sorted { ($0.value.lastUsed ?? .distantPast) > ($1.value.lastUsed ?? .distantPast) }
            .prefix(limit)
            .compactMap { byRef[$0.key] }
    }

    /// The log sheet's Recent list for `meal`: the foods mostly logged at that meal first (the
    /// most often logged there first, at most 12), then the rest, the most recent first
    /// (`RecentFoods`). An empty meal id gives just the most recent first.
    func recents(for meal: String, limit: Int = 40, now: Date = Date()) -> MealRecents {
        let known: [FoodRef: FoodRecord] = byRef
        let split = RecentFoods.split(usage, meal: meal, now: now, limit: limit) { (ref: FoodRef) -> Bool in
            known[ref] != nil
        }
        return MealRecents(forMeal: split.forMeal.compactMap { known[$0] }, others: split.others.compactMap { known[$0] })
    }

    /// The Recent list for a meal in two parts (`recents(for:limit:now:)`).
    struct MealRecents: Equatable {
        /// Mostly logged at the meal ("Mostly at breakfast").
        var forMeal: [FoodRecord] = []
        /// Everything else logged lately, the most recent first.
        var others: [FoodRecord] = []

        var all: [FoodRecord] { forMeal + others }
    }

    /// Logged most often first.
    func frequent(limit: Int = 25) -> [FoodRecord] {
        usage.sorted { $0.value.count > $1.value.count }
            .prefix(limit)
            .compactMap { byRef[$0.key] }
    }

    func usage(of ref: FoodRef) -> FoodUsage? { usage[ref] }

    /// Each food's place in an A–Z list the way people read it (accents and numbers sorted
    /// naturally), worked out once per rebuild – lists sort by this number instead of comparing
    /// names on every render.
    func nameOrder() -> [FoodRef: Int] {
        if let cache = nameOrderCache, cache.version == version { return cache.order }
        let language = self.language
        let names = records.map { ($0.ref, $0.displayName(language)) }
        let sorted = names.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        var order: [FoodRef: Int] = [:]
        order.reserveCapacity(sorted.count)
        for (position, item) in sorted.enumerated() { order[item.0] = position }
        nameOrderCache = (version, order)
        return order
    }

    /// "200 g chicken, 2 eggs" → matches with amounts (the preview before logging). A line with a
    /// joiner that finds nothing is tried again split on it ("2 Semmeln mit Butter").
    func quickMatches(_ text: String) -> [QuickMatch] {
        QuickParser.parse(text).flatMap { item -> [QuickMatch] in
            let match = quickMatch(item)
            guard match.food == nil, !item.isEnergyOnly else { return [match] }
            let parts = QuickParser.splitOnEveryJoiner(item)
            guard !parts.isEmpty else { return [match] }
            let retried = parts.map(quickMatch)
            return retried.contains { $0.food != nil } ? retried : [match]
        }
    }

    private func quickMatch(_ item: QuickItem) -> QuickMatch {
        if item.isEnergyOnly {
            return QuickMatch(item: item, food: nil, alternatives: [], amount: nil, language: language)
        }
        let found = index.search(item.query, usage: usage, limit: 5)
        guard let food = found.first else {
            return QuickMatch(item: item, food: nil, alternatives: [], amount: nil, language: language)
        }
        return QuickMatch(item: item, food: food, alternatives: Array(found.dropFirst()),
                          amount: QuickParser.amount(for: item, food: food), language: language)
    }

    /// True when the text reads like an amount + food list rather than a plain search ("2 eggs, toast").
    static func looksLikeQuickAdd(_ text: String) -> Bool {
        let items = QuickParser.parse(text)
        if items.count > 1 { return true }
        guard let item = items.first else { return false }
        return item.quantity != nil || item.unit != nil
    }
}

/// What the library was built from, read with a few counting queries: when it matches the last
/// rebuild's, nothing the library shows has changed.
private struct LibraryToken: Equatable {
    struct Foods: Equatable {
        var count: Int
        var latest: Date?
        var recipes: Int
        var latestRecipe: Date?
    }

    struct Usage: Equatable {
        var since: String
        var count: Int
        var eaten: Int
        var latest: Date?
    }

    var language: FoodLanguage
    var foods: Foods
    var usage: Usage

    @MainActor
    static func read(context: ModelContext, language: FoodLanguage, since: String) -> LibraryToken {
        let liveFoods = #Predicate<Food> { $0.deletedAt == nil }
        var latestFood = FetchDescriptor<Food>(predicate: liveFoods, sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        latestFood.fetchLimit = 1
        let liveRecipes = #Predicate<Recipe> { $0.deletedAt == nil }
        var latestRecipe = FetchDescriptor<Recipe>(predicate: liveRecipes, sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        latestRecipe.fetchLimit = 1
        let foods = Foods(
            count: (try? context.fetchCount(FetchDescriptor<Food>(predicate: liveFoods))) ?? -1,
            latest: (try? context.fetch(latestFood))?.first?.modifiedAt,
            recipes: (try? context.fetchCount(FetchDescriptor<Recipe>(predicate: liveRecipes))) ?? -1,
            latestRecipe: (try? context.fetch(latestRecipe))?.first?.modifiedAt
        )

        let eatenStatus = EntryStatus.eaten.rawValue
        let window = #Predicate<LogEntry> { $0.day >= since && $0.deletedAt == nil && $0.foodRef != "" }
        let eatenWindow = #Predicate<LogEntry> { $0.day >= since && $0.deletedAt == nil && $0.foodRef != "" && $0.status == eatenStatus }
        var latestEntry = FetchDescriptor<LogEntry>(predicate: window, sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        latestEntry.fetchLimit = 1
        let usage = Usage(
            since: since,
            count: (try? context.fetchCount(FetchDescriptor<LogEntry>(predicate: window))) ?? -1,
            eaten: (try? context.fetchCount(FetchDescriptor<LogEntry>(predicate: eatenWindow))) ?? -1,
            latest: (try? context.fetch(latestEntry))?.first?.modifiedAt
        )
        return LibraryToken(language: language, foods: foods, usage: usage)
    }
}
