import Foundation
import BinisoftKitCore

/// What the tour's practice page looks like right now (built from the demo store after every change).
public struct NinaTourSnapshot: Equatable, Sendable {
    public var itemCount = 0
    public var doneCount = 0
    public var trashedCount = 0
    public var folderCount = 0
    /// Open item ids in list order.
    public var order: [String] = []
    public var isCreateOpen = false
    public var isEditorOpen = false

    public init() {}
}

/// Nina's interactive tour. To teach a new feature: add a step with `since: version + 1` and
/// bump `version`. People who already took the tour then get just the new steps as "What's new".
/// `swift test` checks the catalog.
public enum NinaTour {
    public static let version = 1

    public static let catalog = TourCatalog<NinaTourSnapshot>.standard(
        appName: "Nina",
        version: version,
        practiceNoun: "items",
        replayHint: "Settings or Help → Nina Tour",
        steps: [
            TourStep(
                id: "create", symbol: "plus.circle", title: "Everything starts at +",
                body: "Tap + at the top. It's the one place to create anything – and to import the data you already have.",
                macBody: "Click + in the toolbar or press ⇧⌘N. It's the one place to create anything – and to import the data you already have.",
                goal: .isTrue(\.isCreateOpen)
            ),
            TourStep(
                id: "add", symbol: "square.and.pencil", title: "Add an item",
                body: "In the + sheet tap New Item, type a title and tap Save.",
                macBody: "Press ⌘N, type a title and press Return.",
                goal: .increased(\.itemCount)
            ),
            TourStep(
                id: "done", symbol: "checkmark.circle", title: "Check it off",
                body: "Tap the circle next to an item, or swipe right. Done items move to the Done tab.",
                macBody: "Click the circle next to an item. Done items move to Done in the sidebar.",
                goal: .increased(\.doneCount)
            ),
            TourStep(
                id: "undo", symbol: "arrow.uturn.backward", title: "Mistakes are fine",
                body: "Swipe left on an item and tap Delete, then tap Undo in the message that pops up. Shaking your iPhone undoes the last change too.",
                macBody: "Right-click an item and choose Delete, then click Undo in the message – or press ⌘Z.",
                goal: .undone(\.trashedCount)
            ),
            TourStep(
                id: "reorder", symbol: "arrow.up.arrow.down", title: "Your order",
                body: "Touch and hold an item, then drag it up or down.",
                macBody: "Drag an item up or down.",
                goal: .changed(\.order)
            ),
            TourStep(
                id: "edit", symbol: "info.circle", title: "Everything else",
                body: "Tap an item to edit its title, notes and folder.",
                macBody: "Click an item (or right-click → Edit) for its title, notes and folder.",
                goal: .isTrue(\.isEditorOpen)
            ),
            TourStep(
                id: "everywhere", symbol: "applewatch", title: "Everywhere you are",
                body: "Nina syncs through your iCloud with your Mac and Apple Watch. The widget shows what's next. Settings shows the sync status and where your data lives.",
                macBody: "Nina syncs through your iCloud with your iPhone and Apple Watch. Settings (⌘,) shows the sync status and where your data lives.",
                goal: .none
            ),
        ]
    )
}
