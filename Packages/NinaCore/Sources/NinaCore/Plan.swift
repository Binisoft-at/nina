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
/// – even with several devices, which converge on the oldest group.
public enum PlanSchedule {
    public static func key(rule: UUID, day: DayKey) -> String {
        "rule:\(rule.uuidString):\(day.rawValue)"
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

    /// Of several groups created for the same key (two devices planned before they synced),
    /// keep the one created first; the others are duplicates.
    public static func duplicates<T>(_ groups: [(key: String, createdAt: Date, group: T)]) -> [T] {
        var byKey: [String: [(createdAt: Date, group: T)]] = [:]
        for item in groups where !item.key.isEmpty {
            byKey[item.key, default: []].append((item.createdAt, item.group))
        }
        var result: [T] = []
        for (_, items) in byKey where items.count > 1 {
            let sorted = items.sorted { $0.createdAt < $1.createdAt }
            result.append(contentsOf: sorted.dropFirst().map(\.group))
        }
        return result
    }
}
