import AppIntents
import Foundation
import SwiftData
import NinaCore

// Siri, Shortcuts, Spotlight and the Action button. Every intent writes through the store with
// the app's rules: today is the diary day (Settings → Day starts at), a weigh-in passes the same
// sanity check as the weigh-in sheet, day types and checks come from the plan. Values read from
// Apple Health are only compared with, never stored. When the app is running its model does the
// write (a toast with Undo, Apple Health written right away); otherwise the store does, and the
// app catches up on Apple Health at its next refresh. Energy is always kcal.

/// "Log food in Nina" – Siri, Shortcuts, the Action button. Understands the same text as quick add.
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Logs foods to today in Nina, e.g. \u{201C}2 eggs and a toast\u{201D} or \u{201C}200 g Skyr\u{201D}.")

    @Parameter(title: "What did you eat?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let store = NinaStore(context: context)
        let settings = store.settings
        let library = FoodLibrary()
        library.rebuild(context: context, language: settings.language)
        let all = library.quickMatches(text)
        let matches = all.filter(\.isResolved)
        // What wasn't found is said, not dropped: the diary would be short without a word.
        let missing = all.filter { !$0.isResolved }.map(\.item.query).filter { !$0.isEmpty }
        guard !matches.isEmpty else {
            return .result(dialog: "I couldn't find \u{201C}\(text)\u{201D} in Nina. Open the app to create it.")
        }
        let day = settings.today()
        let meal = settings.suggestedMeal().id
        var names: [String] = []
        var energy = 0.0
        for match in matches {
            if match.item.isEnergyOnly {
                let entry = store.logQuick(name: match.item.query.isEmpty ? "Quick entry" : match.item.query, nutrients: match.nutrients,
                                           day: day, meal: meal, source: "shortcut")
                names.append(entry.displayName)
                energy += entry.energy
            } else if let food = match.food, let amount = match.amountText {
                let entry = store.log(food, amount: amount, day: day, meal: meal, source: "shortcut", language: settings.language, saveNow: false)
                names.append(entry.displayName)
                energy += entry.energy
            }
        }
        store.save()
        var answer = "Logged \(names.joined(separator: ", ")) to \(settings.meal(meal).name.lowercased()) – \(NinaIntentContext.kcal(energy))."
        if !missing.isEmpty {
            let quoted = missing.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
            answer += " Couldn't find \(quoted) – open Nina to add it."
        }
        return .result(dialog: "\(answer)")
    }
}

/// "Add a glass of water in Nina": your glass size from Settings unless you say how much.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds a glass of water (your glass size in Nina) or the amount you say to today.")

    @Parameter(title: "Milliliters")
    var milliliters: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let settings = store.settings
        let today = settings.today()
        let amount: Double = milliliters.map { Double($0) } ?? settings.waterGlass
        store.addWater(amount, day: today)
        let total = store.water(on: today).map(\.amount).reduce(0, +)
        return .result(dialog: "Added \(Fmt.milliliters(amount)) – \(Fmt.volume(total)) today.")
    }
}

struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Left Today"
    static let description = IntentDescription("Tells you what's left of today's calories and protein in Nina.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = NinaStore(context: Persistence.shared.container.mainContext).todaySnapshot()
        let remaining = snapshot.remaining
        let energy = remaining >= 0
            ? "\(NinaIntentContext.kcal(remaining)) left today"
            : "\(NinaIntentContext.kcal(-remaining)) over today"
        return .result(dialog: "\(energy). Protein \(Fmt.number(snapshot.protein)) of \(Fmt.number(snapshot.proteinGoal)) g.")
    }
}

// MARK: - Coach

