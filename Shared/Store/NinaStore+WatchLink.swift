import Foundation
import SwiftData
import NinaCore

// The freshness of a day's numbers for the iPhone → Apple Watch snapshot (`WatchSnapshotRelay`):
// the iPhone sends it with its snapshot, the watch compares its own with it. Also the iPhone's
// coach part (what only it knows from Apple Health) with the freshness of what the coach's status
// line rests on. Used by the iPhone app (`PhoneWatchLink`) and the watch app (`WatchPhoneLink`).

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

    /// When what the coach's status line rests on (besides Apple Health) last changed in this
    /// store: the weigh-ins, trashed ones included, the profile with the plan, and the saved
    /// check-ins. The iPhone sends it with its coach part; the watch shows the iPhone's numbers
    /// only while its own is not newer (`WatchSnapshotRelay.usesPhoneNumbers`). A food or a check
    /// tick saved on the watch doesn't count: it doesn't change the weight numbers.
    func watchLinkCoachFreshness() -> Date? {
        var weights = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        weights.fetchLimit = 1
        let kind = DayMarkKind.checkIn.rawValue
        var checkIns = FetchDescriptor<DayMark>(predicate: #Predicate<DayMark> { $0.kind == kind },
                                                sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        checkIns.fetchLimit = 1
        var changes: [Date] = []
        changes += ((try? context.fetch(weights)) ?? []).map(\.modifiedAt)
        changes += ((try? context.fetch(checkIns)) ?? []).map(\.modifiedAt)
        if let profile = profile() { changes.append(profile.modifiedAt) }
        return WatchSnapshotRelay.freshness(changes)
    }

    /// The iPhone's coach part for its Apple Watch (`WatchSnapshotRelay.PhoneCoach`): `health` the
    /// live Apple Health weigh-ins (never stored), `activeEnergy` today's active energy from Health
    /// as the iPhone's own ring counts it on today's diary day (kcal, before "Add to my budget").
    func watchLinkPhoneCoach(health: [WeightSignal.Reading], activeEnergy: Double, now: Date = Date()) -> WatchSnapshotRelay.PhoneCoach {
        let settings = self.settings
        let calendar = self.calendar
        let today = settings.today(now: now, calendar: calendar)
        let signal = weightSignal(adding: health, settings: settings)
        return WatchSnapshotRelay.phoneCoach(signal: signal, plan: settings.plan, checkIns: checkIns(), today: today,
                                             freshness: watchLinkCoachFreshness(), activeEnergy: activeEnergy,
                                             activeEnergyDay: today, calendar: calendar)
    }
}
