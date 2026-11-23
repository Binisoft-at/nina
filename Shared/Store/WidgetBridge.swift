import Foundation
import BinisoftKitCore
import NinaCore
#if os(iOS) || os(watchOS)
import WidgetKit
#endif
#if os(iOS)
import AppIntents
#endif

/// The widget snapshots in the shared App Group: `<group>/Nina/today.json` – today's numbers only,
/// never the diary – and `<group>/Nina/coach.json` for the coach widget (`CoachSnapshot`). On the watch the same file feeds the complications; the iPhone also hands its
/// snapshot to the watch (`PhoneWatchLink`, through `didWrite`), so the watch face follows what is
/// logged on the iPhone or the Mac. Compiled into the widgets too: nothing here starts a
/// connection – the iPhone app sets `didWrite` at launch, the widgets never do.
enum WidgetBridge {
    nonisolated(unsafe) private static var lastPublished: TodaySnapshot?
    /// Today's active energy from Apple Health (kcal) with the calendar day it was read for.
    nonisolated(unsafe) private static var storedBonus: ActivityBonus?
    /// Called after a new snapshot was written (the iPhone app hands it on to the Apple Watch).
    /// nil in the widgets, on the Mac and on the watch.
    nonisolated(unsafe) static var didWrite: ((TodaySnapshot) -> Void)?

    /// Device-only (never synced): the bonus outlives a relaunch, so a background refresh (a
    /// CloudKit import, a notification button, Siri) doesn't drop it from the widget's budget.
    private static let bonusKey = "nina.widget.activityBonus"

    private struct ActivityBonus: Codable {
        var day: String
        var kilocalories: Double
    }

    /// Active energy (kcal) from Apple Health today, as last read by the Health service; 0 when
    /// it was read on another day (yesterday's must never raise today's budget). Setting it stores
    /// it for today.
    static var activityBonus: Double {
        get { activityBonus(on: DayKey(date: Date())) }
        set { setActivityBonus(newValue, day: DayKey(date: Date())) }
    }

    /// The bonus read for `day`, else 0.
    static func activityBonus(on day: DayKey) -> Double {
        if storedBonus == nil,
           let data = UserDefaults.standard.data(forKey: bonusKey),
           let stored = try? JSONDecoder().decode(ActivityBonus.self, from: data) {
            storedBonus = stored
        }
        guard let stored = storedBonus, stored.day == day.rawValue else { return 0 }
        return stored.kilocalories
    }

    /// Remembers the active energy read for `day` (the calendar day of the reading).
    static func setActivityBonus(_ kilocalories: Double, day: DayKey) {
        let bonus = ActivityBonus(day: day.rawValue, kilocalories: max(0, kilocalories))
        storedBonus = bonus
        if let data = try? JSONEncoder().encode(bonus) {
            UserDefaults.standard.set(data, forKey: bonusKey)
        }
    }

    static var folder: URL? {
        guard let group = AppIdentifiers.main.sharedAppGroup,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Writes the snapshot and reloads the widgets when something changed.
    static func publish(_ snapshot: TodaySnapshot) {
        guard !snapshot.hasSameContent(as: lastPublished), let folder else { return }
        do {
            try SnapshotFile<TodaySnapshot>(folder: folder, name: TodaySnapshot.fileName).write(snapshot)
            lastPublished = snapshot
            #if os(iOS) || os(watchOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            didWrite?(snapshot)
        } catch {
            AppLog.warning("Widget snapshot not written: \(error.localizedDescription)", category: "widgets")
        }
    }

    static func read() -> TodaySnapshot? {
        guard let folder else { return nil }
        return SnapshotFile<TodaySnapshot>(folder: folder, name: TodaySnapshot.fileName).read()
    }

    // MARK: Coach widget

    /// The coach widget's kind (`CoachWidget`): only its timelines reload on a coach change.
    static let coachKind = "NinaCoach"
    nonisolated(unsafe) private static var lastCoach: CoachSnapshot?

    /// Writes the coach snapshot (`<group>/Nina/coach.json`) and reloads the coach widget when
    /// something changed. Device-only: the file is kept out of device backups too, since its
    /// average can count Apple Health weigh-ins (shown on this device only, never synced).
    static func publishCoach(_ snapshot: CoachSnapshot) {
        guard !snapshot.hasSameContent(as: lastCoach), let folder else { return }
        let file = SnapshotFile<CoachSnapshot>(folder: folder, name: CoachSnapshot.fileName)
        do {
            try file.write(snapshot)
            lastCoach = snapshot
            var url = file.url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            #if os(iOS) || os(watchOS)
            WidgetCenter.shared.reloadTimelines(ofKind: coachKind)
            #endif
        } catch {
            AppLog.warning("Coach widget snapshot not written: \(error.localizedDescription)", category: "widgets")
        }
    }

    static func readCoach() -> CoachSnapshot? {
        guard let folder else { return nil }
        return SnapshotFile<CoachSnapshot>(folder: folder, name: CoachSnapshot.fileName).read()
    }
}

#if os(iOS)
// MARK: - Controls (Control Center, Lock Screen, Action button)

/// A nina:// link a control or a Shortcut asked the app to open. The intents below run in the
/// app (they open it first); the app hands over its window model once it is ready
/// (`CoachWidgetFeed` sets `handler`), and a link asked for before that – a cold start – waits
/// here and is opened once, right after. Compiled into the widgets too, where nothing sets it.
@MainActor
enum NinaIntentRoute {
    /// Opens a link in the app's window; nil until the app is ready (and always in the widgets).
    static var handler: ((URL) -> Void)?
    private static var pending: (url: URL, at: Date)?

    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        if let handler {
            handler(url)
        } else {
            pending = (url, Date())
        }
    }

    /// The link asked for before the app was ready, once; nil after a minute (a launch that never
    /// got that far shouldn't open a sheet much later).
    static func takePending(now: Date = Date()) -> URL? {
        defer { pending = nil }
        guard let pending, now.timeIntervalSince(pending.at) < 60 else { return nil }
        return pending.url
    }
}

/// "Log Food" in Control Center, on the Lock Screen or the Action button: opens Nina at Log Food
/// for the meal that fits the time (nina://add). Compiled into the app and the widget extension –
/// the control names it, the app runs it.
struct NinaOpenLogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Log Food"
    static let description: IntentDescription? = IntentDescription("Opens Nina at Log Food for the meal that fits the time.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        NinaIntentRoute.open("\(AppInfo.urlScheme)://add")
        return .result()
    }
}

/// "Weigh In": opens Nina at the weigh-in sheet (nina://weigh).
struct NinaOpenWeighInIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Weigh-In"
    static let description: IntentDescription? = IntentDescription("Opens Nina at the weigh-in, ready to type today's weight.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        NinaIntentRoute.open("\(AppInfo.urlScheme)://weigh")
        return .result()
    }
}

/// "Add Water": opens Nina and adds a glass (the glass size from Settings) with Undo in the toast
/// (nina://water). Siri's "Log Water" adds water without opening the app.
struct NinaOpenAddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Glass of Water"
    static let description: IntentDescription? = IntentDescription("Opens Nina and adds a glass of water (your glass size) to today, with Undo.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        NinaIntentRoute.open("\(AppInfo.urlScheme)://water")
        return .result()
    }
}
#endif