/// "Log weight in Nina": today's weigh-in in kilograms (Siri and Shortcuts read 74,2 and 74.2).
/// The weigh-in sheet's sanity check first: outside 25–300 kg nothing is saved (a misplaced
/// decimal point is offered instead, "742" → 74.2 kg), more than 3 kg from the 7-day average asks
/// before it saves.
struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Weight"
    static let description: IntentDescription? = IntentDescription("Saves today's weigh-in in Nina, in kilograms – e.g. 74.2.")
    /// Its answers say the 7-day average: on a locked iPhone Siri asks to unlock first (the Coach
    /// widget hides the weight on the Lock Screen too).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Weight (kg)", description: "Your weight in kilograms, e.g. 74.2.", controlStyle: .field,
               requestValueDialog: "How much do you weigh, in kilograms?")
    var kilograms: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$kilograms) kg")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NinaIntentContext.store
        let settings = store.settings
        let now = Date()
        let today = settings.today(now: now, calendar: store.calendar)
        let health = NinaIntentContext.healthReadings
        let signal = store.weightSignal(adding: health, settings: settings)
        // To 0.1 kg, as the weigh-in sheet takes a value from a link.
        var value = (kilograms * 10).rounded() / 10
        switch signal.sanity(value, on: today) {
        case .ok:
            break
        case .outOfRange:
            let reference = signal.average(on: today).value ?? signal.trend(on: today)
            guard let suggestion = WeightSignal.typoSuggestion(for: value, reference: reference) else {
                return .result(dialog: "\(Fmt.kilograms(value)) isn't a weight Nina can save – anything from 25 to 300 kg works. Nothing was saved.")
            }
            try await requestConfirmation(actionName: .add,
                                          dialog: "\(Fmt.kilograms(value)) can't be right. Save \(Fmt.kilograms(suggestion)) instead?")
            value = suggestion
        case .typo(let reference):
            try await requestConfirmation(actionName: .add,
                                          dialog: "\(Fmt.kilograms(value)) is more than 3 kg from your 7-day average of \(Fmt.kilograms(reference)). Save it anyway?")
        }
        if let app = NinaIntentContext.app {
            app.logWeight(value, day: today, time: now)
        } else {
            store.addWeight(value, day: today, time: now)
        }
        NinaIntentContext.refreshWidgets(store)
        let average = store.weightSignal(adding: health, settings: settings).average(on: today).value
        if let average {
            return .result(dialog: "Saved \(Fmt.kilograms(value)). Your 7-day average is \(Fmt.kilograms(average)).")
        }
        return .result(dialog: "Saved \(Fmt.kilograms(value)) for today.")
    }
}

/// "Today is a Tennis day in Nina": today's day type from the plan (or back to the schedule);
/// today's targets follow it.
struct SetDayTypeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Day Type"
    static let description: IntentDescription? = IntentDescription("Picks today's day type from your plan in Nina – Gym, Tennis, Rest … – and today's targets follow it.")

    @Parameter(title: "Day Type", requestValueDialog: "Which day type is today?")
    var dayType: NinaDayTypeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Today is \(\.$dayType)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NinaIntentContext.store
        let settings = store.settings
        let calendar = store.calendar
        let today = settings.today(now: Date(), calendar: calendar)
        guard settings.plan.isSetUp, !settings.plan.dayTypes.isEmpty else {
            return .result(dialog: "Your plan in Nina has no day types yet. Open Nina → My Plan to add some.")
        }
        var typeID: String?
        if dayType.id != NinaDayTypeEntity.scheduleID {
            guard settings.plan.dayType(id: dayType.id) != nil else {
                return .result(dialog: "\u{201C}\(dayType.name)\u{201D} isn't a day type in your plan any more.")
            }
            typeID = dayType.id
        }
        if let app = NinaIntentContext.app {
            app.setDayType(typeID, on: today)
        } else {
            store.setDayType(day: today, typeID: typeID)
        }
        NinaIntentContext.refreshWidgets(store)
        let updated = store.settings
        let target = NinaIntentContext.kcal(updated.targets(for: today, calendar: calendar).energy)
        guard let type = updated.dayType(for: today, calendar: calendar) else {
            return .result(dialog: "Back to your schedule – \(target) today.")
        }
        if typeID == nil {
            return .result(dialog: "Back to your schedule: today is a \(CoachSiriNames.dayTitle(type.name)), \(target).")
        }
        return .result(dialog: "Today is a \(CoachSiriNames.dayTitle(type.name)) – \(target).")
    }
}

