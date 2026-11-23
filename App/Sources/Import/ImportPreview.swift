import Foundation
import SwiftData
import BinisoftKit
import NinaCore

/// What an import will do, for every format, with lookups for rows without nutrition. Reading
/// and planning run off the main thread; only the records the file names are fetched.
struct ImportPreview {
    struct Line: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let action: String
        /// A recipe's lookups ("Oats → Oats, rolled · Kidney beans → not found").
        var lookups = ""
        /// Something on this line can't be imported as it is (orange).
        var warning = false
    }

    let kind: ImportKind
    let lines: [Line]
    let skipped: [String]
    let summary: String
    let hasChanges: Bool
    private var foodPlan: ImportPlan<FoodDraft>?
    private var diaryPlan: ImportPlan<DiaryDraft>?
    private var recipePlan: ImportPlan<RecipeDraft>?
    /// Goals & settings: what the file changes (preview groups, body records, plan) and the
    /// settings before.
    private(set) var settings: (result: SettingsResult, previous: SettingsState)?
    /// What the AI found that Nina can't store yet.
    var wishes: [String] = []
    /// Weight & body history: the weigh-ins and measurements the file adds (for the preview) and
    /// the file's text, planned again when it is imported.
    private var historyPlan: BodyHistoryPlan?
    private var historyText: String?
    /// Diary rows to add or change from the last 14 days (the ones Apple Health is written for).
    private(set) var recentRows = 0
    /// The names (normalised) of the foods this part adds or changes, so later parts of the same
    /// answer find them.
    private(set) var foodNames: Set<String> = []

    /// Every changed setting is shown; rows of other files up to ten.
    var visibleLines: Int { kind == .settings ? 50 : 10 }

    /// Whether importing changes anything, without the body values the person unticked.
    func hasChanges(excluding unticked: Set<String>) -> Bool {
        guard let settings else { return hasChanges }
        return settings.result.removingBodyValues(unticked).hasChanges
    }

    /// `bundleFoods`: foods (normalised names) an earlier part of the same answer adds.
    @MainActor
    static func make(kind: ImportKind, text: String, app: AppModel, bundleFoods: Set<String> = []) async -> ImportPreview {
        switch kind {
        case .settings:
            return settingsPreview(text, app: app)
        case .foods:
            return await foodsPreview(text, app: app)
        case .diary:
            return await diaryPreview(text, app: app, bundleFoods: bundleFoods)
        case .recipes:
            return await recipesPreview(text, app: app, bundleFoods: bundleFoods)
        case .measurements:
            return historyPreview(text, app: app)
        }
    }

    /// "new", "update", "same".
    static func label<Record: Equatable>(_ action: ImportPlan<Record>.Action) -> String {
        switch action {
        case .create: "new"
        case .update: "update"
        case .unchanged: "same"
        }
    }

    // MARK: Goals & settings, weight & body

    @MainActor
    private static func settingsPreview(_ text: String, app: AppModel) -> ImportPreview {
        let previous = app.settingsState
        let draft = SettingsCSV.parse(text)
        let result = SettingsCSV.apply(draft, to: previous, year: Calendar.current.component(.year, from: Date()), today: app.today)
        let lines = result.changes.map { Line(title: $0.title, detail: "\($0.old) → \($0.new)", action: "change") }
        let count = result.changes.count
        var summary = result.hasChanges ? "\(count) setting\(count == 1 ? "" : "s") change" : "Your settings already match"
        if result.plan?.isSetUp == true, previous.plan?.isSetUp != true { summary = "Sets up your coach plan · " + summary }
        return ImportPreview(kind: .settings, lines: lines, skipped: draft.skipped + result.notes, summary: summary,
                             hasChanges: result.hasChanges, settings: (result, previous), wishes: draft.wishes)
    }

    @MainActor
    private static func historyPreview(_ text: String, app: AppModel) -> ImportPreview {
        let plan = app.store.bodyHistoryPlan(text, cutoffMinutes: app.settings.plan.routine.morningCutoffMinutes, today: app.today)
        return ImportPreview(kind: .measurements, lines: historyLines(plan, today: app.today), skipped: plan.notes, summary: plan.summary,
                             hasChanges: plan.hasChanges, historyPlan: plan, historyText: text)
    }

    // MARK: Foods

    /// Every key an own food answers to: its uuid, its import key and – for the person's own
    /// foods – name and brand.
    @MainActor
    static func keys(_ food: Food) -> [String] {
        var keys = ImportColumns.lookupKeys(uuid: food.uuid, importKey: food.importKey)
        if food.catalogID.isEmpty { keys.append(ImportPlan<FoodDraft>.contentKey([food.name, food.brand])) }
        return keys
    }

    @MainActor
    private static func foodsPreview(_ text: String, app: AppModel) async -> ImportPreview {
        let parsed = await Task.detached(priority: .userInitiated) { FoodCSV.parse(text) }.value
        let wanted = Set(parsed.rows.map(\.key))
        var existing: [String: FoodDraft] = [:]
        for food in app.store.foods() {
            let foodKeys = keys(food).filter(wanted.contains)
            guard !foodKeys.isEmpty else { continue }
            let draft = food.draft
            for key in foodKeys where existing[key] == nil { existing[key] = draft }
        }
        let known = existing
        let plan = await Task.detached(priority: .userInitiated) { ImportBox(value: FoodCSV.plan(parsed, existing: known)) }.value.value
        let unit = app.energyUnit
        let lines = plan.entries.map { entry -> Line in
            let record = entry.record
            let per = "per 100 \(record.unit.symbol)"
            let energy = Fmt.energy(record.nutrients.energy, unit: unit)
            guard entry.action == .update, let old = known[entry.key] else {
                return Line(title: record.name, detail: "\(energy) \(per)", action: label(entry.action))
            }
            // What the update replaces: "was Greek yogurt 2% · 73 → 63 kcal per 100 g".
            var parts: [String] = []
            if old.name != record.name { parts.append("was \(old.name)") }
            let before = Fmt.energy(old.nutrients.energy, unit: unit)
            parts.append(before == energy ? "\(energy) \(per)" : "\(before) → \(energy) \(per)")
            return Line(title: record.name, detail: parts.joined(separator: " · "), action: label(entry.action))
        }
        var preview = ImportPreview(kind: .foods, lines: lines, skipped: plan.skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                                    foodPlan: plan)
        preview.foodNames = Set(plan.entries.filter { $0.action != .unchanged }.map { SearchText.normalize($0.record.name) })
        return preview
    }

    // MARK: Diary

    @MainActor
    private static func diaryPreview(_ text: String, app: AppModel, bundleFoods: Set<String>) async -> ImportPreview {
        let parsed = await Task.detached(priority: .userInitiated) { DiaryCSV.parse(text) }.value
        let wanted = Set(parsed.rows.map(\.key))
        var existing: [String: DiaryDraft] = [:]
        for entry in allEntries(app) {
            let entryKeys = DiaryCSV.storedKeys(uuid: entry.uuid, importKey: entry.importKey, draft: { entry.draft }).filter(wanted.contains)
            guard !entryKeys.isEmpty else { continue }
            let draft = entry.draft
            for key in entryKeys { existing[key] = draft }
        }
        let known = existing
        let meals = app.settings.meals
        let plan = await Task.detached(priority: .userInitiated) { ImportBox(value: DiaryCSV.plan(parsed, existing: known, meals: meals)) }.value.value
        let settings = app.settings
        let recent = app.today.adding(days: -14)
        let lines = plan.entries.map { entry -> Line in
            let draft = entry.record
            let meal = settings.meal(DiaryCSV.mealID(draft, in: meals)).name
            var warning = false
            let value: String
            if !draft.needsLookup {
                value = Fmt.energy(draft.nutrients.energy, unit: app.energyUnit)
            } else if let food = app.library.bestMatch(draft.name) {
                value = "looked up: \(food.displayName(app.language))"
            } else if bundleFoods.contains(SearchText.normalize(draft.name)) {
                value = "from this import"
            } else {
                value = "not found – skipped"
                warning = true
            }
            return Line(title: draft.name, detail: "\(draft.day.rawValue) · \(meal) · \(value)", action: label(entry.action), warning: warning)
        }
        var preview = ImportPreview(kind: .diary, lines: lines, skipped: plan.skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                                    diaryPlan: plan)
        preview.recentRows = plan.entries.filter { $0.action != .unchanged && $0.record.day >= recent && $0.record.status == .eaten }.count
        return preview
    }

    /// Every live diary entry (the diary formats reach from 2000 to a year ahead).
    @MainActor
    static func allEntries(_ app: AppModel) -> [LogEntry] {
        app.store.entries(from: DayKey(year: 2000, month: 1, day: 1), through: app.today.adding(days: 366))
    }

    // MARK: Meals & recipes

    @MainActor
    private static func recipesPreview(_ text: String, app: AppModel, bundleFoods: Set<String>) async -> ImportPreview {
        var existing: [String: RecipeDraft] = [:]
        for recipe in app.store.recipes() {
            let key = RecipeCSV.key(forName: recipe.displayName)
            if existing[key] == nil { existing[key] = recipe.draft }
        }
        let known = existing
        let plan = await Task.detached(priority: .userInitiated) { ImportBox(value: RecipeCSV.planImport(text, existing: known)) }.value.value
        var skipped = plan.skipped
        let lines = plan.entries.map { entry -> Line in
            let record = entry.record
            let count = record.items.count
            let detail = "\(record.kind.title) · \(count == 1 ? "1 food" : "\(count) foods")"
            var lookups: [String] = []
            var missing: [String] = []
            for item in record.items where item.needsLookup {
                if let food = app.library.bestMatch(item.name) {
                    lookups.append("\(item.name) → \(food.displayName(app.language))")
                } else if bundleFoods.contains(SearchText.normalize(item.name)) {
                    lookups.append("\(item.name) → from this import")
                } else {
                    lookups.append("\(item.name) → not found")
                    missing.append(item.name)
                }
            }
            if !missing.isEmpty, entry.action != .unchanged {
                skipped.append("\(record.name): \(missing.joined(separator: ", ")) not found – this \(record.kind.title.lowercased()) isn't saved")
            }
            return Line(title: record.name, detail: detail, action: label(entry.action), lookups: lookups.joined(separator: " · "),
                        warning: !missing.isEmpty)
        }
        return ImportPreview(kind: .recipes, lines: lines, skipped: skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                             recipePlan: plan)
    }

    // MARK: Importing

    /// Applies the plan, without the body values the person unticked; returns the toast text and
    /// what Undo puts back: for goals & settings `undo`, for foods, diary and meals & recipes `rows`.
    /// `writeToHealth`: new diary rows may be written to Apple Health (off: their source says to
    /// leave them out).
    @MainActor
    func apply(app: AppModel, excluding unticked: Set<String> = [], writeToHealth: Bool = true)
        -> (summary: String, undo: SettingsImportUndo?, rows: ImportRowsUndo) {
        if let settings {
            let result = settings.result.removingBodyValues(unticked)
            let undo = app.store.applySettings(result, previous: settings.previous, day: app.today)
            AppLog.info("Import settings: \(result.changes.count) changes, \(result.bodyRecords.count) body records", category: "import")
            let count = result.changes.count
            return (count == 1 ? "1 setting changed" : "\(count) settings changed", undo, ImportRowsUndo())
        }
        if let preview = historyPlan {
            var undo = ImportRowsUndo()
            let store = app.store
            // Planned again now: the settings part of the same answer was applied first, so the
            // weigh-in and body values it just saved count as existing (today's weight in block 1
            // and a row for today in block 4 are one weigh-in).
            let plan = historyText.map {
                store.bodyHistoryPlan($0, cutoffMinutes: app.settings.plan.routine.morningCutoffMinutes, today: app.today)
            } ?? preview
            // Imported weigh-ins are not written to Apple Health.
            let added = store.importBodyHistory(plan)
            undo.weights = added.weights
            undo.measurements = added.measurements
            AppLog.info("Import \(kind.rawValue): \(plan.records.count) new, \(plan.duplicates) already saved", category: "import")
            return (plan.importedText, nil, undo)
        }
        var count = ImportCount()
        var undo = ImportRowsUndo()
        if let plan = foodPlan { ImportApply.foods(plan, app: app, count: &count, undo: &undo) }
        if let plan = diaryPlan { ImportApply.diary(plan, app: app, writeToHealth: writeToHealth, count: &count, undo: &undo) }
        if let plan = recipePlan { ImportApply.recipes(plan, app: app, count: &count, undo: &undo) }
        AppLog.info("Import \(kind.rawValue): \(count.created) new, \(count.updated) updated, \(count.skipped) skipped", category: "import")
        return (count.text, nil, undo)
    }
}

