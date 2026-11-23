import SwiftUI
import SwiftData
import CoreData
import BinisoftKit
import NinaCore

/// The watch app syncs on its own through the app's iCloud container (same store code as the phone)
/// and feeds the complications through the watch's App Group snapshot. The iPhone also sends its
/// snapshot device to device (`WatchPhoneLink`), so the face follows what is logged on the iPhone
/// or the Mac while this app isn't running.
@main
struct NinaWatchApp: App {
    @State private var model: WatchModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppLog.bootstrap(appName: AppInfo.name)
        let opened = Persistence.shared
        _model = State(initialValue: WatchModel(container: opened.container))
        WatchPhoneLink.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.becameActive() }
            }
        }
        .modelContainer(model.container)
        // The iPhone's snapshot arrived while the app wasn't running: write it for the face, then
        // the system suspends the app again.
        .backgroundTask(.watchConnectivity) {
            await WatchPhoneLink.finishPendingTransfers()
        }
    }
}

/// State for the watch: settings, the food library and logging with haptics and a short Undo.
/// Plans are made on the iPhone, iPad or Mac (they reach the watch through iCloud), so the watch
/// never creates planned meals itself.
@MainActor
@Observable
final class WatchModel {
    let container: ModelContainer
    /// The foods for the Log screen: built the first time it opens (`prepareLibrary`), not at
    /// launch – the home screen doesn't need it.
    private(set) var library: FoodLibrary? = nil
    private(set) var settings: NinaSettings
    /// The day the home screen shows: set on every refresh, so it moves on to a new day when the
    /// app comes back after midnight (settings alone don't change then).
    private(set) var homeDay: DayKey
    /// Bumped on every refresh: the coach on the home screen reloads on it.
    private(set) var dataVersion = 0
    /// The last write the home screen offers to undo for a few seconds (`WatchModel+Coach`).
    var undo: WatchUndo?
    /// The Log screen is on screen: refreshes keep the library current right away.
    @ObservationIgnored var logIsVisible = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// A change came from iCloud since the last refresh (its snapshot isn't written yet).
    @ObservationIgnored private var pendingRemote = false
    @ObservationIgnored private var libraryIsStale = false
    @ObservationIgnored private var isPreparingLibrary = false

