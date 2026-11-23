#if os(macOS)
import AppKit
import CoreServices
import SwiftUI
import BinisoftKit

// The Mac's windows. Sheets, the tour and the toasts show in the main window, so menu commands,
// the Settings window and notification clicks bring it forward first – un-minimized, or opened
// again after ⌘W. The Settings window shows the toasts while it is the key window; the main
// window's stay silent then, so a toast never shows twice.

/// The main window: found through the reader RootView carries, else by its scene id ("main-…").
@MainActor
enum MainWindow {
    /// RootView's window (weak: SwiftUI lets it go on ⌘W).
    static weak var window: NSWindow?
    /// The Settings window (⌘,).
    static weak var settingsWindow: NSWindow?
    /// The app menu's `openWindow` (Window → Nina hands it over): the menu is there with or
    /// without a window, so it opens the main window for callers without a view of their own –
    /// the menu bar item, Nina becoming active without a window.
    private static var appOpenWindow: OpenWindowAction?

    /// A main window that is still open: shown, minimized, or in a hidden app.
    static var existing: NSWindow? {
        var candidates: [NSWindow] = []
        if let window { candidates.append(window) }
        candidates += NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
        return candidates.first { $0.isVisible || $0.isMiniaturized }
    }

    /// Kept from the app menu (`NinaWindowCommand`).
    static func keepAppOpenWindow(_ openWindow: OpenWindowAction) {
        appOpenWindow = openWindow
    }

    /// Shows the main window in front and key, or opens a new one when it was closed. `openWindow`
    /// comes from the caller's environment; without one the app menu's is used, and should that
    /// not have opened the window a second later (or there is none yet), the app sends itself the
    /// Dock's "reopen" event, which makes SwiftUI open it (as `MainWindowGuard` does after launch).
    static func bringForward(openWindow: OpenWindowAction? = nil) {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate()
        if let window = existing {
            if window.isMiniaturized { window.deminiaturize(nil) }
            // Already in front (it, or a sheet or the tour on it, is key): the focus stays where it
            // is, e.g. in an editor's text field when ⌘1 or ⌃⌘W is pressed.
            if let key = NSApp.keyWindow, isOrIsOn(key, window) { return }
            var front = window
            while let sheet = front.attachedSheet { front = sheet }
            if front === window {
                window.makeKeyAndOrderFront(nil)
            } else {
                // A sheet is up: the window comes forward with it, and the sheet keeps the focus.
                window.orderFront(nil)
                front.makeKey()
            }
            return
        }
        if let openWindow {
            openWindow(id: "main")
        } else if let appOpenWindow {
            appOpenWindow(id: "main")
            reopenIfStillClosed()
        } else {
            sendReopenEvent()
        }
    }

    /// The app menu's action normally opens the window at once; if not, the reopen event does.
    private static func reopenIfStillClosed() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard MainWindow.existing == nil else { return }
            MainWindow.sendReopenEvent()
        }
    }

    /// The Settings window, or a sheet, popover or panel on it.
    static func belongsToSettings(_ window: NSWindow) -> Bool {
        var current: NSWindow? = window
        while let candidate = current {
            if let settingsWindow, candidate === settingsWindow { return true }
            if candidate.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true { return true }
            current = candidate.sheetParent ?? candidate.parent
        }
        return false
    }

    /// `window` is `owner`, or a sheet, popover or panel on it.
    private static func isOrIsOn(_ window: NSWindow, _ owner: NSWindow) -> Bool {
        var current: NSWindow? = window
        while let candidate = current {
            if candidate === owner { return true }
            current = candidate.sheetParent ?? candidate.parent
        }
        return false
    }

    private static func sendReopenEvent() {
        let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 2)
        } catch {
            AppLog.warning("Reopen event failed: \(error.localizedDescription)", category: "launch")
        }
    }
}

/// Which window is key (for the toasts), and the main window when Nina becomes active without
/// any window – e.g. a reminder clicked after ⌘W: its link waits for the window. Started once
/// from `NinaApp.init`.
@MainActor
@Observable
final class MacWindowState {
    static let shared = MacWindowState()

