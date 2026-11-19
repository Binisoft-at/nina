import Foundation

/// The review decisions on the phases (phase `DayMark`s with review-keep, review-hold or
/// review-cut), as the day of the newest one per phase.
///
/// A decision answers the review that was open when it was made, so the two kinds of trigger
/// (F5) are counted apart:
/// - the **review checkpoint** counts as reviewed only by a decision on or after the day the
///   7-day average reached it. A review a ceiling opened earlier in the phase doesn't use it up;
/// - a **ceiling** (waist gain, waist-to-height, body fat) counts as reviewed by any decision in
///   the phase.
///
/// Every place that asks "is the review still open?" reads it from here: Today's review card
/// (`CoachBoard`), the check-in (`CheckInInput.use(signal:reviews:)`), the review sheet and the
/// review notification (`CoachReminders`).
public struct PhaseReviews: Equatable, Sendable, ExpressibleByDictionaryLiteral {
    /// The phase events that are review decisions.
    public static let events: Set<PhaseEvent> = [.reviewKeep, .reviewHold, .reviewCut]

    /// Phase id → the day of its newest review decision.
    public var days: [String: DayKey]

    public init(_ days: [String: DayKey] = [:]) {
        self.days = days
    }

    public init(dictionaryLiteral elements: (String, DayKey)...) {
        self.init(Dictionary(elements, uniquingKeysWith: { max($0, $1) }))
    }

    /// From phase decisions in any order: review events only, the newest day per phase.
    public init(events: [(phaseID: String, event: PhaseEvent, day: DayKey)]) {
        var days: [String: DayKey] = [:]
        for item in events where PhaseReviews.events.contains(item.event) {
            days[item.phaseID] = max(days[item.phaseID] ?? item.day, item.day)
        }
        self.days = days
    }

    /// The day of the phase's newest review decision; nil = never reviewed.
    public func lastReview(of phaseID: String) -> DayKey? {
        days[phaseID]
    }

    /// The phase has a review decision: a ceiling counts as reviewed.
    public func hasReview(_ phaseID: String) -> Bool {
        days[phaseID] != nil
    }

    /// The checkpoint the 7-day average reached on `crossing` was reviewed: a decision on or
    /// after that day.
    public func reviewedCheckpoint(_ phaseID: String, crossing: DayKey) -> Bool {
        days[phaseID].map { $0 >= crossing } ?? false
    }

    /// The checkpoint was reached (`crossing`, nil = not reached) and not reviewed since: it
    /// stops the check-in and shows the review.
    public func checkpointIsOpen(_ phaseID: String, crossing: DayKey?) -> Bool {
        guard let crossing else { return false }
        return !reviewedCheckpoint(phaseID, crossing: crossing)
    }

    /// A reached ceiling still waits for a decision: the phase has none yet.
    public func ceilingIsOpen(_ phaseID: String, ceilings: [BodyCeiling]) -> Bool {
        !ceilings.isEmpty && !hasReview(phaseID)
    }

    /// The phase review is open: the checkpoint reached and not reviewed since, or a ceiling
    /// reached and no decision yet.
    public func isOpen(_ phaseID: String, crossing: DayKey?, ceilings: [BodyCeiling]) -> Bool {
        checkpointIsOpen(phaseID, crossing: crossing) || ceilingIsOpen(phaseID, ceilings: ceilings)
    }
}
