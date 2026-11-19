import Foundation
import NinaCore

// The plan changes behind the phase sheet and the phase review: placing an edited phase, the
// "Calculate" targets, starting, holding, ending and deleting a phase, and the numbers the
// review shows. Glue over NinaCore's `CoachPlan` and `PhaseTransition` (Foundation and NinaCore
// only); every write goes through `AppModel.phaseSheetCommit` / `updatePlan` with one Undo.

/// One day type's targets before and after a change (the previews).
struct PhaseSheetTargetRow: Identifiable, Equatable {
    /// The day type id ("" = the baseline, for plans without day types).
    let id: String
    let title: String
    let before: DailyTargets
    let after: DailyTargets

    var energyChange: Double { after.energy - before.energy }
    var macroText: String {
        CheckInSheetText.macroChange(protein: after.protein - before.protein, carbs: after.carbs - before.carbs,
                                     fat: after.fat - before.fat)
    }
}

enum PhaseSheetPlan {
    /// What starting a phase on a day writes, with the targets before and after for the preview.
    struct Start {
        var plan: CoachPlan
        /// The transition proposal, when the phase had no targets of its own.
        var proposal: PhaseTransition.Proposal?
        /// The targets in force on the day before and after.
        var before: CoachPlan.Revision?
        var after: CoachPlan.Revision?
    }

    /// The id of the stand-in phase `calculation` uses (never saved).
    private static let standInID = "phase-sheet-stand-in"

    /// A new phase id: the next number after the plan's numeric ids ("1", "2" …).
    static func newID(in plan: CoachPlan) -> String {
        var next = (plan.phases.compactMap { Int($0.id) }.max() ?? 0) + 1
        while plan.phase(id: String(next)) != nil { next += 1 }
        return String(next)
    }

    /// A new planned phase: it starts the day after the last phase's end (else today).
    static func newPhase(in plan: CoachPlan, today: DayKey, calendar: Calendar = .current) -> CoachPlan.Phase {
        let lastEnd = plan.phases.compactMap(\.end).max()
        let start = lastEnd.map { max($0.adding(days: 1, calendar: calendar), today) } ?? today
        return CoachPlan.Phase(id: newID(in: plan), goal: .maintain, start: start)
    }

    /// A sensible rate range for a goal when none is set yet (kg/week).
    static func defaultRate(for goal: WeightGoal) -> ClosedRange<Double> {
        goal == .lose ? 0.25...0.5 : 0.15...0.25
    }

    /// The plan with `phase` in place: replacing the phase with its id, or inserted in start order.
    static func placing(_ phase: CoachPlan.Phase, in plan: CoachPlan) -> CoachPlan {
        var copy = plan
        if let index = copy.phases.firstIndex(where: { $0.id == phase.id }) {
            copy.phases[index] = phase
            return copy
        }
        let index = copy.phases.firstIndex { other in
            guard let start = phase.start, let otherStart = other.start else { return false }
            return otherStart > start
        } ?? copy.phases.count
        copy.phases.insert(phase, at: index)
        return copy
    }

    /// The day a target change of `phase` starts: today for a started phase, else its start (not
    /// before today).
    static func revisionDay(of phase: CoachPlan.Phase, today: DayKey) -> DayKey {
        guard !phase.isStarted, let start = phase.start else { return today }
        return max(start, today)
    }

    /// The targets of `phase` in force on `day` (else its latest revision).
    static func currentRevision(of phase: CoachPlan.Phase, on day: DayKey) -> CoachPlan.Revision? {
        phase.revision(on: day) ?? phase.revisions.last
    }

    /// "Calculate": the phase's targets from `day` on (`PhaseTransition.proposal`): maintenance
    /// (measured over 28 days when reliable, else the calculator) ± the rate's midpoint × 1,100,
    /// every day type moved by the same kcal. A phase without targets starts from the targets
    /// before it; a phase with targets of its own is moved from those (a stand-in phase holding
    /// them runs on `day`, so the proposal starts from them).
    @MainActor
    static func calculation(for phase: CoachPlan.Phase, in plan: CoachPlan, on day: DayKey,
                            context: CoachContext) -> PhaseTransition.Proposal {
        let weight = context.bodyWeight?.kilograms ?? context.settings.body.weightKg
        var base = placing(phase, in: plan)
        var subject = phase
        if let own = currentRevision(of: phase, on: day) {
            subject.startedAt = nil
            subject.status = .planned
            subject.revisions = []
            let holding = CoachPlan.Revision(from: day, baseline: own.baseline, byType: own.byType, reason: "calculate")
            let standIn = CoachPlan.Phase(id: standInID, goal: .maintain, start: day, startedAt: Date(), status: .active,
                                          revisions: [holding])
            base.phases = base.phases.filter { $0.id != phase.id } + [subject, standIn]
        }
        return PhaseTransition.proposal(for: subject, in: base, on: day, weightKg: weight, maintenance: context.maintenance(),
                                        body: context.settings.body, fallback: context.settings.targets,
                                        calendar: context.calendar)
    }

