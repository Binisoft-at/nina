#if os(macOS)
import SwiftUI
import BinisoftKit
import NinaCore

// Nina in the Mac's menu bar (NinaApp's MenuBarExtra): the icon with "1,234 left" next to it, and
// a menu with today's calories, protein and water, a glass of water, Log Food…, Weigh In… and
// Open Nina – also while Nina is in the background. Settings → Menu Bar turns it off (this Mac
// only, on by default); ⌘-dragging it out of the menu bar turns the switch off too.
//
// It always shows and acts on the real diary's today (never the tour's practice page). Log Food…
// and Weigh In… bring the main window forward first (MainWindow.swift) – opened again after ⌘W –
// and open the sheet there; a sheet or the tour that is already open stays, so nothing half-filled
// is replaced. Adding water doesn't bring Nina forward.

/// The switches and the numbers behind the menu bar extra.
enum NinaMenuBar {
    /// "Show in menu bar" (UserDefaults, this Mac only).
    static let showKey = "nina.mac.menuBar"
    /// "Calories left next to the icon" (UserDefaults, this Mac only).
    static let titleKey = "nina.mac.menuBar.title"
    static let symbol = "fork.knife"

    /// Today's numbers, read again whenever data, the day or the settings change (the views read
    /// `dataVersion`, `today` and `settings` through this). The same sum as Today's ring
    /// (TodayView `progress`), so both always say the same.
    @MainActor
    static func summary(_ app: AppModel) -> NinaMenuBarSummary {
        _ = app.dataVersion
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

/// The menu bar icon, with the calories left next to it unless that is switched off.
struct NinaMenuBarLabel: View {
    let app: AppModel
    @AppStorage(NinaMenuBar.titleKey) private var showsTitle = true

    var body: some View {
        let summary = NinaMenuBar.summary(app)
        Image(systemName: NinaMenuBar.symbol)
            .accessibilityLabel(summary.accessibilityLabel(appName: AppInfo.name))
        if showsTitle {
            Text(summary.title)
        }
    }
}

/// The menu: today's numbers, then the quick actions.
struct NinaMenuBarMenu: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let summary = NinaMenuBar.summary(app)
        Text(summary.energyLine)
        Text(summary.proteinLine)
        Text(summary.waterLine)
        Divider()
        Button(waterTitle, action: addWater)
        Button("Log Food…", action: logFood)
        Button("Weigh In…", action: weighIn)
        Divider()
        Button("Open \(AppInfo.name)", action: openNina)
    }

    private var waterTitle: String {
        "Add a Glass of Water (\(Fmt.milliliters(app.settings.waterGlass)))"
    }

    /// One glass on today, with the usual toast (and its Undo) in the main window.
    private func addWater() {
        app.addWater(app.settings.waterGlass, day: app.today)
    }

    private func logFood() {
        present(.addFood(day: app.today, meal: app.settings.suggestedMeal().id))
    }

    private func weighIn() {
        present(.weight(nil))
    }

    private func openNina() {
        MainWindow.bringForward(openWindow: openWindow)
    }

    /// The main window comes forward and shows the sheet; one that is already open (or the tour)
    /// stays in front instead.
    private func present(_ sheet: AppSheet) {
        MainWindow.bringForward(openWindow: openWindow)
        guard app.sheet == nil, app.tour == nil else { return }
        app.sheet = sheet
    }
}

/// Settings → Menu Bar (the Mac's Settings window, General): the menu bar extra on or off, and the
/// calories next to its icon. This Mac only.
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
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        "Calories, protein and water today, a glass of water, Log Food… and Weigh In… right from the menu bar – also while \(AppInfo.name) is in the background. This Mac only."
    }
}
#endif