/// What an import did, for its toast.
struct ImportCount {
    var created = 0
    var updated = 0
    /// Rows whose food wasn't found.
    var skipped = 0
    /// Meals and recipes left out because an ingredient wasn't found.
    var notSaved: [String] = []

    /// "Imported: 3 new, 1 updated, 2 not found".
    var text: String {
        var text = "Imported: \(created) new, \(updated) updated"
        if skipped > 0 { text += ", \(skipped) not found" }
        if !notSaved.isEmpty { text += " · not saved: \(notSaved.joined(separator: ", "))" }
        return text
    }
}

/// Writing foods, diary rows and meals & recipes. An update writes only what the file changed:
/// the merged record (`FoodCSV.merge`, `DiaryCSV.merge`, `RecipeCSV.mergeImported`) keeps every
/// value the file doesn't have or didn't change, and an entry keeps its portion, food link and
/// source unless the file changed them. One save at the end.
@MainActor
enum ImportApply {
    static func foods(_ plan: ImportPlan<FoodDraft>, app: AppModel, count: inout ImportCount, undo: inout ImportRowsUndo) {
        let store = app.store
        let wanted = Set(plan.entries.filter { $0.action == .update }.map(\.key))
        var byKey: [String: Food] = [:]
        for food in store.foods() {
            for key in ImportPreview.keys(food) where wanted.contains(key) && byKey[key] == nil { byKey[key] = food }
        }
        for entry in plan.entries where entry.action != .unchanged {
            if entry.action == .update, let food = byKey[entry.key] {
                undo.foodDrafts.append(ImportFoodState(food: food, draft: food.draft))
                food.apply(entry.record)
                food.touch()
                count.updated += 1
            } else {
                // New (also an update whose food is gone): the row's key finds it next time.
                let food = Food(name: entry.record.name)
                food.source = FoodSource.imported.rawValue
                store.context.insert(food)
                food.apply(entry.record)
                food.importKey = entry.key
                undo.foods.append(food)
                count.created += 1
            }
        }
        store.save()
    }

