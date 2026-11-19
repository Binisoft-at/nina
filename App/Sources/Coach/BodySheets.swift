import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

// Stubs with the final names and initializers; the sheets module replaces the bodies.

/// The weigh-in sheet (`AppSheet.weight`): nil logs a new weigh-in, an entry edits it. Owns its
/// NavigationStack and `.sheetFrame`. Reads and clears `app.pendingWeighIn` (a value from
/// nina://weigh that needs a look). Stub: the old weight editor.
struct WeighInSheet: View {
    let entry: WeightEntry?

    var body: some View {
        WeightEditor(entry: entry)
    }
}

/// Tape measurements (`AppSheet.measure`): the weekly sites or the full set; a record edits it.
/// Owns its NavigationStack and `.sheetFrame`.
struct MeasureSheet: View {
    let mode: MeasureMode
    let record: BodyMeasurement?

    var body: some View {
        BodySheetPlaceholder(title: mode == .full ? "Full Measurement" : "Measurements", symbol: "ruler")
    }
}

/// A body-fat assessment (`AppSheet.assessment`); a record edits it. Owns its NavigationStack
/// and `.sheetFrame`.
struct AssessmentSheet: View {
    let record: BodyMeasurement?

    var body: some View {
        BodySheetPlaceholder(title: "Body Fat", symbol: "percent")
    }
}

private struct BodySheetPlaceholder: View {
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
        .sheetFrame(minWidth: 460, minHeight: 520)
    }
}
