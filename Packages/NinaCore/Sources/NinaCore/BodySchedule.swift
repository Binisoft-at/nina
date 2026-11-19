import Foundation

/// When to measure (F12): the weigh-in every morning until the cutoff, the weekly sites on the
/// check-in weekday, a full set (and a body-fat assessment) every few weeks on the check-in day
/// nearest to the last one + the interval, plus a baseline when the plan is set up and full sets
/// at each phase start and end and at the review checkpoint.
///
/// Missing a week never shifts the weekday; a full set also counts as that week's weekly check.
/// Everything is computed from the days things were measured; nothing here is stored.
public struct BodySchedule: Equatable, Sendable {
    /// Why something is due.
    public enum Reason: String, Codable, Sendable, CaseIterable {
        /// The regular rhythm (weekly, or every `fullEveryWeeks`).
        case schedule
        /// The plan was set up.
        case baseline
        case phaseStart
        case phaseEnd
        /// The 7-day average reached the review weight.
        case checkpoint

        /// On the same day, the first reason in this order is the one shown.
        var rank: Int {
            switch self {
            case .baseline: 0
            case .phaseStart: 1
            case .phaseEnd: 2
            case .checkpoint: 3
            case .schedule: 4
            }
        }
    }

    /// A day that asks for a full set (and an assessment).
    public struct Event: Equatable, Sendable, Codable {
        public var day: DayKey
        public var reason: Reason

        public init(day: DayKey, reason: Reason) {
            self.day = day
            self.reason = reason
        }
    }

    /// A due day and why.
    public struct Due: Equatable, Sendable, Codable {
        public var day: DayKey
        public var reason: Reason

        public init(day: DayKey, reason: Reason) {
            self.day = day
            self.reason = reason
        }

        /// Days past the due day on `day` (0 on the due day or before it).
        public func overdueDays(on day: DayKey, calendar: Calendar = .current) -> Int {
            max(0, self.day.days(to: day, calendar: calendar))
        }
    }

    /// A full set (or assessment) up to this many days before an event counts for it.
    public static let recentDays = 14
    /// An item this many days overdue says so ("overdue 3 days") once.
    public static let overdueNoticeDays = 3

    public var routine: CoachPlan.Routine
    /// The day the plan was set up: the baseline is due then. Nothing is due before it.
    public var start: DayKey?
    /// Days with a weekly site measured, full sets included (sorted).
    public var weeklyDays: [DayKey]
    /// Days with a full set (sorted).
    public var fullDays: [DayKey]
    /// Days with a body-fat assessment (sorted).
    public var assessmentDays: [DayKey]
    /// Phase starts and ends, the review checkpoint (the baseline comes from `start`).
    public var events: [Event]
    /// Nothing is due on paused days.
    public var pauses: [CoachPlan.Pause]
    /// Without a plan nothing is due.
    public var isSetUp: Bool

    public init(routine: CoachPlan.Routine = CoachPlan.Routine(), start: DayKey? = nil, weeklyDays: [DayKey] = [],
                fullDays: [DayKey] = [], assessmentDays: [DayKey] = [], events: [Event] = [], pauses: [CoachPlan.Pause] = [],
                isSetUp: Bool = true) {
        self.routine = routine
        self.start = start
        self.fullDays = Array(Set(fullDays)).sorted()
        self.weeklyDays = Array(Set(weeklyDays + fullDays)).sorted()
        self.assessmentDays = Array(Set(assessmentDays)).sorted()
        self.events = events
        self.pauses = pauses
        self.isSetUp = isSetUp
    }

    /// The schedule of a plan. `start`: the day the plan was set up (see `setUpDay(of:)`).
    /// `tape`: all tape records (any conditions; the sites measured on one day count together).
    /// `assessmentDays`: days of body-fat assessment records. `checkpoint`: the day the review
    /// checkpoint fired (`checkpointCrossed`), if it did.
    public init(plan: CoachPlan, start: DayKey?, tape: [BodyTapeRecord], assessmentDays: [DayKey], checkpoint: DayKey? = nil) {
        var sitesByDay: [DayKey: Set<BodySite>] = [:]
        for record in tape {
            sitesByDay[record.day, default: []].formUnion(record.values.sites.keys.map(\.base))
        }
        let routine = plan.routine
        let full = sitesByDay.filter { BodySchedule.isFullSet($0.value, routine: routine) }.map(\.key)
        let weekly = sitesByDay.filter { BodySchedule.coversWeekly($0.value, routine: routine) }.map(\.key)
        var events: [Event] = []
        for phase in plan.phases where phase.isStarted {
            if let day = phase.start { events.append(Event(day: day, reason: .phaseStart)) }
            if let day = phase.end { events.append(Event(day: day, reason: .phaseEnd)) }
        }
        if let checkpoint { events.append(Event(day: checkpoint, reason: .checkpoint)) }
        self.init(routine: routine, start: start, weeklyDays: weekly, fullDays: full, assessmentDays: assessmentDays,
                  events: events, pauses: plan.pauses, isSetUp: plan.isSetUp)
    }

