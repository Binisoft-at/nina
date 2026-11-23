import Foundation
import NinaCore

/// The ⓘ texts of the weekly check-in (`InfoButton`: a title and one or two short sentences).
/// Numbers come from the plan's own adjustment settings (`CoachPlan.Adjust`) and the rate rules,
/// so they stay true when the person changes them in My Plan → Adjustments.
enum CheckInSheetInfo {
    /// A title and its text.
    typealias Item = (title: String, text: String)

    /// "tap" on iPhone and iPad, "click" on the Mac.
    static var tap: String {
        #if os(macOS)
        "click"
        #else
        "tap"
        #endif
    }

    /// One text per step of the live check-in (`CheckInSheetFacts.pageTitles`).
    static func step(_ page: Int) -> Item {
        switch page {
        case 0:
            return (title: "Your week",
                    text: "The 7-day average evens out the daily ups and downs, and the rate is how fast it moves per week. On the bar, the dot is your rate and the green band your phase's range.")
        case 1:
            return (title: "Your waist",
                    text: "Once a week the tape shows what the scale can't – for example whether a gain goes to your middle. One reading is enough; when it moved more than \(Fmt.number(BodyReadings.recheckChange, decimals: 1)) cm since last time, Nina asks for a second to be sure.")
        case 2:
            return (title: "How it went",
                    text: "How closely you followed your plan this week. Nina only proposes a calorie change when you logged most days and ate close to your targets – otherwise the scale can't show whether the targets work.")
        default:
            return (title: "Next week",
                    text: "Nina compares your rate with your phase's range and says what it means for next week. A change comes only when the rules call for it, and nothing changes until you \(tap) Apply.")
        }
    }

    /// Why the rate is still "Gathering data" (step 1, and the reason on step 4).
    static func gathering(minimumDays: Int, minimumWeighIns: Int) -> Item {
        (title: "Gathering data",
         text: "Your rate needs at least \(minimumWeighIns) morning weigh-ins spread over \(minimumDays) days, counted from the phase start or your last calorie change. Until then Nina doesn't judge your pace – just keep weighing in each morning.")
    }

    /// The lock after a calorie change (rule `.locked`).
    static func lock(days: Int) -> Item {
        guard days > 0 else {
            return (title: "Waiting after a change",
                    text: "New targets need time before the scale shows what they do. The next check-in judges them, and your rate counts only weigh-ins since the change.")
        }
        return (title: "Waiting after a change",
                text: "New targets need time before the scale shows what they do. So Nina proposes nothing new for \(days) days after a calorie change, and your rate counts only weigh-ins since then.")
    }

    /// Outside the range once: waiting for the next check-in (rule `.confirming`).
    static func confirming(checks: Int) -> Item {
        (title: "Why not change yet",
         text: "One week outside your range can be water, salt or a busy week. Nina suggests a change only when \(count(checks)) check-ins in a row are outside on the same side.")
    }

    /// The adherence gate (rules `.logging` and `.intake`).
    static func adherence(tolerance: Double) -> Item {
        (title: "Why no change",
         text: "A change only makes sense when the targets were really eaten: at least \(Fmt.number(CheckInEngine.minimumLoggedShare * 100)) % of the days logged and your average within \(Fmt.number(tolerance)) kcal of your targets. Hit them this week, and the next check-in can judge your rate.")
    }

    /// The ⓘ next to the reason on "Next week", for the rules that hold a change back; nil for
    /// the others (their sentence says enough).
    static func reason(_ rule: CheckInEngine.Rule, adjust: CoachPlan.Adjust, minimumDays: Int, minimumWeighIns: Int) -> Item? {
        switch rule {
        case .gathering:
            return gathering(minimumDays: minimumDays, minimumWeighIns: minimumWeighIns)
        case .locked:
            return lock(days: adjust.lockDays)
        case .confirming:
            return confirming(checks: max(1, adjust.confirmChecks))
        case .logging, .intake:
            return adherence(tolerance: adjust.intakeTolerance)
        default:
            return nil
        }
    }

    /// Why there is a proposal, and why the step is small (`CheckInEngine.step`).
    static func proposal(adjust: CoachPlan.Adjust) -> Item {
        let low = max(0, min(adjust.stepMin, adjust.stepMax))
        let high = max(0, adjust.stepMin, adjust.stepMax)
        let size = low == high ? "\(Fmt.number(low)) kcal" : "\(Fmt.number(low))–\(Fmt.number(high)) kcal"
        return (title: "Why this change",
                text: "Your rate was outside your range at \(count(max(1, adjust.confirmChecks))) check-ins in a row, so Nina suggests the same change for every day type. A step of \(size) a day – bigger the further you are from the middle of your range – moves your rate without overshooting.")
    }

    /// The optional 1–5 ratings.
    static let ratings: Item = (title: "How you felt",
                                text: "Optional scores for how your week felt. They never change your targets – they're saved with this check-in, so you can look back on them later.")

    /// "two", "three" … for small counts, digits otherwise.
    static func count(_ value: Int) -> String {
        let words = ["one", "two", "three", "four", "five", "six"]
        return (1...words.count).contains(value) ? words[value - 1] : "\(value)"
    }
}