    static func diary(_ plan: ImportPlan<DiaryDraft>, app: AppModel, writeToHealth: Bool, count: inout ImportCount,
                      undo: inout ImportRowsUndo) {
        let store = app.store
        let wanted = Set(plan.entries.filter { $0.action == .update }.map(\.key))
        var byKey: [String: LogEntry] = [:]
        for entry in ImportPreview.allEntries(app) {
            for key in DiaryCSV.storedKeys(uuid: entry.uuid, importKey: entry.importKey, draft: { entry.draft }) where wanted.contains(key) {
                byKey[key] = entry
            }
        }
        let settings = app.settings
        for row in plan.entries where row.action != .unchanged {
            let draft = row.record
            if row.action == .update, let entry = byKey[row.key] {
                let state = ImportEntryState(entry)
                guard update(entry, to: draft, app: app, settings: settings) else {
                    count.skipped += 1
                    continue
                }
                undo.entryStates.append(state)
                count.updated += 1
                continue
            }
            let mealID = DiaryCSV.mealID(draft, in: settings.meals)
            var values = draft.nutrients
            var lookedUp: (amount: Double, unit: BaseUnit)?
            var food: FoodRecord?
            if draft.needsLookup {
                guard let found = app.library.bestMatch(draft.name) else {
                    count.skipped += 1
                    continue
                }
                let amount = lookupAmount(draft, food: found)
                values = found.nutrients(forAmount: amount)
                lookedUp = (amount, found.unit)
                food = found
            }
            let time = draft.minutes.map { draft.day.date(minutes: $0) } ?? draft.day.date(minutes: settings.meal(mealID).minutes)
            let entry = LogEntry(day: draft.day, time: time, meal: mealID, name: draft.name)
            store.context.insert(entry)
            undo.entries.append(entry)
            entry.brand = draft.brand
            if let food {
                entry.foodRef = food.ref.rawValue
                entry.category = food.category.rawValue
            }
            write(draft.storedAmount(lookedUp: lookedUp), to: entry)
            entry.nutrients = values.encoded
            entry.note = draft.note
            entry.status = draft.status.rawValue
            // Rows from another app are usually in Apple Health already: the person decides.
            entry.source = writeToHealth ? "import" : "import-skiphealth"
            entry.importKey = row.key
            entry.touch()
            count.created += 1
        }
        store.save()
    }

