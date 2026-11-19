import Foundation

/// What Today shows for one day (F13): the day-type chip, the checks strip (weigh-in, body
/// measurements, daily checks) and at most one coach card, plus the week average line. Pure: the
/// app hands in plain values (the plan, the day's marks, the measuring schedule's due items),
/// the rules come from the coach modules (`CoachPlan`, `BodySchedule`, `WeightSignal`,
/// `DayMarks`). Nothing new appears without a set-up plan.
public struct CoachBoard: Equatable, Sendable {
    /// The check-in card stays up this many days from the check-in day on (F11).
    public static let checkInCardDays = 3
    /// "Later" on the review card asks again after this many days (F5).
    public static let reviewSnoozeDays = 7
    /// "Welcome back" shows on this many days after a pause ended (F19).
    public static let welcomeBackDays = 3

    // MARK: Input

    /// Everything the board needs, as plain values.
    public struct Input: Equatable, Sendable {
        public var plan: CoachPlan
        /// The day shown.
        public var day: DayKey
        /// Today's diary day.
        public var today: DayKey
        public var now: Date
        /// The meal slots: checks timed to a meal are sorted by the slot's usual time.
        public var mealSlots: [MealSlot]
        /// The profile's targets for days the plan has none for (what `NinaSettings` falls back to).
        public var fallback: DailyTargets
        /// Live day-type marks: DayKey raw value → type id (`DayMarks.dayTypes`).
        public var dayTypeMarks: [String: String]
        /// The shown day's check marks: check id → done or skipped (missing = open).
        public var checkStates: [String: CheckState]
        /// Today has a morning weigh-in (typed or from Apple Health).
        public var hasMorningWeighIn: Bool
        /// The measuring schedule's due items for the shown day (`CoachBoard.bodyItems(…)`, which
        /// calls `BodySchedule.dueItems` with `now` only for today).
        public var bodyItems: [BodyDueItem]
        /// Keys of the live check-in marks ("week-2030-01-07").
        public var checkInKeys: Set<String>
        /// The first day the 7-day average reached the active phase's review checkpoint
        /// (`WeightSignal.checkpointCrossing(in:through:)` through today); nil = not reached.
        public var checkpoint: DayKey?
        /// Ceilings reached in the active gain phase (`BodyCeiling.reached`): they open the review too.
        public var ceilings: [BodyCeiling]
        /// Ids of phases with a review decision (a phase mark with review-keep, -hold or -cut).
        public var reviewedPhases: Set<String>
        /// Cards put off with "Later" (device-only): card key → the day it was tapped.
        public var dismissed: [String: DayKey]
        /// Eaten kcal of the logged days (for "Week avg 2,380 of 2,400 kcal"); leave out days
        /// without a log.
        public var eaten: [DayKey: Double]
        public var calendar: Calendar

        public init(plan: CoachPlan, day: DayKey, today: DayKey, now: Date, mealSlots: [MealSlot] = MealSlot.defaults,
                    fallback: DailyTargets = .standard, dayTypeMarks: [String: String] = [:],
                    checkStates: [String: CheckState] = [:], hasMorningWeighIn: Bool = false, bodyItems: [BodyDueItem] = [],
                    checkInKeys: Set<String> = [], checkpoint: DayKey? = nil, ceilings: [BodyCeiling] = [],
                    reviewedPhases: Set<String> = [], dismissed: [String: DayKey] = [:], eaten: [DayKey: Double] = [:],
                    calendar: Calendar = .current) {
            self.plan = plan
            self.day = day
            self.today = today
            self.now = now
            self.mealSlots = mealSlots
            self.fallback = fallback
            self.dayTypeMarks = dayTypeMarks
            self.checkStates = checkStates
            self.hasMorningWeighIn = hasMorningWeighIn
            self.bodyItems = bodyItems
            self.checkInKeys = checkInKeys
            self.checkpoint = checkpoint
            self.ceilings = ceilings
            self.reviewedPhases = reviewedPhases
            self.dismissed = dismissed
            self.eaten = eaten
            self.calendar = calendar
        }
    }

