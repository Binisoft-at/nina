import SwiftUI
import SwiftData
import BinisoftKit

@main
struct NinaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MainWindowGuard.self) private var windowGuard
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var app: AppModel

    init() {
        AppLog.bootstrap(appName: AppInfo.name)
        BinisoftTips.configure()
        NotificationScheduler.shared.activate()
        let opened = Persistence.shared
        _app = State(initialValue: AppModel(container: opened.container, mode: opened.mode))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .modelContainer(app.container)
                .appearanceFromSettings()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.becameActive() }
                }
        }
        .defaultSize(width: 1120, height: 780)
        #if os(macOS)
        // macOS may otherwise finish launching without the main window (see MainWindowGuard).
        .defaultLaunchBehavior(.presented)
        #endif
        .commands {
            NinaCommands(app: app)
        }

        #if os(macOS)
        // Settings window: General, and the plan editor as its own "My Plan" tab (the plan
        // editor and Goals show their own toasts, so changes made here can be undone here).
        Settings {
            TabView {
                Tab("General", systemImage: "gearshape") {
                    NavigationStack {
                        SettingsView()
                    }
                }
                Tab("My Plan", systemImage: "list.bullet.clipboard") {
                    NavigationStack {
                        PlanEditorView(showsDone: false)
                    }
                }
            }
            .environment(app)
            .modelContainer(app.container)
            .appearanceFromSettings()
            .frame(minWidth: 580, minHeight: 680)
        }
        #endif
    }
}
