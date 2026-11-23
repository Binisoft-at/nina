import Foundation
import NinaCore

/// What Today shows of the coach for one day, taken from `CoachContext` once per data change:
/// the board (day-type chip, checks strip, coach card, week average), the protein-per-meal rule
/// for the meal headers and today's morning weigh-in (for the weigh-in pill's short "saved" look).
/// Without a plan (and without a protein minimum in it) nothing is loaded and nothing shows.
struct TodayCoachState: Equatable, Sendable {
    var board: CoachBoard = .empty
    /// The rule behind the meal-header protein pills; nil = no pills.
    var proteinRule: ProteinMeals.Rule?
    /// Today's morning weight and 7-day average, once there is one.
    var weighIn: TodayCoachWeighIn?
    /// A past day's daily checks with their state (done ones too), for the "Checks of this day"
    /// menu; empty on today and later days (the strip covers them).
    var dayChecks: [TodayCoachDayCheck] = []
    /// The calories a day before and after "Start" on a phase card (one row per day type, or
    /// one for the whole day without day types); empty for other cards.
    var cardTargets: [CoachBoard.TargetChange] = []
    /// Today's running phase as one line above the summary card; nil on other days.
    var phaseLine: TodayCoachPhaseLine?
    /// The day can be marked "incomplete log" (a set-up plan, today or earlier).
    var offersIncompleteLog = false
    /// The day is marked "incomplete log": check-ins and adherence leave it out.
    var isIncompleteLog = false
    /// False until the first load finished (the strip then appears without an animation).
    var isLoaded = false

    static let empty = TodayCoachState()

    /// What the checks strip needs.
    var stripInput: TodayCoachStripInput {
        TodayCoachStripInput(items: board.strip, weighIn: weighIn, isLoaded: isLoaded)
    }

    /// The coach parts of `day` with the app's settings, the live Apple Health weigh-ins and this
    /// device's "Later" taps (`CoachContext.load(app:day:now:)`).
    @MainActor
    static func load(app: AppModel, day: DayKey, now: Date = Date()) -> TodayCoachState {
        var state = TodayCoachState()
        state.isLoaded = true
        let plan = app.settings.plan
        guard plan.isSetUp || plan.protein.isSet else { return state }
        let context = CoachContext.load(app: app, day: day, now: now)
        state.board = context.board
        let rule = context.proteinRule
        if TodayCoachState.showsProtein(plan: context.plan), rule.isActive {
            state.proteinRule = rule
        }
        let today = context.today
        if let morning = context.signal.morning(on: today) {
            state.weighIn = TodayCoachWeighIn(kilograms: morning.kilograms,
                                              average: context.signal.average(on: today).value)
        }
        if day < today {
            state.dayChecks = TodayCoachState.pastChecks(context)
        }
        if let card = context.board.card, case .startPhase(let id) = card.primary.action {
            state.cardTargets = TodayCoachState.targetRows(context, startingPhase: id)
        }
        if day == today {
            state.phaseLine = TodayCoachPhaseLine(context)
        }
        if context.isSetUp, day <= today {
            state.offersIncompleteLog = true
            state.isIncompleteLog = app.store.hasDayEvent(TodayCoachEvent.incompleteLog, on: day)
        }
        return state
    }

    /// The calories a day now and after "Start" on `id`, per day type (in plan order), or one row
    /// for the whole day without day types. Now: the running phase's targets today, else the
    /// profile's. After: what Start writes (`CoachContext.startingPlan`: the phase's own targets,
    /// or the proposed ones when it has none). Empty when nothing can be worked out.
    @MainActor
    static func targetRows(_ context: CoachContext, startingPhase id: String) -> [CoachBoard.TargetChange] {
        let today = context.today
        guard let started = context.startingPlan(phase: id), let after = started.revision(on: today) else { return [] }
        return CoachBoard.targetChanges(plan: context.plan, before: context.plan.revision(on: today), after: after,
                                        fallback: context.settings.targets)
    }

