import Foundation

/// How often a food was logged at one meal and when last (part of `FoodUsage.meals`).
public struct FoodMealUse: Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date?

    public init(count: Int = 0, lastUsed: Date? = nil) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

extension FoodUsage {
    /// Counts one eaten diary entry: logged to `meal` at `time`, `amount` in the food's base unit.
    /// The order doesn't matter: the newest entry sets `lastUsed` and `lastAmount` (on equal
    /// times the one counted last).
    public mutating func record(meal: String, at time: Date, amount: Double) {
        count += 1
        if lastUsed.map({ time >= $0 }) ?? true {
            lastUsed = time
            lastAmount = amount
        }
        guard !meal.isEmpty else { return }
        var use = meals[meal] ?? FoodMealUse()
        use.count += 1
        if use.lastUsed.map({ time >= $0 }) ?? true {
            use.lastUsed = time
        }
        meals[meal] = use
    }

    /// The share of this food's logs that went to `meal` (0…1; 0 when never logged).
    public func share(at meal: String) -> Double {
        let atMeal = meals[meal]?.count ?? 0
        let total = max(count, meals.values.reduce(0) { $0 + $1.count })
        guard total > 0 else { return 0 }
        return Double(atMeal) / Double(total)
    }
}

/// The Recent list of the log sheet, sorted for the meal being logged: first the foods mostly
/// logged at that meal ("Mostly at breakfast"), the most often logged there first, then every other
/// food logged lately, the most recent first.
///
/// "Mostly at" a meal: logged there at least twice, at least 40 % of the food's logs went there
/// (coffee at breakfast and as a snack counts for both; the olive oil of 30 dinners doesn't count
/// for one breakfast), and the last time there is at most 60 days ago (old habits drop out).
public enum RecentFoods {
    /// Logs at the meal it takes ("once" is not a habit).
    public static let minimumCount = 2
    /// The share of the food's logs that went to the meal.
    public static let minimumShare = 0.4
    /// The last log at the meal is at most this many days old.
    public static let freshDays = 60
    /// At most this many foods lead the list; more go to the rest by recency.
    public static let mealLimit = 12

    /// The Recent list split in two.
    public struct Split: Equatable, Sendable {
        /// Mostly logged at the meal, the most often logged there first.
        public var forMeal: [FoodRef]
        /// The other foods logged lately, the most recent first.
        public var others: [FoodRef]

        public init(forMeal: [FoodRef] = [], others: [FoodRef] = []) {
            self.forMeal = forMeal
            self.others = others
        }

        /// The whole list in order.
        public var all: [FoodRef] { forMeal + others }
    }

    /// A food that is mostly logged at `meal` (see the type's rules); false for an empty meal id.
    public static func isMostlyAt(_ meal: String, _ use: FoodUsage, now: Date = Date()) -> Bool {
        guard !meal.isEmpty, let atMeal = use.meals[meal], atMeal.count >= minimumCount,
              let last = atMeal.lastUsed, now.timeIntervalSince(last) <= Double(freshDays) * 86_400 else { return false }
        return use.share(at: meal) >= minimumShare - 1e-9
    }

    /// The Recent list for logging to `meal` (empty = no meal: just the most recent first), at most
    /// `limit` foods. `isAvailable` leaves out foods the library no longer has (deleted or hidden),
    /// so the counts stay right.
    public static func split(_ usage: [FoodRef: FoodUsage], meal: String, now: Date = Date(), limit: Int = 40,
                             isAvailable: (FoodRef) -> Bool = { _ in true }) -> Split {
        guard limit > 0 else { return Split() }
        let available: [(key: FoodRef, value: FoodUsage)] = Array(usage.filter { isAvailable($0.key) })
        let leading: [(key: FoodRef, value: FoodUsage)] = available.filter { isMostlyAt(meal, $0.value, now: now) }
        let forMeal: [FoodRef] = leading.sorted { mealOrder(meal, $0, $1) }.prefix(min(mealLimit, limit)).map { $0.key }
        let chosen = Set(forMeal)
        let rest: [(key: FoodRef, value: FoodUsage)] = available.filter { !chosen.contains($0.key) }
        let others: [FoodRef] = rest.sorted { recencyOrder($0, $1) }.prefix(limit - forMeal.count).map { $0.key }
        return Split(forMeal: forMeal, others: others)
    }

    /// `refs` with the foods mostly logged at `meal` moved to the front (the most often logged
    /// there first); the others keep their order. For the saved-meals row above the list.
    public static func sortedForMeal(_ refs: [FoodRef], usage: [FoodRef: FoodUsage], meal: String, now: Date = Date()) -> [FoodRef] {
        var leading: [(key: FoodRef, value: FoodUsage)] = []
        var rest: [FoodRef] = []
        for ref in refs {
            if let use = usage[ref], isMostlyAt(meal, use, now: now) {
                leading.append((key: ref, value: use))
            } else {
                rest.append(ref)
            }
        }
        return leading.sorted { mealOrder(meal, $0, $1) }.map { $0.key } + rest
    }

    /// The small header over the leading foods: "Mostly at breakfast", "Mostly as a snack"; an own
    /// meal (or a renamed one) keeps its name as typed: "Mostly at Second Breakfast".
    public static func hint(for slot: MealSlot) -> String {
        if let standard = MealSlot.defaults.first(where: { $0.id == slot.id }), standard.name == slot.name {
            return slot.id == MealSlot.snack.id ? "Mostly as a snack" : "Mostly at \(slot.name.lowercased())"
        }
        let name = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Mostly at this meal" : "Mostly at \(name)"
    }

    /// The header for the meal id being logged, looked up in the person's meals; a meal that is no
    /// longer one of them (an own meal removed in Settings, still on older entries) reads "Mostly at
    /// this meal" rather than a stand-in name.
    public static func hint(forMeal id: String, in meals: [MealSlot]) -> String {
        guard let slot = meals.first(where: { $0.id == id }) else { return "Mostly at this meal" }
        return hint(for: slot)
    }

    // MARK: Order

    /// Most often at the meal first, then the latest there, then by reference (a stable order).
    private static func mealOrder(_ meal: String, _ a: (key: FoodRef, value: FoodUsage), _ b: (key: FoodRef, value: FoodUsage)) -> Bool {
        let left = a.value.meals[meal] ?? FoodMealUse()
        let right = b.value.meals[meal] ?? FoodMealUse()
        if left.count != right.count { return left.count > right.count }
        let leftLast = left.lastUsed ?? .distantPast
        let rightLast = right.lastUsed ?? .distantPast
        if leftLast != rightLast { return leftLast > rightLast }
        return a.key < b.key
    }

    /// The most recent first, then the most often logged, then by reference (a stable order).
    private static func recencyOrder(_ a: (key: FoodRef, value: FoodUsage), _ b: (key: FoodRef, value: FoodUsage)) -> Bool {
        let leftLast = a.value.lastUsed ?? .distantPast
        let rightLast = b.value.lastUsed ?? .distantPast
        if leftLast != rightLast { return leftLast > rightLast }
        if a.value.count != b.value.count { return a.value.count > b.value.count }
        return a.key < b.key
    }
}