/// "Mark Creatine done in Nina": ticks one of the plan's daily checks off for today.
struct MarkCheckDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Check Done"
    static let description: IntentDescription? = IntentDescription("Ticks one of your plan's daily checks off for today in Nina, e.g. Creatine.")

    @Parameter(title: "Check", requestValueDialog: "Which check?")
    var check: NinaCheckEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$check) done")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NinaIntentContext.store
        let settings = store.settings
        let today = settings.today(now: Date(), calendar: store.calendar)
        guard let item = settings.plan.check(id: check.id) else {
            return .result(dialog: "\u{201C}\(check.name)\u{201D} isn't a daily check in your plan any more.")
        }
        guard store.checkStates(on: today)[item.id] != .done else {
            return .result(dialog: "\(item.name) is already done today.")
        }
        if let app = NinaIntentContext.app {
            app.setCheck(item.id, on: today, state: .done)
        } else {
            store.setCheck(day: today, checkID: item.id, state: .done)
        }
        let snapshot = NinaIntentContext.refreshWidgets(store)
        let progress = snapshot.shown(at: Date(), calendar: store.calendar).checksText
        guard let progress else { return .result(dialog: "\(item.name) ticked off.") }
        return .result(dialog: "\(item.name) ticked off – \(progress.lowercased()) today.")
    }
}

// MARK: - Entities

/// A day type of the plan for Siri and Shortcuts ("Tennis", 2,600 kcal today), plus "Back to
/// Schedule". Siri also hears "Tennis day" and "Tennistag" (`CoachSiriNames`).
struct NinaDayTypeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day Type"
    static let defaultQuery = NinaDayTypeQuery()
    /// "Back to Schedule": not a day type of the plan (ids there are letters and digits only).
    static let scheduleID = "@schedule"

    let id: String
    let name: String
    /// "🎾 · 2,600 kcal today".
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        let synonyms: [LocalizedStringResource] = id == NinaDayTypeEntity.scheduleID
            ? []
            : CoachSiriNames.dayTypeSynonyms(name).map { text -> LocalizedStringResource in "\(text)" }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)", image: nil, synonyms: synonyms)
    }
}

