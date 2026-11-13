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
        let matches = library.quickMatches(text).filter(\.isResolved)
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
        return .result(dialog: "Logged \(names.joined(separator: ", ")) to \(settings.meal(meal).name.lowercased()) – \(Fmt.energy(energy, unit: settings.energyUnit)).")
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds water to today in Nina.")

    @Parameter(title: "Milliliters", default: 250)
    var milliliters: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let today = store.settings.today()
        store.addWater(Double(milliliters), day: today)
        let total = store.water(on: today).map(\.amount).reduce(0, +)
        return .result(dialog: "Added \(milliliters) ml – \(Fmt.volume(total)) today.")
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