    init(container: ModelContainer) {
        self.container = container
        let settings = NinaStore(context: container.mainContext).settings
        self.settings = settings
        homeDay = settings.today()
        // A save on the watch: its snapshot is already written (NinaStore.save); the rest follows
        // after the tap.
        observers.append(NotificationCenter.default.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                WatchLinkLocalChange.record()
                self?.scheduleRefresh(remote: false)
            }
        })
        // Changes from the iPhone, iPad or Mac arriving through iCloud while the app runs: new
        // targets, day types, plans, and the numbers for the face.
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(remote: true) }
        })
    }

    var store: NinaStore { NinaStore(context: container.mainContext) }
    var today: DayKey { settings.today() }

    // MARK: Refresh

    /// Coalesces saves and imports into one refresh, after the tap that caused it.
    func scheduleRefresh(remote: Bool) {
        if remote { pendingRemote = true }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(remote ? 600 : 150))
            guard !Task.isCancelled, let self else { return }
            let publish = self.pendingRemote
            self.pendingRemote = false
            self.refresh(publish: publish)
        }
    }

    /// The app came to the front: a new day may have started.
    func becameActive() {
        refreshTask?.cancel()
        pendingRemote = false
        refresh(publish: true)
    }

    /// Settings, the coach (`dataVersion`), the library when the Log screen needs it, and – after
    /// an import or at activation – the complications' snapshot.
    func refresh(publish: Bool = true) {
        let store = self.store
        let newSettings = store.settings
        if newSettings != settings { settings = newSettings }
        let day = newSettings.today()
        if day != homeDay { homeDay = day }
        dataVersion += 1
        if library != nil {
            if logIsVisible { rebuildLibrary() } else { libraryIsStale = true }
        }
        if publish { publishSnapshot(store: store) }
    }

    /// The complications' snapshot from this watch's store – unless the iPhone sent fresher numbers
    /// and this store hasn't caught up with them yet (`WatchSnapshotRelay.acceptsOwn`).
    private func publishSnapshot(store: NinaStore) {
        let snapshot = store.todaySnapshot(activityBonus: 0)
        guard let day = DayKey(snapshot.day) else { return }
        let freshness = store.watchLinkFreshness(on: day)
        guard WatchSnapshotRelay.acceptsOwn(day: snapshot.day, freshness: freshness, phone: WatchPhoneLink.lastPhoneMark) else { return }
        WidgetBridge.publish(snapshot)
    }

    // MARK: Food library

    /// The Log screen appeared: builds the library the first time (the bundled catalog is decoded
    /// off the main thread first), or brings it up to date.
    func prepareLibrary() async {
        if library != nil {
            if libraryIsStale { rebuildLibrary() }
            return
        }
        guard !isPreparingLibrary else { return }
        isPreparingLibrary = true
        await Task.detached(priority: .userInitiated) {
            _ = FoodCatalog.bundled.foods.count
        }.value
        let made = FoodLibrary()
        made.rebuild(context: container.mainContext, language: settings.language)
        library = made
        libraryIsStale = false
        isPreparingLibrary = false
    }

    private func rebuildLibrary() {
        library?.rebuild(context: container.mainContext, language: settings.language)
        libraryIsStale = false
    }

    // MARK: Logging (each with a short Undo)

    func log(_ record: FoodRecord, amount: AmountText, meal: String) {
        let entry = store.log(record, amount: amount, day: today, meal: meal, source: "watch", language: settings.language)
        WKHaptics.success()
        offerAdded([entry], name: entry.displayName)
    }

    func logMatches(_ matches: [QuickMatch], meal: String) {
        let store = self.store
        let day = today
        let group = matches.count > 1 ? UUID().uuidString : ""
        var created: [LogEntry] = []
        for match in matches where match.isResolved {
            if match.item.isEnergyOnly {
                created.append(store.logQuick(name: match.item.query.isEmpty ? "Quick entry" : match.item.query, nutrients: match.nutrients,
                                              day: day, meal: meal, source: "watch"))
            } else if let food = match.food, let amount = match.amountText {
                created.append(store.log(food, amount: amount, day: day, meal: meal, source: "watch", language: settings.language,
                                         groupID: group, saveNow: false))
            }
        }
        store.save()
        WKHaptics.success()
        guard !created.isEmpty else { return }
        offerAdded(created, name: created.count == 1 ? created[0].displayName : "\(created.count) foods")
    }

    func logRecipe(_ recipe: Recipe, meal: String) {
        let entries = store.logRecipe(recipe, day: today, meal: meal, source: "watch", language: settings.language)
        WKHaptics.success()
        offerAdded(entries, name: recipe.displayName)
    }

    func addWater(_ milliliters: Double) {
        let log = store.addWater(milliliters, day: today)
        WKHaptics.click()
        offerUndo("+\(Fmt.milliliters(milliliters)) water", symbol: "drop.fill") { [weak self] in
            self?.store.purge([log])
        }
    }

    func quick(_ kilocalories: Double, meal: String) {
        let entry = store.logQuick(name: "Quick entry", nutrients: NutrientValues([.energy: kilocalories, .protein: 0, .carbs: 0, .fat: 0]),
                                   day: today, meal: meal, source: "watch")
        WKHaptics.success()
        offerAdded([entry], name: entry.displayName)
    }

    /// A meal's planned foods → eaten in one tap; Undo makes them planned again at their times.
    func confirm(_ entries: [LogEntry]) {
        let planned = entries.filter { !$0.isEaten }
        guard !planned.isEmpty else { return }
        let times: [(entry: LogEntry, time: Date)] = planned.map { (entry: $0, time: $0.time) }
        store.confirm(planned)
        WKHaptics.success()
        let energy = planned.map(\.energy).reduce(0, +)
        offerUndo("Eaten · \(Fmt.energy(energy, unit: settings.energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            guard let self else { return }
            for item in times { item.entry.time = item.time }
            self.store.setStatus(planned, .planned)
        }
    }

    /// Swipe to delete: to Recently Deleted, with Undo.
    func delete(_ entry: LogEntry) {
        let name = entry.displayName
        let trashed = store.trash([entry])
        WKHaptics.click()
        offerUndo("Deleted \u{201C}\(name)\u{201D}", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    /// "Added Skyr · 180 kcal"; Undo deletes what was just added.
    private func offerAdded(_ entries: [LogEntry], name: String) {
        let energy = entries.map(\.energy).reduce(0, +)
        offerUndo("Added \(name) · \(Fmt.energy(energy, unit: settings.energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            self?.store.purge(entries)
        }
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
