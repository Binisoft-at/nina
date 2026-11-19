import Foundation
import SwiftData
import NinaCore

/// The plan editor's reads, writes and display text (no SwiftUI). Every change reads the plan as
/// stored right now (`app.store.settings.plan`; `app.settings` follows a moment after each save),
/// changes one part (`PlanEdits`) and saves it with `app.updatePlan`, whose toast's Undo puts the
/// plan back as it was.
@MainActor
enum PlanEditorData {
    /// The plan as stored now.
    static func storedPlan(_ app: AppModel) -> CoachPlan { app.store.settings.plan }

    /// Saves `plan` when it differs from the stored one, with a toast whose Undo restores the plan before.
    @discardableResult
    static func save(_ plan: CoachPlan, app: AppModel, message: String, symbol: String = "checkmark.circle.fill") -> Bool {
        guard plan != storedPlan(app) else { return false }
        app.updatePlan(plan, message: message, symbol: symbol)
        return true
    }

    // MARK: Setting up and phases

    /// "Set Up My Plan": day types from the training days and one phase from today, following the goal.
    static func setUp(app: AppModel) {
        let plan = PlanEdits.settingUp(storedPlan(app), from: app.settingsState, on: app.today)
        save(plan, app: app, message: "Plan set up – your first phase starts today", symbol: "sparkles")
    }

    static func deletePhase(_ id: String, app: AppModel) {
        var plan = storedPlan(app)
        guard let phase = plan.phase(id: id) else { return }
        plan.phases.removeAll { $0.id == id }
        save(plan, app: app, message: "Deleted \u{201C}\(phaseName(phase))\u{201D}", symbol: "trash.fill")
    }

    // MARK: Day types and targets

    /// Adds a day type and returns its id (nil with four day types already).
    static func addDayType(named name: String, app: AppModel) -> String? {
        guard let added = PlanEdits.addingDayType(named: name, to: storedPlan(app)) else { return nil }
        let label = added.plan.dayType(id: added.id).map(typeLabel) ?? "Day type"
        save(added.plan, app: app, message: "\(label) added", symbol: "plus.circle.fill")
        return added.id
    }