    /// Starts phase `id` on `day` (`CoachPlan.starting`: the running phase ends the day before);
    /// a phase without targets gets the transition proposal's.
    @MainActor
    static func starting(_ id: String, in plan: CoachPlan, on day: DayKey, context: CoachContext) -> Start {
        let before = plan.revision(on: day)
        let started = plan.starting(phase: id, on: day, now: Date(), calendar: context.calendar)
        guard let phase = started.phase(id: id) else { return Start(plan: plan, proposal: nil, before: before, after: before) }
        guard phase.revisions.isEmpty else {
            return Start(plan: started, proposal: nil, before: before, after: currentRevision(of: phase, on: day))
        }
        let weight = context.bodyWeight?.kilograms ?? context.settings.body.weightKg
        let proposal = PhaseTransition.proposal(for: phase, in: started, on: day, weightKg: weight,
                                                maintenance: context.maintenance(), body: context.settings.body,
                                                fallback: context.settings.targets, calendar: context.calendar)
        let applied = proposal.applied(to: started)
        let after = applied.phase(id: id).flatMap { currentRevision(of: $0, on: day) }
        return Start(plan: applied, proposal: proposal, before: before, after: after)
    }

    /// The next planned phase (not started, not done), earliest start first.
    static func nextPhase(after active: CoachPlan.Phase?, in plan: CoachPlan) -> CoachPlan.Phase? {
        let far = DayKey(year: 9999, month: 12, day: 31)
        return plan.phases.filter { !$0.isStarted && $0.status != .done && $0.id != active?.id }
            .min { ($0.start ?? far) < ($1.start ?? far) }
    }

    /// "Hold my weight": a maintain phase from `day` until the next planned phase (or open-ended),
    /// started right away at maintenance; the running phase ends the day before.
    @MainActor
    static func holding(after active: CoachPlan.Phase, in plan: CoachPlan, from day: DayKey,
                        context: CoachContext) -> (start: Start, phaseID: String) {
        let id = newID(in: plan)
        let next = nextPhase(after: active, in: plan)
        var end: DayKey?
        if let nextStart = next?.start, nextStart > day { end = nextStart.adding(days: -1, calendar: context.calendar) }
        let hold = CoachPlan.Phase(id: id, name: CoachPlan.Phase.defaultName(for: .maintain), goal: .maintain, start: day,
                                   end: end, endApprox: end != nil && (next?.startApprox ?? false))
        var copy = plan
        let index = copy.phases.firstIndex(where: { $0.id == active.id }).map { $0 + 1 } ?? copy.phases.count
        copy.phases.insert(hold, at: index)
        return (start: starting(id, in: copy, on: day, context: context), phaseID: id)
    }

    /// The maintenance bridge a review offers after a long gain phase before a loss phase
    /// (`PhaseTransition.suggestsBridge`): a maintain phase from `day` for `days` days, started
    /// right away at maintenance (the running phase ends the day before, as with Hold), and `next`
    /// moved to start the day after it. An end of `next` that would fall before its new start
    /// moves by the same number of days.
    @MainActor
    static func bridging(after active: CoachPlan.Phase, before next: CoachPlan.Phase, days: Int, in plan: CoachPlan,
                         from day: DayKey, context: CoachContext) -> (start: Start, phaseID: String) {
        let calendar = context.calendar
        let id = newID(in: plan)
        let end = day.adding(days: max(1, days) - 1, calendar: calendar)
        let bridge = CoachPlan.Phase(id: id, name: "Maintenance bridge", goal: .maintain, start: day, end: end)
        var copy = plan
        if let index = copy.phases.firstIndex(where: { $0.id == next.id }) {
            let newStart = end.adding(days: 1, calendar: calendar)
            if let oldStart = copy.phases[index].start, let oldEnd = copy.phases[index].end, oldEnd < newStart {
                let moved = max(0, oldStart.days(to: newStart, calendar: calendar))
                copy.phases[index].end = oldEnd.adding(days: moved, calendar: calendar)
            }
            copy.phases[index].start = newStart
            copy.phases[index].startApprox = false
        }
        let index = copy.phases.firstIndex(where: { $0.id == active.id }).map { $0 + 1 } ?? copy.phases.count
        copy.phases.insert(bridge, at: index)
        return (start: starting(id, in: copy, on: day, context: context), phaseID: id)
    }

