import AppIntents
import Foundation
import SwiftData
import NinaCore

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
        var answer = "Logged \(names.joined(separator: ", ")) to \(settings.meal(meal).name.lowercased()) – \(Fmt.energy(energy, unit: settings.energyUnit))."
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
        let unit = snapshot.unit
        let remaining = snapshot.remaining
        let energy = remaining >= 0
            ? "\(Fmt.energy(remaining, unit: unit)) left today"
            : "\(Fmt.energy(-remaining, unit: unit)) over today"
        return .result(dialog: "\(energy). Protein \(Fmt.number(snapshot.protein)) of \(Fmt.number(snapshot.proteinGoal)) g.")
    }
}

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
    }
}
