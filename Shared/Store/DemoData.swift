import Foundation
import SwiftData
import NinaCore

/// Sample data. It lives only in separate in-memory stores (`-Demo` launches for screenshots, the
/// tour's practice day) and never syncs. Values are per 100 g from the bundled catalog's sources.
@MainActor
enum DemoData {
    struct DemoFood {
        let ref: String
        let name: String
        let category: FoodCategory
        let unit: BaseUnit
        let per100: NutrientValues
        let portion: (label: String, amount: Double)?
    }

    static let foods: [String: DemoFood] = {
        func n(_ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double, fiber: Double = 0, sugar: Double = 0) -> NutrientValues {
            NutrientValues([.energy: kcal, .protein: protein, .carbs: carbs, .fat: fat, .fiber: fiber, .sugar: sugar])
        }
        let list = [
            DemoFood(ref: "usda:08120", name: "Oats", category: .cereals, unit: .gram, per100: n(389, 16.9, 66.3, 6.9, fiber: 10.6, sugar: 0), portion: nil),
            DemoFood(ref: "usda:01079", name: "Milk 2%", category: .dairy, unit: .milliliter, per100: n(51, 3.4, 4.9, 2.0, sugar: 5.2), portion: ("glass", 250)),
            DemoFood(ref: "usda:09040", name: "Banana", category: .fruit, unit: .gram, per100: n(89, 1.1, 22.8, 0.3, fiber: 2.6, sugar: 12.2), portion: ("medium", 118)),
            DemoFood(ref: "usda:09003", name: "Apple", category: .fruit, unit: .gram, per100: n(52, 0.3, 13.8, 0.2, fiber: 2.4, sugar: 10.4), portion: ("medium", 182)),
            DemoFood(ref: "usda:05064", name: "Chicken breast, roasted", category: .poultry, unit: .gram, per100: n(165, 31, 0, 3.6), portion: nil),
            DemoFood(ref: "usda:20045", name: "White rice, cooked", category: .grains, unit: .gram, per100: n(130, 2.7, 28.2, 0.3, fiber: 0.4), portion: nil),
            DemoFood(ref: "usda:11251", name: "Lettuce", category: .vegetables, unit: .gram, per100: n(15, 1.4, 2.9, 0.2, fiber: 1.3, sugar: 0.8), portion: nil),
            DemoFood(ref: "usda:04053", name: "Olive oil", category: .fats, unit: .gram, per100: n(884, 0, 0, 100), portion: ("tbsp", 13.5)),
            DemoFood(ref: "nina:skyr-natur", name: "Skyr, plain", category: .dairy, unit: .gram, per100: n(63, 11, 4, 0.2, sugar: 4), portion: ("pot", 150)),
            DemoFood(ref: "usda:20121", name: "Spaghetti, cooked", category: .grains, unit: .gram, per100: n(158, 5.8, 30.9, 0.9, fiber: 1.8, sugar: 0.6), portion: nil),
            DemoFood(ref: "usda:11529", name: "Tomato", category: .vegetables, unit: .gram, per100: n(18, 0.9, 3.9, 0.2, fiber: 1.2, sugar: 2.6), portion: ("medium", 123)),
            DemoFood(ref: "usda:01123", name: "Egg", category: .eggs, unit: .gram, per100: n(143, 12.6, 0.7, 9.5), portion: ("large", 50)),
            DemoFood(ref: "nina:vollkornbrot", name: "Whole-grain bread", category: .bread, unit: .gram, per100: n(220, 8, 38, 2.5, fiber: 7.5, sugar: 3), portion: ("slice", 45)),
            DemoFood(ref: "usda:12061", name: "Almonds", category: .nuts, unit: .gram, per100: n(579, 21.2, 21.6, 49.9, fiber: 12.5, sugar: 4.4), portion: ("handful", 28)),
            DemoFood(ref: "usda:15076", name: "Salmon, baked", category: .fish, unit: .gram, per100: n(206, 22.1, 0, 12.4), portion: ("fillet", 154)),
            DemoFood(ref: "usda:11674", name: "Potatoes, boiled", category: .vegetables, unit: .gram, per100: n(87, 1.9, 20.1, 0.1, fiber: 1.8, sugar: 0.9), portion: nil),
            DemoFood(ref: "usda:19904", name: "Dark chocolate 70%", category: .sweets, unit: .gram, per100: n(598, 7.8, 45.9, 42.6, fiber: 10.9, sugar: 24), portion: ("square", 10)),
            DemoFood(ref: "usda:14209", name: "Coffee", category: .beverages, unit: .milliliter, per100: n(1, 0.1, 0, 0), portion: ("mug", 250)),
        ]
        var map: [String: DemoFood] = [:]
        for food in list { map[food.name] = food }
        return map
    }()

