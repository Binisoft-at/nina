import Foundation

/// ISO weekdays (1 = Monday … 7 = Sunday) a plan repeats on, stored as "1,2,3,4,5".
public struct Weekdays: Equatable, Hashable, Sendable {
    public private(set) var days: Set<Int>

    public init(_ days: Set<Int>) {
        self.days = days.filter { (1...7).contains($0) }
    }

    public init(encoded: String) {
        self.init(Set(encoded.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }))
    }

    public var encoded: String { days.sorted().map(String.init).joined(separator: ",") }

    public static let everyDay = Weekdays(Set(1...7))
    public static let workdays = Weekdays(Set(1...5))
    public static let weekend = Weekdays([6, 7])

    public func contains(_ day: DayKey, calendar: Calendar = .current) -> Bool {
        days.contains(day.weekday(calendar: calendar))
    }

    public var isEmpty: Bool { days.isEmpty }

    public mutating func toggle(_ weekday: Int) {
        if days.contains(weekday) { days.remove(weekday) } else if (1...7).contains(weekday) { days.insert(weekday) }
    }

    /// "Every day", "Mon–Fri", "Sat, Sun", "Mon, Wed, Fri".
    public var summary: String {
        if days == Weekdays.everyDay.days { return "Every day" }
        if days == Weekdays.workdays.days { return "Mon–Fri" }
        if days.isEmpty { return "Never" }
        return days.sorted().map { Weekdays.shortNames[$0 - 1] }.joined(separator: ", ")
    }

    public static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
}

/// Planned meals: a rule ("my usual breakfast, Mon–Fri at 07:30") is turned into planned entries
/// for the next days. Each planned group carries a key, so it is created once per day and rule
/// – even with several devices, which converge on the same group (`duplicates`).
public enum PlanSchedule {
    /// `LogEntry.source` of a copy the clean-up took out (`duplicates`): it keeps the day's key, so
    /// the routine doesn't plan that day again, and it never counts as the person's delete.
    public static let duplicateSource = "plan-duplicate"
    /// `LogEntry.source` of planned entries taken out because their routine was deleted, paused or
    /// changed: they don't keep the routine from planning that day again (a resumed or edited
    /// routine plans it anew), and they never count as the person's delete.
    public static let retiredSource = "plan-off"

    public static func key(rule: UUID, day: DayKey) -> String {
        "rule:\(rule.uuidString):\(day.rawValue)"
    }

    /// The start every key of a rule shares ("rule:<uuid>:").
    public static func keyPrefix(rule: UUID) -> String {
        "rule:\(rule.uuidString):"
    }

    /// The rule a key belongs to; nil for anything that isn't "rule:<uuid>:<day>".
    public static func ruleID(of key: String) -> UUID? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "rule", DayKey(String(parts[2])) != nil else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// The day of a key "rule:<uuid>:<day>".
    public static func day(of key: String) -> DayKey? {
        guard ruleID(of: key) != nil, let last = key.split(separator: ":").last else { return nil }
        return DayKey(String(last))
    }

    /// A planned entry the person hasn't acted on: still planned and not changed since it was made
    /// (a second of slack for the save).
    public static func isUntouched(status: String, createdAt: Date, modifiedAt: Date) -> Bool {
        status == EntryStatus.planned.rawValue && modifiedAt.timeIntervalSince(createdAt) <= 1
    }

    /// Planned entries taken out by the clean-up or a routine change, not by the person.
    public static func isMarked(source: String) -> Bool {
        source == duplicateSource || source == retiredSource
    }

    /// Days in `[from, from + horizon)` on which the rule should have planned entries.
    public static func days(for weekdays: Weekdays, from start: DayKey, horizon: Int, startDay: DayKey? = nil,
                            endDay: DayKey? = nil, calendar: Calendar = .current) -> [DayKey] {
        guard horizon > 0, !weekdays.isEmpty else { return [] }
        return (0..<horizon).map { start.adding(days: $0, calendar: calendar) }.filter { day in
            if let startDay, day < startDay { return false }
            if let endDay, day > endDay { return false }
            return weekdays.contains(day, calendar: calendar)
        }
    }

    /// The keys a rule plans in `[from, from + horizon)` (`days(for:…)`). An entry moved to
    /// another day ("Move to Day…", a new date in the entry editor) keeps the key of the day it was
    /// planned for, so the store looks these keys up on any day, not only in the window: the day
    /// the person moved a planned meal away from isn't planned again (`takenKeys`).
    public static func keys(rule: UUID, weekdays: Weekdays, from start: DayKey, horizon: Int, startDay: DayKey? = nil,
                            endDay: DayKey? = nil, calendar: Calendar = .current) -> [String] {
        days(for: weekdays, from: start, horizon: horizon, startDay: startDay, endDay: endDay, calendar: calendar)
            .map { key(rule: rule, day: $0) }
    }

    /// One planned entry as the clean-up sees it (live or in the trash).
    public struct Item: Equatable, Sendable {
        public var id: String
        /// The entry's plan key ("" = not planned by a routine).
        public var key: String
        /// Entries logged together share it ("" for a single entry, e.g. a recipe portion).
        public var groupID: String
        public var status: String
        public var source: String
        public var createdAt: Date
        public var modifiedAt: Date
        public var isTrashed: Bool