    /// The measuring schedule's items for the board: `dueItems(on: day)` with `now` (the weigh-in)
    /// only when `day` is today.
    public static func bodyItems(_ schedule: BodySchedule, on day: DayKey, today: DayKey, now: Date, hasMorningWeighIn: Bool,
                                 calendar: Calendar = .current) -> [BodyDueItem] {
        schedule.dueItems(on: day, now: day == today ? now : nil, hasMorningWeighIn: hasMorningWeighIn, calendar: calendar)
    }

    // MARK: Output

    /// What a tap does (on a strip pill or a card button).
    public enum Action: Equatable, Sendable {
        /// Open the weigh-in sheet.
        case weighIn
        /// Open the measure sheet for a weekly or full set (the item has the sites and whether the
        /// body-fat step is due too).
        case measure(BodyDueItem)
        /// Open the body-fat assessment sheet.
        case assessment(BodyDueItem)
        /// A daily check (by id): open → done; done → open again.
        case check(String)
        /// Start a planned phase today (`CoachPlan.starting(phase:on:)`).
        case startPhase(String)
        /// Move a planned phase's start on by a week (`CoachPlan.postponing(phase:from:)`).
        case postponePhase(String)
        /// Open the phase sheet.
        case editPhase(String)
        /// Open the plan editor.
        case editPlan
        /// Open the phase review.
        case review(String)
        /// Open the weekly check-in of the week of this check-in day.
        case checkIn(DayKey)
        /// Close the card (recorded like "Later").
        case dismiss
    }

    /// The day-type chip on the summary card ("🏋️ Gym day").
    public struct Chip: Equatable, Sendable {
        public var id: String
        public var name: String
        /// The type's emoji, else a fitting one for its name ("" when none fits).
        public var emoji: String
        /// "Gym day".
        public var title: String
        /// Picked by hand (a filled chip; "Back to schedule" is offered) rather than from the schedule.
        public var isManual: Bool
        /// Flexible types: "Tennis · 1 of 2 this week"; nil otherwise.
        public var quotaText: String?
        /// The day's kcal target.
        public var energy: Double
        /// The chip menu: every day type, in plan order.
        public var options: [ChipOption]