struct NinaDayTypeQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [NinaDayTypeEntity.ID]) async throws -> [NinaDayTypeEntity] {
        NinaCoachEntities.dayTypes().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [NinaDayTypeEntity] {
        NinaCoachEntities.dayTypes().filter { CoachSiriNames.matches(string, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [NinaDayTypeEntity] {
        NinaCoachEntities.dayTypes()
    }
}

/// A daily check of the plan for Siri and Shortcuts ("Creatine", 3–5 g · open today).
struct NinaCheckEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Daily Check"
    static let defaultQuery = NinaCheckQuery()

    let id: String
    let name: String
    /// "💊 · 3–5 g · open today".
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }
}

struct NinaCheckQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [NinaCheckEntity.ID]) async throws -> [NinaCheckEntity] {
        NinaCoachEntities.checks().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [NinaCheckEntity] {
        NinaCoachEntities.checks().filter { CoachSiriNames.matches(string, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [NinaCheckEntity] {
        NinaCoachEntities.checks()
    }
}

/// The plan's day types and checks as entities, read fresh from the store.
@MainActor
enum NinaCoachEntities {
    /// Every day type in plan order with today's kcal if picked, then "Back to Schedule"; empty
    /// without day types.
    static func dayTypes() -> [NinaDayTypeEntity] {
        let store = NinaIntentContext.store
        let settings = store.settings
        let plan = settings.plan
        let calendar = store.calendar
        guard plan.isSetUp, !plan.dayTypes.isEmpty else { return [] }
        let today = settings.today(now: Date(), calendar: calendar)
        let fallback = settings.legacyTargets(for: today, calendar: calendar)
        let current = plan.dayType(on: today, marks: settings.dayTypeMarks, calendar: calendar)?.id
        var entities = plan.dayTypes.map { type -> NinaDayTypeEntity in
            var marks = settings.dayTypeMarks
            marks[today.rawValue] = type.id
            let energy = plan.targets(on: today, marks: marks, fallback: fallback, calendar: calendar).energy
            var parts = [TodaySnapshot.emoji(of: type), "\(NinaIntentContext.kcal(energy)) today"]
            if type.id == current { parts.append("today's type") }
            return NinaDayTypeEntity(id: type.id, name: type.name, detail: parts.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        entities.append(NinaDayTypeEntity(id: NinaDayTypeEntity.scheduleID, name: "Back to Schedule",
                                          detail: "The day type your plan's schedule gives today"))
        return entities
    }

    /// Every daily check: the ones due today first (in the Today strip's order), then the rest.
    static func checks() -> [NinaCheckEntity] {
        let store = NinaIntentContext.store
        let plan = store.settings.plan
        guard plan.isSetUp, !plan.checks.isEmpty else { return [] }
        let today = CoachSnapshot(CoachWidgetFeed.input(store: store, health: NinaIntentContext.healthReadings)).days.first
        let due = today?.checks ?? []
        let dueIDs = Set(due.map(\.id))
        var entities = due.map { check in
            NinaCheckEntity(id: check.id, name: check.name, detail: detail(emoji: check.emoji, dose: check.dose, state: check.state))
        }
        for check in plan.checks where !dueIDs.contains(check.id) {
            entities.append(NinaCheckEntity(id: check.id, name: check.name,
                                            detail: detail(emoji: check.emoji, dose: check.dose, state: nil)))
        }
        return entities
    }

    private static func detail(emoji: String, dose: String, state: CoachBoard.StripItem.State?) -> String {
        let stateText: String
        switch state {
        case .open?: stateText = "open today"
        case .done?: stateText = "done today"
        case .skipped?: stateText = "not today"
        case nil: stateText = "not due today"
        }
        return [emoji, dose.trimmingCharacters(in: .whitespaces), stateText].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Where the intents act and what they say.
@MainActor
enum NinaIntentContext {
    /// The running app's model, when there is one (`CoachWidgetFeed`).
    static var app: AppModel? { CoachWidgetFeed.app }

    /// The app's store, else one on the shared container (a launch that only answers Siri).
    static var store: NinaStore {
        app?.store ?? NinaStore(context: Persistence.shared.container.mainContext)
    }

    /// The live Apple Health weigh-ins (memory only, never stored): the app's, else the last ones
    /// this launch read.
    static var healthReadings: [WeightSignal.Reading] {
        app?.healthWeightReadings ?? CoachContext.latestHealthReadings
    }

    /// Writes the coach widget's snapshot right away (a Siri request can end before the app's own
    /// refresh) and returns it.
    @discardableResult
    static func refreshWidgets(_ store: NinaStore) -> CoachSnapshot {
        CoachWidgetFeed.publishNow(store: store, health: healthReadings)
    }

    /// "2,500 kcal" – Nina always speaks kcal.
    static func kcal(_ value: Double) -> String {
        Fmt.number(value.rounded(), decimals: 0) + " kcal"
    }
}

// MARK: - Phrases

/// The phrases Siri knows without any setup. German phrases come from
/// `App/Resources/de.lproj/AppShortcuts.strings` (one German phrase per English one).
struct NinaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: [
            "Log food in \(.applicationName)",
            "Add food to \(.applicationName)",
        ], shortTitle: "Log Food", systemImageName: "fork.knife")
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)",
            "Add a glass of water in \(.applicationName)",
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: CaloriesLeftIntent(), phrases: [
            "Calories left in \(.applicationName)",
            "How many calories are left in \(.applicationName)",
        ], shortTitle: "Calories Left", systemImageName: "flame")
        AppShortcut(intent: LogWeightIntent(), phrases: [
            "Log weight in \(.applicationName)",
            "Log my weight in \(.applicationName)",
            "Weigh in with \(.applicationName)",
        ], shortTitle: "Log Weight", systemImageName: "scalemass")
        AppShortcut(intent: SetDayTypeIntent(), phrases: [
            "Today is a \(\.$dayType) in \(.applicationName)",
            "Today is \(\.$dayType) in \(.applicationName)",
            "Set the day type in \(.applicationName)",
        ], shortTitle: "Set Day Type", systemImageName: "calendar")
        AppShortcut(intent: MarkCheckDoneIntent(), phrases: [
            "Mark \(\.$check) done in \(.applicationName)",
            "\(\.$check) done in \(.applicationName)",
            "Tick off a check in \(.applicationName)",
        ], shortTitle: "Mark Check Done", systemImageName: "checkmark.circle")
    }
}