    /// A fallback for the day the plan was set up: the earliest start of a started phase.
    public static func setUpDay(of plan: CoachPlan) -> DayKey? {
        plan.phases.filter(\.isStarted).compactMap(\.start).min()
    }

    /// The check-in weekday, 1 (Monday) … 7.
    public var checkInWeekday: Int { min(7, max(1, routine.checkInWeekday)) }

    /// Body-fat assessments are scheduled: an interval is set and the tracking method isn't the
    /// tape estimate (that one comes from the full set's tape values).
    public var needsAssessments: Bool { routine.bodyFatEveryWeeks > 0 && routine.bodyFatMethod != .navy }

    /// The weekly sites with their side keys.
    public var weeklySites: [BodySite] { BodySchedule.expanded(routine.weeklySites, side: routine.side) }
    /// The full-set sites with their side keys.
    public var fullSites: [BodySite] { BodySchedule.expanded(routine.fullSites, side: routine.side) }

    // MARK: Classifying a day's tape values

    /// The sites measured on a day make a full set: at least half of the full-set sites (at least
    /// 2, or the only one), including one that isn't a weekly site. Skipping a site or two still
    /// counts; a weekly waist alone doesn't.
    public static func isFullSet(_ sites: Set<BodySite>, routine: CoachPlan.Routine) -> Bool {
        let wanted = Set(routine.fullSites.map(\.base))
        guard !wanted.isEmpty else { return false }
        let got = wanted.intersection(sites.map(\.base))
        let needed = wanted.count == 1 ? 1 : max(2, Int((Double(wanted.count) / 2).rounded(.up)))
        guard got.count >= needed else { return false }
        let extra = wanted.subtracting(routine.weeklySites.map(\.base))
        return extra.isEmpty || !got.isDisjoint(with: extra)
    }

    /// The sites measured on a day include a weekly site.
    public static func coversWeekly(_ sites: Set<BodySite>, routine: CoachPlan.Routine) -> Bool {
        !Set(routine.weeklySites.map(\.base)).isDisjoint(with: sites.map(\.base))
    }

    static func expanded(_ sites: [BodySite], side: BodySide) -> [BodySite] {
        var seen = Set<BodySite>()
        return sites.flatMap { $0.sites(for: side) }.filter { seen.insert($0).inserted }
    }

    // MARK: Weekdays

    /// The day with that ISO weekday nearest to `day` (never a tie: the two candidates are 3 and 4
    /// days away at most).
    public static func nearest(weekday: Int, to day: DayKey, calendar: Calendar = .current) -> DayKey {
        let current = day.weekday(calendar: calendar)
        let forward = (weekday - current + 7) % 7
        let backward = (current - weekday + 7) % 7
        return forward <= backward ? day.adding(days: forward, calendar: calendar) : day.adding(days: -backward, calendar: calendar)
    }

    /// The latest day with that ISO weekday on or before `day`.
    public static func onOrBefore(weekday: Int, _ day: DayKey, calendar: Calendar = .current) -> DayKey {
        day.adding(days: -((day.weekday(calendar: calendar) - weekday + 7) % 7), calendar: calendar)
    }

    /// The first day with that ISO weekday on or after `day`.
    public static func onOrAfter(weekday: Int, _ day: DayKey, calendar: Calendar = .current) -> DayKey {
        day.adding(days: (weekday - day.weekday(calendar: calendar) + 7) % 7, calendar: calendar)
    }

    // MARK: Next due days

    /// The weekly measurement: this week's check-in day while nothing was measured since it
    /// (overdue after it), otherwise next week's. A missed week never shifts the weekday. Nothing
    /// is due before `start`.
    public static func nextWeekly(lastMeasured: DayKey?, today: DayKey, checkInWeekday: Int, start: DayKey? = nil,
                                  calendar: Calendar = .current) -> DayKey {
        let weekday = min(7, max(1, checkInWeekday))
        let current = onOrBefore(weekday: weekday, today, calendar: calendar)
        if let start, current < start { return onOrAfter(weekday: weekday, start, calendar: calendar) }
        if let lastMeasured, lastMeasured >= current { return current.adding(days: 7, calendar: calendar) }
        return current
    }