    /// Saves a day type; with `targetsChanged` also its targets in the active phase (nil = same as
    /// the baseline) as a revision from today.
    static func saveDayType(_ type: CoachPlan.DayType, targets: DailyTargets?, targetsChanged: Bool, app: AppModel) {
        var cleaned = type
        cleaned.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = storedPlan(app).dayType(id: type.id)?.name ?? "Day" }
        cleaned.emoji = type.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.perWeek = max(0, min(7, type.perWeek))
        var plan = PlanEdits.updatingDayType(cleaned, in: storedPlan(app))
        if targetsChanged { plan = PlanEdits.settingTargets(targets, forType: type.id, in: plan, on: app.today) }
        save(plan, app: app, message: "\(typeLabel(cleaned)) saved")
    }

    static func deleteDayType(_ id: String, app: AppModel) {
        var plan = storedPlan(app)
        guard let type = plan.dayType(id: id) else { return }
        plan.dayTypes.removeAll { $0.id == id }
        save(plan, app: app, message: "Deleted \u{201C}\(type.name)\u{201D}", symbol: "trash.fill")
    }

    /// The baseline of the active phase (targets of days without their own) from today.
    static func saveBaseline(_ targets: DailyTargets, app: AppModel) {
        let plan = PlanEdits.settingBaseline(targets, in: storedPlan(app), on: app.today)
        save(plan, app: app, message: "Targets saved from today")
    }

    /// The calculator's targets for the active phase from today; every day type moves by the same calories.
    static func applyCalculated(_ targets: DailyTargets, app: AppModel) {
        let settings = app.settings
        let plan = PlanEdits.applyingCalculated(targets, to: storedPlan(app), on: app.today,
                                                weightKg: settings.bodyWeightKg ?? 0, fallback: settings.targets)
        save(plan, app: app, message: "Phase targets: \(Fmt.energy(targets.energy, unit: app.energyUnit)) from today", symbol: "target")
    }

    /// The targets a day type or the baseline starts from when it gets its own.
    static func startingTargets(plan: CoachPlan, app: AppModel) -> DailyTargets {
        plan.revision(on: app.today)?.baseline ?? app.settings.legacyTargets(for: app.today)
    }

    // MARK: Checks

    static func addCheck(named name: String, app: AppModel) -> String {
        let added = PlanEdits.addingCheck(named: name, to: storedPlan(app))
        save(added.plan, app: app, message: "\(added.plan.check(id: added.id)?.name ?? "Check") added", symbol: "plus.circle.fill")
        return added.id
    }

    static func saveCheck(_ check: CoachPlan.Check, app: AppModel) {
        var cleaned = check
        cleaned.name = check.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty { cleaned.name = storedPlan(app).check(id: check.id)?.name ?? "Check" }
        cleaned.emoji = check.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.dose = check.dose.trimmingCharacters(in: .whitespacesAndNewlines)
        save(PlanEdits.updatingCheck(cleaned, in: storedPlan(app)), app: app, message: "\(cleaned.name) saved")
    }

    static func deleteCheck(_ id: String, app: AppModel) {
        var plan = storedPlan(app)
        guard let check = plan.check(id: id) else { return }
        plan.checks.removeAll { $0.id == id }
        save(plan, app: app, message: "Deleted \u{201C}\(check.name)\u{201D}", symbol: "trash.fill")
    }

    // MARK: Measuring, adjustments, protein, long-term goal, notes

    static func saveRoutine(_ routine: CoachPlan.Routine, app: AppModel) {
        var plan = storedPlan(app)
        var cleaned = routine
        cleaned.thighMark = routine.thighMark.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.fullEveryWeeks = max(1, routine.fullEveryWeeks)
        cleaned.bodyFatEveryWeeks = max(1, routine.bodyFatEveryWeeks)
        plan.routine = cleaned
        save(plan, app: app, message: "Measuring saved", symbol: "ruler.fill")
    }

    static func saveAdjust(_ adjust: CoachPlan.Adjust, app: AppModel) {
        var plan = storedPlan(app)
        var cleaned = adjust
        cleaned.stepMax = max(adjust.stepMin, adjust.stepMax)
        cleaned.windowMaxDays = max(adjust.windowMinDays, adjust.windowMaxDays)
        plan.adjust = cleaned
        save(plan, app: app, message: "Adjustments saved")
    }

    static func saveProtein(_ protein: CoachPlan.Protein, app: AppModel) {
        var plan = storedPlan(app)
        var cleaned = protein
        if cleaned.mealMax > 0, cleaned.mealMax < cleaned.mealMin { cleaned.mealMax = cleaned.mealMin }
        plan.protein = cleaned
        save(plan, app: app, message: "Protein per meal saved")
    }

    static func saveLongTerm(_ goal: CoachPlan.LongTerm, app: AppModel) {
        var plan = storedPlan(app)
        var cleaned = goal
        cleaned.note = goal.note.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.longTerm = cleaned
        save(plan, app: app, message: "Long-term goal saved", symbol: "flag.checkered")
    }

    /// Deletes the note at `index` when it still reads `text` (it may have changed on another device).
    static func deleteNote(at index: Int, text: String, app: AppModel) {
        var plan = storedPlan(app)
        if plan.notes.indices.contains(index), plan.notes[index] == text {
            plan.notes.remove(at: index)
        } else if let found = plan.notes.firstIndex(of: text) {
            plan.notes.remove(at: found)
        } else {
            return
        }
        save(plan, app: app, message: "Note deleted", symbol: "trash.fill")
    }

    // MARK: Pausing

    static func pause(until end: DayKey?, reason: CoachPlan.PauseReason, app: AppModel) {
        let plan = PlanEdits.pausing(storedPlan(app), from: app.today, until: end, reason: reason)
        let until = end.map { " until \(Fmt.shortDay($0))" } ?? ""
        save(plan, app: app, message: "Coaching paused\(until)", symbol: "pause.circle.fill")
    }

    static func resume(app: AppModel) {
        let store = app.store
        let plan = PlanEdits.resuming(store.settings.plan, on: app.today, calendar: store.calendar)
        save(plan, app: app, message: "Coaching resumed", symbol: "play.circle.fill")
    }

    // MARK: Export and "Copy for my AI"

    /// The goals & settings file with the whole plan (Import & Export writes the same).
    static func exportText(app: AppModel) -> String {
        SettingsCSV.export(app.settingsState, today: app.today)
    }

    /// "Copy for my AI": the plan, the last four weeks and the body numbers. Weigh-ins from Apple
    /// Health (and a Health weight in the settings) only with `includeHealth`.
    static func aiText(app: AppModel, includeHealth: Bool) -> String {
        let store = app.store
        let calendar = store.calendar
        let today = app.today
        let start = CoachCopy.firstDay(today: today, calendar: calendar)
        let weights = store.weights()
        var readings = weights.map(\.reading)
        if includeHealth { readings += app.healthWeightReadings }
        var state = app.settingsState
        state.weightKg = weights.last?.kilograms ?? (includeHealth ? app.health.latestWeight ?? 0 : 0)
        let measurements = store.measurements()
        let bodyFat = (measurements.compactMap(\.bodyFatReading) + weights.compactMap(\.bodyFatReading)).sorted { $0.day < $1.day }
        let incomplete = Set(store.dayMarks(.event, from: start, through: today).filter { $0.key == "incompleteLog" }.map(\.dayKey))
        let input = CoachCopy.Input(
            today: today, state: state, readings: readings, includeHealth: includeHealth,
            totals: CoachContext.totals(store: store, from: start, through: today), dayTypeMarks: store.dayTypeMarks(),
            doneChecks: store.doneChecks(from: start, through: today), incompleteDays: incomplete,
            tape: measurements.compactMap(\.tapeRecord), bodyFat: bodyFat, checkIns: store.checkIns(),
            currentSettings: SettingsCSV.export(state, today: today), appName: AppInfo.name)
        return CoachCopy.text(input, calendar: calendar)
    }

    // MARK: Display text

    static func phaseName(_ phase: CoachPlan.Phase) -> String {
        phase.name.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : phase.name
    }

    /// "Running · week 2 of 21", "Ready to start", "Planned", "Done".
    static func phaseStatus(_ phase: CoachPlan.Phase, plan: CoachPlan, today: DayKey) -> String {
        if plan.activePhase(on: today)?.id == phase.id {
            guard let week = phase.week(on: today) else { return "Running" }
            return "Running · week \(week)" + (phase.weeks().map { " of \($0)" } ?? "")
        }
        if phase.status == .done { return "Done" }
        if phase.isStarted { return "Ended" }
        if let start = phase.start, start <= today { return "Ready to start" }
        return "Planned"
    }

    /// "7 Jan – ~31 May · Gain weight 0.10–0.20 kg a week".
    static func phaseDetail(_ phase: CoachPlan.Phase) -> String {
        var parts: [String] = []
        let start = phase.start.map { (phase.startApprox ? "~" : "") + Fmt.shortDay($0) }
        let end = phase.end.map { (phase.endApprox ? "~" : "") + Fmt.shortDay($0) }
        if let start, let end {
            parts.append("\(start) – \(end)")
        } else if let start {
            parts.append("From \(start)")
        } else if let end {
            parts.append("Until \(end)")
        } else {
            parts.append("No dates yet")
        }
        let range = phase.rateRange
        if phase.goal != .maintain, range.upperBound > 0 {
            let low = Fmt.number(range.lowerBound, decimals: 2), high = Fmt.number(range.upperBound, decimals: 2)
            parts.append("\(phase.goal.title) \(low == high ? low : "\(low)–\(high)") kg a week")
        } else {
            parts.append(phase.goal.title)
        }
        return parts.joined(separator: " · ")
    }

    /// "🏋️ Gym", or the name alone.
    static func typeLabel(_ type: CoachPlan.DayType) -> String {
        let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
        return [emoji, type.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "Mon, Wed, Fri", "2 per week", "All other days".
    static func scheduleText(_ type: CoachPlan.DayType) -> String {
        switch type.schedule {
        case .fixed: type.weekdays.isEmpty ? "No weekdays yet" : type.weekdays.summary
        case .flexible: type.perWeek > 0 ? "Flexible · \(type.perWeek) per week" : "Flexible"
        case .default: "All other days"
        }
    }

    /// "2,600 kcal · 160 g P · 310 g C · 80 g F".
    static func targetsLine(_ targets: DailyTargets, unit: EnergyUnit) -> String {
        "\(Fmt.energy(targets.energy, unit: unit)) · \(Fmt.number(targets.protein)) g P · \(Fmt.number(targets.carbs)) g C · "
            + "\(Fmt.number(targets.fat)) g F"
    }

    /// The day type's targets in the active phase on `day`, or how it gets them.
    static func typeTargetsText(_ type: CoachPlan.DayType, plan: CoachPlan, day: DayKey, unit: EnergyUnit) -> String {
        guard let revision = plan.revision(on: day) else { return "No phase running" }
        if let own = revision.byType[type.id] { return Fmt.energy(own.energy, unit: unit) }
        if let baseline = revision.baseline { return "\(Fmt.energy(baseline.energy, unit: unit)) (baseline)" }
        return "Your daily targets"
    }

    /// The live line under the day types ("Week avg 2,486 kcal") and the plan's warnings: the
    /// planned week against the phase's baseline, and macros that don't add up to the calories.
    static func weekLines(plan: CoachPlan, day: DayKey, unit: EnergyUnit) -> (line: String?, warnings: [String]) {
        guard let revision = plan.revision(on: day) else { return (nil, []) }
        var warnings: [String] = []
        if let warning = plan.weekAverageWarning(revision) { warnings.append(warning) }
        if let baseline = revision.baseline, let warning = CoachPlan.macroWarning(baseline) {
            warnings.append("Baseline: \(warning)")
        }
        for type in plan.dayTypes {
            if let own = revision.byType[type.id], let warning = CoachPlan.macroWarning(own) {
                warnings.append("\(type.name): \(warning)")
            }
        }
        let line = plan.plannedWeekAverage(revision).map { "Week avg \(Fmt.energy($0, unit: unit))" }
        return (line, warnings)
    }

    /// "3–5 g · with Breakfast · every day · optional".
    static func checkDetail(_ check: CoachPlan.Check, plan: CoachPlan, settings: NinaSettings) -> String {
        var parts: [String] = []
        if !check.dose.isEmpty { parts.append(check.dose) }
        switch check.timing {
        case .anytime: parts.append("Anytime")
        case .meal(let id): parts.append("With \(settings.meal(id).name)")
        case .time(let minutes): parts.append("At \(Fmt.clock(minutes))")
        }
        switch check.days {
        case .daily: parts.append("every day")
        case .weekdays(let days): parts.append(days.summary)
        case .dayTypes(let ids): parts.append(ids.map { plan.dayType(id: $0)?.name ?? $0 }.joined(separator: ", ") + " days")
        }
        if check.isOptional { parts.append("optional") }
        if check.remind { parts.append("reminder") }
        return parts.joined(separator: " · ")
    }

    static func routineSummary(_ routine: CoachPlan.Routine) -> String {
        let weekly = routine.weeklySites.isEmpty ? "No weekly sites" : routine.weeklySites.map(\.title).joined(separator: ", ") + " weekly"
        return "\(weekly) · full set every \(routine.fullEveryWeeks) weeks"
    }

    static func adjustSummary(_ adjust: CoachPlan.Adjust) -> String {
        "\(Fmt.number(adjust.stepMin))–\(Fmt.number(adjust.stepMax)) kcal after \(adjust.windowMinDays)–\(adjust.windowMaxDays) days"
    }

    static func proteinSummary(_ protein: CoachPlan.Protein, settings: NinaSettings) -> String {
        let count = protein.effectiveCount(mealSlots: settings.meals.count)
        guard protein.mealMin > 0 else { return "Automatic · \(count) meals" }
        let range = protein.mealMax > protein.mealMin ? "\(Fmt.number(protein.mealMin))–\(Fmt.number(protein.mealMax)) g" : "\(Fmt.number(protein.mealMin)) g"
        return "\(range) · \(count) meals"
    }

    static func longTermSummary(_ goal: CoachPlan.LongTerm) -> String {
        var parts: [String] = []
        if goal.weightKg > 0 { parts.append(Fmt.kilograms(goal.weightKg)) }
        if goal.bodyFat > 0 { parts.append("\(Fmt.number(goal.bodyFat, decimals: 1)) %") }
        if goal.waistCm > 0 { parts.append("waist \(Fmt.number(goal.waistCm, decimals: 1)) cm") }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    /// "Holiday · until 12 Feb", "Sick · until you resume".
    static func pauseText(_ pause: CoachPlan.Pause) -> String {
        "\(reasonTitle(pause.reason)) · " + (pause.end.map { "until \(Fmt.shortDay($0))" } ?? "until you resume")
    }

    static func reasonTitle(_ reason: CoachPlan.PauseReason) -> String {
        switch reason {
        case .holiday: "Holiday"
        case .sick: "Ill"
        case .other: "Other"
        }
    }

    /// Protein of today's targets per kg body weight (and lean mass once a body-fat value exists):
    /// "160 g a day = 2.0 g/kg · 2.5 g/kg lean mass".
    static func proteinRatio(app: AppModel) -> String? {
        let settings = app.settings
        guard let weight = settings.bodyWeightKg else { return nil }
        let grams = settings.targets(for: app.today).protein
        let latest = app.store.bodyFatReadings().last
        guard let ratio = ProteinMeals.ratio(grams: grams, weightKg: weight, leanKg: latest?.leanKg, bodyFat: latest?.bodyFat) else { return nil }
        return "\(Fmt.number(grams)) g a day = \(ratio.text)"
    }
}
