import SwiftUI
import BinisoftKit
import NinaCore

/// The weekly check-in of the week starting on `week` (a Monday) (`AppSheet.checkIn`). Owns its
/// NavigationStack and `.sheetFrame`. Stub; the checkin module replaces the body.
struct CheckInSheet: View {
    let week: DayKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Weekly Check-in", systemImage: "checklist", description: Text("Not ready yet."))
                .navigationTitle("Check-in")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
        .sheetFrame(minWidth: 520, minHeight: 640)
    }
}