    /// The next full set by the rhythm: the check-in weekday nearest to the last full set +
    /// `everyWeeks` weeks (never before `start`). Without a full set yet: `start` (the baseline).
    /// nil without either, or without an interval.
    public static func nextFull(lastFull: DayKey?, everyWeeks: Int, checkInWeekday: Int, start: DayKey? = nil,
                                calendar: Calendar = .current) -> DayKey? {
        guard let lastFull else { return start }
        guard everyWeeks > 0 else { return nil }
        let day = nearest(weekday: min(7, max(1, checkInWeekday)), to: lastFull.adding(days: everyWeeks * 7, calendar: calendar),
                          calendar: calendar)
        if let start, day < start { return start }
        return day
    }

    /// The weekly sites' due day as of `today` (nil without weekly sites).
    public func nextWeekly(today: DayKey, calendar: Calendar = .current) -> DayKey? {
        guard !routine.weeklySites.isEmpty else { return nil }
        return BodySchedule.nextWeekly(lastMeasured: weeklyDays.last { $0 <= today }, today: today, checkInWeekday: checkInWeekday,
                                       start: start, calendar: calendar)
    }

    /// The next full set as of `today` (on or before `today` = due): the earliest of the rhythm
    /// (from the last full set), the latest event that has passed without a full set within 14
    /// days before it, and the next event to come. nil when nothing is planned.
    public func nextFull(today: DayKey, calendar: Calendar = .current) -> Due? {
        next(done: fullDays, everyWeeks: routine.fullEveryWeeks, today: today, calendar: calendar)
    }

    /// The next body-fat assessment, by the same rules with `bodyFatEveryWeeks` (nil when
    /// assessments aren't scheduled).
    public func nextAssessment(today: DayKey, calendar: Calendar = .current) -> Due? {
        guard needsAssessments else { return nil }
        return next(done: assessmentDays, everyWeeks: routine.bodyFatEveryWeeks, today: today, calendar: calendar)
    }

    /// All events, the baseline included, none before `start`.
    var allEvents: [Event] {
        var all = events
        if let start { all.append(Event(day: start, reason: .baseline)) }
        return start.map { start in all.filter { $0.day >= start } } ?? all
    }

    private func next(done allDone: [DayKey], everyWeeks: Int, today: DayKey, calendar: Calendar) -> Due? {
        let done = allDone.filter { $0 <= today }
        var candidates: [Due] = []
        if let last = done.last, everyWeeks > 0,
           let day = BodySchedule.nextFull(lastFull: last, everyWeeks: everyWeeks, checkInWeekday: checkInWeekday, start: start,
                                           calendar: calendar) {
            candidates.append(Due(day: day, reason: .schedule))
        }
        func satisfied(_ event: Event) -> Bool {
            let from = event.day.adding(days: -BodySchedule.recentDays, calendar: calendar)
            return done.contains { $0 >= from }
        }
        func first(_ events: [Event], latest: Bool) -> Event? {
            events.min { lhs, rhs in
                if lhs.day != rhs.day { return latest ? lhs.day > rhs.day : lhs.day < rhs.day }
                return lhs.reason.rank < rhs.reason.rank
            }
        }
        let events = allEvents
        // A full set done for a later event also covers earlier ones, so only the latest past
        // event can still be open.
        if let latest = first(events.filter { $0.day <= today }, latest: true), !satisfied(latest) {
            candidates.append(Due(day: latest.day, reason: latest.reason))
        }
        if let upcoming = first(events.filter { $0.day > today && !satisfied($0) }, latest: false) {
            candidates.append(Due(day: upcoming.day, reason: upcoming.reason))
        }
        return candidates.min { lhs, rhs in
            lhs.day != rhs.day ? lhs.day < rhs.day : lhs.reason.rank < rhs.reason.rank
        }
    }

    // MARK: Review checkpoint

    /// The weight that fires a phase's review checkpoint: the lower bound of the review range
    /// (the upper one when only that is set), as `WeightSignal.checkpoint(of:)`. nil for maintain
    /// phases or without a review range.
    public static func reviewThreshold(of phase: CoachPlan.Phase) -> Double? {
        WeightSignal.checkpoint(of: phase)
    }

    /// The first day (from `since` on) whose 7-day average reached `threshold`: at or above it
    /// while gaining, at or below it while losing (`WeightSignal.hasReached`). Single weigh-ins
    /// never count; pass valid 7-day averages only (`WeightSignal.averageHistory`). nil while
    /// maintaining or until it happens.
    public static func checkpointCrossed(avg7History: [DayKey: Double], threshold: Double, goal: WeightGoal,
                                         since: DayKey? = nil) -> DayKey? {
        guard threshold > 0, goal != .maintain else { return nil }
        return avg7History.filter { entry in
            guard entry.value.isFinite, since.map({ entry.key >= $0 }) ?? true else { return false }
            return WeightSignal.hasReached(entry.value, checkpoint: threshold, goal: goal)
        }.keys.min()
    }

