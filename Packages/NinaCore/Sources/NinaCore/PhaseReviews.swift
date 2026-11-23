import Foundation

/// The review decisions on the phases (phase `DayMark`s with review-keep, review-hold or
/// review-cut): the day of the newest one per phase, and the ceilings the decisions answered.
///
/// A decision answers the review that was open when it was made, so the two kinds of trigger
/// (F5) are counted apart:
/// - the **review checkpoint** counts as reviewed only by a decision on or after the day the
///   7-day average reached it. A review a ceiling opened earlier in the phase doesn't use it up;
/// - a **ceiling** (waist gain, waist-to-height, body fat) counts as reviewed by a decision that
///   answered it: one made while it was reached (the mark's meta "ceilings=waistGain,bodyFat").
///   "Keep going" at the review weight answers no ceiling, so a body-fat ceiling reached weeks
///   later still opens the review. Decisions saved before Nina recorded this answer every ceiling.
///
/// Every place that asks "is the review still open?" reads it from here: Today's review card
/// (`CoachBoard`), the check-in (`CheckInInput.use(signal:reviews:)`), the review sheet and the
/// review notification (`CoachReminders`).
public struct PhaseReviews: Equatable, Sendable, ExpressibleByDictionaryLiteral {
    /// The phase events that are review decisions.
    public static let events: Set<PhaseEvent> = [.reviewKeep, .reviewHold, .reviewCut]
    /// The meta key of the ceilings a decision answered ("ceilings=waistGain,bodyFat").
    public static let ceilingsKey = "ceilings"

    /// Phase id → the day of its newest review decision.
    public var days: [String: DayKey]
    /// Phase id → the ceilings its decisions answered (all of them together).
    public var answered: [String: Set<BodyCeiling>]

    /// Each phase with a decision answered every ceiling (decisions without a record).
    public init(_ days: [String: DayKey] = [:]) {
        self.init(days: days, answered: days.mapValues { _ in Set(BodyCeiling.allCases) })
    }

    public init(days: [String: DayKey], answered: [String: Set<BodyCeiling>]) {
        self.days = days
        self.answered = answered
    }

    public init(dictionaryLiteral elements: (String, DayKey)...) {
        self.init(Dictionary(elements, uniquingKeysWith: { max($0, $1) }))
    }

    /// From phase decisions in any order: review events only, the newest day per phase; each
    /// answered every ceiling.
    public init(events: [(phaseID: String, event: PhaseEvent, day: DayKey)]) {
        self.init(decisions: events.map { (phaseID: $0.phaseID, event: $0.event, day: $0.day, ceilings: nil) })
    }

    /// From phase decisions in any order with the ceilings each answered (`ceilings(fromMeta:)`;
    /// nil = not recorded: every ceiling).
    public init(decisions: [(phaseID: String, event: PhaseEvent, day: DayKey, ceilings: [BodyCeiling]?)]) {
        var days: [String: DayKey] = [:]
        var answered: [String: Set<BodyCeiling>] = [:]
        for item in decisions where PhaseReviews.events.contains(item.event) {
            days[item.phaseID] = max(days[item.phaseID] ?? item.day, item.day)
            answered[item.phaseID, default: []].formUnion(item.ceilings ?? BodyCeiling.allCases)
        }
        self.days = days
        self.answered = answered
    }

    /// The day of the phase's newest review decision; nil = never reviewed.
    public func lastReview(of phaseID: String) -> DayKey? {
        days[phaseID]
    }

    /// The phase has a review decision.
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

    /// A reached ceiling still waits for a decision: no decision of the phase answered it.
    public func ceilingIsOpen(_ phaseID: String, ceilings: [BodyCeiling]) -> Bool {
        !openCeilings(phaseID, ceilings: ceilings).isEmpty
    }

    /// The reached ceilings no decision answered yet, in the order given.
    public func openCeilings(_ phaseID: String, ceilings: [BodyCeiling]) -> [BodyCeiling] {
        let done = answered[phaseID] ?? []
        return ceilings.filter { !done.contains($0) }
    }

    /// The phase review is open: the checkpoint reached and not reviewed since, or a ceiling
    /// reached that no decision answered.
    public func isOpen(_ phaseID: String, crossing: DayKey?, ceilings: [BodyCeiling]) -> Bool {
        checkpointIsOpen(phaseID, crossing: crossing) || ceilingIsOpen(phaseID, ceilings: ceilings)
    }

    // MARK: Meta

    /// The meta value for the ceilings a decision answered: "waistGain,bodyFat", "none".
    public static func metaValue(_ ceilings: [BodyCeiling]) -> String {
        ceilings.isEmpty ? "none" : ceilings.map(\.rawValue).joined(separator: ",")
    }

    /// The ceilings a decision answered, from its meta value; nil when it wasn't recorded (an
    /// older decision: every ceiling). Unknown names are ignored.
    public static func ceilings(fromMeta value: String?) -> [BodyCeiling]? {
        guard let value else { return nil }
        return value.split(separator: ",").compactMap { BodyCeiling(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