    /// Writes what the merged row changed; false when its food had to be looked up and wasn't found.
    private static func update(_ entry: LogEntry, to draft: DiaryDraft, app: AppModel, settings: NinaSettings) -> Bool {
        let stored = entry.draft
        var values = draft.nutrients
        var lookedUp: (amount: Double, unit: BaseUnit)?
        if draft.needsLookup {
            guard let food = app.library.bestMatch(draft.name) else { return false }
            let amount = lookupAmount(draft, food: food)
            values = food.nutrients(forAmount: amount)
            lookedUp = (amount, food.unit)
            entry.foodRef = food.ref.rawValue
            entry.category = food.category.rawValue
        }
        let mealID = draft.meal == stored.meal ? entry.meal : DiaryCSV.mealID(draft, in: settings.meals)
        if draft.day != stored.day || draft.minutes != stored.minutes {
            entry.day = draft.day.rawValue
            entry.time = draft.minutes.map { draft.day.date(minutes: $0) } ?? draft.day.date(minutes: settings.meal(mealID).minutes)
        }
        if mealID != entry.meal { entry.meal = mealID }
        if draft.name != stored.name { entry.name = draft.name }
        if draft.brand != stored.brand { entry.brand = draft.brand }
        if lookedUp != nil || !draft.sameAmount(as: stored) { write(draft.storedAmount(lookedUp: lookedUp), to: entry) }
        if values != stored.nutrients { entry.nutrients = values.encoded }
        if draft.note != stored.note { entry.note = draft.note }
        if draft.status != stored.status { entry.status = draft.status.rawValue }
        entry.touch()
        return true
    }

