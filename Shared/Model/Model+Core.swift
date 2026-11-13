import Foundation
import SwiftData
import NinaCore

/// "|"-separated labels in one text field.
enum TagText {
    static func split(_ text: String) -> [String] {
        text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func join(_ tags: [String]) -> String {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "/") }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .joined(separator: "|")
    }
}

extension LogEntry {
    var dayKey: DayKey { DayKey(day) ?? DayKey(date: time) }
    var entryStatus: EntryStatus { EntryStatus(rawValue: status) ?? .eaten }
    var isPlanned: Bool { status == EntryStatus.planned.rawValue }
    var isEaten: Bool { status == EntryStatus.eaten.rawValue }
    var values: NutrientValues { NutrientValues(encoded: nutrients) }
    var energy: Double { values.energy }
    var ref: FoodRef { FoodRef(foodRef) }
    var foodCategory: FoodCategory { FoodCategory(rawValue: category) ?? .other }
    var tagList: [String] { TagText.split(tags) }
    var base: BaseUnit { BaseUnit(rawValue: baseUnit) ?? .gram }
    var isQuickEntry: Bool { foodRef.isEmpty }

    var amount: AmountText {
        AmountText(quantity: quantity, unitLabel: unitLabel, unitAmount: unitAmount, baseUnit: base)
    }

    /// Base amount (g, ml or servings).
    var totalAmount: Double { quantity * unitAmount }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Quick entry" : trimmed
    }

    /// "1 medium (182 g)", or nothing for quick entries.
    var amountDescription: String? {
        isQuickEntry && totalAmount <= 0 ? nil : amount.text
    }

    var facts: EntryFacts {
        EntryFacts(day: dayKey, meal: meal, status: entryStatus, nutrients: values, foodRef: ref, name: displayName,
                   category: foodCategory, time: time, amount: totalAmount)
    }

    var draft: DiaryDraft {
        DiaryDraft(day: dayKey, minutes: ClockTime.minutes(of: time), meal: meal, name: displayName, brand: brand,
                   quantity: quantity, unitLabel: unitLabel, amount: base == .serving ? 0 : totalAmount, unit: base,
                   nutrients: values, note: note, status: entryStatus)
    }

    var key: String { importKey.isEmpty ? "id:" + uuid.uuidString : importKey }
}

extension Food {
    var foodUnit: BaseUnit { BaseUnit(rawValue: unit) ?? .gram }
    var foodCategory: FoodCategory { FoodCategory(rawValue: category) ?? .other }
    var tagList: [String] { TagText.split(tags) }
    var servingList: [Serving] { Serving.decode(servings) }

    /// Catalog overlays keep the catalog reference, so history and usage stay attached.
    var ref: FoodRef { catalogID.isEmpty ? .food(uuid) : FoodRef(catalogID) }

    var record: FoodRecord {
        FoodRecord(
            ref: ref,
            recordID: uuid,
            name: name,
            nameDE: nameDE,
            brand: brand,
            category: foodCategory,
            unit: foodUnit,
            density: density,
            nutrients: NutrientValues(encoded: nutrients),
            servings: servingList,
            aliases: TagText.split(aliases),
            barcode: barcode,
            tags: tagList,
            isFavorite: isFavorite,
            source: FoodSource(rawValue: source) ?? .custom,
            usualAmount: usualAmount
        )
    }

    var draft: FoodDraft {
        FoodDraft(name: name, nameDE: nameDE, brand: brand, category: foodCategory, tags: tagList,
                  unit: foodUnit == .milliliter ? .milliliter : .gram, nutrients: NutrientValues(encoded: nutrients),
                  servings: servingList, barcode: barcode, isFavorite: isFavorite, notes: notes)
    }

    func apply(_ draft: FoodDraft) {
        name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        nameDE = draft.nameDE.trimmingCharacters(in: .whitespacesAndNewlines)
        brand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        category = draft.category.rawValue
        tags = TagText.join(draft.tags)
        unit = draft.unit.rawValue
        nutrients = draft.nutrients.encoded
        servings = Serving.encode(draft.servings)
        barcode = draft.barcode
        isFavorite = draft.isFavorite
        notes = draft.notes
    }

    var key: String { importKey.isEmpty ? "id:" + uuid.uuidString : importKey }
}

extension RecipeItem {
    var values: NutrientValues { NutrientValues(encoded: nutrients) }
    var base: BaseUnit { BaseUnit(rawValue: baseUnit) ?? .gram }
    var amount: AmountText { AmountText(quantity: quantity, unitLabel: unitLabel, unitAmount: unitAmount, baseUnit: base) }
    var ref: FoodRef { FoodRef(foodRef) }
    var foodCategory: FoodCategory { FoodCategory(rawValue: category) ?? .other }
}

extension Recipe {
    var recipeKind: RecipeKind { RecipeKind(rawValue: kind) ?? .meal }
    var tagList: [String] { TagText.split(tags) }

