import SwiftUI
import BinisoftKit
import NinaCore

/// Menu bar commands and keyboard shortcuts (Mac, iPad with a keyboard). While the tour is open
/// they act on its practice page. Each one is a small view, so it follows the app's state:
/// - On the Mac every command brings the main window forward first (MainWindow.swift): its
///   sheets, the tour and the toasts show there, also after ⌘W or when it is minimized.
/// - Commands that open a sheet are off while a sheet is up, so a shortcut never replaces a
///   half-filled editor. Adding water and the day types stay on (they don't open one).
/// - Previous Day, Next Day and Day Type only work while Today (the diary) shows, so ⌘[ and ⌘]
///   are Back and Forward everywhere else.
struct NinaCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            NinaFileCommands(app: app)
        }
        CommandMenu("Day") {
            NinaDayCommands(app: app)
        }
        CommandMenu("Go") {
            NinaGoCommands(app: app)
        }
        #if os(macOS)
        CommandGroup(before: .windowList) {
            NinaWindowCommand()
        }
        #endif
        CommandGroup(replacing: .help) {
            NinaCommandButton(title: "\(AppInfo.name) Tour") { app.startTour() }
        }
    }
}

/// A menu command. On the Mac it brings the main window forward before it acts.
private struct NinaCommandButton: View {
    let title: String
    var shortcut: KeyboardShortcut? = nil
    var isDisabled = false
    let action: () -> Void

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button(title) {
            #if os(macOS)
            MainWindow.bringForward(openWindow: openWindow)
            #endif
            action()
        }
        .keyboardShortcut(shortcut)
        .disabled(isDisabled)
    }
}

/// File: logging, creating, body measurements, import & export and the backup.
private struct NinaFileCommands: View {
    let app: AppModel

    var body: some View {
        let target = app.commandTarget
        let busy = target.sheet != nil
        let hasPlan = target.settings.plan.isSetUp
        NinaCommandButton(title: "Log Food…", shortcut: KeyboardShortcut("n"), isDisabled: busy) {
            target.sheet = .addFood(day: target.selectedDay, meal: nil)
        }
        NinaCommandButton(title: "Quick Calories…", shortcut: KeyboardShortcut("n", modifiers: [.command, .option]), isDisabled: busy) {
            target.sheet = .quickCalories(day: target.selectedDay, meal: nil)
        }
        NinaCommandButton(title: "Create…", shortcut: KeyboardShortcut("n", modifiers: [.command, .shift]), isDisabled: busy) {
            target.sheet = .create
        }
        NinaCommandButton(title: "New Food…", isDisabled: busy) { target.sheet = .newFood(nil) }
        NinaCommandButton(title: "New Meal…", isDisabled: busy) { target.sheet = .recipe(nil, kind: .meal) }
        NinaCommandButton(title: "New Recipe…", isDisabled: busy) { target.sheet = .recipe(nil, kind: .recipe) }
        Divider()
        NinaCommandButton(title: "Add a Glass of Water", shortcut: KeyboardShortcut("w", modifiers: [.command, .control])) {
            target.addWater(target.settings.waterGlass, day: target.selectedDay)
        }
        NinaCommandButton(title: "Log Weight…", isDisabled: busy) { target.sheet = .weight(nil) }
        // ⇧⌘M: ⌥⌘M is the Mac's Minimize All.
        NinaCommandButton(title: "Log Measurements…", shortcut: KeyboardShortcut("m", modifiers: [.command, .shift]), isDisabled: busy) {
            target.measureNow()
        }
        NinaCommandButton(title: "Log Body Fat…", isDisabled: busy || !hasPlan) { target.sheet = .assessment(nil) }
        NinaCommandButton(title: "Add Progress Photos…", isDisabled: busy) {
            target.sheet = .photos(.session(BodyPhotoStart()))
        }
        NinaCommandButton(title: "Weekly Check-in…", isDisabled: busy || !hasPlan) {
            target.sheet = .checkIn(target.currentCheckInWeek)
        }
        Divider()
        NinaCommandButton(title: "Import & Export…", shortcut: KeyboardShortcut("i", modifiers: [.command, .shift]), isDisabled: busy) {
            target.sheet = .importData(nil)
        }
        // Import & Export → Back Up Everything.
        NinaCommandButton(title: "Back Up \(AppInfo.name)…", shortcut: KeyboardShortcut("b", modifiers: [.command, .shift]), isDisabled: busy) {
            target.sheet = .importData(nil)
        }
    }
}

/// Day: the day Today shows (the diary) and its type.
private struct NinaDayCommands: View {
    let app: AppModel

    var body: some View {
        let target = app.commandTarget
        let busy = target.sheet != nil
        let inDiary = Self.diaryShows(app)
        NinaCommandButton(title: "Previous Day", shortcut: KeyboardShortcut("["), isDisabled: busy || !inDiary) {
            target.selectedDay = target.selectedDay.adding(days: -1)
        }
        NinaCommandButton(title: "Next Day", shortcut: KeyboardShortcut("]"), isDisabled: busy || !inDiary) {
            target.selectedDay = target.selectedDay.adding(days: 1)
        }
        NinaCommandButton(title: "Go to Today", shortcut: KeyboardShortcut("t")) {
            target.show(day: target.today)
        }
        Divider()
        NinaCommandButton(title: "Nutrients of the Day", shortcut: KeyboardShortcut("i"), isDisabled: busy) {
            target.sheet = .dayNutrition(target.selectedDay)
        }
        Divider()
        Menu("Day Type") {
            DayTypeCommands(app: app)
        }
        .disabled(!inDiary)
    }

