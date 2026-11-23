import Foundation
import NinaCore

/// The ⓘ texts of the phase sheet and the phase review (`InfoButton`: a title and one or two
/// short sentences). The limits come from NinaCore (`CoachPlan.Phase`, `PhaseTransition`), so the
/// texts follow the rules.
enum PhaseSheetInfo {
    typealias Item = CheckInSheetInfo.Item

    /// The weekly rate range and its share of body weight.
    static var rate: Item {
        let gain = Fmt.number(CoachPlan.Phase.gainCautionPercent, decimals: 1)
        let loss = Fmt.number(CoachPlan.Phase.lossCautionPercent, decimals: 1)
        return (title: "Weekly rate",
                text: "How fast your 7-day average should move each week; your targets aim for the middle of the range. The % is that pace as a share of your weight – above \(gain) % a week for a gain or \(loss) % for a loss, Nina adds a calm note.")
    }

    /// The review checkpoint (`WeightSignal.checkpoint`: the lower of the two numbers).
    static let review: Item = (
        title: "Review weight",
        text: "A weight at which to stop and look back. When your 7-day average reaches it (the lower number, if you enter two), Nina asks how you want to go on – a single weigh-in never does."
    )

    /// The ceilings of a gain phase (`BodyCeiling`).
    static var limits: Item {
        let ratio = Fmt.number(BodyComposition.waistToHeightGuideline, decimals: 1)
        return (title: "Review limits",
                text: "A gain brings some fat along with the muscle, so these limits open the review early. Besides your waist and body-fat limits below, it also opens when your waist-to-height rises to \(ratio) during the phase (with your height in Goals & Plan).")
    }

    /// "Calculate" (`PhaseTransition.proposal`).
    static let calculate: Item = (
        title: "Calculate",
        text: "Your maintenance comes from your log and weigh-ins of the last 28 days, or from your profile while there isn't enough of both. Nina adds or takes away the middle of your rate – 0.1 kg a week ≈ 110 kcal a day – and shows the new targets before anything is saved."
    )

    /// The maintenance bridge after a long gain (`PhaseTransition.suggestsBridge`).
    static var bridge: Item {
        (title: "Maintenance bridge",
         text: "After more than \(PhaseTransition.bridgeAfterWeeks) weeks of gaining, a week or two at maintenance gives you a calm start before the loss phase. Nina adds a short maintenance phase and moves the loss phase to start right after it.")
    }

    /// The choices of a running phase's review (Keep going, Hold, Start the next, the end date).
    /// `laterText`: when "Decide Later" asks again ("in 7 days", "tomorrow"; nil without it).
    static func choices(keepEndsDate: Bool, showsKeep: Bool, hasNext: Bool, laterText: String?) -> Item {
        var parts: [String] = []
        if showsKeep { parts.append(keepEndsDate ? "Keep going removes the end date" : "Keep going keeps your targets") }
        parts.append(hasNext ? "Hold my weight switches to maintenance until your next phase" : "Hold my weight switches to maintenance")
        if hasNext { parts.append("Start now begins your next phase with its own targets") }
        let last: String = parts.removeLast()
        let first: String = parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
        guard let laterText else { return (title: "Your choices", text: first + ".") }
        return (title: "Your choices", text: first + ". Decide Later asks again \(laterText).")
    }

    /// The choices when a planned phase is due (Start now, In a week).
    static var start: Item {
        (title: "Starting a phase",
         text: "Start now switches to this phase's targets from today, and In a week moves its start 7 days later. Decide Later asks again tomorrow; until you choose, nothing changes.")
    }
}
