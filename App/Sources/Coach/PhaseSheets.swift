import SwiftUI
import BinisoftKit
import NinaCore

// Stubs with the final names and initializers; the checkin module replaces the bodies.

/// A phase of the plan (`AppSheet.phase`): nil adds a new phase. Owns its NavigationStack and
/// `.sheetFrame`.
struct PhaseSheet: View {
    let phaseID: String?

    var body: some View {
        PhasePlaceholder(title: phaseID == nil ? "New Phase" : "Phase", symbol: "flag")
    }
}

/// The review of a phase at its checkpoint or a ceiling (`AppSheet.phaseReview`). Owns its
/// NavigationStack and `.sheetFrame`.
struct PhaseReviewSheet: View {
    let phaseID: String

    var body: some View {
        PhasePlaceholder(title: "Review", symbol: "flag.checkered")
    }
}

private struct PhasePlaceholder: View {
    let title: String
    let symbol: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbol, description: Text("Not ready yet."))
                .navigationTitle(title)
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
        .sheetFrame(minWidth: 520, minHeight: 600)
    }
}
