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
            return AmountText(quantity: amount.count, unitLabel: serving.en, unitAmount: serving.amount, baseUnit: food.unit)
        }
        return AmountText(quantity: amount.amount, unitLabel: food.unit.symbol, unitAmount: 1, baseUnit: food.unit)
    }

    var isResolved: Bool { item.isEnergyOnly || food != nil }
}

/// Every food Nina can log, in one place: the bundled catalog, the person's own foods (and
/// personal versions of catalog foods), their recipes and saved meals – with search and the
/// usage that ranks it. Rebuilt after changes; searching is in memory and instant.
@MainActor
@Observable
final class FoodLibrary {
    let catalog: FoodCatalog
    private(set) var language: FoodLanguage = .english
    private(set) var records: [FoodRecord] = []
    private(set) var byRef: [FoodRef: FoodRecord] = [:]
    private(set) var usage: [FoodRef: FoodUsage] = [:]
    /// Grows with every rebuild, so views can refresh.
    private(set) var version = 0
    @ObservationIgnored private var index = FoodSearchIndex([], language: .english)

    init(catalog: FoodCatalog = .bundled) {
        self.catalog = catalog
    }

    func rebuild(context: ModelContext, language: FoodLanguage, usageDays: Int = 180) {
        let started = Date()
        self.language = language
        var merged: [FoodRef: FoodRecord] = [:]
        for food in catalog.foods { merged[food.ref] = food }

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

        // Usage from the diary: how often, how recently and how much.
        let since = DayKey.today().adding(days: -usageDays).rawValue
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day >= since && $0.deletedAt == nil && $0.foodRef != "" },
            sortBy: [SortDescriptor(\.time)]
        )
        var counts: [FoodRef: FoodUsage] = [:]
        for entry in (try? context.fetch(descriptor)) ?? [] where entry.isEaten {
            var use = counts[entry.ref] ?? FoodUsage()
            use.count += 1
            use.lastUsed = entry.time
            use.lastAmount = entry.totalAmount
            counts[entry.ref] = use
        }
        for (ref, use) in counts {
            guard var record = merged[ref], record.unit != .serving || record.ref.kind != .recipe else { continue }
            if record.usualAmount <= 0, use.lastAmount > 0 { record.usualAmount = use.lastAmount }
            merged[ref] = record
        }

        records = merged.values.sorted { $0.displayName(language) < $1.displayName(language) }
        byRef = merged
        usage = counts
        index = FoodSearchIndex(records, language: language)
        version += 1
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.debug("Food library: \(records.count) foods, \(counts.count) used, \(elapsed) ms", category: "foods")
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

    /// Logged most often first.
    func frequent(limit: Int = 25) -> [FoodRecord] {
        usage.sorted { $0.value.count > $1.value.count }
            .prefix(limit)
            .compactMap { byRef[$0.key] }
    }

    func usage(of ref: FoodRef) -> FoodUsage? { usage[ref] }

    /// "200 g chicken, 2 eggs" → matches with amounts (the preview before logging).
    func quickMatches(_ text: String) -> [QuickMatch] {
        QuickParser.parse(text).map { item in
            if item.isEnergyOnly {
                return QuickMatch(item: item, food: nil, alternatives: [], amount: nil)
            }
            let found = index.search(item.query, usage: usage, limit: 5)
            guard let food = found.first else {
                return QuickMatch(item: item, food: nil, alternatives: [], amount: nil)
            }
            return QuickMatch(item: item, food: food, alternatives: Array(found.dropFirst()),
                              amount: QuickParser.amount(for: item, food: food))
        }
    }

    /// True when the text reads like an amount + food list rather than a plain search ("2 eggs, toast").
    static func looksLikeQuickAdd(_ text: String) -> Bool {
        let items = QuickParser.parse(text)
        if items.count > 1 { return true }
        guard let item = items.first else { return false }
        return item.quantity != nil || item.unit != nil
    }
}