    /// The phase marked done; it ends today unless it ended earlier.
    static func markingDone(_ id: String, in plan: CoachPlan, today: DayKey) -> CoachPlan {
        guard let index = plan.phases.firstIndex(where: { $0.id == id }) else { return plan }
        var copy = plan
        copy.phases[index].status = .done
        if copy.phases[index].end.map({ $0 > today }) ?? true {
            copy.phases[index].end = today
            copy.phases[index].endApprox = false
        }
        return copy
    }

    /// The phase with a new end date (nil = open-ended).
    static func changingEnd(_ id: String, to end: DayKey?, approx: Bool, in plan: CoachPlan) -> CoachPlan {
        guard let index = plan.phases.firstIndex(where: { $0.id == id }) else { return plan }
        var copy = plan
        copy.phases[index].end = end
        copy.phases[index].endApprox = end == nil ? false : approx
        return copy
    }

    static func removing(_ id: String, from plan: CoachPlan) -> CoachPlan {
        var copy = plan
        copy.phases.removeAll { $0.id == id }
        return copy
    }

    /// Every day type's targets before → after (one "Every day" row for plans without day types).
    static func rows(plan: CoachPlan, before: CoachPlan.Revision?, after: CoachPlan.Revision?,
                     fallback: DailyTargets) -> [PhaseSheetTargetRow] {
        guard !plan.dayTypes.isEmpty else {
            return [PhaseSheetTargetRow(id: "", title: "Every day", before: before?.baseline ?? fallback,
                                        after: after?.baseline ?? fallback)]
        }
        return plan.dayTypes.map { type in
            PhaseSheetTargetRow(id: type.id, title: CheckInSheetText.dayType(type.id, plan: plan, empty: "Every day"),
                                before: before?.targets(for: type.id) ?? fallback, after: after?.targets(for: type.id) ?? fallback)
        }
    }

    /// "Maintenance 2,450 kcal, measured over the last 28 days" / "… calculated from your profile".
    static func maintenanceLine(_ proposal: PhaseTransition.Proposal) -> String {
        let source = proposal.source == .measured ? "measured over the last 28 days" : "calculated from your profile"
        return "Maintenance \(Fmt.number(proposal.maintenance.rounded())) kcal, \(source)"
    }

    /// "+150 kcal a day over maintenance", "−300 kcal a day under maintenance", "At maintenance".
    static func adjustmentLine(_ proposal: PhaseTransition.Proposal) -> String {
        if abs(proposal.adjustment) < 1 { return "At maintenance" }
        let side = proposal.adjustment > 0 ? "over" : "under"
        return "\(CheckInSheetText.signedKcal(proposal.adjustment)) a day \(side) maintenance"
    }
}

// MARK: - Review

/// Where a phase stands for the phase review: weeks run, weight, rate, waist and body
/// composition since the start, days on plan from the check-ins, and what the sheet is about.
@MainActor
struct PhaseReviewFacts {
    enum Mode: Equatable {
        /// The review checkpoint or a ceiling was reached (and no decision saved yet).
        case review
        /// The running phase has reached its end date.
        case end
        /// A planned phase is due (or could start now).
        case start
        /// Opened any other time.
        case open
        /// The phase is done.
        case done
        /// The phase doesn't exist (any more).
        case missing
    }

    let mode: Mode
    let today: DayKey
    /// The phase the sheet is about.
    let phase: CoachPlan.Phase?
    /// The phase running today.
    let active: CoachPlan.Phase?
    /// The next planned phase after the running one.
    let next: CoachPlan.Phase?
    /// Today's weight numbers (the running phase's start, rate and status).
    let summary: WeightSignal.Summary
    let checkpointReached: DayKey?
    let ceilings: [BodyCeiling]
    let waist: GirthChange?
    let arm: GirthChange?
    let chest: GirthChange?
    let composition: CompositionChange?
    /// Check-ins of this phase: counted days and days on plan.
    let checkInDays: Int
    let onPlanDays: Int
    /// The review asks for a full measurement set first (none in the last 14 days).
    let needsFullSet: Bool
    /// A 1–2 week maintenance bridge is worth offering before the next phase: a gain phase of
    /// more than 12 weeks is under review or at its end, and a loss phase comes next.
    let offersBridge: Bool

    var name: String { phase.map(CheckInSheetText.phaseName) ?? "Phase" }

    /// The card's title.
    var headline: String {
        switch mode {
        case .review: checkpointReached != nil ? "Review weight reached" : "Time for a phase review"
        case .end: phase?.end == today ? "\(name) ends today" : "\(name) has reached its end date"
        case .start: "\(name) is ready to start"
        case .open: name
        case .done: "\(name) is done"
        case .missing: "Phase not found"
        }
    }