    /// Today (the diary) is on screen (the tour's practice page is one).
    static func diaryShows(_ app: AppModel) -> Bool {
        guard app.tourModel == nil else { return true }
        #if os(macOS)
        return (app.sidebar ?? .today) == .today
        #else
        return app.tab == .today
        #endif
    }
}

/// Go: the sections, search, and the goals and plan sheets.
private struct NinaGoCommands: View {
    let app: AppModel

    var body: some View {
        let busy = app.commandTarget.sheet != nil
        // The sidebar's names (Navigation.swift: `SidebarItem.title`), in its order.
        NinaCommandButton(title: SidebarItem.today.title, shortcut: KeyboardShortcut("1")) { go(.today, tab: .today) }
        NinaCommandButton(title: SidebarItem.foods.title, shortcut: KeyboardShortcut("2")) { go(.foods, tab: .foods) }
        NinaCommandButton(title: SidebarItem.recipes.title, shortcut: KeyboardShortcut("3")) { go(.recipes, tab: .foods) }
        NinaCommandButton(title: SidebarItem.plan.title, shortcut: KeyboardShortcut("4")) { go(.plan, tab: .plan) }
        NinaCommandButton(title: SidebarItem.insights.title, shortcut: KeyboardShortcut("5")) { go(.insights, tab: .insights) }
        NinaCommandButton(title: SidebarItem.body.title, shortcut: KeyboardShortcut("6")) { go(.body, tab: .insights) }
        Divider()
        NinaCommandButton(title: "Search Everything", shortcut: KeyboardShortcut("f", modifiers: [.command, .shift])) {
            go(.search, tab: .search)
        }
        Divider()
        NinaCommandButton(title: "Goals & Plan…", shortcut: KeyboardShortcut("g", modifiers: [.command, .shift]), isDisabled: busy) {
            app.commandTarget.sheet = .goals
        }
        NinaCommandButton(title: "My Plan…", isDisabled: busy) { app.commandTarget.sheet = .plan }
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

#if os(macOS)
/// Window → Nina (⌘0): the main window back, also after ⌘W. Its `openWindow` works with no window
/// open, so it is kept for the menu bar item (MainWindow.swift).
private struct NinaWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = MainWindow.keepAppOpenWindow(openWindow)
        Button(AppInfo.name) { MainWindow.bringForward(openWindow: openWindow) }
            .keyboardShortcut("0")
    }
}
#endif

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
                NinaCommandButton(title: title(type),
                                  shortcut: KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])) {
                    _ = target.setDayType(type.id, on: target.selectedDay)
                }
            }
        }
        Divider()
        NinaCommandButton(title: "Back to Schedule",
                          isDisabled: !target.settings.plan.isManualDayType(on: target.selectedDay, marks: target.settings.dayTypeMarks)) {
            _ = target.setDayType(nil, on: target.selectedDay)
        }
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
        CreateSheet(
            options: options,
            footnote: "Tip: on the Mac and iPad, ⌘N logs a food right away; ⌥⌘N adds quick calories."
        )
    }

    private var options: [CreateOption] {
        let day = app.selectedDay
        let meal = app.settings.suggestedMeal().id
        var options: [CreateOption] = [
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
            CreateOption(id: "bodyfat", title: "Body Fat", subtitle: "A scan, scale or estimate",
                         symbol: "percent", tint: .indigo, isFeatured: false) { app.sheet = .assessment(nil) },
            // The same start as Take Photos on the body page's Photos card.
            CreateOption(id: "photos", title: "Progress Photos", subtitle: "Front, side and back",
                         symbol: "camera.fill", tint: .blue, isFeatured: false) { app.sheet = .photos(.session(BodyPhotoStart())) },
        ]
        if app.settings.plan.isSetUp {
            options.append(CreateOption(id: "checkin", title: "Check-in", subtitle: "Your week, and what to change",
                                        symbol: "checklist", tint: .orange, isFeatured: false) { app.sheet = .checkIn(app.currentCheckInWeek) })
        }
        options += [
            CreateOption(id: "food", title: "New Food", subtitle: "From a label – per 100 g or 100 ml",
                         symbol: "carrot.fill", tint: .green, isFeatured: false) { app.sheet = .newFood(nil) },
            CreateOption(id: "meal", title: "New Meal", subtitle: "Foods you eat together, logged in one tap",
                         symbol: "takeoutbag.and.cup.and.straw.fill", tint: .teal, isFeatured: false) { app.sheet = .recipe(nil, kind: .meal) },
            CreateOption(id: "recipe", title: "New Recipe", subtitle: "Cooked once, eaten in portions",
                         symbol: "frying.pan.fill", tint: .brown, isFeatured: false) { app.sheet = .recipe(nil, kind: .recipe) },
            CreateOption(id: "routine", title: "New Routine", subtitle: "Plan a meal on chosen weekdays",
                         symbol: "calendar.badge.clock", tint: .purple, isFeatured: false) { app.sheet = .planRule(nil, recipe: nil) },
            CreateOption(id: "import", title: "Import My Data", subtitle: "Plan, foods, diary, recipes or weigh-ins – your file, or one another AI wrote",
                         symbol: "square.and.arrow.down", tint: .pink, isFeatured: false) { app.sheet = .importData(nil) },
        ]
        return options
    }
}