    /// The checks of a past day: those due that day (by its day type) and any with a mark, in the
    /// plan's order. None before the plan was set up or while coaching was paused.
    @MainActor
    private static func pastChecks(_ context: CoachContext) -> [TodayCoachDayCheck] {
        let plan = context.plan
        let day = context.day
        let calendar = context.calendar
        guard plan.isSetUp, !plan.isPaused(on: day) else { return [] }
        if let setUp = BodySchedule.setUpDay(of: plan, calendar: calendar), day < setUp { return [] }
        let typeID: String? = context.dayType?.id
        let states: [String: CheckState] = context.checkStates
        let due: [CoachPlan.Check] = plan.checks.filter { check in
            check.isDue(on: day, dayTypeID: typeID, calendar: calendar) || states[check.id] != nil
        }
        return due.map { check in
            TodayCoachDayCheck(id: check.id, name: check.name, emoji: check.emoji, state: states[check.id])
        }
    }

    /// "Week avg 2,380 of 2,400 kcal" once two days of this week are logged (eaten against those
    /// days' targets); nil before that. The plan's planned average belongs to the plan editor.
    func weekAverageText(unit: EnergyUnit) -> String? {
        guard let average = board.weekAverage, let eaten = average.eaten, let target = average.target else { return nil }
        return "Week avg \(Fmt.energy(eaten, unit: unit, showUnit: false)) of \(Fmt.energy(target, unit: unit))"
    }

    /// "Protein meals 3 of 4" (eaten meals that reached the minimum, at most the day's count);
    /// nil without a protein rule.
    static func proteinMealsText(_ day: ProteinMeals.Day?) -> String? {
        guard let day, day.target > 0 else { return nil }
        return "Protein meals \(day.text)"
    }

    /// Protein pills and the search hint show with a set-up plan (minimum from the plan, else
    /// 0.4 g/kg of the body weight, as the check-in counts protein meals) or, without one, when
    /// the plan sets a minimum per meal.
    static func showsProtein(plan: CoachPlan) -> Bool {
        plan.isSetUp || plan.protein.isSet
    }
}

/// Today's morning weigh-in for the weigh-in pill right after saving.
struct TodayCoachWeighIn: Equatable, Sendable {
    var kilograms: Double
    /// The valid 7-day average (nil while it needs more mornings).
    var average: Double?

    /// "74.2 · avg 74.6"; just "74.2 kg" while the 7-day average isn't there yet.
    var text: String {
        guard let average else { return Fmt.kilograms(kilograms) }
        return "\(Fmt.number(kilograms, decimals: 1)) · avg \(Fmt.number(average, decimals: 1))"
    }
}

/// A phase card's "before → after" line in the app's energy unit.
extension CoachBoard.TargetChange {
    /// "2,450 → 2,150 kcal", or "2,450 kcal" when it stays.
    func todayCoachText(unit: EnergyUnit) -> String {
        let next = Fmt.energy(after, unit: unit)
        guard changes else { return next }
        return "\(Fmt.energy(before, unit: unit, showUnit: false)) → \(next)"
    }

    /// "Gym: 2,450 kcal now, 2,150 kcal after starting"
    func todayCoachAccessibility(unit: EnergyUnit) -> String {
        let next = Fmt.energy(after, unit: unit)
        guard changes else { return "\(name): stays at \(next)" }
        return "\(name): \(Fmt.energy(before, unit: unit)) now, \(next) after starting"
    }
}

/// Today's running phase in one line above the summary card: "Lean gain · week 3 of 16", the
/// status words of the body page ("In range", "Slower", "Off track" …) and the share of the phase
/// gone. Built from `BodyPageData.header`, so Today and Progress always say the same.
struct TodayCoachPhaseLine: Equatable, Sendable {
    var phaseID: String
    /// "Lean gain · week 3 of 16"
    var title: String
    /// "In range"
    var status: String
    var tone: BodyPageTone
    /// Share of the phase gone (0…1); nil without an end date.
    var progress: Double?
    /// Coaching is paused ("Paused · until 12 Feb"): the line offers Resume.
    var isPaused = false
    /// The phase has a pace range (without one the status reads "No rate set").
    var hasPace = true

