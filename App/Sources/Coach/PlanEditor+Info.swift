import Foundation
import NinaCore

/// The ⓘ texts of My Plan and its pages (`InfoButton`: a title and one or two short sentences).
enum PlanEditorInfo {
    typealias Item = CheckInSheetInfo.Item

    static let dayTypes: Item = (
        title: "Day types",
        text: "Each day type has its own calories and macros and comes on fixed weekdays, when you pick it, or on all other days. A change from the check-in moves all of them by the same amount, so the differences between them stay."
    )

    /// Fixed, flexible and the default (`CoachPlan.Schedule`).
    static let schedule: Item = (
        title: "When a day type comes",
        text: "Fixed weekdays come by themselves on those days; flexible ones you pick on the day (the number per week is only a hint). All other days covers every day no other type claims – usually Rest; without such a type, those days get the baseline."
    )

    /// A day type's own targets against the baseline.
    static let baseline: Item = (
        title: "Same as baseline",
        text: "The baseline is what every day without its own targets gets. Switch this off to give this day type its own calories and macros; a change from the check-in still moves both by the same amount."
    )

    static let checks: Item = (
        title: "Daily checks",
        text: "Small things your plan asks you to do, like taking a supplement – every day, on some weekdays or on certain day types. They show as pills on Today to tick off, and the check-in counts how often you did them."
    )

    static let measuring: Item = (
        title: "Measuring & check-in",
        text: "Measuring sets when you weigh in, your check-in day, which sites you measure and how you track body fat. Adjustments sets how big a calorie change from the weekly check-in can be and how long Nina waits between changes."
    )

    /// The morning cutoff (`CoachPlan.Routine.morningCutoffMinutes`).
    static let morningCutoff: Item = (
        title: "Morning weights",
        text: "Your first weigh-in of the day before this time is your morning weight – the one the 7-day average and your rate use. Later weigh-ins still show on the chart but don't count."
    )

    /// Two readings per site in a full set (`BodyReadings`).
    static var twoReadings: Item {
        (title: "Two readings",
         text: "In a full set each site is measured twice and Nina saves the average; when the two differ by more than \(Fmt.number(BodyReadings.maxDifference, decimals: 1)) cm, it asks for a third and keeps the middle one. Off: one reading, and a second only when it moved more than \(Fmt.number(BodyReadings.recheckChange, decimals: 1)) cm since last time.")
    }

    /// The step range of a proposal (`CoachPlan.Adjust.stepMin/stepMax`).
    static let step: Item = (
        title: "Step size",
        text: "How much one proposal from the check-in changes your daily calories. Nina picks a size in this range – the further your rate is from the middle of your range, the bigger – and moves every day type by it."
    )

    /// The window and the lock (`CoachPlan.Adjust`).
    static let timing: Item = (
        title: "Timing",
        text: "The first row is how many days of weigh-ins your rate needs before a check-in judges it, the second how far back it looks at most. The days between changes give new targets time to show on the scale before Nina proposes another."
    )

    /// Protein per meal (`CoachPlan.Protein`).
    static let protein: Item = (
        title: "Protein per meal",
        text: "Protein spread over your meals: a meal that reaches the minimum fills the protein pill in its header on Today, and the check-in counts those meals. The maximum is only a guide – going over never shows a warning."
    )

    /// The long-term body goal (`CoachPlan.LongTerm`).
    static let longTerm: Item = (
        title: "Long-term goal",
        text: "Where you want to end up, maybe over several phases. The Body page shows it as the Body goal card with what's still to go; your current phase's target weight is separate."
    )

    static let pause: Item = (
        title: "Pausing",
        text: "Your plan stays as it is – only the coaching rests. When the pause ends, your rate starts fresh from the next day, so the break never counts against you."
    )

    static let ai: Item = (
        title: "Your AI",
        text: "Copy for My AI puts your plan, the last 4 weeks and your body numbers on the clipboard – Nina sends nothing anywhere. Your AI answers with a settings block; Import from My AI shows it as a preview first, and one Undo takes it all back."
    )
}
