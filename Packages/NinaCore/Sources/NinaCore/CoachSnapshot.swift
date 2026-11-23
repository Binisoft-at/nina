import Foundation

/// The coach widget's summary in the shared App Group (`<group>/Nina/coach.json`), written by
/// the iPhone app through `WidgetBridge`: the day type and the daily checks of today and
/// tomorrow, the morning weigh-in while it is open, the 7-day average and the weekly rate with
/// the status words, and the next body measurement. Small and device-only: it is never synced
/// and never goes to iCloud (its average can count Apple Health weigh-ins, which may only be
/// shown on this device). The widget turns it into what it shows at a moment (`shown(at:)`), so
/// the weigh-in leaves at the morning cutoff and a new day starts without the app.
public struct CoachSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "coach.json"
    public static let currentVersion = 1

    public var v: Int
    /// The diary day it was made for.
    public var day: String
    public var updatedAt: Date
    /// The hour the diary day starts (Settings → Day starts at).
    public var dayStartHour: Int
    /// A coach plan is set up (without one the widget offers to set it up).
    public var isSetUp: Bool
    /// The made day and the one after it, in order.
    public var days: [Day]
    /// The 7-day average, the weekly rate and the status words; nil without either.
    public var weight: Weight?
    /// The next body measurement (weekly sites, full set or body-fat assessment); nil without one.
    public var measurement: NextMeasurement?

    public init(day: DayKey, updatedAt: Date, dayStartHour: Int, isSetUp: Bool, days: [Day], weight: Weight?,
                measurement: NextMeasurement?) {
        v = CoachSnapshot.currentVersion
        self.day = day.rawValue
        self.updatedAt = updatedAt
        self.dayStartHour = dayStartHour
        self.isSetUp = isSetUp
        self.days = days
        self.weight = weight
        self.measurement = measurement
    }

    // MARK: Parts

    /// One diary day: its day type, its checks and the morning weigh-in.
    public struct Day: Codable, Equatable, Sendable {
        public var day: String
        public var dayType: DayType?
        /// The checks due that day (or ticked anyway), in the Today strip's order.
        public var checks: [Check]
        /// The morning weigh-in is asked for until this moment (the plan's morning cutoff); nil
        /// when it isn't (weighed in already, paused, no plan).
        public var weighInUntil: Date?
        /// Coaching is paused that day.
        public var isPaused: Bool

        public init(day: DayKey, dayType: DayType?, checks: [Check], weighInUntil: Date?, isPaused: Bool) {
            self.day = day.rawValue
            self.dayType = dayType
            self.checks = checks
            self.weighInUntil = weighInUntil
            self.isPaused = isPaused
        }
    }

    /// The day's type with its kcal target: "🎾 Tennis · 2,600 kcal".
    public struct DayType: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// The type's emoji, else a fitting one for its name ("" when none fits).
        public var emoji: String
        /// The day's kcal target with this type.
        public var energy: Double
        /// Picked by hand rather than by the schedule.
        public var isManual: Bool

        public init(id: String, name: String, emoji: String, energy: Double, isManual: Bool) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.energy = energy
            self.isManual = isManual
        }

        /// "🎾 Tennis" ("Tennis" without an emoji).
        public var label: String { [emoji, name].filter { !$0.isEmpty }.joined(separator: " ") }
        /// "Tennis day".
        public var title: String { "\(name) day" }
    }

    /// A daily check from the plan with its state that day.
    public struct Check: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var emoji: String
        /// "3–5 g" as written in the plan.
        public var dose: String
        public var state: CoachBoard.StripItem.State
        /// Optional checks never count as missed.
        public var isOptional: Bool

        public init(id: String, name: String, emoji: String, dose: String, state: CoachBoard.StripItem.State, isOptional: Bool) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.dose = dose
            self.state = state
            self.isOptional = isOptional
        }

        public var isOpen: Bool { state == .open }
        /// "💊 Creatine".
        public var label: String { [emoji, name].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    /// How the status reads (the app's colours).
    public enum Tone: String, Codable, Sendable, CaseIterable {
        case good, watch, alert, neutral
    }

    /// "avg 74.6 kg · +0.15 kg/wk · In range".
    public struct Weight: Codable, Equatable, Sendable {
        /// The valid 7-day average (kg).
        public var average: Double?
        /// The valid decision rate (kg/week); nil while paused.
        public var rate: Double?
        /// "In range", "Slower than planned", "Faster than planned", "Gathering data", "Off track",
        /// "New targets", "Paused"; nil without an active phase with a range.
        public var word: String?
        /// The whole status line ("New targets since Tue · first look Mon 21 Jan").
        public var line: String?
        public var tone: Tone
        /// The active phase ("Lean gain").
        public var phaseName: String?

        public init(average: Double?, rate: Double?, word: String?, line: String?, tone: Tone, phaseName: String?) {
            self.average = average
            self.rate = rate
            self.word = word
            self.line = line
            self.tone = tone
            self.phaseName = phaseName
        }

        /// "+0.15 kg/wk"; nil without a rate. `number` writes an absolute value with fixed decimals.
        public func rateText(number: (Double, Int) -> String = CoachSnapshot.fixed) -> String? {
            rate.map { CoachSnapshot.signed($0, decimals: 2, number: number) + " kg/wk" }
        }

        /// "74.6 kg"; nil without an average.
        public func averageText(number: (Double, Int) -> String = CoachSnapshot.fixed) -> String? {
            average.map { number($0, 1) + " kg" }
        }

        /// "+0.15 kg/wk · In range" (either part alone when the other is missing; nil without both).
        public func statusText(number: (Double, Int) -> String = CoachSnapshot.fixed) -> String? {
            let parts = [rateText(number: number), word].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// The next body measurement: what and when.
    public struct NextMeasurement: Codable, Equatable, Sendable {
        /// `.weekly`, `.full` or `.assessment` (never `.weighIn`).
        public var kind: BodyDueItem.Kind
        /// "Waist", "Measurements", "Full measurement", "Body fat".
        public var title: String
        public var dueDay: String

        public init(kind: BodyDueItem.Kind, title: String, dueDay: DayKey) {
            self.kind = kind
            self.title = title
            self.dueDay = dueDay.rawValue
        }

        /// The SF Symbol the Today strip uses for it.
        public var symbol: String {
            switch kind {
            case .weighIn: "scalemass"
            case .weekly: "ruler"
            case .full: "figure.arms.open"
            case .assessment: "percent"
            }
        }

        /// Due on or before `today`.
        public func isDue(on today: DayKey) -> Bool {
            guard let due = DayKey(dueDay) else { return false }
            return due <= today
        }

        /// When, seen from `today`: "today", "overdue 2 days", "tomorrow", "Thu" (within a week),
        /// "21 Jan".
        public func whenText(on today: DayKey, calendar: Calendar = .current) -> String {
            guard let due = DayKey(dueDay) else { return "" }
            let days = today.days(to: due, calendar: calendar)
            switch days {
            case ..<0:
                let late = -days
                return "overdue \(late) \(late == 1 ? "day" : "days")"
            case 0: return "today"
            case 1: return "tomorrow"
            case 2...6: return Weekdays.shortNames[max(1, min(7, due.weekday(calendar: calendar))) - 1]
            default: return WeightSignal.StatusLine.shortDate(due)
            }
        }
    }

    /// What a tap opens (nina:// links the app understands, `AppModel.open`).
    public enum Link: Equatable, Sendable {
        case weighIn
        case measure(BodyDueItem.Kind)
        case check(String)
        case progress
        case plan
        case today

        /// "nina://weigh", "nina://measure?mode=weekly", "nina://check/creatine", "nina://progress",
        /// "nina://plan", "nina://today".
        public func url(scheme: String) -> String {
            switch self {
            case .weighIn: return "\(scheme)://weigh"
            case .measure(let kind):
                switch kind {
                case .weighIn: return "\(scheme)://weigh"
                case .weekly: return "\(scheme)://measure?mode=weekly"
                case .full: return "\(scheme)://measure?mode=full"
                case .assessment: return "\(scheme)://measure?mode=assessment"
                }
            case .check(let id):
                let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
                    ?? id
                return "\(scheme)://check/\(path)"
            case .progress: return "\(scheme)://progress"
            case .plan: return "\(scheme)://plan"
            case .today: return "\(scheme)://today"
            }
        }
    }

    // MARK: Numbers

    /// A number with a decimal point and fixed decimals ("74.6"), without a minus for zero.
    public static func fixed(_ value: Double, _ decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        let text = String(format: "%.\(max(0, decimals))f", value)
        return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
    }

    /// "+0.15", "−0.20" (a real minus), "0.00" for zero. `number` writes the absolute value.
    public static func signed(_ value: Double, decimals: Int, number: (Double, Int) -> String = CoachSnapshot.fixed) -> String {
        let text = number(abs(value), decimals)
        guard value.isFinite, fixed(abs(value), decimals) != fixed(0, decimals) else { return text }
        return (value < 0 ? "\u{2212}" : "+") + text
    }
}

// MARK: - Building it

extension CoachSnapshot {
    /// Everything the snapshot is made of, as plain values (the app gathers them).
    public struct Input {
        public var plan: CoachPlan
        /// Today's diary day.
        public var today: DayKey
        public var now: Date
        public var dayStartHour: Int
        /// Live day-type marks: DayKey raw value → type id.
        public var dayTypeMarks: [String: String]
        /// Today's check marks: check id → done or skipped (missing = open).
        public var checkStates: [String: CheckState]
        /// The meal slots: checks timed to a meal are sorted by the slot's usual time.
        public var mealSlots: [MealSlot]
        /// What Today shows as the kcal target of today and of tomorrow (`NinaSettings.targets(for:)`).
        public var energyToday: Double
        public var energyTomorrow: Double
        /// The measuring schedule (`NinaStore.bodySchedule`).
        public var schedule: BodySchedule
        /// Today has a morning weigh-in (typed or from Apple Health).
        public var hasMorningWeighIn: Bool
        /// The weight signal's summary of today; nil without weigh-ins worth showing.
        public var summary: WeightSignal.Summary?
        /// The saved check-ins (for "Off track").
        public var checkIns: [CheckInSnapshot]
        public var calendar: Calendar

        public init(plan: CoachPlan, today: DayKey, now: Date, dayStartHour: Int = 0, dayTypeMarks: [String: String] = [:],
                    checkStates: [String: CheckState] = [:], mealSlots: [MealSlot] = MealSlot.defaults, energyToday: Double = 0,
                    energyTomorrow: Double = 0, schedule: BodySchedule = BodySchedule(isSetUp: false),
                    hasMorningWeighIn: Bool = false, summary: WeightSignal.Summary? = nil, checkIns: [CheckInSnapshot] = [],
                    calendar: Calendar = .current) {
            self.plan = plan
            self.today = today
            self.now = now
            self.dayStartHour = dayStartHour
            self.dayTypeMarks = dayTypeMarks
            self.checkStates = checkStates
            self.mealSlots = mealSlots
            self.energyToday = energyToday
            self.energyTomorrow = energyTomorrow
            self.schedule = schedule
            self.hasMorningWeighIn = hasMorningWeighIn
            self.summary = summary
            self.checkIns = checkIns
            self.calendar = calendar
        }
    }

    /// The snapshot of `input.today` and the day after, by the Today strip's rules: checks due by
    /// the plan (or ticked anyway) in the strip's order, nothing before the plan was set up or on a
    /// paused day, the weigh-in until the morning cutoff while there is no morning weigh-in.
    public init(_ input: Input) {
        let calendar = input.calendar
        let tomorrow = input.today.adding(days: 1, calendar: calendar)
        let first = CoachSnapshot.makeDay(input.today, input: input, states: input.checkStates, energy: input.energyToday,
                                          hasMorningWeighIn: input.hasMorningWeighIn)
        let second = CoachSnapshot.makeDay(tomorrow, input: input, states: [:], energy: input.energyTomorrow, hasMorningWeighIn: false)
        var today = first
        // After the cutoff the weigh-in isn't asked for any more.
        if let until = today.weighInUntil, until <= input.now { today.weighInUntil = nil }
        self.init(day: input.today, updatedAt: input.now, dayStartHour: input.dayStartHour, isSetUp: input.plan.isSetUp,
                  days: [today, second], weight: CoachSnapshot.makeWeight(input),
                  measurement: CoachSnapshot.makeMeasurement(input))
    }

    static func makeDay(_ day: DayKey, input: Input, states: [String: CheckState], energy: Double,
                        hasMorningWeighIn: Bool) -> Day {
        let plan = input.plan, calendar = input.calendar
        guard plan.isSetUp else { return Day(day: day, dayType: nil, checks: [], weighInUntil: nil, isPaused: false) }
        let paused = plan.isPaused(on: day)
        let type = plan.dayType(on: day, marks: input.dayTypeMarks, calendar: calendar)
        let dayType = type.map { type in
            DayType(id: type.id, name: type.name, emoji: CoachBoard.emoji(of: type), energy: energy,
                    isManual: plan.isManualDayType(on: day, marks: input.dayTypeMarks))
        }
        // The strip shows nothing before the plan was set up, or while paused.
        let beforeSetUp = BodySchedule.setUpDay(of: plan, calendar: calendar).map { day < $0 } ?? false
        guard !paused, !beforeSetUp else { return Day(day: day, dayType: dayType, checks: [], weighInUntil: nil, isPaused: paused) }
        let due = plan.checks.enumerated().filter { _, check in
            check.isDue(on: day, dayTypeID: type?.id, calendar: calendar) || states[check.id] != nil
        }
        let sorted = due.sorted { lhs, rhs in
            let left = CoachBoard.timingOrder(lhs.element.timing, input.mealSlots)
            let right = CoachBoard.timingOrder(rhs.element.timing, input.mealSlots)
            if left.group != right.group { return left.group < right.group }
            if left.minutes != right.minutes { return left.minutes < right.minutes }
            return lhs.offset < rhs.offset
        }
        let checks = sorted.map { _, check -> Check in
            let state: CoachBoard.StripItem.State
            switch states[check.id] {
            case .done?: state = .done
            case .skipped?: state = .skipped
            case nil: state = .open
            }
            return Check(id: check.id, name: check.name, emoji: check.emoji, dose: check.dose.trimmingCharacters(in: .whitespaces),
                         state: state, isOptional: check.isOptional)
        }
        // The weigh-in as the strip asks for it: a moment early on the day stands for "before the cutoff".
        let cutoff = plan.routine.morningCutoffMinutes
        let early = day.date(minutes: 0, calendar: calendar)
        let asks = input.schedule.dueItems(on: day, now: early, hasMorningWeighIn: hasMorningWeighIn, calendar: calendar)
            .contains { $0.kind == .weighIn }
        let until = asks ? day.date(minutes: cutoff, calendar: calendar) : nil
        return Day(day: day, dayType: dayType, checks: checks, weighInUntil: until, isPaused: false)
    }

    static func makeWeight(_ input: Input) -> Weight? {
        guard let summary = input.summary else { return nil }
        let plan = input.plan, calendar = input.calendar
        let line = plan.isSetUp
            ? WeightSignal.statusLine(on: input.today, plan: plan, rate: summary.rate, checkIns: input.checkIns, calendar: calendar)
            : nil
        let average = summary.average.value
        guard average != nil || line != nil else { return nil }
        // While paused (or without a valid rate) there is no rate to show.
        let rate = line?.isPaused == true ? nil : summary.rate.value
        let word: String? = line.map { line in
            switch line.state {
            case .status(let status): return status.title
            case .offTrack: return CheckInVerdict.offTarget.title
            case .newTargets: return "New targets"
            case .paused: return "Paused"
            }
        }
        return Weight(average: average, rate: rate, word: word, line: line?.text(calendar: calendar),
                      tone: line.map { Tone(rawValue: $0.tone.rawValue) ?? .neutral } ?? .neutral,
                      phaseName: plan.activePhase(on: input.today)?.name)
    }

    /// The earliest of the weekly sites, the full set and the body-fat assessment (a full set
    /// wins a tie, it covers the weekly sites); nil without a plan, while paused or with nothing
    /// scheduled.
    static func makeMeasurement(_ input: Input) -> NextMeasurement? {
        let plan = input.plan, schedule = input.schedule, calendar = input.calendar, today = input.today
        guard plan.isSetUp, schedule.isSetUp, !plan.isPaused(on: today) else { return nil }
        var candidates: [(rank: Int, item: BodyDueItem)] = []
        if let full = schedule.nextFull(today: today, calendar: calendar) {
            candidates.append((0, BodyDueItem(kind: .full, dueDay: full.day, reason: full.reason, sites: schedule.fullSites)))
        }
        if let weekly = schedule.nextWeekly(today: today, calendar: calendar) {
            candidates.append((1, BodyDueItem(kind: .weekly, dueDay: weekly, sites: schedule.weeklySites)))
        }
        if let assessment = schedule.nextAssessment(today: today, calendar: calendar) {
            candidates.append((2, BodyDueItem(kind: .assessment, dueDay: assessment.day, reason: assessment.reason)))
        }
        let next = candidates.min { lhs, rhs in
            lhs.item.dueDay != rhs.item.dueDay ? lhs.item.dueDay < rhs.item.dueDay : lhs.rank < rhs.rank
        }
        return next.map { NextMeasurement(kind: $0.item.kind, title: $0.item.title, dueDay: $0.item.dueDay) }
    }
}

// MARK: - What the widget shows

extension CoachSnapshot {
    /// The snapshot as the widget shows it at one moment.
    public struct Shown: Equatable, Sendable {
        /// The diary day it is at that moment.
        public var day: DayKey
        public var isSetUp: Bool
        /// The snapshot doesn't cover this day (the app hasn't run since the day before
        /// yesterday): the day type and the checks aren't known.
        public var isOutdated: Bool
        public var isPaused: Bool
        public var dayType: DayType?
        /// The morning weigh-in is still open.
        public var needsWeighIn: Bool
        public var checks: [Check]
        public var weight: Weight?
        public var measurement: NextMeasurement?

        /// The checks still open, in order.
        public var openChecks: [Check] { checks.filter(\.isOpen) }

        /// "1 of 3 done", "All 3 done", "Done"; nil without checks. Skipped ("not today") counts
        /// as handled.
        public var checksText: String? {
            guard !checks.isEmpty else { return nil }
            let handled = checks.count - openChecks.count
            if handled == checks.count { return checks.count == 1 ? "Done" : "All \(checks.count) done" }
            return "\(handled) of \(checks.count) done"
        }

        /// "today", "overdue 2 days", "tomorrow", "Thu", "21 Jan"; nil without a measurement.
        public func measurementWhen(calendar: Calendar = .current) -> String? {
            measurement.map { $0.whenText(on: day, calendar: calendar) }
        }

        /// "Waist · today".
        public func measurementLine(calendar: Calendar = .current) -> String? {
            guard let measurement else { return nil }
            return "\(measurement.title) · \(measurement.whenText(on: day, calendar: calendar))"
        }

        /// What a tap on the whole widget opens: the plan without one, the weigh-in while it is
        /// open, a measurement that is due, else the Body page.
        public var primary: Link {
            guard isSetUp else { return .plan }
            if needsWeighIn { return .weighIn }
            if let measurement, measurement.isDue(on: day) { return .measure(measurement.kind) }
            return .progress
        }
    }

    /// The diary day `now` counts for, with the snapshot's day start.
    public func today(now: Date, calendar: Calendar = .current) -> DayKey {
        DayKey(date: now, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// What the widget shows at `now`: the stored day that `now` falls on (tomorrow's once the
    /// day has changed), the weigh-in only before its cutoff, the measurement seen from that day.
    public func shown(at now: Date, calendar: Calendar = .current) -> Shown {
        let today = today(now: now, calendar: calendar)
        let stored = days.first { $0.day == today.rawValue }
        let paused = stored?.isPaused ?? false
        return Shown(day: today, isSetUp: isSetUp, isOutdated: stored == nil, isPaused: paused, dayType: stored?.dayType,
                     needsWeighIn: stored?.weighInUntil.map { now < $0 } ?? false, checks: stored?.checks ?? [],
                     weight: weight, measurement: paused ? nil : measurement)
    }

    /// One widget timeline entry: what to show from `date` on.
    public struct TimelinePoint: Equatable, Sendable {
        public var date: Date
        public var shown: Shown
    }

    /// The widget's timeline from `now`: now, each open weigh-in's cutoff, and the start of every
    /// stored day after now and of the day after the last one (from there the snapshot is
    /// outdated). The widget asks again after the last entry (`nextReload`).
    public func timeline(now: Date, calendar: Calendar = .current) -> [TimelinePoint] {
        var dates: [Date] = days.compactMap(\.weighInUntil)
        for stored in days {
            guard let key = DayKey(stored.day) else { continue }
            dates.append(key.start(dayStartHour: dayStartHour, calendar: calendar))
        }
        if let last = days.last.flatMap({ DayKey($0.day) }) {
            dates.append(last.adding(days: 1, calendar: calendar).start(dayStartHour: dayStartHour, calendar: calendar))
        }
        let later = Set(dates.filter { $0 > now }).sorted()
        return ([now] + later).map { TimelinePoint(date: $0, shown: shown(at: $0, calendar: calendar)) }
    }

    /// When the widget should ask for a new timeline: a minute after the day after `now`'s day
    /// starts (the app reloads it on every change before that).
    public func nextReload(after now: Date, calendar: Calendar = .current) -> Date {
        today(now: now, calendar: calendar).adding(days: 1, calendar: calendar)
            .start(dayStartHour: dayStartHour, calendar: calendar).addingTimeInterval(60)
    }

    /// Equal apart from when it was made (no widget reload needed).
    public func hasSameContent(as other: CoachSnapshot?) -> Bool {
        guard let other else { return false }
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    // MARK: Placeholder

    /// Made-up numbers for the widget gallery and before the app wrote anything.
    public static let placeholder: CoachSnapshot = {
        let day = DayKey(year: 2030, month: 1, day: 14)
        let checks = [
            Check(id: "creatine", name: "Creatine", emoji: "💊", dose: "3–5 g", state: .done, isOptional: false),
            Check(id: "omega", name: "Omega-3", emoji: "🐟", dose: "", state: .open, isOptional: false),
            Check(id: "magnesium", name: "Magnesium", emoji: "🌙", dose: "", state: .open, isOptional: false),
        ]
        let gym = DayType(id: "gym", name: "Gym", emoji: "🏋️", energy: 2500, isManual: false)
        let today = Day(day: day, dayType: gym, checks: checks, weighInUntil: nil, isPaused: false)
        let weight = Weight(average: 74.6, rate: 0.15, word: WeightSignal.Status.inRange.title,
                            line: WeightSignal.Status.inRange.title, tone: .good, phaseName: "Lean gain")
        return CoachSnapshot(day: day, updatedAt: Date(timeIntervalSince1970: 0), dayStartHour: 0, isSetUp: true, days: [today],
                             weight: weight, measurement: NextMeasurement(kind: .weekly, title: "Waist", dueDay: day))
    }()

    /// The placeholder as the widget shows it (on its own day, whatever the date).
    public static var placeholderShown: Shown {
        let snapshot = placeholder
        let day = DayKey(snapshot.day) ?? DayKey(year: 2030, month: 1, day: 14)
        return Shown(day: day, isSetUp: true, isOutdated: false, isPaused: false, dayType: snapshot.days.first?.dayType,
                     needsWeighIn: false, checks: snapshot.days.first?.checks ?? [], weight: snapshot.weight,
                     measurement: snapshot.measurement)
    }
}

// MARK: - Spoken names (Siri)

/// How Siri hears the plan's day types and checks. "Today is a Tennis day in Nina" and the German
/// "Heute ist ein Tennistag in Nina" name the day type "Tennis": its synonyms say the compound
/// forms, and `matches` finds a type or check by what was said or typed, whatever the case, the
/// accents or a trailing "day"/"Tag".
public enum CoachSiriNames {
    /// The other ways to say a day type: "Tennis day", "Tennistag", "Tennis Tag"; none for a name
    /// that already ends in "day" or "Tag" ("Rest day", "Ruhetag").
    public static func dayTypeSynonyms(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty, !lower.hasSuffix("day"), !lower.hasSuffix("tag") else { return [] }
        return ["\(trimmed) day", "\(trimmed)tag", "\(trimmed) Tag"]
    }

    /// What is compared: lowercased letters and digits only (no accents, spaces or dashes), without
    /// a trailing "day" or "Tag" ("Tennistag" → "tennis", "Rest day" → "rest", "Omega-3" → "omega3").
    public static func key(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["-tag", " tag", "tag", " day", "day"] where folded.hasSuffix(suffix) && folded.count > suffix.count {
            folded = String(folded.dropLast(suffix.count))
            break
        }
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// `query` names `name`: the same key, or one begins with the other ("Ten" finds "Tennis",
    /// "Creatine 5 g" finds "Creatine").
    public static func matches(_ query: String, name: String) -> Bool {
        let wanted = key(query), candidate = key(name)
        guard !wanted.isEmpty, !candidate.isEmpty else { return false }
        return wanted == candidate || candidate.hasPrefix(wanted) || wanted.hasPrefix(candidate)
    }
}
