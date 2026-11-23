import Foundation
import SwiftData
import BinisoftKit
import NinaCore

extension Notification.Name {
    /// Posted after every save through NinaStore (food library, Health sync and widgets refresh).
    static let ninaDataChanged = Notification.Name("at.binisoft.nina.dataChanged")
    /// Posted instead of `ninaDataChanged` when a save through NinaStore failed (the app says so).
    static let ninaSaveFailed = Notification.Name("at.binisoft.nina.saveFailed")
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

    /// The oldest profile wins: a fresh device's default never overrides the synced one. A coach
    /// plan only a newer copy has (set up on a device before its first sync) is carried over first,
    /// with the goals it mirrors, so it isn't lost on every device.
    func profile() -> NinaProfile? {
        let all = (try? context.fetch(FetchDescriptor<NinaProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let first = all.first else { return nil }
        if all.count > 1 {
            let duplicates = all.dropFirst()
            if first.coachPlan.isEmpty,
               let donor = duplicates.filter({ !$0.coachPlan.isEmpty }).max(by: { $0.modifiedAt < $1.modifiedAt }) {
                first.coachPlan = donor.coachPlan
                first.targets = donor.targets
                first.trainingTargets = donor.trainingTargets
                first.trainingDays = donor.trainingDays
                first.goal = donor.goal
                first.ratePerWeek = donor.ratePerWeek
                first.targetWeight = donor.targetWeight
                first.modifiedAt = Date()
                AppLog.notice("Kept the coach plan of a newer duplicate profile", category: "store")
            }
            // Synced settings set on a device before its first sync (Thalia off) aren't lost either.
            if first.syncedSettings.isEmpty,
               let donor = duplicates.filter({ !$0.syncedSettings.isEmpty }).max(by: { $0.modifiedAt < $1.modifiedAt }) {
                first.syncedSettings = donor.syncedSettings
                first.modifiedAt = Date()
            }
            for duplicate in duplicates { context.delete(duplicate) }
            AppLog.notice("Removed \(all.count - 1) duplicate profile(s)", category: "store")
            try? context.save()
        }
        return first
    }

    /// The profile's settings with the live day-type marks, so every day's targets follow the plan.
    var settings: NinaSettings { NinaSettings(profile(), dayTypeMarks: dayTypeMarks()) }

    /// Goals & settings from an import: the profile, the coach plan (through `updatePlan`, so the
    /// profile mirrors it), today's body records (baseline assessment and tape) and today's weight
    /// when the file had a new one. Returns what the toast's Undo puts back (`undo(_:)`).
    @discardableResult
    func applySettings(_ result: SettingsResult, previous: SettingsState, day: DayKey, now: Date = Date()) -> SettingsImportUndo {
        var undo = SettingsImportUndo(profile: SettingsImportUndo.Profile(profile() ?? NinaProfile()))
        let plan = result.state.plan ?? CoachPlan()
        let planChanged = plan != (previous.plan ?? CoachPlan())
        var state = result.state
        state.plan = previous.plan
        updateProfile { profile in profile.apply(state, previous: previous) }
        if planChanged {
            _ = updatePlan(plan, on: day)
        }
        for record in result.bodyRecords {
            let key = record.importKey
            let descriptor = FetchDescriptor<BodyMeasurement>(
                predicate: #Predicate<BodyMeasurement> { $0.importKey == key && $0.deletedAt == nil }
            )
            if let existing = try? context.fetch(descriptor).first {
                undo.edited.append(SettingsImportUndo.Edit(measurement: existing, previous: existing.draft))
            }
        }
        let saved = importBodyRecords(result.bodyRecords, time: now)
        undo.added = saved.filter { measurement in !undo.edited.contains { $0.measurement === measurement } }
        if let weight = result.newWeight {
            undo.weight = addWeight(weight, day: day, time: now, note: "import")
        }
        return undo
    }

    /// Puts back what a settings import changed: every profile field (the plan included), the body
    /// records as they were (added ones go to the trash) and the logged weight.
    func undo(_ change: SettingsImportUndo) {
        let now = Date()
        if let profile = profile() {
            change.profile.write(to: profile)
            profile.modifiedAt = now
        }
        for edit in change.edited {
            edit.previous.write(to: edit.measurement)
            edit.measurement.modifiedAt = now
        }
        for measurement in change.added { measurement.moveToTrash(now: now) }
        change.weight?.moveToTrash(now: now)
        save()
    }

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

    /// The settings that follow the person to every device (`NinaProfile.syncedSettings`); nil
    /// while this device has no profile yet (the synced one may still be on its way).
    func syncedSettings() -> SyncedSettings? {
        profile().map { SyncedSettings(encoded: $0.syncedSettings) }
    }

    /// Changes the synced settings, keeping every key a newer Nina wrote. Saves (and creates the
    /// profile, like every settings change) only when a value really changed, so an unchanged
    /// write never reaches iCloud.
    func updateSyncedSettings(_ change: (inout SyncedSettings) -> Void) {
        let before = SyncedSettings(encoded: profile()?.syncedSettings ?? "")
        var settings = before
        change(&settings)
        guard !settings.sameValues(as: before) else { return }
        let text = settings.encoded
        updateProfile { $0.syncedSettings = text }
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
    /// `saveNow: false` leaves the save to the caller (several in a row save once).
    @discardableResult
    func logRecipe(_ recipe: Recipe, amount: AmountText? = nil, day: DayKey, meal: String, time: Date? = nil,
                   status: EntryStatus = .eaten, planKey: String = "", source: String, language: FoodLanguage,
                   saveNow: Bool = true) -> [LogEntry] {
        recipe.lastUsedAt = Date()
        if recipe.recipeKind == .recipe {
            let record = recipe.record
            let portion = amount ?? AmountText(quantity: 1, unitLabel: record.servings.first?.label(language) ?? BaseUnit.serving.symbol,
                                               unitAmount: record.servings.first?.amount ?? 1, baseUnit: record.unit)
            return [log(record, amount: portion, day: day, meal: meal, time: time, status: status, source: source,
                        language: language, planKey: planKey, saveNow: saveNow)]
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
        if saveNow { save() }
        return created
    }

    /// A meal's usual time on that day; now when logging for today at a time past it.
    func defaultTime(on day: DayKey, meal: String, now: Date = Date()) -> Date {
        defaultTime(on: day, meal: meal, settings: settings, now: now)
    }

    /// The same with the settings already read (several entries in a row). A meal time before the
    /// day start (a 00:30 snack with the day starting at 3:00) is the night after.
    func defaultTime(on day: DayKey, meal: String, settings: NinaSettings, now: Date = Date()) -> Date {
        if day == settings.today(now: now, calendar: calendar) { return now }
        return day.date(minutes: settings.meal(meal).minutes, dayStartHour: settings.dayStartHour, calendar: calendar)
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
    /// A routine's entry copied to a day its routine covers (`PlanSchedule.copyRule`): left out of a
    /// planned copy when the routine's plan is already there, else it carries the routine's key for
    /// that day, so the routine doesn't plan the meal a second time.
    @discardableResult
    func copy(_ entries: [LogEntry], to day: DayKey, meal: String? = nil, status: EntryStatus = .eaten) -> [LogEntry] {
        let settings = self.settings
        let copies = planKeys(forCopying: entries, to: day, planned: status == .planned)
        var created: [LogEntry] = []
        let group = UUID().uuidString
        for (index, (source, planKey)) in copies.enumerated() {
            let target = meal ?? source.meal
            let entry = LogEntry(day: day, time: defaultTime(on: day, meal: target, settings: settings), meal: target, name: source.name)
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
            entry.groupID = copies.count > 1 ? group : ""
            entry.planKey = planKey
            entry.sortOrder = Date().timeIntervalSinceReferenceDate + Double(index) / 100
            context.insert(entry)
            created.append(entry)
        }
        if !created.isEmpty { save() }
        return created
    }

    /// The entries to copy onto `day`, each with the plan key its copy gets ("" for most).
    private func planKeys(forCopying entries: [LogEntry], to day: DayKey, planned: Bool) -> [(LogEntry, String)] {
        guard entries.contains(where: { !$0.planKey.isEmpty }) else { return entries.map { ($0, "") } }
        let existing = entriesIncludingTrash(from: day, through: day).map(\.cleanupItem)
        let rules = Dictionary(planRules().map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let calendar = self.calendar
        let covers: (UUID) -> Bool = { id in
            guard let rule = rules[id], rule.isActive else { return false }
            return !PlanSchedule.days(for: rule.days, from: day, horizon: 1, startDay: rule.start, endDay: rule.end,
                                      calendar: calendar).isEmpty
        }
        var result: [(LogEntry, String)] = []
        for source in entries {
            switch PlanSchedule.copyRule(sourceKey: source.planKey, to: day, planned: planned, existing: existing, ruleCovers: covers) {
            case .skip: continue
            case .key(let key): result.append((source, key))
            case .plain: result.append((source, ""))
            }
        }
        return result
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

    /// Days things stay in the trash before the sweep deletes them for good: two more than
    /// Recently Deleted says, so a device that was off for a while sees a restore made elsewhere
    /// before it would delete the record everywhere.
    var purgeDays: Int { trashPolicy.keepDays + 2 }

    /// Empties what has been in the trash longer than `purgeDays`. Fetches only trashed records
    /// (a typed predicate per model). The app runs it once a day, after the launch's first sync.
    func purgeExpired(now: Date = Date()) {
        let policy = TrashPolicy(keepDays: purgeDays)
        var count = 0
        func sweep<T: PersistentModel & SoftDeletable>(_ descriptor: FetchDescriptor<T>) {
            for record in (try? context.fetch(descriptor)) ?? [] where policy.isExpired(deletedAt: record.deletedAt, now: now) {
                context.delete(record)
                count += 1
            }
        }
        sweep(FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<WaterLog>(predicate: #Predicate<WaterLog> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<WeightEntry>(predicate: #Predicate<WeightEntry> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<PlanRule>(predicate: #Predicate<PlanRule> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<BodyMeasurement>(predicate: #Predicate<BodyMeasurement> { $0.deletedAt != nil }))
        sweep(FetchDescriptor<DayMark>(predicate: #Predicate<DayMark> { $0.deletedAt != nil }))
        #if !os(watchOS)
        sweep(FetchDescriptor<ProgressPhoto>(predicate: #Predicate<ProgressPhoto> { $0.deletedAt != nil }))
        #endif
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
    /// rule and day, even if the person deleted them (then they stay deleted). Entries a routine
    /// change took out don't count (`PlanSchedule.takenKeys`). Saves once; returns what it planned.
    @discardableResult
    func materializePlans(today: DayKey, horizon: Int = 3) -> [LogEntry] {
        let rules = planRules().filter(\.isActive)
        guard !rules.isEmpty else { return [] }
        let settings = self.settings
        let end = today.adding(days: horizon - 1, calendar: calendar)
        let existing = PlanSchedule.takenKeys(entriesIncludingTrash(from: today, through: end).map(\.cleanupItem))
        var created: [LogEntry] = []
        for rule in rules {
            guard let recipeID = rule.recipeUUID, let recipe = recipe(recipeID), recipe.deletedAt == nil else { continue }
            for day in PlanSchedule.days(for: rule.days, from: today, horizon: horizon, startDay: rule.start, endDay: rule.end, calendar: calendar) {
                let key = PlanSchedule.key(rule: rule.uuid, day: day)
                guard !existing.contains(key) else { continue }
                let time = day.date(minutes: rule.minutes, dayStartHour: settings.dayStartHour, calendar: calendar)
                created += logRecipe(recipe, day: day, meal: rule.meal, time: time, status: .planned, planKey: key,
                                     source: "plan", language: settings.language, saveNow: false)
            }
        }
        if !created.isEmpty {
            AppLog.info("Planned \(created.count) food(s) from routines", category: "plan")
            save()
        }
        removeDuplicatePlans(from: today, through: end)
        return created
    }

    /// Devices that planned the same routine day before they synced: one copy stays, the same on
    /// every device (`PlanSchedule.duplicates`: what the person acted on, else the oldest; a plan
    /// the person deleted stays deleted). The others go to the trash, marked as the clean-up's, so
    /// nothing the person did is lost, Apple Health hears of it, and no open sheet holds a deleted
    /// entry.
    func removeDuplicatePlans(from start: DayKey, through end: DayKey) {
        let planned = entriesIncludingTrash(from: start, through: end).filter { !$0.planKey.isEmpty }
        let losers = Set(PlanSchedule.duplicates(planned.map(\.cleanupItem)))
        guard !losers.isEmpty else { return }
        let now = Date()
        var moved = 0
        for entry in planned where losers.contains(entry.uuid.uuidString) && entry.deletedAt == nil {
            entry.source = PlanSchedule.duplicateSource
            entry.moveToTrash(now: now)
            moved += 1
        }
        guard moved > 0 else { return }
        AppLog.notice("Moved \(moved) duplicate planned entries to the trash", category: "plan")
        save()
    }

    /// A routine's planned entries the person hasn't touched, from `day` on.
    func untouchedPlans(of rule: PlanRule, from day: DayKey) -> [LogEntry] {
        let first = day.rawValue
        let planned = EntryStatus.planned.rawValue
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day >= first && $0.deletedAt == nil && $0.status == planned }
        )
        let prefix = PlanSchedule.keyPrefix(rule: rule.uuid)
        return ((try? context.fetch(descriptor)) ?? []).filter { entry in
            entry.planKey.hasPrefix(prefix)
                && PlanSchedule.isUntouched(status: entry.status, createdAt: entry.createdAt, modifiedAt: entry.modifiedAt)
        }
    }

    /// Planned entries taken out because their routine was deleted, paused or changed, as they
    /// were (`bringBack` puts them back).
    struct RetiredPlans {
        var entries: [LogEntry] = []
        var sources: [String] = []
        var modified: [Date] = []
        var isEmpty: Bool { entries.isEmpty }
    }

    /// Moves planned entries to the trash, marked as a routine change's: they don't keep the
    /// routine from planning those days again, and other devices don't take them for the person's
    /// delete.
    @discardableResult
    func retirePlans(_ entries: [LogEntry], saveNow: Bool = true) -> RetiredPlans {
        let retired = RetiredPlans(entries: entries, sources: entries.map(\.source), modified: entries.map(\.modifiedAt))
        guard !entries.isEmpty else { return retired }
        let now = Date()
        for entry in entries {
            entry.source = PlanSchedule.retiredSource
            entry.moveToTrash(now: now)
        }
        if saveNow { save() }
        return retired
    }

    /// Puts retired plans back as they were – still untouched, so a later change of the routine
    /// replaces them again.
    func bringBack(_ retired: RetiredPlans, saveNow: Bool = true) {
        guard !retired.isEmpty else { return }
        for (index, entry) in retired.entries.enumerated() {
            entry.deletedAt = nil
            entry.source = retired.sources[index]
            entry.modifiedAt = retired.modified[index]
        }
        if saveNow { save() }
    }

    /// A routine's settings as they were (the Undo of an edit).
    struct RoutineFields {
        var recipeID: String
        var title: String
        var meal: String
        var minutes: Int
        var weekdays: String
        var notify: Bool
        var startDay: String

        init(_ rule: PlanRule) {
            recipeID = rule.recipeID
            title = rule.title
            meal = rule.meal
            minutes = rule.minutes
            weekdays = rule.weekdays
            notify = rule.notify
            startDay = rule.startDay
        }

        /// What decides the planned entries changed (not just the reminder or the title). The
        /// start day isn't compared: the editor only fills in a missing one with today, which
        /// changes nothing from today on.
        func plansDiffer(from other: RoutineFields) -> Bool {
            recipeID != other.recipeID || meal != other.meal || minutes != other.minutes || weekdays != other.weekdays
        }

        func write(to rule: PlanRule) {
            rule.recipeID = recipeID
            rule.title = title
            rule.meal = meal
            rule.minutes = minutes
            rule.weekdays = weekdays
            rule.notify = notify
            rule.startDay = startDay
            rule.touch()
        }
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
        var snapshot = TodaySnapshot(progress: progress, nextPlanned: nextText, energyUnit: settings.energyUnit, now: now)
        // The plan's day type (its emoji goes in front of the numbers) and tomorrow's goals for
        // the widget's entry after the day changes (calorie cycling changes them from day to day).
        snapshot.use(dayType: settings.dayType(for: today, calendar: calendar),
                     isManual: settings.plan.isManualDayType(on: today, marks: settings.dayTypeMarks))
        let tomorrow = today.adding(days: 1, calendar: calendar)
        snapshot.tomorrow = TodaySnapshot.Goals(day: tomorrow, targets: settings.targets(for: tomorrow, calendar: calendar),
                                                dayType: settings.dayType(for: tomorrow, calendar: calendar))
        // The widget changes day at the diary's day start, and its "next planned" line moves on
        // through today's and tomorrow's planned meals by itself.
        snapshot.dayStartHour = settings.dayStartHour
        let upcoming = entries.filter { $0.isPlanned && $0.time >= now } + self.entries(on: tomorrow).filter(\.isPlanned)
        snapshot.planned = plannedItems(upcoming, settings: settings)
        return snapshot
    }

    /// One widget line per planned meal and time ("Lunch · 12:30"), earliest first, at most 12.
    private func plannedItems(_ entries: [LogEntry], settings: NinaSettings) -> [TodaySnapshot.PlannedItem] {
        var seen = Set<String>()
        var items: [TodaySnapshot.PlannedItem] = []
        for entry in entries.sorted(by: { $0.time < $1.time }) {
            let id = "\(entry.day)|\(entry.meal)|\(entry.time.timeIntervalSinceReferenceDate)"
            guard seen.insert(id).inserted else { continue }
            items.append(TodaySnapshot.PlannedItem(day: entry.dayKey, time: entry.time,
                                                   text: "\(settings.meal(entry.meal).name) · \(Fmt.time(entry.time))"))
            if items.count == 12 { break }
        }
        return items
    }

    /// Saves, refreshes the widget snapshot (not for the tour's or the demo's in-memory stores)
    /// and tells the app that data changed. A failed save says so (`ninaSaveFailed`, the app shows
    /// it) instead of looking like a change.
    func save() {
        do {
            try context.save()
        } catch {
            AppLog.error("Save failed: \(error.localizedDescription)", category: "store")
            NotificationCenter.default.post(name: .ninaSaveFailed, object: nil)
            return
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

private extension LogEntry {
    /// The entry as the plan clean-up and copies see it.
    var cleanupItem: PlanSchedule.Item {
        PlanSchedule.Item(id: uuid.uuidString, key: planKey, groupID: groupID, status: status, source: source,
                          createdAt: createdAt, modifiedAt: modifiedAt, isTrashed: deletedAt != nil)
    }
}

/// What a settings import changed (`NinaStore.applySettings`), so its toast's Undo can put it back.
struct SettingsImportUndo {
    /// Every profile field the import writes, as it was.
    struct Profile {
        var targets: String
        var trainingTargets: String
        var trainingDays: String
        var meals: String
        var sex: String
        var birthYear: Int
        var heightCm: Double
        var activity: String
        var goal: String
        var ratePerWeek: Double
        var targetWeight: Double
        var macroSplit: String
        var foodLanguage: String
        var energyUnit: String
        var dayStartHour: Int
        var activityBonusShare: Double
        var focusNutrients: String
        var waterGlass: Double
        var coachPlan: String

        init(_ profile: NinaProfile) {
            targets = profile.targets
            trainingTargets = profile.trainingTargets
            trainingDays = profile.trainingDays
            meals = profile.meals
            sex = profile.sex
            birthYear = profile.birthYear
            heightCm = profile.heightCm
            activity = profile.activity
            goal = profile.goal
            ratePerWeek = profile.ratePerWeek
            targetWeight = profile.targetWeight
            macroSplit = profile.macroSplit
            foodLanguage = profile.foodLanguage
            energyUnit = profile.energyUnit
            dayStartHour = profile.dayStartHour
            activityBonusShare = profile.activityBonusShare
            focusNutrients = profile.focusNutrients
            waterGlass = profile.waterGlass
            coachPlan = profile.coachPlan
        }

        func write(to profile: NinaProfile) {
            profile.targets = targets
            profile.trainingTargets = trainingTargets
            profile.trainingDays = trainingDays
            profile.meals = meals
            profile.sex = sex
            profile.birthYear = birthYear
            profile.heightCm = heightCm
            profile.activity = activity
            profile.goal = goal
            profile.ratePerWeek = ratePerWeek
            profile.targetWeight = targetWeight
            profile.macroSplit = macroSplit
            profile.foodLanguage = foodLanguage
            profile.energyUnit = energyUnit
            profile.dayStartHour = dayStartHour
            profile.activityBonusShare = activityBonusShare
            profile.focusNutrients = focusNutrients
            profile.waterGlass = waterGlass
            profile.coachPlan = coachPlan
        }
    }

    /// A body record the import updated, with its values before.
    struct Edit {
        let measurement: BodyMeasurement
        let previous: BodyMeasurementDraft
    }

    var profile: Profile
    var added: [BodyMeasurement] = []
    var edited: [Edit] = []
    var weight: WeightEntry?
}
