import SwiftUI
import SwiftData
import CoreData
import BinisoftKit
import NinaCore

/// App-wide state shared by all windows: navigation, the selected day, the food library and the
/// actions that show a toast with Undo. The tour's practice page gets its own instance on its own
/// in-memory store (`isSandbox`), so nothing done there touches real data.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let mode: StorageMode
    let sync: SyncMonitor
    let toasts: ToastCenter
    let launch: LaunchOptions
    let isSandbox: Bool
    let library: FoodLibrary
    let health: HealthService

    private(set) var settings: NinaSettings
    var tab: AppTab = .today
    var sidebar: SidebarItem? = .today
    var selectedDay: DayKey
    var sheet: AppSheet?
    var tour: TourRequest?
    /// The practice page's model while the tour is open: menu commands act there.
    var tourModel: AppModel?
    /// A CSV opened from Files / "Open in" – the import sheet picks it up.
    var pendingImport: URL?
    /// iPhone: Recently Deleted is pushed from Settings.
    var showTrash = false
    /// Grows with every data change (views that compute from fetches refresh on it).
    private(set) var dataVersion = 0

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(container: ModelContainer, mode: StorageMode, launch: LaunchOptions = .current, isSandbox: Bool = false) {
        self.container = container
        self.mode = mode
        self.launch = launch
        self.isSandbox = isSandbox
        self.sync = SyncMonitor(mode: isSandbox ? .demo : mode, appName: AppInfo.name)
        self.toasts = ToastCenter()
        self.library = FoodLibrary()
        self.health = HealthService(enabled: !isSandbox && !launch.isDemo)
        let store = NinaStore(context: container.mainContext)
        let settings = store.settings
        self.settings = settings
        self.selectedDay = settings.today()
        library.rebuild(context: container.mainContext, language: settings.language)
        guard !isSandbox else {
            observeChanges(rebuildOnly: true)
            return
        }
        observeChanges(rebuildOnly: false)
        applyLaunchOptions()
        if !launch.isDemo {
            store.purgeExpired()
            store.materializePlans(today: settings.today())
        }
    }

    var store: NinaStore { NinaStore(context: container.mainContext) }
    var today: DayKey { settings.today() }
    var language: FoodLanguage { settings.language }
    var energyUnit: EnergyUnit { settings.energyUnit }

    /// Where menu commands act: the practice page during the tour, otherwise this model.
    var commandTarget: AppModel { tourModel ?? self }

    // MARK: Data changes

    private func observeChanges(rebuildOnly: Bool) {
        observers.append(NotificationCenter.default.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        guard !rebuildOnly else { return }
        // CloudKit imports from other devices.
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(remote: true) }
        })
    }

    /// Coalesces bursts of saves (an import, a meal of five foods) into one refresh.
    func scheduleRefresh(remote: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(remote ? 600 : 150))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
            if remote, !self.isSandbox {
                self.store.removeDuplicatePlans(from: self.today, through: self.today.adding(days: 3))
            }
        }
    }

    func refresh() {
        let store = self.store
        let newSettings = store.settings
        if newSettings != settings { settings = newSettings }
        library.rebuild(context: container.mainContext, language: settings.language)
        dataVersion += 1
        guard !isSandbox, !launch.isDemo else { return }
        WidgetBridge.publish(store.todaySnapshot())
        health.scheduleSync(container: container)
        NotificationScheduler.shared.reschedule(context: container.mainContext, settings: settings)
    }

    /// The app came to the foreground: a new day may have started, plans and Health need a look.
    func becameActive() {
        guard !isSandbox, !launch.isDemo else { return }
        let newToday = settings.today()
        if selectedDay < newToday, selectedDay == newToday.adding(days: -1) { selectedDay = newToday }
        store.materializePlans(today: newToday)
        Task { await health.refreshReadings() }
        refresh()
    }

    // MARK: Logging with Undo

    @discardableResult
    func log(_ record: FoodRecord, amount: AmountText, day: DayKey, meal: String, time: Date? = nil,
             status: EntryStatus = .eaten, source: String = "search") -> LogEntry? {
        if record.ref.kind == .recipe, let id = record.recordID, let recipe = store.recipe(id), recipe.recipeKind == .meal {
            logRecipe(recipe, day: day, meal: meal, status: status)
            return nil
        }
        if record.recordID != nil, record.ref.kind != .recipe { store.rememberAmount(amount.total, for: record) }
        let entry = store.log(record, amount: amount, day: day, meal: meal, time: time, status: status, source: source, language: language)
        let verb = status == .planned ? "Planned" : "Added"
        toasts.show("\(verb) \(entry.displayName) · \(Fmt.energy(entry.energy, unit: energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            self?.store.purge([entry])
        }
        return entry
    }

    func logRecipe(_ recipe: Recipe, amount: AmountText? = nil, day: DayKey, meal: String, status: EntryStatus = .eaten) {
        let entries = store.logRecipe(recipe, amount: amount, day: day, meal: meal, status: status, source: "recipe", language: language)
        let energy = entries.map(\.energy).reduce(0, +)
        toasts.show("Added \(recipe.displayName) · \(Fmt.energy(energy, unit: energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            self?.store.purge(entries)
        }
    }

    /// Logs every resolved line of a quick-add preview.
    func logMatches(_ matches: [QuickMatch], day: DayKey, meal: String, status: EntryStatus = .eaten) {
        var created: [LogEntry] = []
        let group = matches.count > 1 ? UUID().uuidString : ""
        for match in matches {
            if match.item.isEnergyOnly {
                let name = match.item.query.isEmpty ? "Quick entry" : match.item.query
                created.append(store.logQuick(name: name, nutrients: match.nutrients, day: day, meal: meal))
            } else if let food = match.food, let amount = match.amountText {
                created.append(store.log(food, amount: amount, day: day, meal: meal, status: status, source: "quick",
                                         language: language, groupID: group, saveNow: false))
            }
        }
        store.save()
        guard !created.isEmpty else { return }
        let energy = created.map(\.energy).reduce(0, +)
        let label = created.count == 1 ? created[0].displayName : "\(created.count) foods"
        toasts.show("Added \(label) · \(Fmt.energy(energy, unit: energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            self?.store.purge(created)
        }
    }

    func logQuick(name: String, nutrients: NutrientValues, day: DayKey, meal: String) {
        let entry = store.logQuick(name: name, nutrients: nutrients, day: day, meal: meal)
        toasts.show("Added \(entry.displayName) · \(Fmt.energy(entry.energy, unit: energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            self?.store.purge([entry])
        }
    }

    func logAgain(_ entries: [LogEntry]) {
        guard !entries.isEmpty else { return }
        let meal = entries.count == 1 ? settings.suggestedMeal().id : nil
        let copies = store.copy(entries, to: today, meal: meal)
        let energy = copies.map(\.energy).reduce(0, +)
        toasts.show("Logged again · \(Fmt.energy(energy, unit: energyUnit))", symbol: "arrow.clockwise.circle.fill") { [weak self] in
            self?.store.purge(copies)
        }
    }

    func trash(_ entries: [LogEntry]) {
        guard !entries.isEmpty else { return }
        let trashed = store.trash(entries)
        let label = trashed.count == 1 ? "Deleted \u{201C}\(trashed[0].displayName)\u{201D}" : "Deleted \(trashed.count) entries"
        toasts.show(label, symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    func move(_ entries: [LogEntry], to meal: String) {
        let previous = entries.map { ($0, $0.meal) }
        store.move(entries, to: meal)
        toasts.show("Moved to \(settings.meal(meal).name)", symbol: "arrow.left.arrow.right") { [weak self] in
            guard let self else { return }
            for (entry, meal) in previous { entry.meal = meal }
            self.store.save()
        }
    }

    func copy(_ entries: [LogEntry], to day: DayKey, status: EntryStatus = .eaten) {
        let copies = store.copy(entries, to: day, status: status)
        let what = copies.count == 1 ? copies[0].displayName : "\(copies.count) entries"
        toasts.show("Copied \(what) to \(Fmt.dayTitle(day, today: today).lowercased())", symbol: "doc.on.doc.fill") { [weak self] in
            self?.store.purge(copies)
        }
    }

    func confirm(_ entries: [LogEntry]) {
        let planned = entries.filter { !$0.isEaten }
        guard !planned.isEmpty else { return }
        let times = planned.map { ($0, $0.time, $0.status) }
        store.confirm(planned)
        let energy = planned.map(\.energy).reduce(0, +)
        toasts.show("Eaten · \(Fmt.energy(energy, unit: energyUnit))", symbol: "checkmark.circle.fill") { [weak self] in
            guard let self else { return }
            for (entry, time, status) in times {
                entry.time = time
                entry.status = status
            }
            self.store.save()
        }
    }

    func setStatus(_ entries: [LogEntry], _ status: EntryStatus) {
        store.setStatus(entries, status)
    }

    // MARK: Water and weight

    func addWater(_ milliliters: Double, day: DayKey? = nil) {
        let log = store.addWater(milliliters, day: day ?? selectedDay, time: (day ?? selectedDay) == today ? Date() : (day ?? selectedDay).date(minutes: 12 * 60))
        toasts.show("+\(Fmt.milliliters(milliliters)) water", symbol: "drop.fill") { [weak self] in
            self?.store.purge([log])
        }
    }

    func removeLastWater(on day: DayKey) {
        guard let last = store.water(on: day).last else { return }
        let trashed = store.trash([last])
        toasts.show("−\(Fmt.milliliters(last.amount)) water", symbol: "drop") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    // MARK: Foods and recipes

    func toggleFavorite(_ record: FoodRecord) {
        store.setFavorite(record, !record.isFavorite)
        toasts.show(record.isFavorite ? "Removed from favorites" : "Added to favorites", symbol: record.isFavorite ? "star.slash" : "star.fill")
    }

    func trash(_ food: Food) {
        let trashed = store.trash([food])
        toasts.show("Deleted \u{201C}\(food.name)\u{201D}", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    func trash(_ recipe: Recipe) {
        let trashed = store.trash([recipe])
        toasts.show("Deleted \u{201C}\(recipe.displayName)\u{201D}", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    func trash(_ rule: PlanRule) {
        let trashed = store.trash([rule])
        toasts.show("Routine deleted", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    func updateSettings(_ change: (NinaProfile) -> Void) {
        store.updateProfile(change)
    }

    // MARK: Navigation helpers

    func show(day: DayKey) {
        selectedDay = day
        tab = .today
        sidebar = .today
    }

    func addFood(meal: String? = nil, day: DayKey? = nil) {
        sheet = .addFood(day: day ?? selectedDay, meal: meal)
    }

    /// Opens a sheet after the current one closed (one sheet at a time).
    func present(_ next: AppSheet) {
        guard sheet != nil else {
            sheet = next
            return
        }
        sheet = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.sheet = next
        }
    }

    // MARK: Tour

    /// Opens the tour once after install, and the What's new steps after an update that added some.
    func offerTourIfNeeded() {
        guard !isSandbox, !launch.isDemo, tour == nil else { return }
        let steps = TourSchedule().stepsToOffer(NinaTour.catalog)
        guard !steps.isEmpty else { return }
        AppLog.info("Tour offered (\(steps.count) steps)", category: "tour")
        tour = TourRequest(steps: steps)
    }

    /// Replay from Settings or Help → Nina Tour. A sheet has to close first.
    func startTour() {
        guard sheet != nil else {
            tour = TourRequest(steps: NinaTour.catalog.allSteps)
            return
        }
        sheet = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.tour = TourRequest(steps: NinaTour.catalog.allSteps)
        }
    }

    func finishTour() {
        TourSchedule().markSeen(NinaTour.catalog)
        tour = nil
        tourModel = nil
    }

    // MARK: URLs

    /// nina://add, nina://water?ml=250, nina://today, or a CSV opened from Files.
    func open(_ url: URL) {
        if url.scheme == AppInfo.urlScheme {
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            switch url.host ?? "" {
            case "add":
                show(day: today)
                present(.addFood(day: today, meal: nil))
            case "water":
                let amount = parts?.queryItems?.first { $0.name == "ml" }?.value.flatMap(Double.init) ?? settings.waterGlass
                show(day: today)
                addWater(amount, day: today)
            case "quick":
                present(.quickCalories(day: today, meal: nil))
            default:
                show(day: today)
            }
            return
        }
        AppLog.info("Opened \(url.lastPathComponent)", category: "import")
        pendingImport = url
        present(.importData(nil))
    }

    // MARK: Launch arguments (screenshots in CI)

    /// `-Demo -DemoScreen <name>` opens a screen; `-Tour` / `-TourStep <id>` open the tour.
    private func applyLaunchOptions() {
        if launch.resetTour { TourSchedule().reset() }
        switch launch.screen {
        case "foods":
            tab = .foods
            sidebar = .foods
        case "plan":
            tab = .plan
            sidebar = .plan
        case "insights":
            tab = .insights
            sidebar = .insights
        case "recipes":
            sidebar = .recipes
            tab = .foods
        case "body":
            sidebar = .body
            tab = .insights
        case "create":
            sheet = .create
        case "add":
            sheet = .addFood(day: today, meal: "dinner")
        case "quick":
            sheet = .addFood(day: today, meal: "snack")
        case "food":
            if let banana = library.record(FoodRef("usda:09040")) ?? library.records.first { sheet = .food(banana) }
        case "goals":
            sheet = .goals
        case "import":
            sheet = .importData(.foods)
        case "settings":
            sheet = .settings
        case "nutrition":
            sheet = .dayNutrition(today)
        default:
            break
        }
        if launch.startTour { startTour() }
    }
}
