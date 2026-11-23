#if os(macOS)
import AppKit
import Observation
import SwiftUI
import BinisoftKit
import NinaCore

// Nina in the Mac's menu bar: the icon with "1,234 left" next to it, and a menu with today's
// calories, protein and water, a glass of water, Log Food…, Weigh In…, Open Nina and Settings… –
// also while Nina is in the background. Settings → Menu Bar turns it off (this Mac only, on by
// default); ⌘-dragging it out of the menu bar turns the switch off too.
//
// An AppKit status item (`NinaMenuBarController`), not a SwiftUI `MenuBarExtra` scene: with that
// scene in the app, macOS finished launching without the main window (and the reopen event of
// `MainWindowGuard` didn't open one either). The app's scenes stay the main window and Settings.
//
// It always shows and acts on the real diary's today (never the tour's practice page). Log Food…
// and Weigh In… bring the main window forward first (MainWindow.swift) – opened again after ⌘W –
// and open the sheet there; a sheet or the tour that is already open stays, so nothing half-filled
// is replaced. Adding water doesn't bring Nina forward.

/// The switches and the numbers behind the menu bar item.
enum NinaMenuBar {
    /// "Show in menu bar" (UserDefaults, this Mac only).
    static let showKey = "nina.mac.menuBar"
    /// "Calories left next to the icon" (UserDefaults, this Mac only).
    static let titleKey = "nina.mac.menuBar.title"
    static let symbol = "fork.knife"

    /// Today's numbers. The same sum as Today's ring (TodayView `progress`), so both always say
    /// the same.
    @MainActor
    static func summary(_ app: AppModel) -> NinaMenuBarSummary {
        let day = app.today
        let settings = app.settings
        let store = app.store
        let water: Double = store.water(on: day).map(\.amount).reduce(0, +)
        let totals = DayTotals(day: day, entries: store.entries(on: day).map(\.facts), water: water)
        // Read live like Today does (never stored); the Mac has no Apple Health, so this is 0 there.
        let bonus: Double = app.health.activeEnergyToday * settings.activityBonusShare
        let progress = DayProgress(totals: totals, targets: settings.targets(for: day), activityBonus: bonus)
        return NinaMenuBarSummary(progress: progress, emoji: settings.todayCoachEmoji(for: day))
    }
}

/// The menu bar item: an `NSStatusItem` with the icon and the calories left, and its menu, built
/// again each time it opens. Started once from `NinaApp.init`; the item itself is made once
/// launching is done, so it never stands in the way of the main window. The title follows the
/// data (`AppModel.dataVersion`, the day, the settings) and the two switches in Settings.
@MainActor
final class NinaMenuBarController: NSObject, NSMenuDelegate {
    static let shared = NinaMenuBarController()

    /// The two switches in Settings → Menu Bar.
    private struct Switches: Equatable {
        var shows: Bool
        var showsTitle: Bool

        static var current: Switches {
            let defaults = UserDefaults.standard
            return Switches(shows: defaults.object(forKey: NinaMenuBar.showKey) as? Bool ?? true,
                            showsTitle: defaults.object(forKey: NinaMenuBar.titleKey) as? Bool ?? true)
        }
    }

    private var app: AppModel?
    private var item: NSStatusItem?
    private var switches = Switches(shows: true, showsTitle: true)
    private var visibility: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var updateQueued = false

    /// Where the item sits in the menu bar (and whether macOS shows it) is remembered under this.
    private static let autosaveName = "nina.menuBar"

