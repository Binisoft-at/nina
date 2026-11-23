import Foundation
import BinisoftKitCore
import NinaCore
#if os(iOS) || os(watchOS)
import WidgetKit
#endif

/// The widget snapshot in the shared App Group: `<group>/Nina/today.json` – today's numbers only,
/// never the diary. On the watch the same file feeds the complications; the iPhone also hands its
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
}