        public init(id: String, name: String, emoji: String, title: String, isManual: Bool, quotaText: String?, energy: Double,
                    options: [ChipOption]) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.title = title
            self.isManual = isManual
            self.quotaText = quotaText
            self.energy = energy
            self.options = options
        }
    }

    /// One day type in the chip menu.
    public struct ChipOption: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var emoji: String
        /// The day's kcal target with this type.
        public var energy: Double
        /// Flexible types: "1 of 2 this week"; nil otherwise.
        public var quotaText: String?
        public var isSelected: Bool

        public init(id: String, name: String, emoji: String, energy: Double, quotaText: String?, isSelected: Bool) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.energy = energy
            self.quotaText = quotaText
            self.isSelected = isSelected
        }
    }

    /// One pill in the checks strip.
    public struct StripItem: Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case weighIn, body, check
        }

        public enum State: String, Codable, Sendable, CaseIterable {
            case open, done, skipped
        }

        /// "weighIn", "body.weekly", "body.full", "body.assessment", "check.<check id>".
        public var id: String
        public var kind: Kind
        /// "Weigh in", "Waist", "Full measurement", "Body fat", "Creatine · 3–5 g".
        public var title: String
        /// "overdue 3 days" once a body item is that late; nil otherwise.
        public var detail: String?
        /// The check's emoji ("" for body items and checks without one).
        public var emoji: String
        /// An SF Symbol name when there is no emoji ("" otherwise).
        public var symbol: String
        public var state: State
        public var action: Action

        public init(id: String, kind: Kind, title: String, detail: String? = nil, emoji: String = "", symbol: String = "",
                    state: State = .open, action: Action) {
            self.id = id
            self.kind = kind
            self.title = title
            self.detail = detail
            self.emoji = emoji
            self.symbol = symbol
            self.state = state
            self.action = action
        }
    }

    /// The one coach card above the meals.
    public struct Card: Equatable, Sendable, Identifiable {
        /// In priority order.
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case phaseStart, phaseEnd, review, checkIn, baseline, welcomeBack
        }

        /// A button on the card.
        public struct Choice: Equatable, Sendable {
            public var title: String
            public var action: Action

            public init(title: String, action: Action) {
                self.title = title
                self.action = action
            }
        }

        /// Stable: "phaseStart.<phase id>", "phaseEnd.<phase id>", "review.<phase id>",
        /// "checkIn.week-<Monday>", "baseline.<due day>", "welcomeBack.<pause end>".
        public var key: String
        public var kind: Kind
        public var title: String
        /// One sentence.
        public var message: String
        public var primary: Choice
        public var secondary: Choice?
        /// Further choices for the card's menu ("Edit"); "Later" is always offered by the app.
        public var more: [Choice]
        /// The phase it is about, if any.
        public var phaseID: String?

        public init(key: String, kind: Kind, title: String, message: String, primary: Choice, secondary: Choice? = nil,
                    more: [Choice] = [], phaseID: String? = nil) {
            self.key = key
            self.kind = kind
            self.title = title
            self.message = message
            self.primary = primary
            self.secondary = secondary
            self.more = more
            self.phaseID = phaseID
        }

        public var id: String { key }
    }

    /// The week average on the summary card.
    public struct WeekAverage: Equatable, Sendable {
        /// The plan's average kcal per day for the week (`CoachPlan.plannedWeekAverage`).
        public var planned: Double
        /// Average eaten on this week's logged days, with the average target of those days (nil
        /// with fewer than 2 logged days).
        public var eaten: Double?
        public var target: Double?
        public var loggedDays: Int
        /// "Week avg 2,380 of 2,400 kcal", or the plan's "Week avg 2,400 kcal".
        public var text: String

        public init(planned: Double, eaten: Double?, target: Double?, loggedDays: Int, text: String) {
            self.planned = planned
            self.eaten = eaten
            self.target = target
            self.loggedDays = loggedDays
            self.text = text
        }
    }

    /// The day type, or nil without a set-up plan or without day types.
    public var chip: Chip?
    /// The pills in order; empty = the strip is hidden (nothing is open).
    public var strip: [StripItem]
    /// The coach card, or nil.
    public var card: Card?
    public var weekAverage: WeekAverage?

    /// "Week avg 2,400 kcal" (nil without at least two day types or targets for the week).
    public var weekAverageLine: String? { weekAverage?.text }

    public init(_ input: Input) {
        chip = CoachBoard.chip(input)
        strip = CoachBoard.strip(input)
        card = CoachBoard.card(input)
        weekAverage = CoachBoard.weekAverage(input)
    }

    public init(chip: Chip?, strip: [StripItem], card: Card?, weekAverage: WeekAverage?) {
        self.chip = chip
        self.strip = strip
        self.card = card
        self.weekAverage = weekAverage
    }

    /// Nothing to show.
    public static let empty = CoachBoard(chip: nil, strip: [], card: nil, weekAverage: nil)
}

// MARK: - Chip

