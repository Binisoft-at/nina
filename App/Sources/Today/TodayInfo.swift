import Foundation
import NinaCore

/// The ⓘ texts of Today: what "kcal left" counts, the day type, the week average and protein
/// meals, the checks strip, the coach card, the phase line and "Set your goal". Plain strings (no
/// SwiftUI) that say what Nina's rules really do (`DayProgress`, `CoachBoard`, `ProteinMeals`,
/// `WeightSignal.StatusLine`, docs/BODY.md). Mac texts say "click" where iPhone and iPad say "tap".
enum TodayInfo {
    /// One ⓘ: a few words and one or two short sentences.
    struct Note: Equatable {
        let title: String
        let text: String
    }

    // MARK: Summary card

    /// The goal tile next to the ring: what "kcal left" counts, the activity bonus and planned food.
    /// - Parameters:
    ///   - activityBonus: kcal added to the goal from Apple Health today (0 = none).
    ///   - bonusShare: Settings → Apple Health → "Add to my budget" (0, 0.5 or 1).
    ///   - fromPlan: the goal comes from a set-up coach plan (My Plan) rather than Goals & Plan.
    static func caloriesLeft(activityBonus: Double, bonusShare: Double, fromPlan: Bool) -> Note {
        let source = fromPlan ? "your plan" : "Goals & Plan"
        let planned = "Planned food shows as dots on the ring and only counts once you mark it eaten."
        guard activityBonus > 0 else {
            return Note(title: "Calories left",
                        text: "What's left of this day's goal (from \(source)) after what you've eaten. " + planned)
        }
        return Note(title: "Calories left",
                    text: "Today's goal plus \(shareWord(bonusShare)) of today's active energy from Apple Health (Settings → "
                        + "Apple Health), minus what you've eaten. " + planned)
    }

    /// "all", "half" or "part" of the active energy.
    static func shareWord(_ share: Double) -> String {
        if share >= 0.99 { return "all" }
        if abs(share - 0.5) < 0.01 { return "half" }
        return "part"
    }

    /// The day-type chip at the top of the summary card. `hasQuota`: a flexible type whose chip
    /// counts its days in the week ("Tennis · 1 of 2 this week").
    static func dayType(hasQuota: Bool) -> Note {
        var types: String = "Your plan gives each kind of day, like Gym or Rest, its own calories, and the goal follows "
            + "the day's type."
        if hasQuota {
            types = "Your plan gives each kind of day its own calories, and the goal follows the day's type – for this "
                + "type the chip also counts its days in the week."
        }
        return Note(title: "Day type",
                    text: types + " \(tapCapitalized) the chip to change it – filled means you picked it by hand, outlined "
                        + "means it follows your schedule.")
    }

    /// The small line at the bottom of the summary card: "Week avg …" and/or "Protein meals …".
    static func footnotes(weekAverage: Bool, proteinMeals: Bool) -> Note {
        let week = "Week avg is what you ate per day on average over this week's finished days with a log, against "
            + "those days' targets (days marked Log Is Incomplete stay out)."
        let protein = "Protein meals counts this day's meals whose eaten protein reached your minimum per meal (the "
            + "pill in each meal's header fills), out of the number your plan asks for."
        switch (weekAverage, proteinMeals) {
        case (true, true): return Note(title: "Week average and protein meals", text: week + " " + protein)
        case (true, false): return Note(title: "Week average", text: week)
        default: return Note(title: "Protein meals", text: protein)
        }
    }

    /// The water card: the glass button's hidden "other amounts".
    static var water: Note {
        #if os(macOS)
        let more = "or use its arrow for other amounts"
        #else
        let more = "or touch and hold it for other amounts"
        #endif
        return Note(title: "Water",
                    text: "\(tapCapitalized) the + button to add one glass (its size is under Settings → Water glass), "
                        + "\(more). − takes the last one back.")
    }

    // MARK: Coach

    /// The checks strip under the summary card.
    static var checks: Note {
        #if os(macOS)
        let act = "Click one to do it; right-click a check for Not Today."
        #else
        let act = "Tap one to do it; touch and hold a check for Not Today."
        #endif
        return Note(title: "Checks",
                    text: "What your plan asks for on this day: the morning weigh-in, measurements that are due and your "
                        + "daily checks. " + act)
    }

