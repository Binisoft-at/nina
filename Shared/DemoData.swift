import Foundation
import SwiftData

/// Sample data. It lives only in separate in-memory stores (`-Demo` launches for screenshots, the
/// tour's practice page) and never syncs.
@MainActor
enum DemoData {
    /// `-Demo` launches: a realistic list for screenshots.
    static func seed(_ context: ModelContext) {
        let store = ItemStore(context: context)
        let home = store.addFolder(name: "Home")
        let work = store.addFolder(name: "Work")
        store.addItem(title: "Water the plants", folder: home)
        store.addItem(title: "Send the invoice", notes: "Before Friday", folder: work)
        store.addItem(title: "Prepare slides for Monday", folder: work)
        store.addItem(title: "Call grandma")
        store.addItem(title: "Buy flowers", folder: home)
        let done = store.addItem(title: "Book the dentist")
        store.setDone([done], true)
    }

    /// The tour's practice page. Tour steps refer to these items.
    static func seedPractice(_ context: ModelContext) {
        let store = ItemStore(context: context)
        let weekend = store.addFolder(name: "Weekend")
        store.addItem(title: "Water the plants")
        store.addItem(title: "Reply to Anna's email")
        store.addItem(title: "Plan a hike", notes: "Check the weather first", folder: weekend)
        store.addItem(title: "Buy flowers", folder: weekend)
    }
}