extension CoachBoard {
    static func chip(_ input: Input) -> Chip? {
        let plan = input.plan, day = input.day, calendar = input.calendar
        guard plan.isSetUp, let type = plan.dayType(on: day, marks: input.dayTypeMarks, calendar: calendar) else { return nil }
        let options = plan.dayTypes.map { option in
            var marks = input.dayTypeMarks
            marks[day.rawValue] = option.id
            return ChipOption(id: option.id, name: option.name, emoji: emoji(of: option),
                              energy: plan.targets(on: day, marks: marks, fallback: input.fallback, calendar: calendar).energy,
                              quotaText: quota(of: option, input), isSelected: option.id == type.id)
        }
        return Chip(id: type.id, name: type.name, emoji: emoji(of: type), title: "\(type.name) day",
                    isManual: plan.isManualDayType(on: day, marks: input.dayTypeMarks),
                    quotaText: quota(of: type, input).map { "\(type.name) · \($0)" },
                    energy: plan.targets(on: day, marks: input.dayTypeMarks, fallback: input.fallback, calendar: calendar).energy,
                    options: options)
    }

    static func emoji(of type: CoachPlan.DayType) -> String {
        type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
    }

    /// "1 of 2 this week" for a flexible type (counted in the ISO week of the shown day).
    static func quota(of type: CoachPlan.DayType, _ input: Input) -> String? {
        guard type.schedule == .flexible else { return nil }
        let calendar = input.calendar
        let count = input.plan.flexibleCount(of: type.id, inWeekOf: input.day, marks: input.dayTypeMarks, calendar: calendar)
        let week = input.day.startOfWeek(calendar: calendar) == input.today.startOfWeek(calendar: calendar) ? "this week" : "that week"
        return type.perWeek > 0 ? "\(count) of \(type.perWeek) \(week)" : "\(count) \(week)"
    }
}

// MARK: - Checks strip

extension CoachBoard {
    static func strip(_ input: Input) -> [StripItem] {
        let plan = input.plan, day = input.day, calendar = input.calendar
        guard plan.isSetUp, !plan.isPaused(on: day) else { return [] }
        if let setUp = BodySchedule.setUpDay(of: plan, calendar: calendar), day < setUp { return [] }
        var items: [StripItem] = []
        if day >= input.today {
            let body = input.bodyItems.filter { $0.kind != .weighIn || day == input.today }
            // The weigh-in first, then the measurements in the schedule's order.
            items += body.filter { $0.kind == .weighIn }.map(item(body:))
            items += body.filter { $0.kind != .weighIn }.map(item(body:))
        }
        let typeID = plan.dayType(on: day, marks: input.dayTypeMarks, calendar: calendar)?.id
        let checks = plan.checks.enumerated().filter { _, check in
            check.isDue(on: day, dayTypeID: typeID, calendar: calendar) || input.checkStates[check.id] != nil
        }
        let sorted = checks.sorted { lhs, rhs in
            let left = timingOrder(lhs.element.timing, input.mealSlots), right = timingOrder(rhs.element.timing, input.mealSlots)
            if left.group != right.group { return left.group < right.group }
            if left.minutes != right.minutes { return left.minutes < right.minutes }
            return lhs.offset < rhs.offset
        }
        items += sorted.map { item(check: $0.element, state: input.checkStates[$0.element.id]) }
        if day < input.today {
            items = items.filter { $0.state == .open }
        }
        guard items.contains(where: { $0.state == .open }) else { return [] }
        return items
    }

    /// Meal-timed checks first (by the meal's usual time), then clock times, then anytime.
    static func timingOrder(_ timing: CoachPlan.CheckTiming, _ slots: [MealSlot]) -> (group: Int, minutes: Int) {
        switch timing {
        case .meal(let id):
            guard let slot = slots.first(where: { $0.id == id }) else { return (2, 0) }
            return (0, slot.minutes)
        case .time(let minutes):
            return (1, minutes)
        case .anytime:
            return (2, 0)
        }
    }