    /// The Settings window (or a sheet on it) is the key window: it shows the toasts.
    private(set) var settingsIsKey = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// When the app started: right after launch `MainWindowGuard` looks after the window.
    private let started = Date()

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
    }

    func update() {
        var isKey = false
        if let key = NSApp.keyWindow { isKey = MainWindow.belongsToSettings(key) }
        if isKey != settingsIsKey { settingsIsKey = isKey }
    }

    /// No window at all: open the main window. Right after launch `MainWindowGuard` does that,
    /// and a Dock click opens one by itself (hence the wait before looking).
    private func becameActive() {
        guard Date().timeIntervalSince(started) > 5 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard NSApp.isActive, !MainWindowGuard.hasVisibleWindow, MainWindow.existing == nil else { return }
            AppLog.info("Active without a window – opening the main window", category: "launch")
            MainWindow.bringForward()
        }
    }
}

/// Tells `MainWindow` which NSWindow a view is in (RootView: the main window; the Settings window).
struct NinaWindowReader: NSViewRepresentable {
    enum Role {
        case main, settings
    }

    let role: Role

    func makeNSView(context: Context) -> NinaWindowReaderView {
        NinaWindowReaderView(role: role)
    }

    func updateNSView(_ nsView: NinaWindowReaderView, context: Context) {}
}

/// An invisible view that reports its window once it is in one.
final class NinaWindowReaderView: NSView {
    let role: NinaWindowReader.Role

    init(role: NinaWindowReader.Role) {
        self.role = role
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        role = .main
        super.init(coder: coder)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        switch role {
        case .main: MainWindow.window = window
        case .settings: MainWindow.settingsWindow = window
        }
        MacWindowState.shared.update()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The Settings window (⌘,): General and My Plan as tabs. One toast host for the window, shown
/// while it is the key window; Import & Export opens here as its own sheet, and Replay the Tour
/// closes the window and starts the tour in the main window. A sheet opened from here (a phase in
/// My Plan …) shows in the main window, which comes forward – or opens again after ⌘W.
struct SettingsWindowContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var showsImport = false

    var body: some View {
        tabs
            .environment(\.settingsWindowActions, actions)
            .sheet(isPresented: $showsImport) {
                ImportView(initialKind: nil)
                    .sheetToasts(importToasts)
                    .environment(app)
                    .modelContainer(app.container)
            }
            .sheetToasts(windowToasts)
            .onChange(of: app.sheet?.id) { _, id in
                if id != nil { showMainWindow() }
            }
            .onChange(of: app.tour?.id) { _, id in
                if id != nil { showMainWindow() }
            }
            .background {
                NinaWindowReader(role: .settings)
                    .frame(width: 0, height: 0)
            }
    }

    private var tabs: some View {
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
    }

    /// Silent while the main window is key or the import sheet shows them.
    private var windowToasts: ToastCenter {
        MacWindowState.shared.settingsIsKey && !showsImport ? app.toasts : ToastCenter.silent
    }

    /// The import sheet's: silent while the main window is key (it shows them then).
    private var importToasts: ToastCenter {
        MacWindowState.shared.settingsIsKey ? app.toasts : ToastCenter.silent
    }

    /// The main window shows app sheets and the tour: in front when this window was key, opened
    /// again when it was closed (no RootView is there to notice the sheet then).
    private func showMainWindow() {
        guard MacWindowState.shared.settingsIsKey || MainWindow.existing == nil else { return }
        MainWindow.bringForward(openWindow: openWindow)
    }

    private var actions: SettingsWindowActions {
        SettingsWindowActions(
            importData: { showsImport = true },
            replayTour: { replayTour() }
        )
    }

    private func replayTour() {
        (MainWindow.settingsWindow ?? NSApp.keyWindow)?.close()
        MainWindow.bringForward(openWindow: openWindow)
        app.startTour()
    }
}
#endif
