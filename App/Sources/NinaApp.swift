import SwiftUI
import SwiftData
import BinisoftKit

@main
struct NinaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MainWindowGuard.self) private var windowGuard
    #endif
    @State private var app: AppModel

    init() {
        AppLog.bootstrap(appName: AppInfo.name)
        BinisoftTips.configure()
        let opened = Persistence.open()
        _app = State(initialValue: AppModel(container: opened.container, mode: opened.mode))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .modelContainer(app.container)
                .appearanceFromSettings()
        }
        .defaultSize(width: 1000, height: 720)
        #if os(macOS)
        // macOS may otherwise finish launching without the main window (see MainWindowGuard).
        .defaultLaunchBehavior(.presented)
        #endif
        .commands {
            NinaCommands(app: app)
        }

        #if os(macOS)
        Settings {
            NavigationStack {
                SettingsView()
            }
            .environment(app)
            .modelContainer(app.container)
            .appearanceFromSettings()
            .frame(minWidth: 520, minHeight: 600)
        }
        #endif
    }
}

/// Menu bar commands and keyboard shortcuts (Mac, iPad with a keyboard). While the tour is
/// open they act on its practice page.
struct NinaCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Item") { app.commandTarget.sheet = .newItem(nil) }
                .keyboardShortcut("n")
            Button("Create…") { app.commandTarget.sheet = .create }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Folder…") { app.commandTarget.sheet = .newFolder }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Import My Data…") { app.commandTarget.sheet = .importData }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Items") { app.sidebar = .items; app.tab = .items }
                .keyboardShortcut("1")
            Button("Done") { app.sidebar = .done; app.tab = .done }
                .keyboardShortcut("2")
            Button("Recently Deleted") { app.sidebar = .trash; app.showTrash = true }
                .keyboardShortcut("3")
        }
        CommandGroup(replacing: .help) {
            Button("\(AppInfo.name) Tour") { app.startTour() }
        }
    }
}