    static func item(body: BodyDueItem) -> StripItem {
        let symbol: String
        let action: Action
        switch body.kind {
        case .weighIn:
            symbol = "scalemass"
            action = .weighIn
        case .weekly:
            symbol = "ruler"
            action = .measure(body)
        case .full:
            symbol = "figure.arms.open"
            action = .measure(body)
        case .assessment:
            symbol = "percent"
            action = .assessment(body)
        }
        return StripItem(id: body.kind == .weighIn ? "weighIn" : "body.\(body.kind.rawValue)",
                         kind: body.kind == .weighIn ? .weighIn : .body, title: body.title,
                         detail: body.isOverdueNotice ? body.overdueText : nil, emoji: "", symbol: symbol, state: .open,
                         action: action)
    }

    static func item(check: CoachPlan.Check, state: CheckState?) -> StripItem {
        let dose = check.dose.trimmingCharacters(in: .whitespaces)
        let itemState: StripItem.State
        switch state {
        case .done?: itemState = .done
        case .skipped?: itemState = .skipped
        case nil: itemState = .open
        }
        return StripItem(id: "check.\(check.id)", kind: .check, title: dose.isEmpty ? check.name : "\(check.name) · \(dose)",
                         detail: nil, emoji: check.emoji, symbol: check.emoji.isEmpty ? "pills" : "", state: itemState,
                         action: .check(check.id))
    }
}

// MARK: - Coach card

extension CoachBoard {
    /// The first card by priority that wasn't put off: phase start/end decision > review
    /// checkpoint > weekly check-in > baseline measurement > "Welcome back". Only on today, never
    /// while coaching is paused.
    static func card(_ input: Input) -> Card? {
        let plan = input.plan
        guard plan.isSetUp, input.day == input.today, !plan.isPaused(on: input.today) else { return nil }
        let candidates: [Card?] = [phaseCard(input), reviewCard(input), checkInCard(input), baselineCard(input),
                                   welcomeBackCard(input)]
        return candidates.compactMap { $0 }.first { !isDismissed($0, input) }
    }

    /// "Later" hides a card until tomorrow, the review for 7 days, "Welcome back" for good.
    static func isDismissed(_ card: Card, _ input: Input) -> Bool {
        guard let day = input.dismissed[card.key] else { return false }
        switch card.kind {
        case .review:
            let days = day.days(to: input.today, calendar: input.calendar)
            return days >= 0 && days < reviewSnoozeDays
        case .welcomeBack:
            return true
        default:
            return day == input.today
        }
    }

    static func name(of phase: CoachPlan.Phase) -> String {
        let trimmed = phase.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : trimmed
    }

    /// A planned phase whose start has come, else the running phase's end date reached.
    static func phaseCard(_ input: Input) -> Card? {
        let plan = input.plan, today = input.today
        if let phase = plan.duePhase(on: today) {
            let title = phase.start == today ? "\(name(of: phase)) starts today" : "\(name(of: phase)) is ready to start"
            let message: String
            if let current = plan.activePhase(on: today) {
                message = "Tap Start to switch to its targets – \(name(of: current)) keeps running until you do."
            } else {
                message = "Tap Start to switch to its targets."
            }
            return Card(key: "phaseStart.\(phase.id)", kind: .phaseStart, title: title, message: message,
                        primary: Card.Choice(title: "Start", action: .startPhase(phase.id)),
                        secondary: Card.Choice(title: "In a week", action: .postponePhase(phase.id)),
                        more: [Card.Choice(title: "Edit", action: .editPhase(phase.id))], phaseID: phase.id)
        }
        guard let active = plan.activePhase(on: today), active.status != .done, let end = active.end, end <= today else { return nil }
        let title = end == today ? "\(name(of: active)) ends today" : "\(name(of: active)) has reached its end date"
        let next = plan.phases.filter { !$0.isStarted && $0.status != .done && $0.id != active.id }
            .min { ($0.start ?? DayKey(year: 9999, month: 12, day: 31)) < ($1.start ?? DayKey(year: 9999, month: 12, day: 31)) }
        if let next {
            return Card(key: "phaseEnd.\(active.id)", kind: .phaseEnd, title: title,
                        message: "Start \(name(of: next)) now, or keep going until you're ready.",
                        primary: Card.Choice(title: "Start \(name(of: next))", action: .startPhase(next.id)),
                        secondary: Card.Choice(title: "Edit dates", action: .editPhase(active.id)), more: [], phaseID: active.id)
        }
        return Card(key: "phaseEnd.\(active.id)", kind: .phaseEnd, title: title,
                    message: "Decide what comes next: hold your weight, or plan a new phase.",
                    primary: Card.Choice(title: "Plan what's next", action: .editPlan),
                    secondary: Card.Choice(title: "Edit dates", action: .editPhase(active.id)), more: [], phaseID: active.id)
    }

