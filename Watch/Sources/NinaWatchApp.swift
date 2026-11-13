import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The watch app syncs on its own through the app's iCloud container (same store code as the phone)
/// and feeds the complications through the watch's App Group snapshot.
@main
struct NinaWatchApp: App {
    @State private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLog.bootstrap(appName: AppInfo.name)
        let opened = Persistence.shared
        _model = State(initialValue: WatchModel(container: opened.container))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.refresh() }
            }
        }
        .modelContainer(model.container)
    }
}

/// State for the watch: settings, the food library and logging with haptics.
@MainActor
@Observable
final class WatchModel {
    let container: ModelContainer
    let library = FoodLibrary()
    private(set) var settings: NinaSettings
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(container: ModelContainer) {
        self.container = container
        let store = NinaStore(context: container.mainContext)
        settings = store.settings
        library.rebuild(context: container.mainContext, language: settings.language)
        observer = NotificationCenter.default.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if !LaunchOptions.current.isDemo {
            store.materializePlans(today: settings.today(), horizon: 2)
        }
    }

    var store: NinaStore { NinaStore(context: container.mainContext) }
    var today: DayKey { settings.today() }

    func refresh() {
        settings = store.settings
        library.rebuild(context: container.mainContext, language: settings.language)
        WidgetBridge.publish(store.todaySnapshot(activityBonus: 0))
    }

    func log(_ record: FoodRecord, amount: AmountText, meal: String) {
        store.log(record, amount: amount, day: today, meal: meal, source: "watch", language: settings.language)
        WKHaptics.success()
    }

    func logMatches(_ matches: [QuickMatch], meal: String) {
        for match in matches where match.isResolved {
            if match.item.isEnergyOnly {
                store.logQuick(name: match.item.query.isEmpty ? "Quick entry" : match.item.query, nutrients: match.nutrients,
                               day: today, meal: meal, source: "watch")
            } else if let food = match.food, let amount = match.amountText {
                store.log(food, amount: amount, day: today, meal: meal, source: "watch", language: settings.language, saveNow: false)
            }
        }
        store.save()
        WKHaptics.success()
    }

    func logRecipe(_ recipe: Recipe, meal: String) {
        store.logRecipe(recipe, day: today, meal: meal, source: "watch", language: settings.language)
        WKHaptics.success()
    }

    func addWater(_ milliliters: Double) {
        store.addWater(milliliters, day: today)
        WKHaptics.click()
    }

    func quick(_ kilocalories: Double, meal: String) {
        store.logQuick(name: "Quick entry", nutrients: NutrientValues([.energy: kilocalories, .protein: 0, .carbs: 0, .fat: 0]),
                       day: today, meal: meal, source: "watch")
        WKHaptics.success()
    }
}

/// Haptics without importing WatchKit everywhere.
enum WKHaptics {
    static func success() {
        WatchHaptics.play(.success)
    }

    static func click() {
        WatchHaptics.play(.click)
    }
}
