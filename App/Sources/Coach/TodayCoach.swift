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
        return state
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
