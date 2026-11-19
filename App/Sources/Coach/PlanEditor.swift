import SwiftUI
import BinisoftKit
import NinaCore

/// The plan editor, Settings → "Goals & Plan" (F15). No NavigationStack of its own: it is pushed
/// from Settings, shown in the Mac Settings window, and wrapped in one for `AppSheet.plan`.
/// `showsDone`: a Done button (as a sheet). Stub; the plan module replaces the body.
struct PlanEditorView: View {
    let showsDone: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Your plan: phases, day types, daily checks and measuring.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Goals & Plan")
        .inlineNavigationTitle()
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