    func start(app: AppModel) {
        guard self.app == nil else { return }
        self.app = app
        if NSRunningApplication.current.isFinishedLaunching {
            install()
            return
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            // A turn later: the main window comes first.
            Task { @MainActor [weak self] in self?.install() }
        })
    }

    private func install() {
        guard app != nil else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        // The switches in Settings (any change of the defaults; only these two count).
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.switchesMayHaveChanged() }
        })
        observeData()
        update()
    }

    // MARK: Updating

    /// Calls `setNeedsUpdate` once when the numbers behind the title may have changed: every
    /// refresh grows `dataVersion`; the day and the settings move with it.
    private func observeData() {
        guard let app else { return }
        withObservationTracking {
            _ = app.dataVersion
            _ = app.today
            _ = app.settings
            _ = app.health.activeEnergyToday
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeData()
                self.setNeedsUpdate()
            }
        }
    }

    private func switchesMayHaveChanged() {
        guard Switches.current != switches else { return }
        setNeedsUpdate()
    }

    /// One update for a burst of changes.
    private func setNeedsUpdate() {
        guard !updateQueued else { return }
        updateQueued = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateQueued = false
            self.update()
        }
    }

    /// Shows or removes the item and sets its title.
    private func update() {
        guard let app else { return }
        switches = Switches.current
        guard switches.shows else {
            removeItem()
            return
        }
        let item = self.item ?? makeItem()
        guard let button = item.button else { return }
        let summary = NinaMenuBar.summary(app)
        let title = switches.showsTitle ? summary.title : ""
        if button.title != title { button.title = title }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(summary.accessibilityLabel(appName: AppInfo.name))
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        // ⌘-drag out of the menu bar: allowed, and it turns the switch off (`removedByUser`).
        item.behavior = .removalAllowed
        if !item.isVisible { item.isVisible = true }
        if let button = item.button {
            let image = NSImage(systemSymbolName: NinaMenuBar.symbol, accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        visibility = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor [weak self] in self?.removedByUser() }
        }
        self.item = item
        return item
    }

    private func removeItem() {
        visibility?.invalidate()
        visibility = nil
        guard let item else { return }
        self.item = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    /// ⌘-dragged out of the menu bar: Settings → Menu Bar → "Show in menu bar" goes off.
    private func removedByUser() {
        guard let item, !item.isVisible else { return }
        AppLog.info("Menu bar item removed – switching it off", category: "app")
        UserDefaults.standard.set(false, forKey: NinaMenuBar.showKey)
        update()
    }

    // MARK: The menu

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { self.rebuild(menu) }
    }

    /// Today's numbers (grey, not clickable), then the actions.
    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }
        let summary = NinaMenuBar.summary(app)
        for line in [summary.energyLine, summary.proteinLine, summary.waterLine] {
            let row = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Add a Glass of Water (\(Fmt.milliliters(app.settings.waterGlass)))", #selector(addGlassOfWater)))
        menu.addItem(actionItem("Log Food…", #selector(logFood)))
        menu.addItem(actionItem("Weigh In…", #selector(weighIn)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionItem("Open \(AppInfo.name)", #selector(openNina)))
        menu.addItem(actionItem("Settings…", #selector(showSettings)))
        // The title says the same as the menu.
        update()
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.isEnabled = true
        return menuItem
    }

    /// One glass on today, with the usual toast (and its Undo) in the main window.
    @objc private func addGlassOfWater() {
        guard let app else { return }
        app.addWater(app.settings.waterGlass, day: app.today)
    }

    @objc private func logFood() {
        guard let app else { return }
        present(.addFood(day: app.today, meal: app.settings.suggestedMeal().id), in: app)
    }

    @objc private func weighIn() {
        guard let app else { return }
        present(.weight(nil), in: app)
    }

    @objc private func openNina() {
        MainWindow.bringForward()
    }

    /// The Settings window (⌘,): in front when it is open, else through the app menu's Settings…
    /// item, the way ⌘, opens it.
    @objc private func showSettings() {
        NSApp.activate()
        if let window = MainWindow.settingsWindow, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let settingsItem = Self.settingsMenuItem(), let appMenu = settingsItem.menu {
            let index = appMenu.index(of: settingsItem)
            if index >= 0 {
                appMenu.performActionForItem(at: index)
                return
            }
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// The app menu's Settings… (⌘,), which SwiftUI's Settings scene adds.
    private static func settingsMenuItem() -> NSMenuItem? {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return nil }
        return appMenu.items.first { candidate in
            candidate.keyEquivalent == "," && candidate.keyEquivalentModifierMask.contains(.command) && candidate.action != nil
        }
    }

    /// The main window comes forward and shows the sheet; one that is already open (or the tour)
    /// stays in front instead.
    private func present(_ sheet: AppSheet, in app: AppModel) {
        MainWindow.bringForward()
        guard app.sheet == nil, app.tour == nil else { return }
        app.sheet = sheet
    }
}

/// Settings → Menu Bar (the Mac's Settings window, General): the menu bar item on or off, and the
/// calories next to its icon. This Mac only. `NinaMenuBarController` follows both switches.
struct NinaMenuBarSettingsSection: View {
    @AppStorage(NinaMenuBar.showKey) private var showsMenuBar = true
    @AppStorage(NinaMenuBar.titleKey) private var showsTitle = true

    var body: some View {
        Section {
            Toggle(isOn: $showsMenuBar) {
                Label("Show in menu bar", systemImage: "menubar.rectangle")
            }
            if showsMenuBar {
                Toggle("Calories left next to the icon", isOn: $showsTitle)
            }
        } header: {
            Text("Menu Bar")
                .info(SettingsInfo.menuBar.title, SettingsInfo.menuBar.text)
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        "Calories, protein and water today, a glass of water, Log Food… and Weigh In… right from the menu bar – also while \(AppInfo.name) is in the background. This Mac only."
    }
}
#endif
