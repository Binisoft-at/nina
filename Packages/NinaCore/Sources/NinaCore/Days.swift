import Foundation

/// A calendar day as "2026-11-13". Entries store the day they count for, so a snack at 01:00
/// can still belong to yesterday (`dayStartHour`), and travelling across time zones never moves
/// what was eaten to another day. Sorts correctly as text.
public struct DayKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible, Identifiable {
    public let rawValue: String

    public init?(_ raw: String) {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), year > 1900 else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init(year: Int, month: Int, day: Int) {
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The day `date` counts for. With `dayStartHour` 3, 02:30 still counts for the day before.
    public init(date: Date, calendar: Calendar = .current, dayStartHour: Int = 0) {
        let shifted = date.addingTimeInterval(-Double(max(0, min(dayStartHour, 12))) * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a day: \(raw)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date(), dayStartHour: Int = 0) -> DayKey {
        DayKey(date: now, calendar: calendar, dayStartHour: dayStartHour)
    }

    public var id: String { rawValue }
    public var description: String { rawValue }
    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public var year: Int { Int(rawValue.prefix(4)) ?? 2000 }
    public var month: Int { Int(rawValue.dropFirst(5).prefix(2)) ?? 1 }
    public var day: Int { Int(rawValue.suffix(2)) ?? 1 }

    /// Midnight at the start of the day.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// A moment on this day at the wall-clock time `minutes` after midnight ("07:00" stays 07:00
    /// on daylight-saving change days). Minutes of 1,440 or more (or below 0) move to the days
    /// after (or before): 1,510 = 01:10 the next day. A time the clock skips (02:30 when it
    /// springs forward) moves forward with it.
    public func date(minutes: Int, calendar: Calendar = .current) -> Date {
        let days = Int((Double(minutes) / 1440).rounded(.down))
        let rest = minutes - days * 1440
        let target = days == 0 ? self : adding(days: days, calendar: calendar)
        let parts = DateComponents(year: target.year, month: target.month, day: target.day, hour: rest / 60, minute: rest % 60)
        return calendar.date(from: parts) ?? target.date(calendar: calendar)
    }

    /// A moment on this diary day at the clock time `minutes` (0..<1440) when the day starts at
    /// `dayStartHour`: a time before the start belongs to the end of the day, so it falls on the
    /// next calendar date (with the day starting at 3:00, 00:30 is the night after).
    public func date(minutes: Int, dayStartHour: Int, calendar: Calendar = .current) -> Date {
        date(minutes: ClockTime.diaryMinutes(minutes, dayStartHour: dayStartHour), calendar: calendar)
    }

    /// When this diary day starts: `dayStartHour` hours after its midnight, the moment
    /// `DayKey(date:dayStartHour:)` moves on to it. On a daylight-saving night that is an hour off
    /// the wall clock (03:00 becomes 04:00 in spring), so the two always agree.
    public func start(dayStartHour: Int, calendar: Calendar = .current) -> Date {
        date(calendar: calendar).addingTimeInterval(Double(DayKey.clampedStartHour(dayStartHour)) * 3600)
    }

    /// The day start hour as `DayKey(date:dayStartHour:)` uses it (0…12).
    static func clampedStartHour(_ hour: Int) -> Int { max(0, min(hour, 12)) }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        // Noon avoids daylight-saving edges.
        let noon = calendar.date(byAdding: .hour, value: 12, to: date(calendar: calendar)) ?? date(calendar: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: noon) ?? noon
        return DayKey(date: moved, calendar: calendar)
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    public func weekday(calendar: Calendar = .current) -> Int {
        let gregorian = calendar.component(.weekday, from: date(calendar: calendar)) // 1 = Sunday
        return gregorian == 1 ? 7 : gregorian - 1
    }

    /// Whole days from this day to `other` (negative when `other` is earlier).
    public func days(to other: DayKey, calendar: Calendar = .current) -> Int {
        let start = calendar.date(byAdding: .hour, value: 12, to: date(calendar: calendar)) ?? date(calendar: calendar)
        let end = calendar.date(byAdding: .hour, value: 12, to: other.date(calendar: calendar)) ?? other.date(calendar: calendar)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Every day from `start` through `end` (inclusive).
    public static func range(_ start: DayKey, through end: DayKey, calendar: Calendar = .current) -> [DayKey] {
        guard start <= end else { return [] }
        var days: [DayKey] = []
        var current = start
        while current <= end, days.count < 3700 {
            days.append(current)
            current = current.adding(days: 1, calendar: calendar)
        }
        return days
    }

    /// Monday of this day's week.
    public func startOfWeek(calendar: Calendar = .current) -> DayKey {
        adding(days: 1 - weekday(calendar: calendar), calendar: calendar)
    }

    /// First day of this day's month.
    public var startOfMonth: DayKey { DayKey(year: year, month: month, day: 1) }
}

/// Minutes after midnight ↔ "07:30".
public enum ClockTime {
    public static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// A clock time counted from the diary day's start: with the day starting at 3:00, 00:30 comes
    /// after dinner (1,470). Sorts meal slots and planned times the way the day runs.
    public static func diaryMinutes(_ minutes: Int, dayStartHour: Int) -> Int {
        minutes < DayKey.clampedStartHour(dayStartHour) * 60 ? minutes + 1440 : minutes
    }

    public static func text(_ minutes: Int) -> String {
        let clamped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "7:30", "07:30", "7.30", "19h", "730" → minutes after midnight.
    public static func parse(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "h", with: ":")
            .replacingOccurrences(of: ".", with: ":")
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count >= 2, let hour = Int(parts[0]) {
            let minute = Int(parts[1]) ?? 0
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        guard let number = Int(text) else { return nil }
        if number <= 23 { return number * 60 }
        let hour = number / 100, minute = number % 100
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
