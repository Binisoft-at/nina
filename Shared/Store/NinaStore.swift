import Foundation
import SwiftData
import BinisoftKit
import NinaCore

extension Notification.Name {
    /// Posted after every save through NinaStore (food library, Health sync and widgets refresh).
    static let ninaDataChanged = Notification.Name("at.binisoft.nina.dataChanged")
}

/// One food line of a meal or recipe being built (search result + amount + totals).
struct RecipeLine: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var brand: String = ""
    var ref: FoodRef
    var category: FoodCategory
    var amount: AmountText
    var nutrients: NutrientValues

    init(name: String, brand: String = "", ref: FoodRef, category: FoodCategory, amount: AmountText, nutrients: NutrientValues) {
        self.name = name
        self.brand = brand
        self.ref = ref
        self.category = category
        self.amount = amount
        self.nutrients = nutrients
    }

    init(record: FoodRecord, amount: AmountText, language: FoodLanguage) {
        self.init(name: record.displayName(language), brand: record.brand, ref: record.ref, category: record.category,
                  amount: amount, nutrients: record.nutrients(forAmount: amount.total))
    }

    init(item: RecipeItem) {
        self.init(name: item.name, brand: item.brand, ref: item.ref, category: item.foodCategory, amount: item.amount, nutrients: item.values)
    }

    init(entry: LogEntry) {
        self.init(name: entry.displayName, brand: entry.brand, ref: entry.ref, category: entry.foodCategory,
                  amount: entry.amount, nutrients: entry.values)
    }
}

/// Every change to Nina's data goes through here – timestamps, ordering, soft delete, plans,
/// save, widget snapshot – so the rules live in one place. Views never write to the model directly.
@MainActor
struct NinaStore {
    let context: ModelContext
    var trashPolicy = TrashPolicy(keepDays: 30)
    var calendar: Calendar = .current

    // MARK: Profile