    /// The review checkpoint (or a ceiling) of the active phase, until a review decision is saved.
    static func reviewCard(_ input: Input) -> Card? {
        guard let phase = input.plan.activePhase(on: input.today), !input.reviewedPhases.contains(phase.id) else { return nil }
        let title: String
        let message: String
        if let crossed = input.checkpoint, crossed <= input.today, let weight = WeightSignal.checkpoint(of: phase) {
            title = "Review weight reached"
            message = "Your 7-day average reached \(NumberText.plain(weight, decimals: 1)) kg – time to look back at "
                + "\(name(of: phase)) and decide how to go on."
        } else if let ceiling = input.ceilings.first {
            title = "Time for a phase review"
            message = "\(ceiling.message)."
        } else {
            return nil
        }
        return Card(key: "review.\(phase.id)", kind: .review, title: title, message: message,
                    primary: Card.Choice(title: "Review", action: .review(phase.id)), secondary: nil, more: [], phaseID: phase.id)
    }

    /// The weekly check-in: from the check-in day (after the morning weigh-in or from the morning
    /// cutoff) for 3 days, while that week's check-in isn't saved.
    static func checkInCard(_ input: Input) -> Card? {
        let plan = input.plan, today = input.today, calendar = input.calendar
        let weekday = min(7, max(1, plan.routine.checkInWeekday))
        let checkInDay = BodySchedule.onOrBefore(weekday: weekday, today, calendar: calendar)
        let offset = checkInDay.days(to: today, calendar: calendar)
        guard offset >= 0, offset < checkInCardDays, !plan.isPaused(on: checkInDay),
              let phase = plan.activePhase(on: checkInDay), let start = phase.start, start < checkInDay else { return nil }
        let key = DayMarks.checkInKey(week: checkInDay, calendar: calendar)
        guard !input.checkInKeys.contains(key) else { return nil }
        if offset == 0, !input.hasMorningWeighIn,
           ClockTime.minutes(of: input.now, calendar: calendar) < plan.routine.morningCutoffMinutes {
            return nil
        }
        return Card(key: "checkIn.\(key)", kind: .checkIn, title: "Weekly check-in",
                    message: "Two minutes: how your week went and what comes next.",
                    primary: Card.Choice(title: "Start", action: .checkIn(checkInDay)), secondary: nil, more: [], phaseID: phase.id)
    }

    /// The baseline measurement the schedule asks for when the plan is set up.
    static func baselineCard(_ input: Input) -> Card? {
        guard let item = input.bodyItems.first(where: { ($0.kind == .full || $0.kind == .assessment) && $0.reason == .baseline })
        else { return nil }
        let key = "baseline.\(item.dueDay.rawValue)"
        if item.kind == .assessment {
            return Card(key: key, kind: .baseline, title: "Baseline measurement",
                        message: "Add your starting body fat so your progress shows later.",
                        primary: Card.Choice(title: "Add body fat", action: .assessment(item)), secondary: nil, more: [], phaseID: nil)
        }
        let message = item.includesAssessment
            ? "Measure your starting point today – tape and body fat – so your progress shows later."
            : "Measure your starting point today so your progress shows later."
        return Card(key: key, kind: .baseline, title: "Baseline measurement", message: message,
                    primary: Card.Choice(title: "Measure", action: .measure(item)), secondary: nil, more: [], phaseID: nil)
    }

