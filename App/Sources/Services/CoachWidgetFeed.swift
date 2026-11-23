import Foundation
import AppIntents
import NinaCore

/// Keeps what lives outside the app's window current after every data change: the coach widget's
/// snapshot (`CoachSnapshot` through `WidgetBridge`, iPhone only – the Mac has no widgets) and
/// Siri's list of the plan's day types and checks (the "Today is a Tennis day" phrases).
/// `AppModel.refresh` calls `publish(app:)` for the real store only (never the demo, the tour's
/// practice page or an in-memory store); the coach intents call `publishNow(store:health:)` right
/// after they write, since a Siri request can end before the app's own refresh.
///
/// It also remembers the running app (`app`): the Siri intents act through it when it is there
/// (a toast with Undo, Apple Health written right away), and the controls' links open in its
/// window (`NinaIntentRoute`).
@MainActor
enum CoachWidgetFeed {
    /// The app's model while it runs (set at its first refresh); nil before that and in a launch
    /// that only answers Siri before the window model refreshed.
    private(set) static weak var app: AppModel?
    private static var task: Task<Void, Never>?
    /// The day types and checks Siri was told about last.
    private static var shortcutKey: String?

    /// After a refresh of the real store: remember the app, open a link a control asked for before
    /// the app was ready, tell Siri about changed day types or checks, and write the widget's
    /// snapshot a moment later (a burst of changes writes it once).
    static func publish(app: AppModel) {
        self.app = app
        #if os(iOS)
        NinaIntentRoute.handler = { [weak app] url in
            app?.open(url)
        }
        if let url = NinaIntentRoute.takePending() {
            Task { @MainActor [weak app] in
                // The window is just appearing on a cold start: give it a moment.
                try? await Task.sleep(for: .milliseconds(300))
                app?.open(url)
            }
        }
        #endif
        updateShortcutParameters(plan: app.settings.plan)
        #if os(iOS)
        task?.cancel()
        task = Task { @MainActor [weak app] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let app else { return }
            publishNow(store: app.store, health: app.healthWeightReadings)
        }
        #endif
    }

    /// Builds the coach widget's snapshot now and writes it (iPhone). `health`: the live Apple
    /// Health weigh-ins (memory only); the snapshot stays on this device.
    @discardableResult
    static func publishNow(store: NinaStore, health: [WeightSignal.Reading], now: Date = Date()) -> CoachSnapshot {
        let snapshot = CoachSnapshot(input(store: store, health: health, now: now))
        #if os(iOS)
        WidgetBridge.publishCoach(snapshot)
        #endif
        return snapshot
    }

    /// The snapshot's plain values from the store: today's and tomorrow's targets as Today shows
    /// them, the measuring schedule, the morning weight signal (typed and Health weigh-ins) and
    /// the saved check-ins.
    static func input(store: NinaStore, health: [WeightSignal.Reading], now: Date = Date()) -> CoachSnapshot.Input {
        let settings = store.settings
        let calendar = store.calendar
        let plan = settings.plan
        let today = settings.today(now: now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let signal = store.weightSignal(adding: health, settings: settings)
        let checkpoint = plan.isSetUp ? signal.checkpointCrossing(in: plan, through: today) : nil
        var input = CoachSnapshot.Input(plan: plan, today: today, now: now, calendar: calendar)
        input.dayStartHour = settings.dayStartHour
        input.dayTypeMarks = settings.dayTypeMarks
        input.checkStates = plan.isSetUp ? store.checkStates(on: today) : [:]
        input.mealSlots = settings.meals
        input.energyToday = settings.targets(for: today, calendar: calendar).energy
        input.energyTomorrow = settings.targets(for: tomorrow, calendar: calendar).energy
        input.schedule = store.bodySchedule(plan: plan, checkpoint: checkpoint)
        input.hasMorningWeighIn = signal.morning(on: today) != nil
        input.summary = signal.summary(on: today, plan: plan)
        input.checkIns = plan.isSetUp ? store.checkIns() : []
        return input
    }

    /// Siri learns the plan's day types and checks for the phrases that name one ("Today is a
    /// Tennis day in Nina"); told again only when their names change.
    static func updateShortcutParameters(plan: CoachPlan) {
        let key = (plan.dayTypes.map { "\($0.id)=\($0.name)" } + plan.checks.map { "\($0.id)=\($0.name)" }).joined(separator: "|")
        guard key != shortcutKey else { return }
        shortcutKey = key
        NinaShortcuts.updateAppShortcutParameters()
    }
}
