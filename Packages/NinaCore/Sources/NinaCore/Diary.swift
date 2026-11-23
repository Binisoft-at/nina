import Foundation

/// An entry is eaten (counts), planned (shown dimmed, counts once confirmed) or skipped.
public enum EntryStatus: String, CaseIterable, Codable, Sendable {
    case eaten, planned, skipped

    public init(text: String) {
        switch SearchText.normalize(text) {
        case "planned", "plan", "geplant", "todo", "later": self = .planned
        case "skipped", "skip", "ubersprungen", "no": self = .skipped
        default: self = .eaten
        }
    }
}

/// A meal of the day. The four standard meals always exist; people add their own
/// ("Jause", "Pre-workout") with a name, emoji and usual time.
public struct MealSlot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Usual time, minutes after midnight (used for planning, reminders and to suggest the meal).
    public var minutes: Int

    public init(id: String, name: String, emoji: String, minutes: Int) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.minutes = minutes
    }

    public var isBuiltIn: Bool { MealSlot.builtInIDs.contains(id) }

    public static let breakfast = MealSlot(id: "breakfast", name: "Breakfast", emoji: "🥐", minutes: 7 * 60 + 30)
    public static let lunch = MealSlot(id: "lunch", name: "Lunch", emoji: "🥗", minutes: 12 * 60 + 30)
    public static let dinner = MealSlot(id: "dinner", name: "Dinner", emoji: "🍝", minutes: 18 * 60 + 30)
    public static let snack = MealSlot(id: "snack", name: "Snacks", emoji: "🍎", minutes: 15 * 60 + 30)
    public static let defaults: [MealSlot] = [.breakfast, .lunch, .dinner, .snack]
    static let builtInIDs: Set<String> = ["breakfast", "lunch", "dinner", "snack"]

    /// JSON for the synced profile.
    public static func encode(_ slots: [MealSlot]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(slots) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Always contains the four standard meals (people can rename them but not lose them).
    public static func decode(_ text: String) -> [MealSlot] {
        var slots: [MealSlot] = []
        if let data = text.data(using: .utf8), let decoded = try? JSONDecoder().decode([MealSlot].self, from: data) {
            slots = decoded
        }
        for builtIn in defaults where !slots.contains(where: { $0.id == builtIn.id }) {
            slots.append(builtIn)
        }
        var seen = Set<String>()
        return slots.filter { seen.insert($0.id).inserted }.sorted { $0.minutes < $1.minutes }
    }

    /// The meal people usually eat at this time: the slot whose usual time is closest
    /// (snacks only win when no main meal is within 75 minutes).
    public static func suggested(atMinutes minutes: Int, in slots: [MealSlot]) -> MealSlot {
        let sorted = slots.isEmpty ? defaults : slots
        func distance(_ slot: MealSlot) -> Int {
            let raw = abs(slot.minutes - minutes)
            return min(raw, 1440 - raw)
        }
        let mains = sorted.filter { $0.id != "snack" }
        if let main = mains.min(by: { distance($0) < distance($1) }), distance(main) <= 75 { return main }
        return sorted.first { $0.id == "snack" } ?? sorted.min(by: { distance($0) < distance($1) }) ?? .snack
    }

    /// Meal names in CSV files and dictation ("Frühstück", "Jause", "Abendessen").
    public static func matching(_ text: String, in slots: [MealSlot]) -> MealSlot? {
        // A meal's own id as stored ("meal-jause", "meal-3f2a1b9c") – normalising would split it.
        let raw = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let byID = slots.first(where: { $0.id.lowercased() == raw }), !raw.isEmpty { return byID }
        let key = SearchText.normalize(text)
        guard !key.isEmpty else { return nil }
        if let exact = slots.first(where: { SearchText.normalize($0.name) == key || $0.id == key }) { return exact }
        let synonyms: [String: String] = [
            "fruhstuck": "breakfast", "morning": "breakfast", "morgen": "breakfast",
            "mittagessen": "lunch", "mittag": "lunch", "noon": "lunch",
            "abendessen": "dinner", "abend": "dinner", "supper": "dinner", "evening": "dinner", "nachtmahl": "dinner",
            "snacks": "snack", "zwischenmahlzeit": "snack", "jause": "snack", "snack": "snack",
        ]
        if let id = synonyms[key] { return slots.first { $0.id == id } }
        return nil
    }
}

