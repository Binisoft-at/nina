import SwiftUI
import SwiftData
import BinisoftKit
#if os(macOS)
import AppKit
#endif

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
        #if os(macOS)
        // One window: no tab bar (and no tab "+" that would open a second window on the same state).
        NSWindow.allowsAutomaticWindowTabbing = false
        // Which window is key (toasts), and the main window when Nina becomes active without one.
        MacWindowState.shared.start()
        #endif
        let opened = Persistence.shared
        let model = AppModel(container: opened.container, mode: opened.mode)
        _app = State(initialValue: model)
        #if os(macOS)
        // Nina in the menu bar (MenuBar.swift): an AppKit status item, set up once launching is
        // done. Not a SwiftUI MenuBarExtra scene – with one, macOS didn't open the main window.
        NinaMenuBarController.shared.start(app: model)
        #endif
    }

    var body: some Scene {
        // One main window: every window would share AppModel's sheet, tour and sidebar, so CSV
        // files and nina:// links go to the open window (a new one only when none is open). iPad
        // runs one scene (UIApplicationSupportsMultipleScenes is off).
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
        .handlesExternalEvents(matching: ["*"])
        .commands {
            NinaCommands(app: app)
        }

        #if os(macOS)
        // Settings window: General, and the plan editor as its own "My Plan" tab
        // (SettingsWindowContent in MainWindow.swift: its own toasts and Import & Export sheet).
        Settings {
            SettingsWindowContent()
                .environment(app)
                .modelContainer(app.container)
                .appearanceFromSettings()
                .frame(minWidth: 580, minHeight: 520)
        }
        #endif
    }
}