    /// "Welcome back" on the first days after a pause ended.
    static func welcomeBackCard(_ input: Input) -> Card? {
        let today = input.today, calendar = input.calendar
        let ended = input.plan.pauses.compactMap(\.end).filter { end in
            let days = end.days(to: today, calendar: calendar)
            return days >= 1 && days <= welcomeBackDays
        }.max()
        guard let end = ended else { return nil }
        let key = "welcomeBack.\(end.rawValue)"
        if input.hasMorningWeighIn {
            return Card(key: key, kind: .welcomeBack, title: "Welcome back",
                        message: "Your 7-day average fills up again over the next mornings.",
                        primary: Card.Choice(title: "Got it", action: .dismiss), secondary: nil, more: [], phaseID: nil)
        }
        if ClockTime.minutes(of: input.now, calendar: calendar) < input.plan.routine.morningCutoffMinutes {
            return Card(key: key, kind: .welcomeBack, title: "Welcome back",
                        message: "Weigh in this morning to restart your 7-day average.",
                        primary: Card.Choice(title: "Weigh in", action: .weighIn),
                        secondary: Card.Choice(title: "Got it", action: .dismiss), more: [], phaseID: nil)
        }
        return Card(key: key, kind: .welcomeBack, title: "Welcome back",
                    message: "Weigh in tomorrow morning to restart your 7-day average.",
                    primary: Card.Choice(title: "Got it", action: .dismiss), secondary: nil, more: [], phaseID: nil)
    }
}

// MARK: - Week average

extension CoachBoard {
    /// With two or more day types and targets for the week: the plan's average kcal per day, and
    /// with two or more logged days this week the average eaten against those days' targets.
    static func weekAverage(_ input: Input) -> WeekAverage? {
        let plan = input.plan, calendar = input.calendar
        guard plan.isSetUp, plan.dayTypes.count >= 2, let revision = plan.revision(on: input.day),
              let planned = plan.plannedWeekAverage(revision) else { return nil }
        let monday = input.day.startOfWeek(calendar: calendar)
        let week = DayKey.range(monday, through: monday.adding(days: 6, calendar: calendar), calendar: calendar)
        let logged = week.filter { $0 <= input.today && input.eaten[$0] != nil && !plan.isPaused(on: $0) }
        guard logged.count >= 2 else {
            return WeekAverage(planned: planned, eaten: nil, target: nil, loggedDays: logged.count,
                               text: "Week avg \(SettingsCSV.grouped(planned)) kcal")
        }
        let eaten = logged.compactMap { input.eaten[$0] }.reduce(0, +) / Double(logged.count)
        let target = logged.map {
            plan.targets(on: $0, marks: input.dayTypeMarks, fallback: input.fallback, calendar: calendar).energy
        }.reduce(0, +) / Double(logged.count)
        return WeekAverage(planned: planned, eaten: eaten, target: target, loggedDays: logged.count,
                           text: "Week avg \(SettingsCSV.grouped(eaten)) of \(SettingsCSV.grouped(target)) kcal")
    }
}

// MARK: - Card actions on the plan

extension CoachPlan {
    /// The plan after "In a week" on the phase-start card: the planned start moves to a week from
    /// its planned day (from `today` when that has already passed). Unknown or started phase:
    /// unchanged.
    public func postponing(phase id: String, by days: Int = 7, from today: DayKey, calendar: Calendar = .current) -> CoachPlan {
        guard let index = phases.firstIndex(where: { $0.id == id }), !phases[index].isStarted else { return self }
        var plan = self
        let base = max(plan.phases[index].start ?? today, today)
        plan.phases[index].start = base.adding(days: days, calendar: calendar)
        return plan
    }
}
