import Foundation
import SwiftData
import NinaCore

// The freshness of a day's numbers for the iPhone → Apple Watch snapshot (`WatchSnapshotRelay`):
// the iPhone sends it with its snapshot, the watch compares its own with it. Used by the iPhone
// app (`PhoneWatchLink`) and the watch app (`WatchPhoneLink`).

/// When this device itself last saved a change through the store (device-only, never synced):
/// an Undo that deletes the newest entry leaves no record behind, but the save still counts.
enum WatchLinkLocalChange {
    private static let key = "nina.watchlink.localChange"

    static func record(_ date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: key)
    }

    static var last: Date? {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? Date(timeIntervalSinceReferenceDate: value) : nil
    }
}

extension NinaStore {
    /// When `day`'s numbers last changed in this store: the newest change of the day's entries
    /// and water, of the day marks of the day and the next (day types), trashed ones included, of
    /// the settings, and this device's own last save when it was on that day.
    func watchLinkFreshness(on day: DayKey) -> Date? {
        let key = day.rawValue
        let next = day.adding(days: 1, calendar: calendar).rawValue
        var changes: [Date] = []
        let entries = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.day == key })
        changes += ((try? context.fetch(entries)) ?? []).map(\.modifiedAt)
        let water = FetchDescriptor<WaterLog>(predicate: #Predicate<WaterLog> { $0.day == key })
        changes += ((try? context.fetch(water)) ?? []).map(\.modifiedAt)
        let marks = FetchDescriptor<DayMark>(predicate: #Predicate<DayMark> { $0.day == key || $0.day == next })
        changes += ((try? context.fetch(marks)) ?? []).map(\.modifiedAt)
        let profile = self.profile()
        if let profile { changes.append(profile.modifiedAt) }
        var local: Date?
        if let last = WatchLinkLocalChange.last, NinaSettings(profile).today(now: last, calendar: calendar) == day {
            local = last
        }
        return WatchSnapshotRelay.freshness(changes, localChange: local)
    }
}
