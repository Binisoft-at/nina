import Foundation

/// The coach's local notifications (F17), planned as plain values: the morning weigh-in, daily
/// checks, the evening before a full measurement, the weekly check-in and phase dates. The app
/// turns the requests into `UNNotificationRequest`s on every reschedule (3-day window), so a task
/// done on any device takes its notification away.
///
/// Quiet rules: nothing before 06:00 or after 21:00; at most one coach notification before 10:00
/// (checks with breakfast, before 09:00 or "anytime" ride along in the morning one, anything else
/// before 10:00 moves to 10:00); a pause silences them all.
public enum CoachReminders {
    /// Days planned ahead, today included (the app's notification window).
    public static let windowDays = 3
    /// Nothing before 06:00 …
    public static let earliestMinutes = 6 * 60
    /// … or after 21:00.
    public static let latestMinutes = 21 * 60
    /// At most one coach notification before 10:00.
    public static let morningUntilMinutes = 10 * 60
    /// Checks due before 09:00 (or with breakfast) are folded into the morning notification.
    public static let foldBeforeMinutes = 9 * 60
    public static let measureEveningMinutes = 20 * 60
    public static let checkInMinutes = 18 * 60
    public static let phaseMinutes = 9 * 60
    /// The most actions a notification shows.
    public static let maxActions = 4
    /// Every coach notification id starts with this.
    public static let idPrefix = "nina.coach."

