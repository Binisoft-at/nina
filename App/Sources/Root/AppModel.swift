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
    var foodsPage: FoodsPage = .foods
    /// iPhone/iPad: the Progress tab's page (Body first once a plan is set up).
    var progressPage: ProgressPage = .body
    var sidebar: SidebarItem? = .today
    var selectedDay: DayKey
    var sheet: AppSheet?
    var tour: TourRequest?
    /// The practice page's model while the tour is open: menu commands act there.
    var tourModel: AppModel?
    /// A CSV opened from Files / "Open in" – the import sheet picks it up.
    var pendingImport: URL?
    /// A weight from `nina://weigh?value=` that needs a look (outside 25–300 kg or more than 3 kg
    /// from the 7-day average): `WeighInSheet` prefills it and sets it back to nil.
    var pendingWeighIn: Double?
    /// The coach cards this device put off with "Later": card key → the day it was tapped.
    /// Device-only (UserDefaults), never synced. Pass it to `CoachBoard` (`CoachContext` does).
    private(set) var coachDismissals: [String: DayKey] = [:]
    /// iPhone: Recently Deleted is pushed from Settings.
    var showTrash = false
    /// iPhone: "Turn on coach reminders?" is on screen (RootView shows it; asked once per device).
    var askCoachReminders = false
    /// Grows with every data change (views that compute from fetches refresh on it).
    private(set) var dataVersion = 0

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var coachQuestionPending = false

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
        let settings = store.coachSettings()
        self.settings = settings
        self.selectedDay = settings.today()
        progressPage = settings.plan.isSetUp ? .body : .nutrition
        if !isSandbox, !launch.isDemo { coachDismissals = CoachLater.load(today: settings.today()) }
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
        // The plan, the day-type marks and the real body weight (typed and Health weigh-ins).
        let newSettings = store.coachSettings(adding: healthWeightReadings)
        if newSettings != settings { settings = newSettings }
        library.rebuild(context: container.mainContext, language: settings.language)
        dataVersion += 1
        guard !isSandbox, !launch.isDemo else { return }
        CoachContext.latestHealthReadings = healthWeightReadings
        WidgetBridge.publish(store.todaySnapshot())
        health.scheduleSync(container: container)
        NotificationScheduler.shared.reschedule(context: container.mainContext, settings: settings)
        offerCoachRemindersIfNeeded()
    }

    /// The app came to the foreground: a new day may have started, plans and Health need a look.
    func becameActive() {
        guard !isSandbox, !launch.isDemo else { return }
        let newToday = settings.today()
        if selectedDay < newToday, selectedDay == newToday.adding(days: -1) { selectedDay = newToday }
        store.materializePlans(today: newToday)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let before = self.health.weightSamples
            await self.health.refreshReadings()
            // New Health weigh-ins change the body weight, the weight signal and the coach board.
            if self.health.weightSamples != before { self.scheduleRefresh() }
        }
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

    // MARK: Coach and body

    /// The weigh-ins read live from Apple Health as weight-signal readings (never stored).
    var healthWeightReadings: [WeightSignal.Reading] {
        let dayStartHour = settings.dayStartHour
        return health.weightSamples.map {
            WeightSignal.Reading(time: $0.date, kilograms: $0.kilograms, source: .health, dayStartHour: dayStartHour)
        }
    }

    /// Shows a toast whose Undo puts back what a coach write changed (`store.undo`).
    func showUndo(_ change: CoachUndo, _ message: String, symbol: String = "checkmark.circle.fill") {
        guard !change.isEmpty else { return }
        toasts.show(message, symbol: symbol) { [weak self] in
            self?.store.undo(change)
        }
    }

    /// Saves the plan (and its mirror in the profile) with a toast; Undo restores the plan before.
    @discardableResult
    func updatePlan(_ plan: CoachPlan, message: String, symbol: String = "checkmark.circle.fill") -> CoachUndo {
        let change = store.updatePlan(plan, on: today)
        showUndo(change, message, symbol: symbol)
        return change
    }

    /// Picks a day's type by hand; nil goes back to the schedule.
    @discardableResult
    func setDayType(_ typeID: String?, on day: DayKey, toast: Bool = true) -> CoachUndo {
        let plan = settings.plan
        let change = store.setDayType(day: day, typeID: typeID)
        guard toast else { return change }
        if let typeID, let type = plan.dayType(id: typeID) {
            let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
            let label = [emoji, type.name].filter { !$0.isEmpty }.joined(separator: " ")
            showUndo(change, "\(label) · \(Fmt.dayTitle(day, today: today))", symbol: "calendar")
        } else {
            showUndo(change, "Back to the schedule", symbol: "calendar")
        }
        return change
    }

    /// Ticks a daily check done or skipped ("Not today"); nil opens it again.
    @discardableResult
    func setCheck(_ checkID: String, on day: DayKey, state: CheckState?, toast: Bool = true) -> CoachUndo {
        let name = settings.plan.check(id: checkID)?.name ?? "Check"
        let change = store.setCheck(day: day, checkID: checkID, state: state)
        guard toast else { return change }
        switch state {
        case .done?: showUndo(change, "\(name) done", symbol: "checkmark.circle.fill")
        case .skipped?: showUndo(change, "\(name) – not today", symbol: "minus.circle")
        case nil: showUndo(change, "\(name) open again", symbol: "circle")
        }
        return change
    }

    /// A tap on a check pill: open or skipped → done, done → open.
    @discardableResult
    func toggleCheck(_ checkID: String, on day: DayKey, toast: Bool = true) -> CoachUndo {
        let current = store.checkStates(on: day)[checkID]
        return setCheck(checkID, on: day, state: current == .done ? nil : .done, toast: toast)
    }

    /// Logs a weigh-in (also to Apple Health when that's on) with Undo; Undo takes it out of
    /// Apple Health again.
    @discardableResult
    func logWeight(_ kilograms: Double, day: DayKey? = nil, time: Date = Date(), bodyFat: Double = 0, note: String = "") -> WeightEntry {
        let entry = store.addWeight(kilograms, day: day ?? DayKey.today(now: time, dayStartHour: settings.dayStartHour),
                                    time: time, bodyFat: bodyFat, note: note)
        let health = self.health
        let write: Task<Void, Never> = Task { await health.writeWeight(kilograms, date: time) }
        toasts.show("Weight \(Fmt.kilograms(kilograms)) saved", symbol: "scalemass.fill") { [weak self] in
            _ = self?.store.trash([entry])
            Task {
                await write.value
                await health.deleteWeight(kilograms, date: time)
            }
        }
        return entry
    }

    /// Deletes a weigh-in (30-day trash) and the sample Nina wrote for it in Apple Health; Undo
    /// brings both back (the Health sample only when there was one).
    func trash(_ weight: WeightEntry) {
        let kilograms = weight.kilograms, time = weight.time
        let trashed = store.trash([weight])
        let health = self.health
        let delete: Task<Bool, Never> = Task { await health.deleteWeight(kilograms, date: time) }
        toasts.show("Weigh-in deleted", symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
            Task {
                guard await delete.value else { return }
                await health.replaceWeight(old: (kilograms, time), new: (kilograms, time))
            }
        }
    }

    /// Brings a weigh-in back from Recently Deleted, and its sample back to Apple Health (written
    /// once: one that is still there is replaced).
    func restore(_ weight: WeightEntry) {
        let kilograms = weight.kilograms, time = weight.time
        store.restore([weight])
        let health = self.health
        Task { await health.replaceWeight(old: (kilograms, time), new: (kilograms, time)) }
    }

    /// Adds a body measurement, or changes `editing`, with Undo.
    @discardableResult
    func saveMeasurement(_ draft: BodyMeasurementDraft, editing measurement: BodyMeasurement? = nil,
                         message: String? = nil) -> BodyMeasurement {
        let store = self.store
        let noun = draft.kind == .assessment ? "Body fat" : "Measurements"
        if let measurement {
            let previous = store.update(measurement, to: draft)
            toasts.show(message ?? "\(noun) updated", symbol: "checkmark.circle.fill") { [weak self] in
                _ = self?.store.update(measurement, to: previous)
            }
            return measurement
        }
        let added = store.addMeasurement(draft)
        toasts.show("\(noun) saved", symbol: "ruler.fill") { [weak self] in
            _ = self?.store.trash([added])
        }
        return added
    }

    func trash(_ measurement: BodyMeasurement) {
        let trashed = store.trash([measurement])
        let label = measurement.recordKind == .assessment ? "Assessment deleted" : "Measurement deleted"
        toasts.show(label, symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    /// "Later" on a coach card (device-only): today only; the review for 7 days, "Welcome back" for good.
    func dismissCard(_ key: String) {
        coachDismissals[key] = today
        if !isSandbox, !launch.isDemo { CoachLater.save(coachDismissals) }
        dataVersion += 1
    }

    /// Does what a checks-strip pill or a coach-card button asks for (`CoachBoard.Action`).
    /// `card`: the card the button belongs to (for `.dismiss`).
    func perform(_ action: CoachBoard.Action, on day: DayKey, card: CoachBoard.Card? = nil) {
        switch action {
        case .weighIn:
            present(.weight(nil))
        case .measure(let item):
            present(.measure(MeasureMode(item), nil))
        case .assessment:
            present(.assessment(nil))
        case .check(let id):
            toggleCheck(id, on: day)
        case .startPhase(let id):
            startPhase(id)
        case .postponePhase(let id):
            postponePhase(id)
        case .editPhase(let id):
            present(.phase(id))
        case .editPlan:
            present(.plan)
        case .review(let id):
            present(.phaseReview(id))
        case .checkIn(let checkInDay):
            present(.checkIn(checkInDay.startOfWeek()))
        case .dismiss:
            if let card { dismissCard(card.key) }
        }
    }

    /// "Start" on a phase: it starts today; a phase without targets gets the transition
    /// proposal (`CoachContext.startingPlan`). One Undo puts the plan back.
    func startPhase(_ id: String) {
        let store = self.store
        // The stored plan, read now: `settings` is refreshed a moment after a save or a sync, and
        // a stale copy written back would undo what just arrived.
        let context = CoachContext.load(store: store, settings: store.coachSettings(adding: healthWeightReadings),
                                        health: healthWeightReadings, dismissed: coachDismissals, day: today)
        guard let plan = context.startingPlan(phase: id) else { return }
        var change = store.updatePlan(plan, on: today)
        change.merge(store.recordPhaseEvent(phaseID: id, event: .started, day: today))
        let name = plan.phase(id: id)?.name ?? "Phase"
        showUndo(change, "\(name.isEmpty ? "Phase" : name) started", symbol: "flag.fill")
    }

    /// "In a week" on a phase that is due to start: its start moves 7 days on.
    func postponePhase(_ id: String) {
        let store = self.store
        let stored = store.settings.plan
        let plan = stored.postponing(phase: id, by: 7, from: today)
        guard plan != stored else { return }
        var change = store.updatePlan(plan, on: today)
        change.merge(store.recordPhaseEvent(phaseID: id, event: .postponed, day: today))
        let start = plan.phase(id: id)?.start.map { Fmt.shortDay($0) } ?? "next week"
        showUndo(change, "Moved to \(start)", symbol: "calendar.badge.clock")
    }

    /// "Apply from tomorrow" (or an edited change) on a check-in: the active phase moves by
    /// `delta` kcal a day from tomorrow, and the check-in is saved with the decision.
    func applyCheckIn(_ evaluation: CheckInEvaluation, delta: Double, decision: CheckInDecision = .applied) {
        let change = store.applyCheckIn(evaluation.snapshot, delta: delta, from: evaluation.applyFrom,
                                        weightKg: evaluation.input.weightKg, decision: decision)
        let sign = delta > 0 ? "+" : "−"
        showUndo(change, "\(sign)\(Fmt.energy(abs(delta), unit: energyUnit)) a day from tomorrow", symbol: "checkmark.circle.fill")
    }

    /// Saves a check-in without a plan change ("Keep for now", or no proposal).
    func saveCheckIn(_ snapshot: CheckInSnapshot, message: String = "Check-in saved") {
        showUndo(store.saveCheckIn(snapshot), message, symbol: "checkmark.circle.fill")
    }

    /// The Monday of the latest check-in week: this week from the plan's check-in weekday on,
    /// else last week (what "Weekly Check-in…" and nina://checkin open).
    var currentCheckInWeek: DayKey {
        BodySchedule.onOrBefore(weekday: settings.plan.routine.checkInWeekday, today).startOfWeek()
    }

    /// The Progress tab on its body page (Mac and iPad sidebar: Body).
    func showProgress(_ page: ProgressPage = .body) {
        progressPage = page
        tab = .insights
        sidebar = page == .body ? .body : .insights
    }

    /// The measure sheet for today's due set: the full set when one is due, else the weekly sites.
    func measureNow() {
        let due = CoachContext.load(app: self, day: today).dueItems
        let mode: MeasureMode = due.contains(where: { $0.kind == .full }) ? .full : .weekly
        present(.measure(mode, nil))
    }

    /// The settings as the goals & settings import and export see them (with the latest weight).
    var settingsState: SettingsState {
        let store = self.store
        return SettingsState(profile: store.profile(), weight: store.weights().last?.kilograms ?? health.latestWeight ?? 0)
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
        offerCoachRemindersIfNeeded()
    }

    // MARK: Coach reminders

    /// iPhone, which sends the coach's reminders by default: asks once per device "Turn on coach
    /// reminders?" (and with it for notification permission) as soon as a plan is set up – also a
    /// plan set up on another device and synced, or before this question existed. Waits until no
    /// sheet or tour is on screen (RootView calls it again when a sheet closes). The settings
    /// import and the plan editor ask on their own; the answer counts on every path.
    func offerCoachRemindersIfNeeded() {
        guard wantsCoachRemindersQuestion, !coachQuestionPending else { return }
        coachQuestionPending = true
        Task { @MainActor [weak self] in
            // Once a closing sheet is gone.
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self else { return }
            self.coachQuestionPending = false
            if self.wantsCoachRemindersQuestion { self.askCoachReminders = true }
        }
    }

    /// Nothing else on screen or about to open (the tour or its "What's new" comes first).
    private var wantsCoachRemindersQuestion: Bool {
        guard PlatformInfo.isPhone, !isSandbox, !launch.isDemo, !askCoachReminders,
              sheet == nil, tour == nil, tourModel == nil,
              NotificationScheduler.shared.shouldOfferCoachReminders(before: CoachPlan(), after: settings.plan) else { return false }
        return TourSchedule().stepsToOffer(NinaTour.catalog).isEmpty
    }

    // MARK: URLs

    /// nina://add, nina://water?ml=250, nina://quick, nina://today, nina://weigh[?value=74.2[&check=1]]
    /// (check: always show the sheet first), nina://measure?mode=weekly|full|assessment|<site key>
    /// (waist, arm_l …: that site only; assessment: the body-fat sheet), nina://checkin,
    /// nina://daytype/<id> (no id: back to the schedule), nina://check/<id>[?state=done|skipped|open]
    /// (an id the plan doesn't have only says so), nina://plan, nina://progress,
    /// nina://review/<phase id> (the phase review; an unknown phase shows Today), or a CSV opened
    /// from Files.
    func open(_ url: URL) {
        if url.scheme == AppInfo.urlScheme {
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            func query(_ name: String) -> String? { parts?.queryItems?.first { $0.name == name }?.value }
            let path = url.pathComponents.first { $0 != "/" }
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
            case "weigh":
                openWeighIn(value: query("value"), confirm: query("check") != nil)
            case "measure":
                if query("mode") == "assessment" {
                    present(.assessment(nil))
                } else if let mode = query("mode").flatMap(MeasureMode.init(rawValue:)) {
                    present(.measure(mode, nil))
                } else {
                    measureNow()
                }
            case "checkin":
                present(.checkIn(currentCheckInWeek))
            case "daytype":
                show(day: today)
                // A missing id means back to the schedule; an id the plan doesn't have writes nothing.
                if let path, settings.plan.dayType(id: path) == nil {
                    toasts.show("No day type \u{201C}\(path)\u{201D} in your plan", symbol: "questionmark.circle")
                    return
                }
                setDayType(path, on: today)
            case "check":
                show(day: today)
                guard let path else { return }
                // An id the plan doesn't have (a typo in a Shortcut, a deleted check) writes nothing.
                guard settings.plan.check(id: path) != nil else {
                    toasts.show("No daily check \u{201C}\(path)\u{201D} in your plan", symbol: "questionmark.circle")
                    return
                }
                switch query("state") ?? "done" {
                case "skipped": setCheck(path, on: today, state: .skipped)
                case "open": setCheck(path, on: today, state: nil)
                default: setCheck(path, on: today, state: .done)
                }
            case "plan":
                present(.plan)
            case "progress":
                showProgress(.body)
            case "review":
                if let path, settings.plan.phase(id: path) != nil {
                    present(.phaseReview(path))
                } else {
                    show(day: today)
                }
            default:
                show(day: today)
            }
            return
        }
        AppLog.info("Opened \(url.lastPathComponent)", category: "import")
        pendingImport = url
        present(.importData(nil))
    }

    /// nina://weigh: a plausible value is saved right away (Undo in the toast); anything else
    /// opens the weigh-in sheet, prefilled with the value when there is one. `confirm` (the "is that
    /// right?" notification) always opens the sheet first, whatever this launch can compare with.
    private func openWeighIn(value text: String?, confirm: Bool = false) {
        guard let text, let kilograms = NumberText.parse(text.replacingOccurrences(of: "kg", with: "")
            .trimmingCharacters(in: .whitespaces)) else {
            present(.weight(nil))
            return
        }
        if confirm {
            pendingWeighIn = kilograms
            present(.weight(nil))
            return
        }
        let signal = store.weightSignal(adding: healthWeightReadings, settings: settings)
        if case .ok = signal.sanity(kilograms, on: today) {
            show(day: today)
            logWeight(kilograms, day: today)
        } else {
            pendingWeighIn = kilograms
            present(.weight(nil))
        }
    }

    // MARK: Launch arguments (screenshots in CI)

    /// `-Demo -DemoScreen <name>` opens a screen; `-Tour` / `-TourStep <id>` open the tour.
    private func applyLaunchOptions() {
        if launch.resetTour { TourSchedule().reset() }
        if launch.isDemo { BodyPhotosDemo.seed(container.mainContext, today: today) }
        switch launch.screen {
        case "foods":
            tab = .foods
            sidebar = .foods
        case "plan":
            tab = .plan
            sidebar = .plan
        case "insights":
            showProgress(.nutrition)
        case "recipes":
            sidebar = .recipes
            tab = .foods
            foodsPage = .recipes
        case "body":
            showProgress(.body)
        case "measure":
            sheet = .measure(.full, nil)
        case "checkin":
            sheet = .checkIn(currentCheckInWeek)
        case "myplan":
            sheet = .plan
        case "photos":
            sheet = .photos(.compare(.front))
        case "phase":
            sheet = .phase(demoPhaseID)
        case "review":
            if let id = demoPhaseID { sheet = .phaseReview(id) }
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

    /// The phase the `phase` and `review` screenshots show: the active one, else the first.
    private var demoPhaseID: String? {
        settings.plan.activePhase(on: today)?.id ?? settings.plan.phases.first?.id
    }
}

/// The device's "Later" taps on coach cards (UserDefaults, never synced): card key → day.
enum CoachLater {
    static let key = "nina.coach.later"
    /// Older taps no longer matter (the longest snooze is 7 days; "Welcome back" ends 3 days
    /// after a pause).
    static let keepDays = 60

    static func load(today: DayKey, defaults: UserDefaults = .standard) -> [String: DayKey] {
        let stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let oldest = today.adding(days: -keepDays)
        var result: [String: DayKey] = [:]
        for (card, raw) in stored {
            if let day = DayKey(raw), day >= oldest { result[card] = day }
        }
        return result
    }

    static func save(_ dismissals: [String: DayKey], defaults: UserDefaults = .standard) {
        defaults.set(dismissals.mapValues(\.rawValue), forKey: key)
    }
}