    @discardableResult
    static func add(_ name: String, amount: Double? = nil, count: Double? = nil, day: DayKey, meal: String, minutes: Int,
                    status: EntryStatus = .eaten, context: ModelContext) -> LogEntry? {
        guard let food = foods[name] else { return nil }
        let entry = LogEntry(day: day, time: day.date(minutes: minutes), meal: meal, name: food.name)
        entry.foodRef = food.ref
        entry.category = food.category.rawValue
        entry.baseUnit = food.unit.rawValue
        let grams: Double
        if let count, let portion = food.portion {
            entry.quantity = count
            entry.unitLabel = portion.label
            entry.unitAmount = portion.amount
            grams = count * portion.amount
        } else {
            let value = amount ?? 100
            entry.quantity = value
            entry.unitLabel = food.unit.symbol
            entry.unitAmount = 1
            grams = value
        }
        entry.nutrients = food.per100.scaled(by: grams / 100).encoded
        entry.status = status.rawValue
        entry.source = "demo"
        context.insert(entry)
        return entry
    }

    /// `-Demo` launches: a realistic month for screenshots (today half logged, dinner planned).
    static func seed(_ context: ModelContext) {
        let profile = NinaProfile()
        profile.targets = DailyTargets(energy: 2200, protein: 140, carbs: 240, fat: 73, fiber: 31, sugarMax: 55,
                                       saturatedFatMax: 24, sodiumMax: 2000, water: 2250).encoded
        profile.sex = Sex.female.rawValue
        profile.birthYear = 1991
        profile.heightCm = 171
        profile.activity = ActivityLevel.moderate.rawValue
        profile.focusNutrients = "protein,carbs,fat,fiber"
        context.insert(profile)

        let today = DayKey.today()
        for offset in (1...34).reversed() {
            let day = today.adding(days: -offset)
            guard offset % 11 != 0 else { continue } // a few unlogged days, like real life
            let variant = offset % 3
            add("Oats", amount: 60, day: day, meal: "breakfast", minutes: 450, context: context)
            add("Milk 2%", amount: 250, day: day, meal: "breakfast", minutes: 450, context: context)
            add(variant == 0 ? "Apple" : "Banana", count: 1, day: day, meal: "breakfast", minutes: 455, context: context)
            if variant == 2 {
                add("Salmon, baked", count: 1, day: day, meal: "lunch", minutes: 750, context: context)
                add("Potatoes, boiled", amount: 250, day: day, meal: "lunch", minutes: 750, context: context)
            } else {
                add("Chicken breast, roasted", amount: 160, day: day, meal: "lunch", minutes: 750, context: context)
                add("White rice, cooked", amount: 200 + Double(variant) * 40, day: day, meal: "lunch", minutes: 750, context: context)
            }
            add("Lettuce", amount: 80, day: day, meal: "lunch", minutes: 752, context: context)
            add("Skyr, plain", count: 1, day: day, meal: "snack", minutes: 960, context: context)
            if offset % 4 == 0 { add("Dark chocolate 70%", count: 3, day: day, meal: "snack", minutes: 1230, context: context) }
            add("Spaghetti, cooked", amount: 230 + Double(offset % 5) * 20, day: day, meal: "dinner", minutes: 1125, context: context)
            add("Tomato", count: 2, day: day, meal: "dinner", minutes: 1125, context: context)
            add("Olive oil", count: 1, day: day, meal: "dinner", minutes: 1125, context: context)
            for index in 0..<(5 + offset % 4) {
                context.insert(WaterLog(day: day, time: day.date(minutes: 480 + index * 100), amount: 250))
            }
            if offset % 2 == 0 {
                let weight = 68.4 - Double(34 - offset) * 0.035 + (offset % 3 == 0 ? 0.3 : -0.2)
                context.insert(WeightEntry(day: day, time: day.date(minutes: 420), kilograms: (weight * 10).rounded() / 10))
            }
        }

        add("Oats", amount: 60, day: today, meal: "breakfast", minutes: 445, context: context)
        add("Milk 2%", amount: 250, day: today, meal: "breakfast", minutes: 445, context: context)
        add("Banana", count: 1, day: today, meal: "breakfast", minutes: 446, context: context)
        add("Coffee", count: 1, day: today, meal: "breakfast", minutes: 450, context: context)
        add("Chicken breast, roasted", amount: 150, day: today, meal: "lunch", minutes: 760, context: context)
        add("White rice, cooked", amount: 220, day: today, meal: "lunch", minutes: 760, context: context)
        add("Lettuce", amount: 80, day: today, meal: "lunch", minutes: 761, context: context)
        add("Skyr, plain", count: 1, day: today, meal: "snack", minutes: 960, context: context)
        add("Almonds", count: 1, day: today, meal: "snack", minutes: 961, context: context)
        add("Salmon, baked", count: 1, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        add("Potatoes, boiled", amount: 250, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        add("Tomato", count: 2, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        for index in 0..<5 {
            context.insert(WaterLog(day: today, time: today.date(minutes: 480 + index * 90), amount: 250))
        }
        context.insert(WeightEntry(day: today, time: today.date(minutes: 420), kilograms: 67.3))

        let breakfast = Recipe(name: "Usual breakfast", kind: .meal)
        breakfast.emoji = "🥣"
        breakfast.isFavorite = true
        breakfast.defaultMeal = "breakfast"
        context.insert(breakfast)
        let lines: [(name: String, amount: Double, count: Double?)] = [("Oats", 60, nil), ("Milk 2%", 250, nil), ("Banana", 0, 1)]
        for (index, line) in lines.enumerated() {
            guard let food = foods[line.name] else { continue }
            let item = RecipeItem(name: food.name)
            item.foodRef = food.ref
            item.category = food.category.rawValue
            item.baseUnit = food.unit.rawValue
            let grams: Double
            if let count = line.count, let portion = food.portion {
                item.quantity = count
                item.unitLabel = portion.label
                item.unitAmount = portion.amount
                grams = count * portion.amount
            } else {
                item.quantity = line.amount
                item.unitLabel = food.unit.symbol
                grams = line.amount
            }
            item.nutrients = food.per100.scaled(by: grams / 100).encoded
            item.sortOrder = Double(index)
            item.recipe = breakfast
            context.insert(item)
        }
        let rule = PlanRule(recipeID: breakfast.uuid, title: breakfast.name, meal: "breakfast", minutes: 450, weekdays: .workdays)
        context.insert(rule)

        let skyr = Food(name: "Skyr, plain")
        skyr.catalogID = "nina:skyr-natur"
        skyr.category = FoodCategory.dairy.rawValue
        skyr.nutrients = NutrientValues([.energy: 63, .protein: 11, .carbs: 4, .fat: 0.2, .sugar: 4]).encoded
        skyr.servings = Serving.encode([Serving(en: "pot", de: "Becher", amount: 150)])
        skyr.isFavorite = true
        skyr.tags = "high-protein|snack"
        context.insert(skyr)
    }

    /// The tour's practice day: breakfast logged, dinner planned.
    static func seedPractice(_ context: ModelContext) {
        let today = DayKey.today()
        add("Oats", amount: 60, day: today, meal: "breakfast", minutes: 450, context: context)
        add("Milk 2%", amount: 200, day: today, meal: "breakfast", minutes: 450, context: context)
        add("Coffee", count: 1, day: today, meal: "breakfast", minutes: 455, context: context)
        add("Spaghetti, cooked", amount: 250, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        add("Tomato", count: 2, day: today, meal: "dinner", minutes: 1110, status: .planned, context: context)
        context.insert(WaterLog(day: today, time: today.date(minutes: 500), amount: 250))
    }
}