    /// The checkpoint of a phase (from its start, at `reviewThreshold(of:)`).
    public static func checkpointCrossed(avg7History: [DayKey: Double], phase: CoachPlan.Phase) -> DayKey? {
        guard let threshold = reviewThreshold(of: phase) else { return nil }
        return checkpointCrossed(avg7History: avg7History, threshold: threshold, goal: phase.goal, since: phase.start)
    }

    // MARK: Due items

    /// What the Today strip shows for `day`, in order: "Weigh in" (only with `now`, before the
    /// morning cutoff, while there is no morning weigh-in), then "Full measurement" (with the
    /// body-fat step when that is due too) or else the weekly sites and a separate body-fat
    /// assessment. Pass `now` only when `day` is today. Nothing without a plan or on a paused day.
    public func dueItems(on day: DayKey, now: Date? = nil, hasMorningWeighIn: Bool = false,
                         calendar: Calendar = .current) -> [BodyDueItem] {
        guard isSetUp, !pauses.contains(where: { $0.contains(day) }) else { return [] }
        var items: [BodyDueItem] = []
        if let now, !hasMorningWeighIn, ClockTime.minutes(of: now, calendar: calendar) < routine.morningCutoffMinutes {
            items.append(BodyDueItem(kind: .weighIn, dueDay: day, overdueDays: 0, reason: .schedule))
        }
        let assessment = nextAssessment(today: day, calendar: calendar).flatMap { $0.day <= day ? $0 : nil }
        if let full = nextFull(today: day, calendar: calendar), full.day <= day {
            items.append(BodyDueItem(kind: .full, dueDay: full.day, overdueDays: full.overdueDays(on: day, calendar: calendar),
                                     reason: full.reason, sites: fullSites, includesAssessment: assessment != nil))
            return items
        }
        if let weekly = nextWeekly(today: day, calendar: calendar), weekly <= day {
            items.append(BodyDueItem(kind: .weekly, dueDay: weekly, overdueDays: max(0, weekly.days(to: day, calendar: calendar)),
                                     reason: .schedule, sites: weeklySites))
        }
        if let assessment {
            items.append(BodyDueItem(kind: .assessment, dueDay: assessment.day,
                                     overdueDays: assessment.overdueDays(on: day, calendar: calendar), reason: assessment.reason))
        }
        return items
    }
}

/// One pill in the Today checks strip for the body: weigh in, the weekly sites, the full set or a
/// body-fat assessment.
public struct BodyDueItem: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case weighIn, weekly, full, assessment
    }

    public var kind: Kind
    /// The day it became due.
    public var dueDay: DayKey
    /// 0 on the due day.
    public var overdueDays: Int
    public var reason: BodySchedule.Reason
    /// Weekly and full: the sites to measure (side keys included).
    public var sites: [BodySite]
    /// Full: the body-fat assessment step is due as well.
    public var includesAssessment: Bool

    public init(kind: Kind, dueDay: DayKey, overdueDays: Int = 0, reason: BodySchedule.Reason = .schedule, sites: [BodySite] = [],
                includesAssessment: Bool = false) {
        self.kind = kind
        self.dueDay = dueDay
        self.overdueDays = overdueDays
        self.reason = reason
        self.sites = sites
        self.includesAssessment = includesAssessment
    }

    public var id: String { kind.rawValue }

    /// "Weigh in", "Waist" (the one weekly site), "Measurements", "Full measurement", "Body fat".
    public var title: String {
        switch kind {
        case .weighIn: return "Weigh in"
        case .weekly:
            let bases = sites.reduce(into: [BodySite]()) { result, site in
                if !result.contains(site.base) { result.append(site.base) }
            }
            return bases.count == 1 ? bases[0].title : "Measurements"
        case .full: return "Full measurement"
        case .assessment: return "Body fat"
        }
    }

    /// "overdue 3 days"; nil when not overdue.
    public var overdueText: String? {
        guard overdueDays > 0 else { return nil }
        return "overdue \(overdueDays) \(overdueDays == 1 ? "day" : "days")"
    }

    /// Overdue long enough to say so (once; then it waits for the check-in).
    public var isOverdueNotice: Bool { overdueDays >= BodySchedule.overdueNoticeDays }
}