    /// The base amount of a row the food was looked up for: its grams, else its count and unit.
    private static func lookupAmount(_ draft: DiaryDraft, food: FoodRecord) -> Double {
        if draft.amount > 0 { return draft.amount }
        let item = QuickItem(original: draft.name, quantity: draft.quantity,
                             unit: QuickParser.unit(for: SearchText.normalize(draft.unitLabel)), query: draft.name)
        return QuickParser.amount(for: item, food: food).amount
    }

    private static func write(_ amount: AmountText, to entry: LogEntry) {
        entry.quantity = amount.quantity
        entry.unitLabel = amount.unitLabel
        entry.unitAmount = amount.unitAmount
        entry.baseUnit = amount.baseUnit.rawValue
    }

    static func recipes(_ plan: ImportPlan<RecipeDraft>, app: AppModel, count: inout ImportCount, undo: inout ImportRowsUndo) {
        let store = app.store
        var byName: [String: Recipe] = [:]
        for recipe in store.recipes() {
            let key = RecipeCSV.key(forName: recipe.displayName)
            if byName[key] == nil { byName[key] = recipe }
        }
        for row in plan.entries where row.action != .unchanged {
            let draft = row.record
            let existing = row.action == .update ? byName[row.key] : nil
            guard let lines = lines(for: draft, existing: existing, app: app, count: &count) else { continue }
            guard !lines.isEmpty else { continue }
            if let existing { undo.recipeStates.append(ImportRecipeState(existing)) }
            // An update keeps the recipe's emoji and usual meal (the file has neither).
            let recipe = store.saveRecipe(existing, name: draft.name, kind: draft.kind, emoji: existing?.emoji ?? "",
                                          servings: draft.servings, totalWeight: draft.totalWeight, notes: draft.notes,
                                          defaultMeal: existing?.defaultMeal ?? "", lines: lines)
            if existing == nil { undo.recipes.append(recipe) }
            if existing == nil { count.created += 1 } else { count.updated += 1 }
        }
    }

