import Foundation

/// The plan editor's changes (Settings → Goals & Plan) as pure functions: setting a plan up, new
/// ids, day types and daily checks added or changed, targets that change as a revision from today,
/// pausing and resuming coaching. The app saves the result with `updatePlan`, whose Undo puts the
/// plan back as it was.
public enum PlanEdits {
    /// The most day types a plan can have.
    public static let maxDayTypes = 4
    /// The emoji `CoachPlan.DayType.suggestedEmoji(for:)` gives rest days.
    static let restEmoji = CoachPlan.DayType.suggestedEmoji(for: "rest")

    // MARK: Setting up

    /// The plan after "Set Up My Plan": the day types and the one open-ended phase that
    /// `CoachPlan.migrated(from:on:)` builds from the goals people had (training days become
    /// "Training" plus "Rest"), keeping what the plan already holds (checks, notes, the long-term
    /// goal, protein per meal, pauses; the routine unless it is the default one). A plan that is
    /// already set up stays as it is.
    public static func settingUp(_ plan: CoachPlan, from state: SettingsState, on day: DayKey, now: Date = Date()) -> CoachPlan {
        guard !plan.isSetUp else { return plan }
        let migrated = CoachPlan.migrated(from: state, on: day, now: now)
        var result = plan
        result.dayTypes = migrated.dayTypes
        result.phases = migrated.phases
        if plan.routine == CoachPlan.Routine() { result.routine = migrated.routine }
        return result
    }

    /// The plan after its first phase was added before "Set Up My Plan" (the phase sheet on a plan
    /// that isn't set up): the same migration as setting up – the training days become "Training"
    /// on its weekdays plus "Rest" on the others (`CoachPlan.migrated(from:on:)`), the routine for
    /// the person's sex while the plan has the default one – and `phase` as the plan's only phase.
    /// A phase without targets gets the targets people had as its first revision from its start
    /// (baseline = the daily targets, Training = the training-day targets, Rest = the daily ones),
    /// so training days keep their calories once it runs and the profile mirror keeps them.
    /// Checks, notes, the long-term goal, protein per meal and pauses stay. A plan that is already
    /// set up gets `phase` put in (replacing the one with its id, else added) and nothing else.
    public static func addingFirstPhase(_ phase: CoachPlan.Phase, to plan: CoachPlan, from state: SettingsState,
                                        on day: DayKey, now: Date = Date()) -> CoachPlan {
        var result = plan
        guard !plan.isSetUp else {
            if let index = result.phases.firstIndex(where: { $0.id == phase.id }) {
                result.phases[index] = phase
            } else {
                result.phases.append(phase)
            }
            return result
        }
        let migrated = CoachPlan.migrated(from: state, on: day, now: now)
        result.dayTypes = migrated.dayTypes
        if plan.routine == CoachPlan.Routine() { result.routine = migrated.routine }
        var first = phase
        if first.revisions.isEmpty, let template = migrated.phases.first?.revisions.first {
            first.revisions = [CoachPlan.Revision(from: phase.start ?? day, baseline: template.baseline, byType: template.byType,
                                                  reason: template.reason)]
        }
        result.phases = [first]
        return result
    }

    // MARK: Ids