    /// One sentence under the title.
    var message: String {
        switch mode {
        case .review:
            if checkpointReached != nil, let phase, let weight = WeightSignal.checkpoint(of: phase) {
                return "Your 7-day average reached \(Fmt.kilograms(weight)) – look back at \(name) and decide how to go on."
            }
            if let ceiling = ceilings.first { return "\(ceiling.message)." }
            return "Look back at \(name) and decide how to go on."
        case .end:
            return "Keep going, hold your weight, or start what comes next."
        case .start:
            if let active { return "Start it now to switch to its targets – \(CheckInSheetText.phaseName(active)) keeps running until you do." }
            return "Start it now to switch to its targets."
        case .open:
            return "Where you stand, and your options."
        case .done:
            return "This phase is finished. Its name and note can still be changed in the phase sheet."
        case .missing:
            return "This phase is no longer in your plan."
        }
    }

    /// The key of the coach card this review belongs to ("Later" hides it).
    var cardKey: String? {
        guard let phase else { return nil }
        switch mode {
        case .review: return "review.\(phase.id)"
        case .end: return "phaseEnd.\(phase.id)"
        case .start: return "phaseStart.\(phase.id)"
        default: return nil
        }
    }

    /// `heightCm`: the profile's height (0 = not set), for the tape estimate.
    static func load(context: CoachContext, phaseID: String, heightCm: Double = 0) -> PhaseReviewFacts {
        let plan = context.plan
        let today = context.today
        let calendar = context.calendar
        let phase = plan.phase(id: phaseID)
        let active = plan.activePhase(on: today)
        let crossing = phase.flatMap { $0.isStarted ? context.signal.checkpointCrossing(of: $0, through: today) : nil }
        var ceilings = phase?.id == active?.id ? context.ceilings : []
        if let active, phase?.id == active.id {
            let latest = PhaseBodyFat.latest(context.bodyFatReadings, tape: context.tapeRecords, sex: context.settings.body.sex,
                                             heightCm: heightCm, method: plan.routine.bodyFatMethod, on: today,
                                             calendar: calendar)
            ceilings = PhaseBodyFat.ceilings(ceilings, phase: active, latestBodyFat: latest)
        }

        let mode: Mode
        if let phase {
            let reviewed = context.reviewedPhases.contains(phase.id)
            if !phase.isStarted {
                mode = phase.status == .done ? .done : .start
            } else if phase.status == .done {
                mode = .done
            } else if phase.id == active?.id, !reviewed, crossing != nil || !ceilings.isEmpty {
                mode = .review
            } else if let end = phase.end, end <= today {
                mode = .end
            } else {
                mode = .open
            }
        } else {
            mode = .missing
        }

        let start = phase?.start
        let records = context.tapeRecords
        let waistSite = CheckInSheetFacts.waistSite(sex: context.settings.body.sex, records: records)
        func change(_ sites: [BodySite]) -> GirthChange? {
            for site in sites {
                if let found = GirthTrend.change(site, in: records, since: start, calendar: calendar), found.from.day < found.to.day {
                    return found
                }
            }
            return nil
        }

        // The tracking series with the live tape estimate, as the Body page shows it.
        let composition = start.flatMap { PhaseBodyFat.change(context: context, since: $0, through: today, heightCm: heightCm) }

        let next = PhaseSheetPlan.nextPhase(after: active ?? phase, in: plan)
        var offersBridge = false
        if let phase, mode == .review || mode == .end, next?.goal == .lose {
            offersBridge = PhaseTransition.suggestsBridge(after: phase, on: today, calendar: calendar)
        }

        let checkIns = context.checkIns.filter { $0.phaseID == phaseID }
        let recent = today.adding(days: -BodySchedule.recentDays, calendar: calendar)
        let hasRecentFull = context.schedule.fullDays.contains { $0 >= recent && $0 <= today }
        return PhaseReviewFacts(
            mode: mode, today: today, phase: phase, active: active, next: next,
            summary: context.summary, checkpointReached: crossing, ceilings: ceilings,
            waist: change([waistSite]), arm: change([.arm, .armLeft]), chest: change([.chest]), composition: composition,
            checkInDays: checkIns.compactMap(\.days).reduce(0, +), onPlanDays: checkIns.compactMap(\.onPlan).reduce(0, +),
            needsFullSet: mode == .review && !plan.routine.fullSites.isEmpty && !hasRecentFull, offersBridge: offersBridge)
    }
}

// MARK: - Writing

extension AppModel {
    /// Writes a plan (nil = unchanged) and records phase decisions, with one toast whose Undo puts
    /// both back.
    func phaseSheetCommit(_ plan: CoachPlan?, events: [(phaseID: String, event: PhaseEvent)], message: String,
                          symbol: String = "flag.fill") {
        let store = self.store
        let day = today
        var change = CoachUndo()
        if let plan { change.merge(store.updatePlan(plan, on: day)) }
        for item in events {
            change.merge(store.recordPhaseEvent(phaseID: item.phaseID, event: item.event, day: day))
        }
        showUndo(change, message, symbol: symbol)
    }
}