    /// The active phase of today; nil without a set-up plan or without a running phase.
    @MainActor
    init?(_ context: CoachContext) {
        guard context.isSetUp, context.day == context.today, context.activePhase != nil,
              let header = BodyPageData.header(context), header.isActive else { return nil }
        phaseID = header.phaseID
        title = header.title
        status = header.status
        tone = header.tone
        progress = header.progress
        isPaused = header.isPaused
        hasPace = header.rate != nil
    }

    /// "Lean gain, week 3 of 16, In range"
    var accessibilityText: String {
        "\(title.replacingOccurrences(of: " · ", with: ", ")), \(status)"
    }
}

/// Keys of `DayMark(kind: event)` marks Today writes.
enum TodayCoachEvent {
    /// The day's log is incomplete: check-ins and adherence leave it out.
    static let incompleteLog = "incompleteLog"
}

/// One daily check of a past day in the "Checks of this day" menu.
struct TodayCoachDayCheck: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var emoji: String
    /// nil = open.
    var state: CheckState?

    /// "💊 Creatine"
    var title: String { emoji.isEmpty ? name : "\(emoji) \(name)" }

    /// The menu item's symbol: a filled check when done, a dash when skipped, a ring when open.
    var symbol: String {
        switch state {
        case .done?: return "checkmark.circle.fill"
        case .skipped?: return "minus.circle"
        case nil: return "circle"
        }
    }
}

/// The checks strip's input: its pills and today's weigh-in (a weigh-in that appears while the
/// weigh-in pill was open shows the weight in place for 2 seconds).
struct TodayCoachStripInput: Equatable, Sendable {
    var items: [CoachBoard.StripItem] = []
    var weighIn: TodayCoachWeighIn?
    var isLoaded = false
}

// MARK: - Settings helpers

extension NinaSettings {
    /// The plan has day types to show (the week strip keeps a line for their emoji).
    var todayCoachHasDayTypes: Bool { plan.isSetUp && !plan.dayTypes.isEmpty }

    /// The emoji of a day's type (its own, else one that fits its name); nil without a plan or
    /// without a fitting emoji. Shown in front of the Today accessory and the Mac sidebar line.
    func todayCoachEmoji(for day: DayKey) -> String? {
        guard let type = dayType(for: day) else { return nil }
        let emoji = type.todayCoachEmoji
        return emoji.isEmpty ? nil : emoji
    }

    /// The week strip's mark under a day: the emoji of any type but the default one (rest days
    /// show nothing).
    func todayCoachStripEmoji(for day: DayKey) -> String? {
        guard let type = dayType(for: day), type.schedule != .default else { return nil }
        let emoji = type.todayCoachEmoji
        return emoji.isEmpty ? nil : emoji
    }

    /// The day-type chip of any day, with its menu options (the week strip's touch-and-hold
    /// menu); nil without a set-up plan with day types.
    func todayCoachChip(for day: DayKey, today: DayKey, now: Date = Date()) -> CoachBoard.Chip? {
        guard todayCoachHasDayTypes else { return nil }
        let input = CoachBoard.Input(plan: plan, day: day, today: today, now: now, mealSlots: meals,
                                     fallback: legacyTargets(for: day), dayTypeMarks: dayTypeMarks)
        return CoachBoard(input).chip
    }

    /// The protein-per-meal rule for the search hint ("+18 g protein to reach 35"), with the
    /// app's body weight; nil when Today shows no protein pills.
    var todayCoachProteinRule: ProteinMeals.Rule? {
        guard TodayCoachState.showsProtein(plan: plan) else { return nil }
        let rule = ProteinMeals.Rule(protein: plan.protein, weightKg: bodyWeightKg ?? 0, mealSlots: meals.map(\.id))
        return rule.isActive ? rule : nil
    }
}

extension CoachPlan.DayType {
    /// Its own emoji, else one that fits its name ("" when none fits).
    var todayCoachEmoji: String {
        emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: name) : emoji
    }
}

// MARK: - Protein pill text

extension ProteinMeals.Meal {
    /// "32 / 35 g" in whole grams (eaten plus planned, as `ProteinMeals` compares them).
    var todayCoachText: String {
        "\(Fmt.number(total.rounded())) / \(Fmt.number(minimum.rounded())) g"
    }

    /// The minimum is reached (filled pill), planned food included.
    var todayCoachIsReached: Bool { fill != .below }
}