    /// An id for a new day type or check: the name in lowercase letters and digits ("Gym" → "gym",
    /// "Käse-Tag" → "kasetag"), `fallback` when nothing is left, with a number when it is taken
    /// ("gym2").
    public static func newID(for name: String, existing: [String], fallback: String = "day") -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var base = String(folded.filter { allowed.contains($0) }.prefix(20))
        if base.isEmpty { base = fallback }
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)\(number)") { number += 1 }
        return "\(base)\(number)"
    }

    // MARK: Day types

    /// The plan with a new day type: a rest day ("Rest", "Off", "Ruhetag" …) becomes the default
    /// type for all other days when the plan has none yet; anything else starts flexible, once a
    /// week. The emoji fits the name when one does. nil when the plan already has `maxDayTypes`.
    public static func addingDayType(named name: String, to plan: CoachPlan) -> (plan: CoachPlan, id: String)? {
        guard plan.dayTypes.count < maxDayTypes else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "New day" : trimmed
        let id = newID(for: title, existing: plan.dayTypes.map(\.id), fallback: "day")
        let emoji = CoachPlan.DayType.suggestedEmoji(for: title)
        let isDefault = plan.defaultDayType == nil && emoji == restEmoji
        let type = CoachPlan.DayType(id: id, name: title, emoji: emoji,
                                     schedule: isDefault ? .default : .flexible, perWeek: isDefault ? 0 : 1)
        var result = plan
        result.dayTypes.append(type)
        return (result, id)
    }

    /// The plan with a day type changed (matched by id). There is only one default type: making
    /// this one the default turns any other default type into a flexible one.
    public static func updatingDayType(_ type: CoachPlan.DayType, in plan: CoachPlan) -> CoachPlan {
        guard let index = plan.dayTypes.firstIndex(where: { $0.id == type.id }) else { return plan }
        var result = plan
        result.dayTypes[index] = type
        if type.schedule == .default {
            for other in result.dayTypes.indices where other != index && result.dayTypes[other].schedule == .default {
                result.dayTypes[other].schedule = .flexible
            }
        }
        return result
    }

    /// The plan without a day type: the type goes, and every daily check that named it no longer
    /// does – a check left without day types is due every day again (as `updatingCheck` saves
    /// it), so no pill or reminder silently disappears. Revisions keep their targets for the type
    /// (they are ignored without it, and come back with Undo). Unknown ids: unchanged.
    public static func deletingDayType(_ id: String, in plan: CoachPlan) -> CoachPlan {
        guard plan.dayType(id: id) != nil else { return plan }
        var result = plan
        result.dayTypes.removeAll { $0.id == id }
        for index in result.checks.indices {
            guard case .dayTypes(let ids) = result.checks[index].days, ids.contains(id) else { continue }
            let rest = ids.filter { $0 != id }
            result.checks[index].days = rest.isEmpty ? .daily : .dayTypes(rest)
        }
        return result
    }

    // MARK: Targets

    /// The plan with a day type's own targets in the phase active on `day` (nil = the same as the
    /// baseline), as a revision from `day` on. Revisions that start later move by the same
    /// difference, so the change holds from `day` on and a change they made (an adjustment
    /// applied from tomorrow) stays on top. Unchanged without an active phase or when nothing differs.
    public static func settingTargets(_ targets: DailyTargets?, forType typeID: String, in plan: CoachPlan, on day: DayKey) -> CoachPlan {
        changingTargets(in: plan, on: day) { revision in
            revision.byType[typeID] = targets
        }
    }

    /// The plan with the baseline (the targets of days without their own) of the phase active on
    /// `day` set from `day` on, like `settingTargets(_:forType:in:on:)`.
    public static func settingBaseline(_ targets: DailyTargets, in plan: CoachPlan, on day: DayKey) -> CoachPlan {
        changingTargets(in: plan, on: day) { revision in
            revision.baseline = targets
        }
    }

    /// Targets from the calculator for the phase active on `day`: they become the baseline from
    /// `day` on, and every day type with its own targets moves by the same calories (split by the
    /// phase's macro rule), so the differences between day types stay. `fallback`: the targets in
    /// force before the phase had a baseline (the profile's).
    public static func applyingCalculated(_ targets: DailyTargets, to plan: CoachPlan, on day: DayKey, weightKg: Double = 0,
                                          fallback: DailyTargets) -> CoachPlan {
        guard let phase = plan.activePhase(on: day) else { return plan }
        let before = phase.revision(on: day)?.baseline ?? fallback
        let shift = targets.energy - before.energy
        let rule = CoachPlan.MacroRule(goal: phase.goal)
        return changingTargets(in: plan, on: day) { revision in
            revision.baseline = targets
            revision.byType = revision.byType.mapValues { CoachPlan.shifted($0, by: shift, macros: rule, weightKg: weightKg) }
        }
    }

    /// Changes the revision in force on `day` (copied into one from `day`, reason "edit"; a
    /// revision that already starts on `day` keeps its reason, so an adjustment's lock stays).
    /// Every later revision of the active phase moves by the same difference, field by field
    /// (`carrying(_:from:to:)`): applying +100 from tomorrow and then raising Gym protein today
    /// keeps tomorrow's +100.
    static func changingTargets(in plan: CoachPlan, on day: DayKey, _ change: (inout CoachPlan.Revision) -> Void) -> CoachPlan {
        guard let phase = plan.activePhase(on: day), let index = plan.phases.firstIndex(where: { $0.id == phase.id }) else { return plan }
        var current = phase.revision(on: day) ?? CoachPlan.Revision(from: day)
        let before = current
        change(&current)
        var later = phase.revisions.filter { $0.from > day }
        let laterBefore = later
        for position in later.indices { later[position] = carrying(later[position], from: before, to: current) }
        guard current.baseline != before.baseline || current.byType != before.byType || later != laterBefore else { return plan }
        let reason = before.from == day && !before.reason.isEmpty ? before.reason : "edit"
        var result = plan.addingRevision(phase: phase.id, from: day, baseline: current.baseline, byType: current.byType, reason: reason)
        guard !later.isEmpty else { return result }
        let kept = result.phases[index].revisions.filter { $0.from <= day }
        result.phases[index].revisions = (kept + later).sorted { $0.from < $1.from }
        return result
    }

    /// A later revision after an edit of the revision in force (`before` → `edited`): the
    /// baseline and every day type move by what the edit changed, field by field, on top of what
    /// the later revision already differs by. A type without its own targets counts as its
    /// revision's baseline. A type set back to the baseline (nil) is nil later too; where there is
    /// nothing to measure the difference from (no baseline before), the edited targets are copied.
    static func carrying(_ revision: CoachPlan.Revision, from before: CoachPlan.Revision, to edited: CoachPlan.Revision) -> CoachPlan.Revision {
        var result = revision
        if before.baseline != edited.baseline {
            if let old = before.baseline, let new = edited.baseline, let value = revision.baseline {
                result.baseline = offset(value, from: old, to: new)
            } else {
                result.baseline = edited.baseline
            }
        }
        let ids = Set(before.byType.keys).union(edited.byType.keys).union(revision.byType.keys)
        for id in ids.sorted() {
            let old = before.byType[id] ?? before.baseline
            let new = edited.byType[id] ?? edited.baseline
            guard old != new || before.byType[id] != edited.byType[id] else { continue }
            if edited.byType[id] == nil, before.byType[id] != nil {
                result.byType[id] = nil
            } else if let old, let new, let value = revision.byType[id] ?? revision.baseline {
                result.byType[id] = offset(value, from: old, to: new)
            } else if let own = edited.byType[id] {
                result.byType[id] = own
            }
        }
        return result
    }

    /// `targets` moved by `edited − before` in every field (never below 0).
    static func offset(_ targets: DailyTargets, from before: DailyTargets, to edited: DailyTargets) -> DailyTargets {
        func moved(_ value: Double, _ old: Double, _ new: Double) -> Double { max(0, value + (new - old)) }
        return DailyTargets(energy: moved(targets.energy, before.energy, edited.energy),
                            protein: moved(targets.protein, before.protein, edited.protein),
                            carbs: moved(targets.carbs, before.carbs, edited.carbs),
                            fat: moved(targets.fat, before.fat, edited.fat),
                            fiber: moved(targets.fiber, before.fiber, edited.fiber),
                            sugarMax: moved(targets.sugarMax, before.sugarMax, edited.sugarMax),
                            saturatedFatMax: moved(targets.saturatedFatMax, before.saturatedFatMax, edited.saturatedFatMax),
                            sodiumMax: moved(targets.sodiumMax, before.sodiumMax, edited.sodiumMax),
                            water: moved(targets.water, before.water, edited.water))
    }

    // MARK: Checks

    /// The plan with a new daily check (anytime, every day, with a reminder as an imported check
    /// gets one; "affects weight" when the name says creatine).
    public static func addingCheck(named name: String, to plan: CoachPlan) -> (plan: CoachPlan, id: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "New check" : trimmed
        let id = newID(for: title, existing: plan.checks.map(\.id), fallback: "check")
        var result = plan
        result.checks.append(CoachPlan.Check(id: id, name: title, remind: true))
        return (result, id)
    }

    /// The plan with a check changed (matched by id). A check left with no weekdays or no day types
    /// is due every day, as the settings file reads such a check back (it would otherwise never be due).
    public static func updatingCheck(_ check: CoachPlan.Check, in plan: CoachPlan) -> CoachPlan {
        guard let index = plan.checks.firstIndex(where: { $0.id == check.id }) else { return plan }
        var changed = check
        switch check.days {
        case .daily: break
        case .weekdays(let days): if days.isEmpty { changed.days = .daily }
        case .dayTypes(let ids): if ids.isEmpty { changed.days = .daily }
        }
        var result = plan
        result.checks[index] = changed
        return result
    }

    // MARK: Pausing

    /// The plan with coaching paused from `day` until `end` (nil = until resumed). A pause that
    /// covers `day` is replaced; an end before `day` is taken as `day`.
    public static func pausing(_ plan: CoachPlan, from day: DayKey, until end: DayKey?, reason: CoachPlan.PauseReason) -> CoachPlan {
        var result = plan
        result.pauses.removeAll { $0.contains(day) }
        result.pauses.append(CoachPlan.Pause(start: day, end: end.map { max($0, day) }, reason: reason))
        result.pauses.sort { $0.start < $1.start }
        return result
    }

    /// The plan with coaching running again on `day`: the pause covering it ends the day before
    /// (or goes, when it started on `day`). Other pauses stay.
    public static func resuming(_ plan: CoachPlan, on day: DayKey, calendar: Calendar = .current) -> CoachPlan {
        guard let index = plan.pauses.firstIndex(where: { $0.contains(day) }) else { return plan }
        var result = plan
        if result.pauses[index].start >= day {
            result.pauses.remove(at: index)
        } else {
            result.pauses[index].end = day.adding(days: -1, calendar: calendar)
        }
        return result
    }
}
