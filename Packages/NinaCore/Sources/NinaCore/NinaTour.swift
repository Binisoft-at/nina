import Foundation
import BinisoftKitCore

/// What the tour's practice day looks like right now (built from the demo store after every change).
public struct NinaTourSnapshot: Equatable, Sendable {
    public var eatenCount = 0
    public var plannedCount = 0
    public var trashedCount = 0
    /// Entries per meal, e.g. "breakfast:2|lunch:1" – changes when something moves to another meal.
    public var mealLayout = ""
    public var water = 0.0
    public var favoriteCount = 0
    public var isCreateOpen = false
    public var isAddOpen = false
    public var isQuickAddOpen = false

    public init() {}
}

/// Nina's interactive tour. To teach a new feature: add a step with `since: version + 1` and bump
/// `version`; people who already took the tour then get just the new steps as "What's new".
/// `swift test` checks the catalog.
public enum NinaTour {
    public static let version = 1

    public static let catalog = TourCatalog<NinaTourSnapshot>.standard(
        appName: "Nina",
        version: version,
        practiceNoun: "diary",
        replayHint: "Settings or Help → Nina Tour",
        steps: [
            TourStep(
                id: "create", symbol: "plus.circle", title: "Everything starts at +",
                body: "Tap + at the top. Foods, quick entries, meals, recipes, water, weight – and importing the data you already have.",
                macBody: "Click + in the toolbar or press ⇧⌘N. Foods, quick entries, meals, recipes, water, weight – and importing the data you already have.",
                goal: .isTrue(\.isCreateOpen)
            ),
            TourStep(
                id: "log", symbol: "magnifyingglass", title: "Log a food",
                body: "Tap + next to Breakfast, search for \u{201C}banana\u{201D} (or \u{201C}Banane\u{201D}) and tap the + next to it. Nina knows about 1,000 everyday foods in English and German.",
                macBody: "Click + next to Breakfast (or press ⌘N), search for \u{201C}banana\u{201D} and press Return. Nina knows about 1,000 everyday foods in English and German.",
                goal: .increased(\.eatenCount)
            ),
            TourStep(
                id: "quick", symbol: "text.bubble", title: "Type it like a message",
                body: "In the same search field, write \u{201C}2 eggs, 1 toast and 200 ml milk\u{201D}. Nina understands amounts and units (also \u{201C}10 dag Extrawurst\u{201D} or \u{201C}ein Achtel Rotwein\u{201D}) and logs everything at once.",
                macBody: "In the search field, write \u{201C}2 eggs, 1 toast and 200 ml milk\u{201D} and press Return. Nina understands amounts and units and logs everything at once.",
                goal: .increased(\.eatenCount)
            ),
            TourStep(
                id: "undo", symbol: "arrow.uturn.backward", title: "Mistakes are fine",
                body: "Swipe left on an entry and tap Delete, then tap Undo in the message. Shaking your iPhone undoes the last change too.",
                macBody: "Right-click an entry and choose Delete, then click Undo in the message – or press ⌘Z.",
                goal: .undone(\.trashedCount)
            ),
            TourStep(
                id: "move", symbol: "arrow.left.arrow.right", title: "Wrong meal? Move it",
                body: "Touch and hold an entry → Move to → Lunch. You can also drag entries between meals, or swipe right to log it again.",
                macBody: "Right-click an entry → Move to → Lunch, or drag it onto another meal.",
                goal: .changed(\.mealLayout)
            ),
            TourStep(
                id: "plan", symbol: "checklist", title: "Plan, then just confirm",
                body: "Dimmed entries are planned. Tap the circle next to the planned dinner when you've eaten it – that's all the logging it needs.",
                macBody: "Dimmed entries are planned. Click the circle next to the planned dinner when you've eaten it – that's all the logging it needs.",
                goal: .decreased(\.plannedCount)
            ),
            TourStep(
                id: "water", symbol: "drop.fill", title: "Water in one tap",
                body: "Tap the glass in the water card to add 250 ml. Touch and hold it for other amounts.",
                macBody: "Click the glass in the water card to add 250 ml. Right-click it for other amounts.",
                goal: .increased(\.water)
            ),
            TourStep(
                id: "everywhere", symbol: "applewatch", title: "Everywhere you are",
                body: "Nina syncs through your iCloud with your Mac and Apple Watch. Log from the watch, see what's left in widgets, and send everything to Apple Health in Settings.",
                macBody: "Nina syncs through your iCloud with your iPhone and Apple Watch. Settings (⌘,) has your goals, Apple Health, meals and the import.",
                goal: .none
            ),
        ]
    )
}