    /// The kinds people can turn on and off (Settings > Reminders > Coach; device-only).
    public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
        case morning, check, measure, checkIn, phase

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .morning: "Morning weigh-in"
            case .check: "Daily checks"
            case .measure: "Evening before a full measurement"
            case .checkIn: "Weekly check-in"
            case .phase: "Phase start, end and review"
            }
        }
    }

    // MARK: Input

    /// Everything the plan needs, as plain values (built by the app from the store).
    public struct Input: Sendable {
        public var plan: CoachPlan
        public var now: Date
        public var today: DayKey
        /// The kinds turned on on this device.
        public var kinds: Set<Kind>
        /// Live day-type marks: DayKey raw value → type id.
        public var dayTypeMarks: [String: String] = [:]
        /// Each day's resolved targets (what Today shows), for "Today 2,400 kcal · 150 g protein".
        public var targets: [DayKey: DailyTargets] = [:]
        public var energyUnit: EnergyUnit = .kcal
        /// The meals and their usual times (checks timed for a meal).
        public var meals: [MealSlot] = MealSlot.defaults
        /// Days that already have a morning weigh-in.
        public var weighedIn: Set<DayKey> = []
        /// The latest weight: the placeholder of "Weight…".
        public var lastWeight: Double?
        /// The latest typed tape value per site: the placeholder of "Waist…" (`lastTape(_:)`).
        public var lastTape: [BodySite: Double] = [:]
        /// Each day's ticked checks: check id → done or skipped (missing = open).
        public var checkStates: [DayKey: [String: CheckState]] = [:]
        /// Saved check-ins ("week-2030-01-07").
        public var checkInKeys: Set<String> = []
        /// Each day's due body items (`BodySchedule.dueItems(on:)` without `now`).
        public var bodyDue: [DayKey: [BodyDueItem]] = [:]
        /// The last full set ("like on 7 Jan").
        public var lastFullSet: DayKey?
        /// The first day the 7-day average reached the active phase's review weight
        /// (`WeightSignal.checkpointCrossing(in:through:)`).
        public var checkpoint: DayKey?
        /// Phases with a review decision.
        public var reviewedPhases: Set<String> = []
        /// When each phase's review notification was first planned (device-only): it comes once.
        public var reviewPlannedAt: [String: Date] = [:]
        public var days: Int = CoachReminders.windowDays
        public var calendar: Calendar = .current

        public init(plan: CoachPlan, now: Date, today: DayKey, kinds: Set<Kind> = Set(Kind.allCases), calendar: Calendar = .current) {
            self.plan = plan
            self.now = now
            self.today = today
            self.kinds = kinds
            self.calendar = calendar
        }
    }

    // MARK: Output

    /// A button on a notification.
    public struct Action: Equatable, Sendable, Identifiable {
        public enum Style: Equatable, Sendable {
            /// Handled without opening the app.
            case background
            /// Opens the app.
            case foreground
            /// A text field in the banner ("Weight…", "Waist…").
            case textInput(button: String, placeholder: String)
        }

        /// What the app does: see `Command` (`open:<url>`, `weight`, `tape:<site>`,
        /// `check.done:<id>`, `check.skip:<id>`, `daytype:<id>`).
        public var id: String
        public var title: String
        public var style: Style

        public init(id: String, title: String, style: Style) {
            self.id = id
            self.title = title
            self.style = style
        }
    }

    /// A notification category: its actions (regenerated from the plan on every reschedule).
    public struct Category: Equatable, Sendable, Identifiable {
        public var id: String
        public var actions: [Action]

        public init(id: String, actions: [Action]) {
            self.id = id
            self.actions = actions
        }
    }

    /// One notification.
    public struct Request: Equatable, Sendable, Identifiable {
        /// Stable: "nina.coach.morning.2030-01-07", "nina.coach.check.creatine.2030-01-07" …
        public var id: String
        public var kind: Kind
        /// The day it belongs to (the check's day, the evening of the measurement eve).
        public var day: DayKey
        public var date: Date
        /// Minutes after midnight of `day`.
        public var minutes: Int
        public var title: String
        public var body: String
        public var category: Category
        /// What a tap on the notification opens (a nina:// URL).
        public var url: String
        /// The check of a check notification.
        public var checkID: String?

        public init(id: String, kind: Kind, day: DayKey, date: Date, minutes: Int, title: String, body: String,
                    category: Category, url: String, checkID: String? = nil) {
            self.id = id
            self.kind = kind
            self.day = day
            self.date = date
            self.minutes = minutes
            self.title = title
            self.body = body
            self.category = category
            self.url = url
            self.checkID = checkID
        }
    }

    /// Every coach notification of the window, earliest first, and their categories.
    public struct Schedule: Equatable, Sendable {
        /// Also the ones whose time passed today (a delivered one stays while its task is open).
        public var requests: [Request]

        public init(requests: [Request]) {
            self.requests = requests
        }

        public static let empty = Schedule(requests: [])

        /// What to hand to the system: the requests still ahead.
        public func pending(after now: Date) -> [Request] { requests.filter { $0.date > now } }

        /// Every request's id: delivered coach notifications with another id are done.
        public var ids: Set<String> { Set(requests.map(\.id)) }

        /// The categories the requests use, each once.
        public var categories: [Category] {
            var seen: Set<String> = []
            return requests.compactMap { request in seen.insert(request.category.id).inserted ? request.category : nil }
        }

        public func request(_ id: String) -> Request? { requests.first { $0.id == id } }
    }

    // MARK: Planning

    /// The coach notifications of the window (empty without a set-up plan).
    public static func plan(_ input: Input) -> Schedule {
        guard input.plan.isSetUp, !input.kinds.isEmpty else { return .empty }
        let calendar = input.calendar
        var requests: [Request] = []
        var reviewRequest = review(input)
        for offset in 0..<max(1, input.days) {
            let day = input.today.adding(days: offset, calendar: calendar)
            guard !input.plan.isPaused(on: day) else { continue }
            var dayRequests: [Request] = []
            if let morning = morning(on: day, input) { dayRequests.append(morning) }
            dayRequests += checks(on: day, input)
            if let measure = measureEvening(on: day, input) { dayRequests.append(measure) }
            if let checkIn = checkIn(on: day, input) { dayRequests.append(checkIn) }
            dayRequests += phases(on: day, input)
            if let review = reviewRequest, review.day == day {
                dayRequests.append(review)
                reviewRequest = nil
            }
            requests += oneBeforeTen(dayRequests, calendar: calendar)
        }
        // A review planned outside the window (it came earlier): kept, so a delivered one stays.
        if let review = reviewRequest, !input.plan.isPaused(on: review.day) { requests.append(review) }
        return Schedule(requests: requests.sorted { ($0.date, $0.id) < ($1.date, $1.id) })
    }

    /// The morning notification: the weigh-in (until done), the checks folded into it, today's
    /// targets, a measurement due today ("Waist…" right in the banner for a one-site weekly
    /// measurement, else a Measure button), and "Tennis today" on a default day with a flexible
    /// type still open this week.
    static func morning(on day: DayKey, _ input: Input) -> Request? {
        let plan = input.plan
        let weighIn = input.kinds.contains(.morning) && !input.weighedIn.contains(day)
        let folded = dueChecks(on: day, input).filter { isFolded($0, input) }
        guard weighIn || !folded.isEmpty else { return nil }
        let type = plan.dayType(on: day, marks: input.dayTypeMarks, calendar: input.calendar)

        var title = "Good morning"
        if let type { title += " · \(label(of: type)) day" }
        var lines: [String] = []
        if weighIn { lines.append("Weigh in before breakfast.") }
        for check in folded { lines.append("\(checkTitle(check)) \(timingText(check, input)).") }
        let measure = (input.bodyDue[day] ?? []).first { $0.dueDay == day && $0.kind != .weighIn }
        if let measure { lines.append("\(measure.title) today.") }
        if let targets = input.targets[day], targets.energy > 0 {
            let energy = SettingsCSV.grouped(input.energyUnit.value(fromKilocalories: targets.energy))
            var line = "Today \(energy) \(input.energyUnit.symbol)"
            if targets.protein > 0 { line += " · \(SettingsCSV.grouped(targets.protein)) g protein" }
            lines.append(line + ".")
        }

        var actions: [Action] = []
        if weighIn {
            let placeholder = input.lastWeight.map { NumberText.plain($0, decimals: 1) + " kg" } ?? "kg"
            actions.append(Action(id: weightActionID, title: "Weight…", style: .textInput(button: "Save", placeholder: placeholder)))
        }
        if let site = measure.flatMap({ bannerSite(of: $0) }) {
            let placeholder = input.lastTape[site].map { NumberText.plain($0, decimals: 1) + " cm" } ?? "cm"
            actions.append(Action(id: tapePrefix + site.rawValue, title: "\(site.title)…",
                                  style: .textInput(button: "Save", placeholder: placeholder)))
        } else if measure != nil {
            actions.append(Action(id: openPrefix + "nina://measure", title: "Measure", style: .foreground))
        }
        if let flexible = flexibleOffer(on: day, input) {
            actions.append(Action(id: dayTypePrefix + flexible.id, title: "\(label(of: flexible)) today", style: .background))
        }
        for check in folded {
            actions.append(Action(id: checkDonePrefix + check.id, title: "\(check.name) done", style: .background))
        }

        let start = input.kinds.contains(.morning)
            ? plan.routine.weighInMinutes
            : folded.map { checkMinutes($0, input) ?? plan.routine.weighInMinutes }.min() ?? plan.routine.weighInMinutes
        let minutes = quiet(start)
        let category = Category(id: idPrefix + "morning.\(day.rawValue)", actions: Array(actions.prefix(maxActions)))
        return Request(id: idPrefix + "morning.\(day.rawValue)", kind: .morning, day: day,
                       date: day.date(minutes: minutes, calendar: input.calendar), minutes: minutes, title: title,
                       body: lines.joined(separator: " "), category: category, url: weighIn ? "nina://weigh" : "nina://today")
    }

    /// One notification per check that has a reminder, at its time or meal time (the early ones
    /// are folded into the morning notification).
    static func checks(on day: DayKey, _ input: Input) -> [Request] {
        dueChecks(on: day, input).filter { !isFolded($0, input) }.compactMap { check in
            guard let raw = checkMinutes(check, input) else { return nil }
            let minutes = quiet(raw)
            var body = "Tap Taken once it's done."
            if case .meal = check.timing {
                let timing = timingText(check, input)
                body = timing.prefix(1).uppercased() + String(timing.dropFirst()) + " – tap Taken once it's done."
            }
            let category = Category(id: idPrefix + "check.\(check.id)", actions: [
                Action(id: checkDonePrefix + check.id, title: "Taken", style: .background),
                Action(id: checkSkipPrefix + check.id, title: "Not today", style: .background),
            ])
            return Request(id: idPrefix + "check.\(check.id).\(day.rawValue)", kind: .check, day: day,
                           date: day.date(minutes: minutes, calendar: input.calendar), minutes: minutes,
                           title: checkTitle(check), body: body, category: category, url: "nina://today", checkID: check.id)
        }
    }

    /// 20:00 the evening before a full set.
    static func measureEvening(on day: DayKey, _ input: Input) -> Request? {
        guard input.kinds.contains(.measure) else { return nil }
        let tomorrow = day.adding(days: 1, calendar: input.calendar)
        guard !input.plan.isPaused(on: tomorrow),
              (input.bodyDue[tomorrow] ?? []).contains(where: { $0.kind == .full && $0.dueDay == tomorrow }) else { return nil }
        var body = "Before breakfast, after the bathroom"
        if let last = input.lastFullSet { body += " – like on \(shortDay(last))" }
        let minutes = quiet(measureEveningMinutes)
        return Request(id: idPrefix + "measure.\(day.rawValue)", kind: .measure, day: day,
                       date: day.date(minutes: minutes, calendar: input.calendar), minutes: minutes,
                       title: "Tomorrow: full measurement", body: body + ".",
                       category: Category(id: idPrefix + "measure", actions: []), url: "nina://today")
    }

    /// 18:00 on the check-in day while that week's check-in isn't saved (the same rule as the
    /// check-in card: an active phase that started before the day).
    static func checkIn(on day: DayKey, _ input: Input) -> Request? {
        let plan = input.plan, calendar = input.calendar
        guard input.kinds.contains(.checkIn), day.weekday(calendar: calendar) == min(7, max(1, plan.routine.checkInWeekday)),
              let phase = plan.activePhase(on: day), let start = phase.start, start < day,
              !input.checkInKeys.contains(DayMarks.checkInKey(week: day, calendar: calendar)) else { return nil }
        let minutes = quiet(checkInMinutes)
        let category = Category(id: idPrefix + "checkin", actions: [Action(id: openPrefix + "nina://checkin", title: "Open", style: .foreground)])
        return Request(id: idPrefix + "checkin.\(day.rawValue)", kind: .checkIn, day: day,
                       date: day.date(minutes: minutes, calendar: calendar), minutes: minutes,
                       title: "Weekly check-in · 2 minutes", body: "How your week went and what comes next.",
                       category: category, url: "nina://checkin")
    }

    /// 09:00 on a phase's start date (not started yet) and on the running phase's end date.
    static func phases(on day: DayKey, _ input: Input) -> [Request] {
        guard input.kinds.contains(.phase) else { return [] }
        let plan = input.plan
        let minutes = quiet(phaseMinutes)
        let date = day.date(minutes: minutes, calendar: input.calendar)
        let category = Category(id: idPrefix + "phase", actions: [Action(id: openPrefix + "nina://plan", title: "My Plan", style: .foreground)])
        var result: [Request] = []
        for phase in plan.phases where !phase.isStarted && phase.status != .done && phase.start == day {
            result.append(Request(id: idPrefix + "phase.start.\(phase.id).\(day.rawValue)", kind: .phase, day: day, date: date,
                                  minutes: minutes, title: "\(name(of: phase)) starts today",
                                  body: "Tap Start on Today to switch to its targets – or move it a week.",
                                  category: category, url: "nina://today"))
        }
        if let active = plan.activePhase(on: day), active.status != .done, active.end == day {
            result.append(Request(id: idPrefix + "phase.end.\(active.id).\(day.rawValue)", kind: .phase, day: day, date: date,
                                  minutes: minutes, title: "\(name(of: active)) ends today",
                                  body: "Decide on Today what comes next.", category: category, url: "nina://today"))
        }
        return result
    }

    /// Once, when the 7-day average reached the active phase's review weight: at the time it was
    /// first planned (`reviewPlannedAt`), else at the next allowed minute.
    static func review(_ input: Input) -> Request? {
        let plan = input.plan, calendar = input.calendar
        guard input.kinds.contains(.phase), let crossed = input.checkpoint, crossed <= input.today,
              let phase = plan.activePhase(on: input.today), !input.reviewedPhases.contains(phase.id),
              let weight = WeightSignal.checkpoint(of: phase) else { return nil }
        let date = input.reviewPlannedAt[phase.id] ?? nextAllowed(after: input.now, calendar: calendar)
        let day = DayKey(date: date, calendar: calendar)
        let category = Category(id: idPrefix + "review", actions: [
            Action(id: openPrefix + "nina://review/\(phase.id)", title: "Review", style: .foreground),
        ])
        return Request(id: idPrefix + "phase.review.\(phase.id)", kind: .phase, day: day, date: date,
                       minutes: ClockTime.minutes(of: date, calendar: calendar), title: "Time for a phase review",
                       body: "\(name(of: phase)): \(NumberText.plain(weight, decimals: 1)) kg reached – time to review.",
                       category: category, url: "nina://review/\(phase.id)")
    }

    /// The one site of a weekly measurement, typed right into the morning banner ("Waist…"); nil
    /// for a full set or several weekly sites (they open the measure sheet).
    static func bannerSite(of item: BodyDueItem) -> BodySite? {
        guard item.kind == .weekly, item.sites.count == 1 else { return nil }
        return item.sites[0]
    }

    // MARK: Rules

    /// Clamps a time into 06:00–21:00.
    public static func quiet(_ minutes: Int) -> Int { min(latestMinutes, max(earliestMinutes, minutes)) }

    /// The first allowed minute after `now`: a minute later, or 09:00 when that is outside
    /// 06:00–21:00 (today before 06:00, else tomorrow).
    static func nextAllowed(after now: Date, calendar: Calendar) -> Date {
        let soon = now.addingTimeInterval(60)
        let minutes = ClockTime.minutes(of: soon, calendar: calendar)
        let day = DayKey(date: soon, calendar: calendar)
        if minutes >= earliestMinutes, minutes <= latestMinutes { return soon }
        let morning = minutes < earliestMinutes ? day : day.adding(days: 1, calendar: calendar)
        return morning.date(minutes: phaseMinutes, calendar: calendar)
    }

    /// At most one coach notification before 10:00: the morning one (else the earliest) stays,
    /// the others move to 10:00.
    static func oneBeforeTen(_ requests: [Request], calendar: Calendar) -> [Request] {
        let early = requests.filter { $0.minutes < morningUntilMinutes }
        guard early.count > 1 else { return requests }
        let keep = early.first { $0.kind == .morning } ?? early.min { ($0.minutes, $0.id) < ($1.minutes, $1.id) }
        return requests.map { request in
            guard request.minutes < morningUntilMinutes, request.id != keep?.id else { return request }
            var moved = request
            moved.minutes = morningUntilMinutes
            moved.date = request.day.date(minutes: morningUntilMinutes, calendar: calendar)
            return moved
        }
    }

    /// Checks with a reminder that are due and still open on a day.
    static func dueChecks(on day: DayKey, _ input: Input) -> [CoachPlan.Check] {
        guard input.kinds.contains(.check) else { return [] }
        let typeID = input.plan.dayType(on: day, marks: input.dayTypeMarks, calendar: input.calendar)?.id
        let states = input.checkStates[day] ?? [:]
        return input.plan.checks.filter { check in
            check.remind && states[check.id] == nil && check.isDue(on: day, dayTypeID: typeID, calendar: input.calendar)
        }
    }

    /// Anytime checks, checks with breakfast and checks before 09:00 ride along in the morning one.
    static func isFolded(_ check: CoachPlan.Check, _ input: Input) -> Bool {
        if case .meal(let id) = check.timing, id == MealSlot.breakfast.id { return true }
        guard let minutes = checkMinutes(check, input) else { return true }
        return minutes < foldBeforeMinutes
    }

    /// A check's time: its clock time or its meal's usual time (nil = anytime).
    static func checkMinutes(_ check: CoachPlan.Check, _ input: Input) -> Int? {
        switch check.timing {
        case .anytime: return nil
        case .time(let minutes): return minutes
        case .meal(let id): return meal(id, input)?.minutes
        }
    }

    static func meal(_ id: String, _ input: Input) -> MealSlot? {
        input.meals.first { $0.id == id } ?? MealSlot.defaults.first { $0.id == id }
    }

    /// "with breakfast", "at 08:00", "today".
    static func timingText(_ check: CoachPlan.Check, _ input: Input) -> String {
        switch check.timing {
        case .anytime: return "today"
        case .time(let minutes): return "at \(ClockTime.text(minutes))"
        case .meal(let id): return "with \((meal(id, input)?.name ?? id).lowercased())"
        }
    }

    /// "💊 Creatine · 3–5 g".
    static func checkTitle(_ check: CoachPlan.Check) -> String {
        let dose = check.dose.trimmingCharacters(in: .whitespaces)
        let name = dose.isEmpty ? check.name : "\(check.name) · \(dose)"
        return check.emoji.isEmpty ? name : "\(check.emoji) \(name)"
    }

    /// A flexible type still open this week, offered on a scheduled default day ("Tennis today").
    static func flexibleOffer(on day: DayKey, _ input: Input) -> CoachPlan.DayType? {
        let plan = input.plan, marks = input.dayTypeMarks, calendar = input.calendar
        guard let type = plan.dayType(on: day, marks: marks, calendar: calendar), type.schedule == .default,
              !plan.isManualDayType(on: day, marks: marks) else { return nil }
        return plan.dayTypes.first { flexible in
            flexible.schedule == .flexible && flexible.perWeek > 0
                && plan.flexibleCount(of: flexible.id, inWeekOf: day, marks: marks, calendar: calendar) < flexible.perWeek
        }
    }

    /// "🎾 Tennis".
    static func label(of type: CoachPlan.DayType) -> String {
        let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
        return emoji.isEmpty ? type.name : "\(emoji) \(type.name)"
    }

    static func name(of phase: CoachPlan.Phase) -> String {
        let trimmed = phase.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : trimmed
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "7 Jan".
    static func shortDay(_ day: DayKey) -> String { "\(day.day) \(months[max(0, min(11, day.month - 1))])" }

    // MARK: Actions

    static let weightActionID = "weight"
    static let tapePrefix = "tape:"
    static let openPrefix = "open:"
    static let checkDonePrefix = "check.done:"
    static let checkSkipPrefix = "check.skip:"
    static let dayTypePrefix = "daytype:"

    /// What an action (or a tap) asks the app to do.
    public enum Command: Equatable, Sendable {
        /// Open a nina:// URL.
        case open(String)
        /// "Weight…": the kilograms typed (nil when the text isn't a weight).
        case weight(Double?)
        /// "Waist…": the site and the centimeters typed (nil when the text isn't a plausible value
        /// for that site).
        case tape(BodySite, Double?)
        /// Taken / Not today / "Creatine done".
        case check(String, CheckState)
        /// "Tennis today".
        case dayType(String)
    }

    /// The command of an action id (`Action.id`) with the text typed into a text action; nil for
    /// other actions.
    public static func command(action id: String, text: String? = nil) -> Command? {
        if id == weightActionID { return .weight(text.flatMap(weight(from:))) }
        if id.hasPrefix(tapePrefix), let site = BodySite(rawValue: String(id.dropFirst(tapePrefix.count))) {
            return .tape(site, text.flatMap { centimeters(from: $0, site: site) })
        }
        if id.hasPrefix(openPrefix) { return .open(String(id.dropFirst(openPrefix.count))) }
        if id.hasPrefix(checkDonePrefix) { return .check(String(id.dropFirst(checkDonePrefix.count)), .done) }
        if id.hasPrefix(checkSkipPrefix) { return .check(String(id.dropFirst(checkSkipPrefix.count)), .skipped) }
        if id.hasPrefix(dayTypePrefix) { return .dayType(String(id.dropFirst(dayTypePrefix.count))) }
        return nil
    }

    /// A weight typed into the banner: "72,4", "72.4 kg", "72.4kg" → 72.4; nil for anything that
    /// isn't a number within 25–300 kg.
    public static func weight(from text: String) -> Double? {
        guard let value = number(from: text), WeightSignal.plausibleRange.contains(value) else { return nil }
        return value
    }

    /// The number in a typed weight, whatever its size ("7,24 kg" → 7.24): what the weigh-in sheet
    /// is prefilled with when the weight needs a look. nil when it isn't one number.
    public static func number(from text: String) -> Double? {
        number(from: text, units: ["kilograms", "kilogram", "kilo", "kgs", "kg"])
    }

    /// A tape value typed into the banner: "84,5", "84.5 cm" → 84.5; nil for anything that isn't
    /// one number within the site's plausible range (waist 50–200 cm).
    public static func centimeters(from text: String, site: BodySite) -> Double? {
        guard let value = number(from: text, units: ["centimeters", "centimetres", "centimeter", "centimetre", "cm"]),
              site.plausibleRange.contains(value) else { return nil }
        return value
    }

    /// The latest typed value of each site, from the tape records (the "Waist…" placeholder).
    public static func lastTape(_ records: [BodyTapeRecord]) -> [BodySite: Double] {
        var result: [BodySite: Double] = [:]
        for record in BodyTapeRecord.sorted(records) {
            for (site, value) in record.values.sites { result[site] = value }
        }
        return result
    }

    /// A tape value typed into the banner needs a look before it is saved: more than 3 cm away
    /// from the site's last reading within 7 days (`BodyReadings.isSuspiciousJump`).
    public static func tapeNeedsALook(_ value: Double, site: BodySite, on day: DayKey, records: [BodyTapeRecord],
                                      calendar: Calendar = .current) -> Bool {
        guard let previous = BodyTapeRecord.sorted(records).last(where: { $0.day <= day && $0.values[site] != nil }),
              let last = previous.values[site] else { return false }
        return BodyReadings.isSuspiciousJump(value, previous: last, daysApart: previous.day.days(to: day, calendar: calendar))
    }

    private static func number(from text: String, units: [String]) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for unit in units where cleaned.hasSuffix(unit) {
            cleaned = String(cleaned.dropLast(unit.count))
            break
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, !cleaned.contains(" "), !cleaned.contains("/"),
              cleaned.filter({ $0 == "," || $0 == "." }).count <= 1,
              let value = NumberText.parse(cleaned), value.isFinite, value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }
}