/// What Core needs to know about a diary entry (built from the SwiftData model).
public struct EntryFacts: Sendable {
    public var day: DayKey
    public var meal: String
    public var status: EntryStatus
    public var nutrients: NutrientValues
    public var foodRef: FoodRef
    public var name: String
    public var category: FoodCategory
    /// When it was (or is planned to be) eaten.
    public var time: Date
    /// Base amount (g/ml/servings), 0 for quick entries.
    public var amount: Double

    public init(day: DayKey, meal: String, status: EntryStatus = .eaten, nutrients: NutrientValues, foodRef: FoodRef = .none,
                name: String, category: FoodCategory = .other, time: Date, amount: Double = 0) {
        self.day = day
        self.meal = meal
        self.status = status
        self.nutrients = nutrients
        self.foodRef = foodRef
        self.name = name
        self.category = category
        self.time = time
        self.amount = amount
    }
}

/// Totals of one day.
public struct DayTotals: Equatable, Sendable {
    public var day: DayKey
    public var eaten: NutrientValues
    public var planned: NutrientValues
    public var byMeal: [String: NutrientValues]
    public var eatenCount: Int
    public var plannedCount: Int
    /// ml from the water log.
    public var water: Double

    public init(day: DayKey, entries: [EntryFacts], water: Double = 0) {
        self.day = day
        var eaten = NutrientValues()
        var planned = NutrientValues()
        var byMeal: [String: NutrientValues] = [:]
        var eatenCount = 0
        var plannedCount = 0
        for entry in entries where entry.day == day {
            switch entry.status {
            case .eaten:
                eaten += entry.nutrients
                byMeal[entry.meal, default: NutrientValues()] += entry.nutrients
                eatenCount += 1
            case .planned:
                planned += entry.nutrients
                plannedCount += 1
            case .skipped:
                break
            }
        }
        self.eaten = eaten
        self.planned = planned
        self.byMeal = byMeal
        self.eatenCount = eatenCount
        self.plannedCount = plannedCount
        self.water = water
    }

    /// Eaten + still planned: where the day will end if the plan holds.
    public var projected: NutrientValues { eaten + planned }
    public var isLogged: Bool { eatenCount > 0 }
}

/// How a day stands against its targets.
public struct DayProgress: Equatable, Sendable {
    public var totals: DayTotals
    public var targets: DailyTargets
    /// kcal burned that are added to the budget (from Apple Health, if enabled).
    public var activityBonus: Double

    public init(totals: DayTotals, targets: DailyTargets, activityBonus: Double = 0) {
        self.totals = totals
        self.targets = targets
        self.activityBonus = max(0, activityBonus)
    }

    public var energyBudget: Double { targets.energy + activityBonus }
    public var energyEaten: Double { totals.eaten.energy }
    /// Negative when over.
    public var energyRemaining: Double { energyBudget - energyEaten }
    public var energyFraction: Double { energyBudget > 0 ? energyEaten / energyBudget : 0 }

    public func fraction(_ nutrient: Nutrient) -> Double {
        let eaten = nutrient == .water ? totals.water : totals.eaten.value(nutrient)
        let target = nutrient == .energy ? energyBudget : (targets.target(for: nutrient) ?? 0)
        guard target > 0 else { return 0 }
        return eaten / target
    }

    public func remaining(_ nutrient: Nutrient) -> Double {
        let eaten = nutrient == .water ? totals.water : totals.eaten.value(nutrient)
        let target = nutrient == .energy ? energyBudget : (targets.target(for: nutrient) ?? 0)
        return target - eaten
    }

    public enum Verdict: String, Sendable { case under, onTrack, over }

    /// Within ±10 % of the energy budget counts as on track.
    public var verdict: Verdict {
        let fraction = energyFraction
        if fraction > 1.1 { return .over }
        if fraction >= 0.9 { return .onTrack }
        return .under
    }
}