        public init(id: String, key: String, groupID: String = "", status: String = EntryStatus.planned.rawValue,
                    source: String = "plan", createdAt: Date, modifiedAt: Date? = nil, isTrashed: Bool = false) {
            self.id = id
            self.key = key
            self.groupID = groupID
            self.status = status
            self.source = source
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt ?? createdAt
            self.isTrashed = isTrashed
        }
    }

    /// The entries logged together for one key: one device's copy of a routine's day.
    struct Copy {
        var items: [Item]
        var createdAt: Date
        var firstID: String
        /// Not all of it in the trash.
        var isLive: Bool
        /// The person ate, skipped, edited or deleted something of it.
        var isActedOn: Bool
        /// Taken out by the clean-up or a routine change before: never ranked again.
        var isMarked: Bool

        init(_ items: [Item]) {
            self.items = items
            createdAt = items.map(\.createdAt).min() ?? .distantPast
            firstID = items.map(\.id).min() ?? ""
            isLive = items.contains { !$0.isTrashed }
            isActedOn = items.contains { item in
                item.isTrashed || !PlanSchedule.isUntouched(status: item.status, createdAt: item.createdAt,
                                                            modifiedAt: item.modifiedAt)
            }
            isMarked = items.contains { PlanSchedule.isMarked(source: $0.source) }
        }

        /// The same order on every device: oldest first, then the smallest id.
        static func precedes(_ a: Copy, _ b: Copy) -> Bool {
            a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.firstID < b.firstID
        }
    }

    /// The keys a routine must not plan again: every entry's key, live or in the trash (the person
    /// deleted that day's plan, so it stays deleted), except entries a routine change took out.
    public static func takenKeys(_ items: [Item]) -> Set<String> {
        Set(items.filter { !$0.key.isEmpty && !($0.isTrashed && $0.source == retiredSource) }.map(\.key))
    }

    /// What a copy of a routine's entry becomes on another day (`copyRule`).
    public enum CopyRule: Equatable, Sendable {
        /// The routine already plans it there: leave the entry out.
        case skip
        /// It carries the routine's key for that day, so the routine doesn't plan it a second time.
        case key(String)
        /// An ordinary copy.
        case plain
    }

    /// A copy of an entry with `sourceKey` onto `day`, whose entries (live and in the trash) are
    /// `existing`. Only when the routine is active and covers that day (`ruleCovers`): a planned
    /// copy is left out when the routine's plan is already there; a day whose plan the person
    /// deleted gets an ordinary copy; any other day's copy takes the routine's key.
    public static func copyRule(sourceKey: String, to day: DayKey, planned: Bool, existing: [Item],
                                ruleCovers: (UUID) -> Bool) -> CopyRule {
        guard let rule = ruleID(of: sourceKey), ruleCovers(rule) else { return .plain }
        let target = key(rule: rule, day: day)
        if existing.contains(where: { $0.key == target && !$0.isTrashed }) { return planned ? .skip : .plain }
        return takenKeys(existing).contains(target) ? .plain : .key(target)
    }

    /// Several copies of one key (devices that planned the same routine day before they synced):
    /// the ids of the live entries to move to the trash (marked `duplicateSource`). Every device
    /// gives the same answer, and the next pass finds nothing more to do:
    /// - a copy the person acted on (ate, skipped, edited, deleted a part of) beats an untouched
    ///   one; between equals the oldest wins, then the smallest id;
    /// - a copy the person deleted, with no live copy acted on, takes the untouched live copies
    ///   with it (the person removed that plan, so it stays removed);
    /// - copies taken out by the clean-up or a routine change are never ranked again.
    /// Copies are told apart by plan key and group id; an entry without a group id (a recipe
    /// portion) is a copy of its own, so two devices' portions don't fall into one group.
    public static func duplicates(_ items: [Item]) -> [String] {
        var byGroup: [String: [Item]] = [:]
        for item in items where !item.key.isEmpty {
            byGroup[item.key + "#" + (item.groupID.isEmpty ? item.id : item.groupID), default: []].append(item)
        }
        var byKey: [String: [Copy]] = [:]
        for group in byGroup.values {
            guard let key = group.first?.key else { continue }
            byKey[key, default: []].append(Copy(group))
        }
        var result: [String] = []
        for copies in byKey.values {
            let ranked = copies.filter { !$0.isMarked }
            let live = ranked.filter(\.isLive).sorted(by: Copy.precedes)
            guard !live.isEmpty else { continue }
            let losers: [Copy]
            if let winner = live.first(where: \.isActedOn) {
                losers = live.filter { $0.firstID != winner.firstID }
            } else if ranked.contains(where: { !$0.isLive }) {
                losers = live
            } else {
                losers = Array(live.dropFirst())
            }
            for copy in losers {
                result.append(contentsOf: copy.items.filter { !$0.isTrashed }.map(\.id))
            }
        }
        return result.sorted()
    }
}
