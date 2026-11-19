import Foundation

// What the Progress page (Body) and Insights read from the plan's daily checks and the saved
// check-ins: check adherence over the last 28 days (F10), the chart event of a check that moves
// the scale (F10/F11) and the weight numbers of a saved check-in for the history list (F11).

/// Daily-check adherence on the Body page: one plain line, "Creatine 26 of 28 days", no streaks.
public enum ProgressChecks {
    /// The window: the last 28 days, today included.
    public static let windowDays = 28

    /// The adherence line and the days it covers.
    public struct Adherence: Equatable, Sendable {
        /// "Creatine 26 of 28 days · Fish oil 4 days".
        public var text: String
        /// The first day counted.
        public var start: DayKey
        /// The window starts later than 28 days ago (the plan is newer than that).
        public var isShortened: Bool

        public init(text: String, start: DayKey, isShortened: Bool) {
            self.text = text
            self.start = start
            self.isShortened = isShortened
        }
    }

    /// The first day of the window: 27 days before today, but never before the plan was set up
    /// (`setUp`, e.g. `BodySchedule.setUpDay(of:)`) and never after today.
    public static func windowStart(today: DayKey, setUp: DayKey?, calendar: Calendar = .current) -> DayKey {
        let earliest = today.adding(days: -(windowDays - 1), calendar: calendar)
        guard let setUp else { return earliest }
        return min(today, max(earliest, setUp))
    }

    /// Check adherence from `start` through `today`. A check still open today isn't missed yet,
    /// paused days are left out, and optional checks only count their ticks ("Fish oil 4 days").
    /// `done`: the checks ticked done per day; `marks`: the day-type marks (DayKey raw → type id)
    /// for checks due on certain day types. nil without a set-up plan with checks, or when
    /// nothing was due or ticked.
    public static func adherence(plan: CoachPlan, today: DayKey, start: DayKey, done: [DayKey: Set<String>],
                                 marks: [String: String] = [:], calendar: Calendar = .current) -> Adherence? {
        guard plan.isSetUp, !plan.checks.isEmpty, start <= today else { return nil }
        let days = DayKey.range(start, through: today, calendar: calendar).filter { !plan.isPaused(on: $0) }
        var typeIDs: [DayKey: String] = [:]
        for day in days {
            if let id = plan.dayType(on: day, marks: marks, calendar: calendar)?.id { typeIDs[day] = id }
        }
        var parts: [String] = []
        for check in plan.checks {
            var due = 0
            var ticked = 0
            for day in days {
                let isDone = done[day]?.contains(check.id) ?? false
                if day == today, !isDone { continue }
                if isDone || check.isDue(on: day, dayTypeID: typeIDs[day], calendar: calendar) { due += 1 }
                if isDone { ticked += 1 }
            }
            let name = check.name.isEmpty ? "Check" : check.name
            if check.isOptional {
                if ticked > 0 { parts.append("\(name) \(ticked) \(ticked == 1 ? "day" : "days")") }
            } else if due > 0 {
                parts.append("\(name) \(ticked) of \(due) \(due == 1 ? "day" : "days")")
            }
        }
        guard !parts.isEmpty else { return nil }
        let full = today.adding(days: -(windowDays - 1), calendar: calendar)
        return Adherence(text: parts.joined(separator: " · "), start: start, isShortened: start > full)
    }
}

/// The first tick of a check that moves the scale (creatine): an event on the weight chart and,
/// for the 28 days "faster than planned" is held (`CheckInEngine.weightCheckHoldDays`), the note
/// "Creatine started 9 days ago – up to ~1 kg may be water".
public struct ProgressWeightEvent: Equatable, Sendable, Identifiable {
    public var checkID: String
    public var name: String
    /// The first day it was ticked done.
    public var day: DayKey

    public init(checkID: String, name: String, day: DayKey) {
        self.checkID = checkID
        self.name = name
        self.day = day
    }

    public var id: String { checkID }

    /// "Creatine started" (the chart label).
    public var title: String { "\(name) started" }

    /// Days since the first tick, 0 on that day.
    public func days(on today: DayKey, calendar: Calendar = .current) -> Int {
        day.days(to: today, calendar: calendar)
    }

    /// Within the 28-day hold (from the first tick on).
    public func isHolding(on today: DayKey, calendar: Calendar = .current) -> Bool {
        let since = days(on: today, calendar: calendar)
        return since >= 0 && since < CheckInEngine.weightCheckHoldDays
    }

    /// "Creatine started 9 days ago – up to ~1 kg may be water" during the hold, else nil.
    public func note(on today: DayKey, calendar: Calendar = .current) -> String? {
        guard isHolding(on: today, calendar: calendar) else { return nil }
        let since = days(on: today, calendar: calendar)
        let when: String
        switch since {
        case 0: when = "today"
        case 1: when = "1 day ago"
        default: when = "\(since) days ago"
        }
        return "\(name) started \(when) – up to ~1 kg may be water"
    }

    /// One event per check in the plan that affects weight and was ticked done: its first done
    /// tick, oldest first. `ticks`: (day, check id) of every done tick (`NinaStore.checkTicks()`).
    public static func events(in plan: CoachPlan, ticks: [(day: DayKey, checkID: String)]) -> [ProgressWeightEvent] {
        var first: [String: DayKey] = [:]
        for tick in ticks {
            guard let check = plan.check(id: tick.checkID), check.affectsWeight else { continue }
            if let current = first[check.id], current <= tick.day { continue }
            first[check.id] = tick.day
        }
        return plan.checks.compactMap { check -> ProgressWeightEvent? in
            guard let day = first[check.id] else { return nil }
            return ProgressWeightEvent(checkID: check.id, name: check.name.isEmpty ? check.id : check.name, day: day)
        }
        .sorted { ($0.day, $0.checkID) < ($1.day, $1.checkID) }
    }
}

/// The weight numbers of a saved check-in for the history list ("avg 74.6 kg · +0.18 kg/wk").
public enum ProgressCheckIns {
    /// The 7-day average and the decision rate of the check-in day. Saved numbers are used as
    /// they are; when Apple Health weights were among them (`usesHealthWeights`) nothing was
    /// stored, so both are recomputed from the live signal with the plan's rules.
    public static func weight(of snapshot: CheckInSnapshot, signal: WeightSignal, plan: CoachPlan) -> (average: Double?, rate: Double?) {
        guard snapshot.usesHealthWeights else { return (snapshot.avg7, snapshot.rate) }
        return (signal.average(on: snapshot.day).value, signal.rate(on: snapshot.day, plan: plan).value)
    }
}