    var sortedItems: [RecipeItem] {
        (items ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var totals: NutrientValues { NutrientValues.sum(sortedItems.map(\.values)) }

    /// Weight the per-100 g values refer to (0 when only servings are known).
    var weight: Double {
        RecipeMath.weight(items: sortedItems.map { ($0.quantity * $0.unitAmount, $0.base) }, cookedWeight: totalWeight)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var symbol: String {
        if !emoji.isEmpty { return emoji }
        return recipeKind == .meal ? "🍱" : "🍲"
    }

    /// A recipe as a food (per 100 g or per serving). A saved meal counts as one serving = all of it.
    var record: FoodRecord {
        var record: FoodRecord
        if recipeKind == .meal {
            record = FoodRecord(ref: .recipe(uuid), recordID: uuid, name: displayName, category: .dishes, unit: .serving,
                                nutrients: totals, servings: [], tags: tagList, isFavorite: isFavorite, source: .recipe)
        } else {
            record = RecipeMath.record(ref: .recipe(uuid), recordID: uuid, name: displayName, totals: totals,
                                       servings: servings, weight: weight, isFavorite: isFavorite, tags: tagList)
        }
        record.aliases = sortedItems.map(\.name)
        return record
    }

    var draft: RecipeDraft {
        RecipeDraft(name: displayName, kind: recipeKind, servings: servings, totalWeight: totalWeight, notes: notes,
                    items: sortedItems.map { item in
                        RecipeItemDraft(name: item.name, quantity: item.quantity, unitLabel: item.unitLabel,
                                        amount: item.base == .serving ? 0 : item.quantity * item.unitAmount,
                                        unit: item.base, nutrients: item.values)
                    })
    }
}

extension WaterLog {
    var dayKey: DayKey { DayKey(day) ?? DayKey(date: time) }
}

extension WeightEntry {
    var dayKey: DayKey { DayKey(day) ?? DayKey(date: time) }
}

extension PlanRule {
    var days: Weekdays { Weekdays(encoded: weekdays) }
    var recipeUUID: UUID? { UUID(uuidString: recipeID) }
    var start: DayKey? { DayKey(startDay) }
    var end: DayKey? { DayKey(endDay) }
}

/// The profile as plain values – what every screen reads. Defaults when no profile exists yet
/// (a new device doesn't create one until something is changed, so it never overrides the
/// synced one).
struct NinaSettings: Equatable {
    var targets: DailyTargets = .standard
    var trainingTargets: DailyTargets?
    var trainingDays = Weekdays([])
    var meals: [MealSlot] = MealSlot.defaults.sorted { $0.minutes < $1.minutes }
    var language: FoodLanguage = FoodLanguage.preferred(languageCodes: Locale.preferredLanguages)
    var energyUnit: EnergyUnit = .kcal
    var dayStartHour = 0
    var activityBonusShare = 0.0
    var focus: [Nutrient] = [.protein, .carbs, .fat]
    var waterGlass = 250.0
    var body = BodyProfile()
    var hasBody = false
    var macroSplit: MacroSplit = .balanced
    var targetWeight = 0.0

    init() {}

    init(_ profile: NinaProfile?) {
        guard let profile else { return }
        targets = profile.targets.isEmpty ? .standard : DailyTargets(encoded: profile.targets)
        trainingTargets = profile.trainingTargets.isEmpty ? nil : DailyTargets(encoded: profile.trainingTargets)
        trainingDays = Weekdays(encoded: profile.trainingDays)
        meals = MealSlot.decode(profile.meals)
        if let language = FoodLanguage(rawValue: profile.foodLanguage) { self.language = language }
        energyUnit = EnergyUnit(rawValue: profile.energyUnit) ?? .kcal
        dayStartHour = profile.dayStartHour
        activityBonusShare = profile.activityBonusShare
        let focus = profile.focusNutrients.split(separator: ",").compactMap { Nutrient(rawValue: String($0)) }
        if !focus.isEmpty { self.focus = focus }
        waterGlass = profile.waterGlass > 0 ? profile.waterGlass : 250
        hasBody = profile.birthYear > 0 && profile.heightCm > 0
        body = BodyProfile(
            sex: Sex(rawValue: profile.sex) ?? .unspecified,
            age: profile.birthYear > 0 ? GoalCalculator.age(birthYear: profile.birthYear) : 35,
            heightCm: profile.heightCm > 0 ? profile.heightCm : 172,
            weightKg: 72,
            activity: ActivityLevel(rawValue: profile.activity) ?? .light,
            goal: WeightGoal(rawValue: profile.goal) ?? .maintain,
            ratePerWeek: profile.ratePerWeek
        )
        macroSplit = MacroSplit.presets.first { $0.id == profile.macroSplit } ?? .balanced
        targetWeight = profile.targetWeight
    }

    /// The targets that apply on a day (training-day targets on training weekdays).
    func targets(for day: DayKey, calendar: Calendar = .current) -> DailyTargets {
        if let trainingTargets, trainingDays.contains(day, calendar: calendar) { return trainingTargets }
        return targets
    }

    func isTrainingDay(_ day: DayKey, calendar: Calendar = .current) -> Bool {
        trainingTargets != nil && trainingDays.contains(day, calendar: calendar)
    }

    func meal(_ id: String) -> MealSlot {
        meals.first { $0.id == id } ?? MealSlot(id: id, name: id.capitalized, emoji: "🍽️", minutes: 12 * 60)
    }

    /// The meal people usually eat now.
    func suggestedMeal(at date: Date = Date(), calendar: Calendar = .current) -> MealSlot {
        MealSlot.suggested(atMinutes: ClockTime.minutes(of: date, calendar: calendar), in: meals)
    }

    func today(now: Date = Date(), calendar: Calendar = .current) -> DayKey {
        DayKey.today(calendar: calendar, now: now, dayStartHour: dayStartHour)
    }
}
