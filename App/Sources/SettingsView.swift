import SwiftUI
import BinisoftKit

/// Settings: appearance, help (tour, hints), iCloud & data, import/export, the app log, version.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var hintsReset = false

    var body: some View {
        Form {
            Section("Appearance") {
                AppearancePicker()
            }

            Section {
                Button("Replay the Tour", systemImage: "graduationcap") { app.startTour() }
                Button(hintsReset ? "Hints Come Back at the Next Launch" : "Show Hints Again", systemImage: "lightbulb") {
                    BinisoftTips.requestReset()
                    hintsReset = true
                }
                .disabled(hintsReset)
            } header: {
                Text("Help")
            } footer: {
                Text("The tour runs on a practice page, so nothing you do there touches your items.")
            }

            SyncStatusSection(
                monitor: app.sync,
                footer: "\(AppInfo.name) has no servers or accounts. Your \(AppInfo.dataNoun) sync through your own private iCloud between iPhone, iPad, Mac and Apple Watch."
            ) {
                DataLocationView(sections: DataSection.standard(appName: AppInfo.name, dataNoun: AppInfo.dataNoun),
                                 monitor: app.sync)
            }

            Section("Your data") {
                Button("Import & Export…", systemImage: "square.and.arrow.up.on.square") { app.sheet = .importData }
            }

            Section {
                NavigationLink {
                    LogView(appName: AppInfo.name, mode: app.mode)
                } label: {
                    Label("App Log", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("If something doesn't work: App Log → Copy log, and paste it into the chat.")
            }

            Section("About") {
                LabeledContent("Version", value: AppVersion.main.display)
                LabeledContent("Storage", value: app.mode.title)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }
}