    /// The recipe's lines: unchanged ingredients stay the stored ones (food link, category,
    /// portion), others are looked up or taken as written. nil when an ingredient wasn't found –
    /// the recipe isn't saved lighter than it is.
    private static func lines(for draft: RecipeDraft, existing: Recipe?, app: AppModel, count: inout ImportCount) -> [RecipeLine]? {
        let storedItems = existing?.sortedItems ?? []
        let kept: [Int?] = existing.map { RecipeCSV.keptIngredientIndices(of: draft, in: $0.draft) }
            ?? Array(repeating: nil, count: draft.items.count)
        var lines: [RecipeLine] = []
        var missing: [String] = []
        for (index, item) in draft.items.enumerated() {
            if index < kept.count, let stored = kept[index], stored < storedItems.count {
                lines.append(RecipeLine(item: storedItems[stored]))
            } else if !item.needsLookup {
                // Values from the file; an ingredient of the same name keeps its food link.
                let name = SearchText.normalize(item.name)
                let same = storedItems.first { SearchText.normalize($0.name) == name }
                let amount = liquidChecked(item, same: same, app: app).storedAmount()
                lines.append(RecipeLine(name: item.name, brand: same?.brand ?? "", ref: same?.ref ?? .none,
                                        category: same?.foodCategory ?? .other, amount: amount, nutrients: item.nutrients))
            } else if let food = app.library.bestMatch(item.name) {
                let quick = QuickParser.amount(for: QuickItem(original: item.name, quantity: item.amount > 0 ? item.amount : item.quantity,
                                                              unit: item.amount > 0 ? .mass(1) : QuickParser.unit(for: SearchText.normalize(item.unitLabel)),
                                                              query: item.name), food: food)
                lines.append(RecipeLine(record: food, amount: item.storedAmount(lookedUp: (quick.amount, food.unit)), language: app.language))
            } else {
                missing.append(item.name)
            }
        }
        guard missing.isEmpty else {
            count.skipped += missing.count
            count.notSaved.append(draft.name)
            return nil
        }
        return lines
    }

    /// The meals & recipes CSV has no base column, so a drink written with a portion word ("1
    /// glass", 250 in grams) or a liquid unit the reader takes for a portion (cl, dl) would be
    /// stored in grams. A liquid unit (cl and dl without grams are converted), the stored
    /// ingredient of the same name, or a drink of exactly that name in the food library makes it
    /// ml again. Anything else stays as the file says.
    static func liquidChecked(_ item: RecipeItemDraft, same: RecipeItem?, app: AppModel) -> RecipeItemDraft {
        guard item.unit == .gram else { return item }
        var checked = item
        let label = SearchText.normalize(item.unitLabel)
        if let perUnit = liquidUnits[label] {
            if checked.amount <= 0 { checked.amount = item.quantity * perUnit }
            checked.unit = .milliliter
            return checked
        }
        guard item.amount > 0, !gramWords.contains(label) else { return item }
        if let same {
            if same.amount.baseUnit == .milliliter { checked.unit = .milliliter }
        } else if let food = app.library.bestMatch(item.name), food.unit == .milliliter {
            let name = SearchText.normalize(item.name)
            if [food.name, food.nameDE].contains(where: { !$0.isEmpty && SearchText.normalize($0) == name }) { checked.unit = .milliliter }
        }
        return checked
    }

    /// ml per unit of the liquid units a meals & recipes file may use.
    private static let liquidUnits: [String: Double] = [
        "ml": 1, "milliliter": 1, "millilitre": 1, "milliliters": 1, "millilitres": 1,
        "cl": 10, "dl": 100, "l": 1000, "liter": 1000, "litre": 1000, "liters": 1000, "litres": 1000,
    ]

    /// Units that mean grams or servings: never a drink's portion.
    private static let gramWords: Set<String> = ["", "g", "gram", "grams", "gramm", "kg", "serving", "servings", "portion", "portions"]
}

/// What Undo puts back after a foods, diary, meals & recipes or weight & body import: the new
/// records go to the trash (kept 30 days, like any delete), the changed ones get their previous values.
struct ImportRowsUndo {
    var foods: [Food] = []
    var foodDrafts: [ImportFoodState] = []
    var entries: [LogEntry] = []
    var entryStates: [ImportEntryState] = []
    var recipes: [Recipe] = []
    var recipeStates: [ImportRecipeState] = []
    var weights: [WeightEntry] = []
    var measurements: [BodyMeasurement] = []