    /// The coach card above the meals, by kind.
    static func card(_ kind: CoachBoard.Card.Kind) -> Note {
        switch kind {
        case .phaseStart:
            return Note(title: "Starting a phase",
                        text: "A phase is a stretch with one goal – gain, maintain or lose – and its own calories. Nothing "
                            + "changes until you \(tap) Start; In a week moves the start a week later.")
        case .phaseEnd:
            return Note(title: "End of a phase",
                        text: "End dates are soft: the phase keeps its calories until you start the next one or plan what "
                            + "comes next. Edit dates moves the end.")
        case .review:
            return Note(title: "Phase review",
                        text: "Your 7-day average reached the review weight you set, or your waist or body fat reached "
                            + "a limit. Review shows where you stand; then keep going, hold your weight or start the next phase.")
        case .checkIn:
            return Note(title: "Weekly check-in",
                        text: "Once a week Nina looks at your weight trend and how closely you followed the plan. It only "
                            + "proposes a small calorie change when the numbers call for it, and nothing changes until you "
                            + "\(tap) Apply.")
        case .baseline:
            return Note(title: "Baseline measurement",
                        text: "Your starting numbers, so later measurements have something to compare with. Measure in the "
                            + "morning before eating – the same way every time.")
        case .welcomeBack:
            return Note(title: "Welcome back",
                        text: "Paused days stay out of your pace, check-ins and adherence. Weigh in on the next mornings "
                            + "so your 7-day average fills up again.")
        case .pauseCheck:
            return Note(title: "Paused coaching",
                        text: "While paused there are no checks, check-ins or coach reminders, and those days stay out of "
                            + "your pace. Resume when you're ready; Later asks again in a week.")
        }
    }

    /// The phase line's status words ("In range", "Slower than planned", "Off track", "Gathering
    /// data", "New targets since …", "Paused · …", "No rate set"). `hasPace`: the phase has a pace
    /// range (without one, and not paused, the status is "No rate set").
    static func phase(status: String, tone: BodyPageTone, isPaused: Bool, hasPace: Bool) -> Note {
        if isPaused {
            return Note(title: "Paused",
                        text: "While coaching is paused there are no checks, check-ins or coach reminders, and these days "
                            + "stay out of your pace. Resume starts coaching again from today.")
        }
        if !hasPace {
            return Note(title: status,
                        text: "This phase has no planned pace (kg a week), so Nina can't judge your weight trend. Set a "
                            + "pace range for the phase in My Plan.")
        }
        if status.hasPrefix("New targets") {
            return Note(title: "New targets",
                        text: "Your calories changed, so your pace is measured afresh from that day. The first check-in "
                            + "that can judge the new targets is on the date shown.")
        }
        switch tone {
        case .good:
            return Note(title: status,
                        text: "Your pace – how fast your 7-day average moves – is inside the range planned for this phase. "
                            + "Keep going.")
        case .watch:
            return Note(title: status,
                        text: "Your pace – how fast your 7-day average moves – is outside the range planned for this phase. "
                            + "One week means little: the weekly check-in only proposes a change when it stays that way.")
        case .alert:
            return Note(title: status,
                        text: "Your pace has stayed outside the planned range at your recent check-ins. The next weekly "
                            + "check-in can propose a small calorie change.")
        case .neutral:
            return Note(title: status,
                        text: "Nina needs about two weeks of morning weigh-ins (at least 10) since the phase start or the "
                            + "last calorie change before it can judge your pace.")
        }
    }

    // MARK: Set your goal

    /// "Set your goal" for new users.
    static func goalCard(_ reason: GoalSetupPrompt.Reason) -> Note {
        switch reason {
        case .standardTargets:
            return Note(title: "Why set your goal?",
                        text: "Until you do, Nina uses the same starting targets for everyone. Goals & Plan works out yours "
                            + "from your sex, age, height, weight, activity and goal – or you type your own.")
        case .missingBody:
            return Note(title: "Why height and birth year?",
                        text: "Nina uses them to check your calorie targets (the calculator in Goals & Plan) and for body "
                            + "numbers such as waist-to-height and the tape estimate of body fat.")
        }
    }

    // MARK: Words

    /// "tap" on iPhone and iPad, "click" on the Mac.
    static var tap: String {
        #if os(macOS)
        return "click"
        #else
        return "tap"
        #endif
    }

    static var tapCapitalized: String {
        #if os(macOS)
        return "Click"
        #else
        return "Tap"
        #endif
    }
}
