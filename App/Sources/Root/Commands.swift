import SwiftUI
import BinisoftKit
import NinaCore

/// Menu bar commands and keyboard shortcuts (Mac, iPad with a keyboard). While the tour is open
/// they act on its practice page.
struct NinaCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Log Food…") {
                let target = app.commandTarget
                target.sheet = .addFood(day: target.selectedDay, meal: nil)
            }
            .keyboardShortcut("n")
            Button("Quick Calories…") {
                let target = app.commandTarget
                target.sheet = .quickCalories(day: target.selectedDay, meal: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Create…") { app.commandTarget.sheet = .create }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Food…") { app.commandTarget.sheet = .newFood(nil) }
            Button("New Meal…") { app.commandTarget.sheet = .recipe(nil, kind: .meal) }
            Button("New Recipe…") { app.commandTarget.sheet = .recipe(nil, kind: .recipe) }
            Divider()
            Button("Add a Glass of Water") {
                let target = app.commandTarget
                target.addWater(target.settings.waterGlass, day: target.selectedDay)
            }
            .keyboardShortcut("w", modifiers: [.command, .control])
            Button("Log Weight…") { app.commandTarget.sheet = .weight(nil) }
            Button("Log Measurements…") { app.commandTarget.measureNow() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            CheckInCommand(app: app)
            Divider()
            Button("Import My Data…") { app.commandTarget.sheet = .importData(nil) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Day") {
            Button("Previous Day") {
                let target = app.commandTarget
                target.selectedDay = target.selectedDay.adding(days: -1)
            }
            .keyboardShortcut("[")
            Button("Next Day") {
                let target = app.commandTarget
                target.selectedDay = target.selectedDay.adding(days: 1)
            }
            .keyboardShortcut("]")
            Button("Go to Today") { app.commandTarget.show(day: app.commandTarget.today) }
                .keyboardShortcut("t")
            Divider()
            Button("Nutrients of the Day") { app.commandTarget.sheet = .dayNutrition(app.commandTarget.selectedDay) }
                .keyboardShortcut("i")
            Divider()
            Menu("Day Type") {
                DayTypeCommands(app: app)
            }
        }
        CommandMenu("Go") {
            Button("Diary") { go(.today, tab: .today) }
                .keyboardShortcut("1")
            Button("Foods") { go(.foods, tab: .foods) }
                .keyboardShortcut("2")
            Button("Meals & Recipes") { go(.recipes, tab: .foods) }
                .keyboardShortcut("3")
            Button("Plan") { go(.plan, tab: .plan) }
                .keyboardShortcut("4")
            Button("Insights") { go(.insights, tab: .insights) }
                .keyboardShortcut("5")
            Button("Body") { go(.body, tab: .insights) }
                .keyboardShortcut("6")
            Divider()
            Button("Goals…") { app.commandTarget.sheet = .goals }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("My Plan…") { app.commandTarget.sheet = .plan }
        }
        CommandGroup(replacing: .help) {
            Button("\(AppInfo.name) Tour") { app.startTour() }
        }
    }

    private func go(_ item: SidebarItem, tab: AppTab) {
        app.sidebar = item
        app.tab = tab
        if item == .foods { app.foodsPage = .foods }
        if item == .recipes { app.foodsPage = .recipes }
        if item == .insights { app.progressPage = .nutrition }
        if item == .body { app.progressPage = .body }
    }
}

/// File → Weekly Check-in… (only with a plan). A view, so it follows the plan as it changes.
private struct CheckInCommand: View {
    let app: AppModel

    var body: some View {
        let target = app.commandTarget
        Button("Weekly Check-in…") { target.sheet = .checkIn(target.currentCheckInWeek) }
            .disabled(!target.settings.plan.isSetUp)
    }
}

/// Day → Day Type: the plan's first four day types (⌃⌘1–⌃⌘4) for the selected day, and back to
/// the schedule. A view, so the titles follow the plan.
private struct DayTypeCommands: View {
    let app: AppModel

    var body: some View {
        let target = app.commandTarget
        let types = Array(target.settings.plan.dayTypes.prefix(4))
        if types.isEmpty {
            Button("No Day Types Yet") {}
                .disabled(true)
        } else {
            ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                Button(title(type)) { _ = target.setDayType(type.id, on: target.selectedDay) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
            }
        }
        Divider()
        Button("Back to Schedule") { _ = target.setDayType(nil, on: target.selectedDay) }
            .disabled(!target.settings.plan.isManualDayType(on: target.selectedDay, marks: target.settings.dayTypeMarks))
    }

    private func title(_ type: CoachPlan.DayType) -> String {
        let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
        return emoji.isEmpty ? type.name : "\(emoji) \(type.name)"
    }
}

/// The central "+": everything that can be created, and importing existing data.
struct NinaCreateSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let day = app.selectedDay
        let meal = app.settings.suggestedMeal().id
        CreateSheet(
            options: [
                CreateOption(id: "log", title: "Log Food", subtitle: "Search, scan, or type \u{201C}2 eggs and a toast\u{201D}",
                             symbol: "fork.knife") { app.sheet = .addFood(day: day, meal: meal) },
                CreateOption(id: "quick", title: "Quick Calories", subtitle: "Just a number when you're in a hurry",
                             symbol: "bolt.fill", tint: .orange) { app.sheet = .quickCalories(day: day, meal: meal) },
                CreateOption(id: "water", title: "Water", subtitle: "\(Fmt.milliliters(app.settings.waterGlass)) or another amount",
                             symbol: "drop.fill", tint: .cyan) { app.sheet = .water(day) },
                CreateOption(id: "weight", title: "Weight", subtitle: "Today's weigh-in",
                             symbol: "scalemass.fill", tint: .indigo) { app.sheet = .weight(nil) },
                CreateOption(id: "measure", title: "Measurements", subtitle: "Waist, or the full set with the tape",
                             symbol: "ruler.fill", tint: .mint, isFeatured: false) { app.measureNow() },
                CreateOption(id: "checkin", title: "Check-in", subtitle: "Your week, and what to change",
                             symbol: "checklist", tint: .orange, isFeatured: false) { app.sheet = .checkIn(app.currentCheckInWeek) },
                CreateOption(id: "food", title: "New Food", subtitle: "From a label – per 100 g or 100 ml",
                             symbol: "carrot.fill", tint: .green, isFeatured: false) { app.sheet = .newFood(nil) },
                CreateOption(id: "meal", title: "New Meal", subtitle: "Foods you eat together, logged in one tap",
                             symbol: "takeoutbag.and.cup.and.straw.fill", tint: .teal, isFeatured: false) { app.sheet = .recipe(nil, kind: .meal) },
                CreateOption(id: "recipe", title: "New Recipe", subtitle: "Cooked once, eaten in portions",
                             symbol: "frying.pan.fill", tint: .brown, isFeatured: false) { app.sheet = .recipe(nil, kind: .recipe) },
                CreateOption(id: "routine", title: "New Routine", subtitle: "Plan a meal on chosen weekdays",
                             symbol: "calendar.badge.clock", tint: .purple, isFeatured: false) { app.sheet = .planRule(nil, recipe: nil) },
                CreateOption(id: "import", title: "Import My Data", subtitle: "Foods, diary or recipes – your file, or one another AI wrote",
                             symbol: "square.and.arrow.down", tint: .pink, isFeatured: false) { app.sheet = .importData(nil) },
            ],
            footnote: "Tip: on the Mac and iPad, ⌘N logs a food right away; ⌥⌘N adds quick calories."
        )
    }
}