    var isEmpty: Bool {
        foods.isEmpty && foodDrafts.isEmpty && entries.isEmpty && entryStates.isEmpty && recipes.isEmpty && recipeStates.isEmpty
            && weights.isEmpty && measurements.isEmpty
    }

    mutating func merge(_ other: ImportRowsUndo) {
        foods += other.foods
        foodDrafts += other.foodDrafts
        entries += other.entries
        entryStates += other.entryStates
        recipes += other.recipes
        recipeStates += other.recipeStates
        weights += other.weights
        measurements += other.measurements
    }

    /// Puts everything back, last imported first: weigh-ins and measurements, recipes, then diary
    /// entries, then foods.
    @MainActor
    func undo(store: NinaStore) {
        guard !isEmpty else { return }
        if !measurements.isEmpty { store.trash(measurements) }
        if !weights.isEmpty { store.trash(weights) }
        for state in recipeStates.reversed() { state.restore(store: store) }
        for state in entryStates.reversed() { state.restore() }
        for state in foodDrafts.reversed() { state.restore() }
        if !recipes.isEmpty { store.trash(recipes) }
        if !entries.isEmpty { store.trash(entries) }
        if !foods.isEmpty { store.trash(foods) }
        store.save()
    }
}

/// An own food's values before an import changed it.
struct ImportFoodState {
    let food: Food
    let draft: FoodDraft

    func restore() {
        food.apply(draft)
        food.touch()
    }
}

/// A diary entry's values before an import changed it.
struct ImportEntryState {
    let entry: LogEntry
    let day: String
    let time: Date
    let meal: String
    let name: String
    let brand: String
    let foodRef: String
    let category: String
    let quantity: Double
    let unitLabel: String
    let unitAmount: Double
    let baseUnit: String
    let nutrients: String
    let note: String
    let status: String
    let source: String
    let importKey: String

    init(_ entry: LogEntry) {
        self.entry = entry
        day = entry.day
        time = entry.time
        meal = entry.meal
        name = entry.name
        brand = entry.brand
        foodRef = entry.foodRef
        category = entry.category
        quantity = entry.quantity
        unitLabel = entry.unitLabel
        unitAmount = entry.unitAmount
        baseUnit = entry.baseUnit
        nutrients = entry.nutrients
        note = entry.note
        status = entry.status
        source = entry.source
        importKey = entry.importKey
    }

    func restore() {
        entry.day = day
        entry.time = time
        entry.meal = meal
        entry.name = name
        entry.brand = brand
        entry.foodRef = foodRef
        entry.category = category
        entry.quantity = quantity
        entry.unitLabel = unitLabel
        entry.unitAmount = unitAmount
        entry.baseUnit = baseUnit
        entry.nutrients = nutrients
        entry.note = note
        entry.status = status
        entry.source = source
        entry.importKey = importKey
        entry.touch()
    }
}

/// A recipe's values and foods before an import changed it.
struct ImportRecipeState {
    let recipe: Recipe
    let name: String
    let kind: RecipeKind
    let emoji: String
    let servings: Double
    let totalWeight: Double
    let notes: String
    let defaultMeal: String
    let lines: [RecipeLine]

    init(_ recipe: Recipe) {
        self.recipe = recipe
        name = recipe.name
        kind = recipe.recipeKind
        emoji = recipe.emoji
        servings = recipe.servings
        totalWeight = recipe.totalWeight
        notes = recipe.notes
        defaultMeal = recipe.defaultMeal
        lines = recipe.sortedItems.map { RecipeLine(item: $0) }
    }

    @MainActor
    func restore(store: NinaStore) {
        store.saveRecipe(recipe, name: name, kind: kind, emoji: emoji, servings: servings, totalWeight: totalWeight,
                         notes: notes, defaultMeal: defaultMeal, lines: lines)
    }
}

/// A plain value handed back from work off the main thread (`ImportPlan` isn't marked Sendable;
/// the plans are values that nothing else touches).
struct ImportBox<Value>: @unchecked Sendable {
    let value: Value
}