    /// The oldest profile wins: a fresh device's default never overrides the synced one.
    func profile() -> NinaProfile? {
        let all = (try? context.fetch(FetchDescriptor<NinaProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let first = all.first else { return nil }
        if all.count > 1 {
            for duplicate in all.dropFirst() { context.delete(duplicate) }
            AppLog.notice("Removed \(all.count - 1) duplicate profile(s)", category: "store")
            try? context.save()
        }
        return first
    }

    var settings: NinaSettings { NinaSettings(profile()) }

    /// Changes the profile, creating it on first use.
    func updateProfile(_ change: (NinaProfile) -> Void) {
        let profile = profile() ?? {
            let created = NinaProfile()
            context.insert(created)
            return created
        }()
        change(profile)
        profile.modifiedAt = Date()
        save()
    }

    // MARK: Reading

    func entries(on day: DayKey) -> [LogEntry] {
        let key = day.rawValue
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.time), SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func entries(from start: DayKey, through end: DayKey) -> [LogEntry] {
        let first = start.rawValue, last = end.rawValue
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func water(on day: DayKey) -> [WaterLog] {
        let key = day.rawValue
        let descriptor = FetchDescriptor<WaterLog>(
            predicate: #Predicate<WaterLog> { $0.day == key && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func water(from start: DayKey, through end: DayKey) -> [WaterLog] {
        let first = start.rawValue, last = end.rawValue
        let descriptor = FetchDescriptor<WaterLog>(
            predicate: #Predicate<WaterLog> { $0.day >= first && $0.day <= last && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func weights() -> [WeightEntry] {
        let descriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate<WeightEntry> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func foods() -> [Food] {
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func food(_ id: UUID) -> Food? {
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    /// The person's version of a catalog food, if they personalised it.
    func overlay(catalogID: String) -> Food? {
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.catalogID == catalogID && $0.deletedAt == nil })
        return try? context.fetch(descriptor).first
    }

    func recipes() -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.deletedAt == nil },
                                                 sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func recipe(_ id: UUID) -> Recipe? {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    func planRules() -> [PlanRule] {
        let descriptor = FetchDescriptor<PlanRule>(predicate: #Predicate<PlanRule> { $0.deletedAt == nil },
                                                   sortBy: [SortDescriptor(\.minutes)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Logging

    /// Logs an amount of a food. Nutrients are copied, so editing the food later never changes the past.
    @discardableResult
    func log(_ record: FoodRecord, amount: AmountText, day: DayKey, meal: String, time: Date? = nil,
             status: EntryStatus = .eaten, source: String, language: FoodLanguage, groupID: String = "",
             planKey: String = "", saveNow: Bool = true) -> LogEntry {
        let entry = LogEntry(day: day, time: time ?? defaultTime(on: day, meal: meal), meal: meal, name: record.displayName(language))
        entry.brand = record.brand
        entry.foodRef = record.ref.rawValue
        entry.category = record.category.rawValue
        entry.quantity = amount.quantity
        entry.unitLabel = amount.unitLabel
        entry.unitAmount = amount.unitAmount
        entry.baseUnit = amount.baseUnit.rawValue
        entry.nutrients = record.nutrients(forAmount: amount.total).encoded
        entry.status = status.rawValue
        entry.source = source
        entry.groupID = groupID
        entry.planKey = planKey
        entry.sortOrder = Date().timeIntervalSinceReferenceDate
        context.insert(entry)
        if saveNow { save() }
        return entry
    }

    /// "350 kcal" without a food.
    @discardableResult
    func logQuick(name: String, nutrients: NutrientValues, day: DayKey, meal: String, time: Date? = nil, source: String = "quick") -> LogEntry {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = LogEntry(day: day, time: time ?? defaultTime(on: day, meal: meal), meal: meal, name: trimmed.isEmpty ? "Quick entry" : trimmed)
        entry.quantity = 1
        entry.unitLabel = BaseUnit.serving.symbol
        entry.unitAmount = 0
        entry.baseUnit = BaseUnit.serving.rawValue
        entry.nutrients = nutrients.encoded
        entry.source = source
        entry.sortOrder = Date().timeIntervalSinceReferenceDate
        context.insert(entry)
        save()
        return entry
    }

    /// A saved meal: one entry per food, sharing a group id. A recipe: one entry of `amount`.
    @discardableResult
    func logRecipe(_ recipe: Recipe, amount: AmountText? = nil, day: DayKey, meal: String, time: Date? = nil,
                   status: EntryStatus = .eaten, planKey: String = "", source: String, language: FoodLanguage) -> [LogEntry] {
        recipe.lastUsedAt = Date()
        if recipe.recipeKind == .recipe {
            let record = recipe.record
            let portion = amount ?? AmountText(quantity: 1, unitLabel: record.servings.first?.label(language) ?? BaseUnit.serving.symbol,
                                               unitAmount: record.servings.first?.amount ?? 1, baseUnit: record.unit)
            return [log(record, amount: portion, day: day, meal: meal, time: time, status: status, source: source,
                        language: language, planKey: planKey)]
        }
        let group = UUID().uuidString
        let when = time ?? defaultTime(on: day, meal: meal)
        var created: [LogEntry] = []
        for (index, item) in recipe.sortedItems.enumerated() {
            let entry = LogEntry(day: day, time: when, meal: meal, name: item.name)
            entry.brand = item.brand
            entry.foodRef = item.foodRef
            entry.category = item.category
            entry.quantity = item.quantity
            entry.unitLabel = item.unitLabel
            entry.unitAmount = item.unitAmount
            entry.baseUnit = item.baseUnit
            entry.nutrients = item.nutrients
            entry.status = status.rawValue
            entry.source = source
            entry.groupID = group
            entry.planKey = planKey
            entry.sortOrder = Date().timeIntervalSinceReferenceDate + Double(index) / 100
            context.insert(entry)
            created.append(entry)
        }
        save()
        return created
    }

    /// A meal's usual time on that day; now when logging for today at a time past it.
    func defaultTime(on day: DayKey, meal: String, now: Date = Date()) -> Date {
        let settings = self.settings
        if day == settings.today(now: now, calendar: calendar) { return now }
        return day.date(minutes: settings.meal(meal).minutes, calendar: calendar)
    }

    // MARK: Editing entries

    /// New amount: nutrients scale with it (quick entries keep their values).
    func update(_ entry: LogEntry, amount: AmountText) {
        let old = entry.totalAmount
        let new = amount.total
        if old > 0, new > 0 {
            entry.nutrients = entry.values.scaled(by: new / old).encoded
        }
        entry.quantity = amount.quantity
        entry.unitLabel = amount.unitLabel
        entry.unitAmount = amount.unitAmount
        entry.baseUnit = amount.baseUnit.rawValue
        entry.touch()
        save()
    }

    func update(_ entry: LogEntry, name: String, meal: String, day: DayKey, time: Date, note: String, status: EntryStatus) {
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.meal = meal
        entry.day = day.rawValue
        entry.time = time
        entry.note = note
        entry.status = status.rawValue
        entry.touch()
        save()
    }

    func setNutrients(_ entry: LogEntry, _ values: NutrientValues) {
        entry.nutrients = values.encoded
        entry.touch()
        save()
    }

    func setTags(_ entries: [LogEntry], _ tags: [String]) {
        let now = Date()
        for entry in entries {
            entry.tags = TagText.join(tags)
            entry.touch(now: now)
        }
        save()
    }

    func move(_ entries: [LogEntry], to meal: String) {
        let now = Date()
        for entry in entries where entry.meal != meal {
            entry.meal = meal
            entry.touch(now: now)
        }
        save()
    }

    /// Copies entries to another day (as eaten or planned), keeping their meals unless one is given.
    @discardableResult
    func copy(_ entries: [LogEntry], to day: DayKey, meal: String? = nil, status: EntryStatus = .eaten) -> [LogEntry] {
        var created: [LogEntry] = []
        let group = UUID().uuidString
        for (index, source) in entries.enumerated() {
            let target = meal ?? source.meal
            let entry = LogEntry(day: day, time: defaultTime(on: day, meal: target), meal: target, name: source.name)
            entry.brand = source.brand
            entry.foodRef = source.foodRef
            entry.category = source.category
            entry.quantity = source.quantity
            entry.unitLabel = source.unitLabel
            entry.unitAmount = source.unitAmount
            entry.baseUnit = source.baseUnit
            entry.nutrients = source.nutrients
            entry.note = source.note
            entry.tags = source.tags
            entry.status = status.rawValue
            entry.source = "copy"
            entry.groupID = entries.count > 1 ? group : ""
            entry.sortOrder = Date().timeIntervalSinceReferenceDate + Double(index) / 100
            context.insert(entry)
            created.append(entry)
        }
        save()
        return created
    }

    /// Planned → eaten. On today, the time becomes now (if it's later than planned).
    func confirm(_ entries: [LogEntry], now: Date = Date()) {
        let today = settings.today(now: now, calendar: calendar)
        for entry in entries where !entry.isEaten {
            entry.status = EntryStatus.eaten.rawValue
            if entry.dayKey == today, entry.time > now { entry.time = now }
            entry.touch(now: now)
        }
        save()
    }

    func setStatus(_ entries: [LogEntry], _ status: EntryStatus) {
        let now = Date()
        for entry in entries where entry.status != status.rawValue {
            entry.status = status.rawValue
            entry.touch(now: now)
        }
        save()
    }

    // MARK: Trash

    @discardableResult
    func trash<T: PersistentModel & SoftDeletable>(_ records: [T]) -> [T] {
        let now = Date()
        for record in records { record.moveToTrash(now: now) }
        save()
        return records
    }

    func restore<T: PersistentModel & SoftDeletable>(_ records: [T]) {
        let now = Date()
        for record in records { record.restoreFromTrash(now: now) }
        save()
    }

    /// Deletes for good (Recently Deleted → Delete Now).
    func purge<T: PersistentModel>(_ records: [T]) {
        for record in records { context.delete(record) }
        save()
    }

    func trashedEntries() -> [LogEntry] {
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.deletedAt != nil },
                                                   sortBy: [SortDescriptor(\.deletedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func trashedFoods() -> [Food] {
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.deletedAt != nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    func trashedRecipes() -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.deletedAt != nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Empties what has been in the trash longer than the policy allows. Run at launch.
    func purgeExpired(now: Date = Date()) {
        var count = 0
        func sweep<T: PersistentModel & SoftDeletable>(_ type: T.Type) {
            let descriptor = FetchDescriptor<T>()
            for record in (try? context.fetch(descriptor)) ?? [] where trashPolicy.isExpired(deletedAt: record.deletedAt, now: now) {
                context.delete(record)
                count += 1
            }
        }
        sweep(LogEntry.self)
        sweep(Food.self)
        sweep(Recipe.self)
        sweep(WaterLog.self)
        sweep(WeightEntry.self)
        sweep(PlanRule.self)
        guard count > 0 else { return }
        AppLog.info("Emptied \(count) record(s) from the trash", category: "store")
        save()
    }

    // MARK: Water and weight

    @discardableResult
    func addWater(_ milliliters: Double, day: DayKey, time: Date = Date()) -> WaterLog {
        let log = WaterLog(day: day, time: time, amount: milliliters)
        context.insert(log)
        save()
        return log
    }

    @discardableResult
    func addWeight(_ kilograms: Double, day: DayKey, time: Date = Date(), bodyFat: Double = 0, note: String = "") -> WeightEntry {
        let entry = WeightEntry(day: day, time: time, kilograms: kilograms)
        entry.bodyFat = bodyFat
        entry.note = note
        context.insert(entry)
        save()
        return entry
    }

    func update(_ weight: WeightEntry, kilograms: Double, day: DayKey, bodyFat: Double, note: String) {
        weight.kilograms = kilograms
        weight.day = day.rawValue
        weight.bodyFat = bodyFat
        weight.note = note
        weight.touch()
        save()
    }

    // MARK: Foods

    /// Creates or updates an own food. `catalogID` makes it the personal version of a catalog food.
    @discardableResult
    func saveFood(_ draft: FoodDraft, editing food: Food? = nil, catalogID: String = "", source: FoodSource = .custom,
                  density: Double? = nil) -> Food {
        let target = food ?? {
            let created = Food(name: draft.name)
            created.catalogID = catalogID
            created.source = source.rawValue
            context.insert(created)
            return created
        }()
        target.apply(draft)
        if let density { target.density = density }
        target.touch()
        save()
        return target
    }

    /// The own record behind a food: the food itself, or a new personal copy of a catalog food.
    func personalize(_ record: FoodRecord) -> Food {
        if let id = record.recordID, let food = food(id) { return food }
        if record.ref.kind == .catalog, let overlay = overlay(catalogID: record.ref.rawValue) { return overlay }
        let food = Food(name: record.name)
        food.catalogID = record.ref.kind == .catalog ? record.ref.rawValue : ""
        food.nameDE = record.nameDE
        food.brand = record.brand
        food.category = record.category.rawValue
        food.unit = record.unit.rawValue
        food.density = record.density
        food.nutrients = record.nutrients.encoded
        food.servings = Serving.encode(record.servings)
        food.aliases = TagText.join(record.aliases)
        food.source = FoodSource.catalog.rawValue
        context.insert(food)
        return food
    }

    func setFavorite(_ record: FoodRecord, _ isFavorite: Bool) {
        if record.ref.kind == .recipe, let id = record.recordID, let recipe = recipe(id) {
            recipe.isFavorite = isFavorite
            recipe.touch()
        } else {
            let food = personalize(record)
            food.isFavorite = isFavorite
            food.touch()
        }
        save()
    }

    func setTags(_ record: FoodRecord, _ tags: [String]) {
        if record.ref.kind == .recipe, let id = record.recordID, let recipe = recipe(id) {
            recipe.tags = TagText.join(tags)
            recipe.touch()
        } else {
            let food = personalize(record)
            food.tags = TagText.join(tags)
            food.touch()
        }
        save()
    }

    func setHidden(_ record: FoodRecord, _ hidden: Bool) {
        let food = personalize(record)
        food.isHidden = hidden
        food.touch()
        save()
    }

    /// Remembers the amount someone usually eats of a food.
    func rememberAmount(_ amount: Double, for record: FoodRecord) {
        guard amount > 0, record.ref.kind != .recipe, let id = record.recordID, let food = food(id) else { return }
        food.usualAmount = amount
    }

    // MARK: Meals and recipes

    @discardableResult
    func saveRecipe(_ recipe: Recipe?, name: String, kind: RecipeKind, emoji: String, servings: Double, totalWeight: Double,
                    notes: String, defaultMeal: String = "", lines: [RecipeLine]) -> Recipe {
        let target = recipe ?? {
            let created = Recipe(name: name, kind: kind)
            created.sortOrder = ListOrder.after(recipes().map(\.sortOrder))
            context.insert(created)
            return created
        }()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind.rawValue
        target.emoji = emoji
        target.servings = max(servings, 1)
        target.totalWeight = max(totalWeight, 0)
        target.notes = notes
        target.defaultMeal = defaultMeal
        for item in target.items ?? [] { context.delete(item) }
        target.items = []
        for (index, line) in lines.enumerated() {
            let item = RecipeItem(name: line.name)
            item.brand = line.brand
            item.foodRef = line.ref.rawValue
            item.category = line.category.rawValue
            item.quantity = line.amount.quantity
            item.unitLabel = line.amount.unitLabel
            item.unitAmount = line.amount.unitAmount
            item.baseUnit = line.amount.baseUnit.rawValue
            item.nutrients = line.nutrients.encoded
            item.sortOrder = Double(index)
            item.recipe = target
            context.insert(item)
        }
        target.touch()
        save()
        return target
    }

    /// "Save as meal" from diary entries.
    @discardableResult
    func saveAsMeal(_ entries: [LogEntry], name: String, defaultMeal: String) -> Recipe {
        saveRecipe(nil, name: name, kind: .meal, emoji: "", servings: 1, totalWeight: 0, notes: "", defaultMeal: defaultMeal,
                   lines: entries.map(RecipeLine.init(entry:)))
    }

    // MARK: Plans

    @discardableResult
    func savePlanRule(_ rule: PlanRule?, recipe: Recipe, meal: String, minutes: Int, weekdays: Weekdays, notify: Bool,
                      startDay: DayKey?) -> PlanRule {
        let target = rule ?? {
            let created = PlanRule(recipeID: recipe.uuid, title: recipe.displayName, meal: meal, minutes: minutes, weekdays: weekdays)
            context.insert(created)
            return created
        }()
        target.recipeID = recipe.uuid.uuidString
        target.title = recipe.displayName
        target.meal = meal
        target.minutes = minutes
        target.weekdays = weekdays.encoded
        target.notify = notify
        target.startDay = startDay?.rawValue ?? ""
        target.touch()
        save()
        return target
    }

    func setActive(_ rule: PlanRule, _ active: Bool) {
        rule.isActive = active
        rule.touch()
        save()
    }

    /// Creates the planned entries of every active rule for today and the next days – once per
    /// rule and day, even if the person deleted them (then they stay deleted).
    func materializePlans(today: DayKey, horizon: Int = 3) {
        let rules = planRules().filter(\.isActive)
        guard !rules.isEmpty else { return }
        let settings = self.settings
        let end = today.adding(days: horizon - 1, calendar: calendar)
        let existing = Set(entriesIncludingTrash(from: today, through: end).map(\.planKey).filter { !$0.isEmpty })
        var created = 0
        for rule in rules {
            guard let recipeID = rule.recipeUUID, let recipe = recipe(recipeID), recipe.deletedAt == nil else { continue }
            for day in PlanSchedule.days(for: rule.days, from: today, horizon: horizon, startDay: rule.start, endDay: rule.end, calendar: calendar) {
                let key = PlanSchedule.key(rule: rule.uuid, day: day)
                guard !existing.contains(key) else { continue }
                logRecipe(recipe, day: day, meal: rule.meal, time: day.date(minutes: rule.minutes, calendar: calendar),
                          status: .planned, planKey: key, source: "plan", language: settings.language)
                created += 1
            }
        }
        if created > 0 { AppLog.info("Planned \(created) meal(s) from routines", category: "plan") }
        removeDuplicatePlans(from: today, through: end)
    }

    /// Two devices that planned the same rule-day before syncing: keep the group created first.
    func removeDuplicatePlans(from start: DayKey, through end: DayKey) {
        let planned = entries(from: start, through: end).filter { !$0.planKey.isEmpty }
        var groups: [String: (key: String, createdAt: Date, entries: [LogEntry])] = [:]
        for entry in planned {
            let groupKey = entry.planKey + "#" + entry.groupID
            var group = groups[groupKey] ?? (entry.planKey, entry.createdAt, [])
            group.createdAt = min(group.createdAt, entry.createdAt)
            group.entries.append(entry)
            groups[groupKey] = group
        }
        let duplicates = PlanSchedule.duplicates(groups.values.map { ($0.key, $0.createdAt, $0.entries) })
        let toRemove = duplicates.flatMap { $0 }
        guard !toRemove.isEmpty else { return }
        for entry in toRemove { context.delete(entry) }
        AppLog.notice("Removed \(toRemove.count) duplicate planned entries", category: "plan")
        save()
    }

    private func entriesIncludingTrash(from start: DayKey, through end: DayKey) -> [LogEntry] {
        let first = start.rawValue, last = end.rawValue
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.day >= first && $0.day <= last })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Saving

    /// Today's numbers for widgets and complications.
    func todaySnapshot(activityBonus: Double = WidgetBridge.activityBonus, now: Date = Date()) -> TodaySnapshot {
        let settings = self.settings
        let today = settings.today(now: now, calendar: calendar)
        let entries = self.entries(on: today)
        let water = self.water(on: today).map(\.amount).reduce(0, +)
        let totals = DayTotals(day: today, entries: entries.map(\.facts), water: water)
        let progress = DayProgress(totals: totals, targets: settings.targets(for: today, calendar: calendar),
                                   activityBonus: activityBonus * settings.activityBonusShare)
        let next = entries.filter { $0.isPlanned && $0.time >= now }.min { $0.time < $1.time }
        let nextText = next.map { "\(settings.meal($0.meal).name) · \(Fmt.time($0.time))" }
        return TodaySnapshot(progress: progress, nextPlanned: nextText, energyUnit: settings.energyUnit, now: now)
    }

    /// Saves, refreshes the widget snapshot (not for the tour's or the demo's in-memory stores)
    /// and tells the app that data changed.
    func save() {
        do {
            try context.save()
        } catch {
            AppLog.error("Save failed: \(error.localizedDescription)", category: "store")
        }
        if !isInMemory {
            WidgetBridge.publish(todaySnapshot())
        }
        NotificationCenter.default.post(name: .ninaDataChanged, object: nil)
    }

    var isInMemory: Bool {
        context.container.configurations.contains { $0.isStoredInMemoryOnly }
    }
}
