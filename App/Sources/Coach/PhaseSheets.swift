import SwiftUI
import BinisoftKit
import NinaCore

// MARK: - Phase sheet

/// A phase of the plan (`AppSheet.phase`): nil adds a new phase. Name, goal, dates (approximate or not),
/// the weekly rate range (0.05 kg steps, bounds by goal, "Slow (lean) gain", a calm caution), the
/// review checkpoint, target weight and body fat, the waist check and a note; "Calculate" fills
/// the targets per day type (`PhaseTransition.proposal`) with a preview. Start now, Mark as Done
/// and Delete. Writes through `app.updatePlan` (Undo restores the plan); new targets are a
/// revision starting today. A finished phase only changes its name and note. Owns its
/// NavigationStack and `.sheetFrame`.
struct PhaseSheet: View {
    let phaseID: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CoachPlan.Phase(id: "")
    @State private var original: CoachPlan.Phase?
    @State private var context: CoachContext?
    @State private var loaded = false
    @State private var reviewOn = false
    @State private var reviewMinText = ""
    @State private var reviewMaxText = ""
    @State private var targetWeightText = ""
    @State private var targetFatText = ""
    @State private var bodyFatCeilingText = ""
    @State private var calculation: PhaseTransition.Proposal?
    /// The goals people had, while no plan is set up: a first phase migrates them
    /// (`PlanEdits.addingFirstPhase`).
    @State private var setUpState: SettingsState?
    /// What the sheet showed when it opened ("Discard changes?").
    @State private var opened: PhaseSheetOpened?
    @State private var confirmsDiscard = false
    @State private var confirmsDelete = false

    private var isNew: Bool { original == nil }
    private var isDone: Bool { original?.status == .done }
    private var isStarted: Bool { original?.isStarted ?? false }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(isNew ? "New Phase" : CheckInSheetText.phaseName(draft))
                .inlineNavigationTitle()
                .toolbar { toolbar }
                .confirmationDialog("Discard changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { dismiss() }
                    Button("Keep Editing", role: .cancel) {}
                }
        }
        // On its own view: one dialog per view.
        .confirmationDialog(deleteTitle, isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Phase", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .task(id: app.dataVersion) { load() }
        .onChange(of: calculationKey) { calculation = nil }
        .onChange(of: draft.goal) { _, goal in goalChanged(to: goal) }
        .interactiveDismissDisabled(isDirty)
        .sheetFrame(minWidth: 540, minHeight: 560)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if isDirty { confirmsDiscard = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .disabled(!isValid)
        }
    }

    /// Something typed or changed since the sheet opened (or targets calculated).
    private var isDirty: Bool {
        guard let opened else { return false }
        return calculation != nil || opened != currentInputs
    }

    private var currentInputs: PhaseSheetOpened {
        PhaseSheetOpened(draft: draft, reviewOn: reviewOn,
                         texts: [reviewMinText, reviewMaxText, targetWeightText, targetFatText, bodyFatCeilingText])
    }

    /// Delete asks first once a phase has started: its targets go with it.
    private func requestDelete() {
        if original?.isStarted == true { confirmsDelete = true } else { delete() }
    }

    private var deleteTitle: String {
        "Delete \(original.map { CheckInSheetText.phaseName($0) } ?? "this phase")?"
    }

    private var deleteMessage: String {
        PlanEditorData.deleteMessage(for: original)
    }

    /// A new phase gets a starting rate and the waist check that fit its goal (a rate the person
    /// set themselves stays).
    private func goalChanged(to goal: WeightGoal) {
        guard isNew, loaded else { return }
        draft.maxWaistGainCm = CoachPlan.Phase.defaultMaxWaistGain(for: goal)
        let defaults: [ClosedRange<Double>] = [PhaseSheetPlan.defaultRate(for: .gain), PhaseSheetPlan.defaultRate(for: .lose)]
        if goal != .maintain, draft.rateMax <= 0 || defaults.contains(draft.rateRange) {
            let range = PhaseSheetPlan.defaultRate(for: goal)
            draft.rateMin = range.lowerBound
            draft.rateMax = range.upperBound
        }
    }

    private var form: some View {
        Form {
            PhaseSheetBasics(draft: $draft, isDone: isDone, isStarted: isStarted, today: app.today)
            if draft.goal != .maintain {
                PhaseSheetRate(draft: $draft, weightKg: weightKg, isDone: isDone, unit: app.energyUnit)
            }
            PhaseSheetGoals(draft: $draft, reviewOn: $reviewOn, reviewMin: $reviewMinText, reviewMax: $reviewMaxText,
                            targetWeight: $targetWeightText, targetFat: $targetFatText, bodyFatCeiling: $bodyFatCeilingText,
                            isDone: isDone)
            targetsSection
            if !isDone {
                actionsSection
            } else if !isNew {
                Section {
                    Button("Delete Phase", systemImage: "trash", role: .destructive, action: requestDelete)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Targets

    private var targetsSection: some View {
        Section {
            if currentRows.isEmpty {
                Text("No targets yet. Calculate them now, or Nina proposes them when the phase starts.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(currentRows) { row in
                    PhaseSheetTargetsLine(title: row.title, targets: row.after, unit: app.energyUnit)
                }
            }
            if let calculation {
                PhaseSheetCalculation(proposal: calculation, rows: calculationRows(calculation), unit: app.energyUnit)
                Button("Don't Use These Targets", systemImage: "xmark.circle") { self.calculation = nil }
            } else if !isDone {
                Button("Calculate", systemImage: "function", action: calculate)
            }
        } header: {
            Text("Targets")
        } footer: {
            Text(targetsFooter)
        }
    }

    private var targetsFooter: String {
        if calculation != nil {
            return "Saved with the phase: the new targets apply from \(CheckInSheetText.day(revisionDay))."
        }
        return "Calculate uses your maintenance from the last 28 days when there's enough data, else your profile, plus the middle of the rate. Every day type moves by the same amount."
    }

    /// The phase's own targets in force (one row per day type). A first phase before the plan is
    /// set up shows the targets it takes over (training days and the rest).
    private var currentRows: [PhaseSheetTargetRow] {
        let working = workingPlan
        let phase = working.phase(id: draft.id) ?? draft
        guard let revision = PhaseSheetPlan.currentRevision(of: phase, on: revisionDay) else { return [] }
        return PhaseSheetPlan.rows(plan: working, before: revision, after: revision, fallback: app.settings.targets)
    }

    private func calculationRows(_ proposal: PhaseTransition.Proposal) -> [PhaseSheetTargetRow] {
        let working = workingPlan
        let phase = working.phase(id: draft.id) ?? builtPhase()
        let before = PhaseSheetPlan.currentRevision(of: phase, on: proposal.day)
            ?? PhaseTransition.targetsBefore(phase, in: working, on: proposal.day)
        return PhaseSheetPlan.rows(plan: working, before: before, after: proposal.revision, fallback: app.settings.targets)
    }

    // MARK: Actions

    private var actionsSection: some View {
        Section {
            if !isStarted {
                Button("Start Now", systemImage: "play.fill", action: startNow)
            } else {
                Button("Mark as Done", systemImage: "checkmark.seal", action: markDone)
            }
            if !isNew {
                Button("Delete Phase", systemImage: "trash", role: .destructive, action: requestDelete)
            }
        } footer: {
            Text(isStarted
                 ? "Mark as Done ends the phase today. Every change can be undone right after."
                 : "Start Now starts the phase today; the running phase ends yesterday. Every change can be undone right after.")
        }
    }

    // MARK: Values

    private var plan: CoachPlan { context?.plan ?? app.settings.plan }

    /// The plan as it would be saved (before a calculation): see `placed(_:in:)`.
    private var workingPlan: CoachPlan { placed(builtPhase(), in: plan) }

    /// `current` with `phase` in place. While no plan is set up, the first phase sets it up the
    /// way "Set Up My Plan" does: training days become day types and the phase takes over the
    /// targets people had, so training days keep their calories (`PlanEdits.addingFirstPhase`).
    private func placed(_ phase: CoachPlan.Phase, in current: CoachPlan) -> CoachPlan {
        guard !current.isSetUp else { return PhaseSheetPlan.placing(phase, in: current) }
        return PlanEdits.addingFirstPhase(phase, to: current, from: setUpState ?? app.settingsState, on: app.today)
    }

    /// The 7-day average (else the trend); 0 without weigh-ins, so the "% of your weight" line and
    /// the caution hide instead of using the 72 kg placeholder.
    private var weightKg: Double { context?.bodyWeight?.kilograms ?? 0 }

    private var revisionDay: DayKey { PhaseSheetPlan.revisionDay(of: draft, today: app.today) }

    /// What the calculated targets depend on: changing it drops a calculation.
    private var calculationKey: String {
        "\(draft.goal.rawValue)|\(draft.rateMin)|\(draft.rateMax)|\(draft.start?.rawValue ?? "")|\(draft.end?.rawValue ?? "")|\(targetWeightText)"
    }

    private var isValid: Bool {
        guard loaded else { return false }
        if let start = draft.start, let end = draft.end, end < start { return false }
        // Only a gain phase keeps its ceiling (`builtPhase`), so only there can it block Save.
        if draft.goal == .gain, PhaseSheetFormat.number(bodyFatCeilingText) > PhaseSheetFormat.maxBodyFat { return false }
        return true
    }

    private func load() {
        let context = CoachContext.load(app: app, day: app.today)
        self.context = context
        setUpState = context.plan.isSetUp ? nil : app.settingsState
        guard !loaded else { return }
        loaded = true
        let phase: CoachPlan.Phase
        if let phaseID, let stored = context.plan.phase(id: phaseID) {
            original = stored
            phase = stored
        } else {
            phase = PhaseSheetPlan.newPhase(in: context.plan, today: context.today, calendar: context.calendar)
        }
        let texts = [phase.reviewMin, phase.reviewMax, phase.targetWeight, phase.targetBodyFat, phase.bodyFatCeiling]
            .map { PhaseSheetFormat.text($0) }
        let review = phase.reviewMin > 0 || phase.reviewMax > 0
        draft = phase
        reviewOn = review
        reviewMinText = texts[0]
        reviewMaxText = texts[1]
        targetWeightText = texts[2]
        targetFatText = texts[3]
        bodyFatCeilingText = texts[4]
        opened = PhaseSheetOpened(draft: phase, reviewOn: review, texts: texts)
    }

    /// The draft with the typed numbers.
    private func builtPhase() -> CoachPlan.Phase { builtPhase(from: currentInputs) }

    /// The phase the sheet's inputs describe.
    private func builtPhase(from inputs: PhaseSheetOpened) -> CoachPlan.Phase {
        var phase = inputs.draft
        let texts = inputs.texts
        phase.name = phase.name.trimmingCharacters(in: .whitespacesAndNewlines)
        phase.targetWeight = PhaseSheetFormat.number(texts[2])
        phase.targetBodyFat = PhaseSheetFormat.number(texts[3])
        // Only a gain phase has ceilings (`BodyCeiling`).
        phase.bodyFatCeiling = phase.goal == .gain ? PhaseSheetFormat.number(texts[4]) : 0
        var low = PhaseSheetFormat.number(texts[0])
        var high = PhaseSheetFormat.number(texts[1])
        if low > 0, high > 0, low > high { swap(&low, &high) }
        if phase.goal == .maintain {
            // A maintain phase keeps its own band (an imported ±rate); a gain or loss rate goes.
            if original?.goal != .maintain {
                phase.rateMin = 0
                phase.rateMax = 0
            }
            low = 0
            high = 0
        } else if !inputs.reviewOn {
            low = 0
            high = 0
        }
        phase.reviewMin = low
        phase.reviewMax = high
        return phase
    }

    /// The saved plan (read fresh) with the edited phase and the calculated targets. An existing
    /// phase starts from the stored one and takes only the fields changed in this sheet (against
    /// what it showed when it opened), so a check-in Apply or a Start made meanwhile (in another
    /// window or on another device) stays, and an untouched sheet writes nothing.
    private func editedPlan() -> CoachPlan {
        let current = app.store.settings.plan
        var phase = builtPhase()
        if let original, let opened, let stored = current.phase(id: original.id) {
            phase = stored.applyingPhaseSheetEdits(original: builtPhase(from: opened), edited: phase)
        }
        var plan = placed(phase, in: current)
        if current.isEmpty { plan.routine = CoachPlan.Routine.defaults(for: app.settings.body.sex) }
        if let calculation {
            // The calculated targets hold from their day on: a later revision (a check-in applied
            // from tomorrow) would otherwise take over again.
            if let index = plan.phases.firstIndex(where: { $0.id == calculation.phaseID }) {
                plan.phases[index].revisions.removeAll { $0.from > calculation.day }
            }
            plan = calculation.applied(to: plan)
        }
        return plan
    }

    private func calculate() {
        let context = self.context ?? CoachContext.load(app: app, day: app.today)
        let phase = builtPhase()
        let day = PhaseSheetPlan.revisionDay(of: phase, today: context.today)
        // A first phase starts from the targets it takes over (per day type), like a phase with its own.
        let base = placed(phase, in: context.plan)
        let subject = base.phase(id: phase.id) ?? phase
        calculation = PhaseSheetPlan.calculation(for: subject, in: base, on: day, context: context)
    }

    private func save() {
        let plan = editedPlan()
        if plan != app.store.settings.plan {
            app.updatePlan(plan, message: isNew ? "Phase added" : "Phase saved", symbol: "flag.fill")
        }
        dismiss()
    }

    private func startNow() {
        let context = self.context ?? CoachContext.load(app: app, day: app.today)
        let phase = builtPhase()
        let start = PhaseSheetPlan.starting(phase.id, in: editedPlan(), on: context.today, context: context)
        app.phaseSheetCommit(start.plan, events: [(phaseID: phase.id, event: .started)],
                             message: "\(CheckInSheetText.phaseName(phase)) started")
        dismiss()
    }

    private func markDone() {
        let phase = builtPhase()
        let plan = PhaseSheetPlan.markingDone(phase.id, in: editedPlan(), today: app.today)
        app.phaseSheetCommit(plan, events: [(phaseID: phase.id, event: .ended)],
                             message: "\(CheckInSheetText.phaseName(phase)) done", symbol: "checkmark.seal.fill")
        dismiss()
    }

    private func delete() {
        guard let original else { return }
        let plan = PhaseSheetPlan.removing(original.id, from: app.store.settings.plan)
        app.updatePlan(plan, message: "\(CheckInSheetText.phaseName(original)) deleted", symbol: "trash.fill")
        dismiss()
    }
}

/// What the phase sheet showed when it opened: an untouched sheet asks nothing on Cancel.
private struct PhaseSheetOpened: Equatable {
    var draft: CoachPlan.Phase
    var reviewOn: Bool
    var texts: [String]
}

/// Typed numbers of the phase sheet (0 = none).
private enum PhaseSheetFormat {
    /// A body-fat ceiling above this (%) isn't saved.
    static let maxBodyFat = 60.0

    /// The number as people type it here: the device's decimal separator ("74,5"), no grouping,
    /// up to two decimals; empty for none.
    static func text(_ value: Double) -> String {
        guard value > 0, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func number(_ text: String) -> Double {
        max(0, NumberText.parse(text) ?? 0)
    }
}

/// Name, goal and dates.
private struct PhaseSheetBasics: View {
    @Binding var draft: CoachPlan.Phase
    let isDone: Bool
    let isStarted: Bool
    let today: DayKey

    var body: some View {
        Section {
            TextField(CoachPlan.Phase.defaultName(for: draft.goal), text: $draft.name)
            Picker("Goal", selection: $draft.goal) {
                Text("Gain").tag(WeightGoal.gain)
                Text("Maintain").tag(WeightGoal.maintain)
                Text("Lose").tag(WeightGoal.lose)
            }
            .pickerStyle(.segmented)
            .disabled(isDone)
            startRows
            endRows
        } header: {
            Text("Phase")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if isDone { return "This phase is finished: only its name and note can change." }
        return "End dates are soft: Nina only asks what's next when one comes. \"Approximate date\" marks a date you haven't fixed yet (shown with ~)."
    }

    @ViewBuilder
    private var startRows: some View {
        if isStarted {
            LabeledContent("Started", value: draft.start.map { Fmt.dayTitle($0, today: today) } ?? "–")
        } else {
            DatePicker("Start", selection: startBinding, displayedComponents: .date)
                .disabled(isDone)
            Toggle("Approximate date", isOn: $draft.startApprox)
                .disabled(isDone)
        }
    }

    @ViewBuilder
    private var endRows: some View {
        Toggle("End date", isOn: hasEnd)
            .disabled(isDone)
        if draft.end != nil {
            DatePicker("End", selection: endBinding, in: (draft.start ?? today).date()..., displayedComponents: .date)
                .disabled(isDone)
            Toggle("Approximate date", isOn: $draft.endApprox)
                .disabled(isDone)
        }
    }

    private var startBinding: Binding<Date> {
        Binding<Date>(get: { (draft.start ?? today).date() }, set: { draft.start = DayKey(date: $0) })
    }

    private var endBinding: Binding<Date> {
        Binding<Date>(get: { (draft.end ?? today).date() }, set: { draft.end = DayKey(date: $0) })
    }

    private var hasEnd: Binding<Bool> {
        Binding<Bool>(get: { draft.end != nil }, set: { (on: Bool) in
            if on {
                draft.end = (draft.start ?? today).adding(days: 83)
            } else {
                draft.end = nil
                draft.endApprox = false
            }
        })
    }
}

/// The weekly rate range, its label and caution.
private struct PhaseSheetRate: View {
    @Binding var draft: CoachPlan.Phase
    let weightKg: Double
    let isDone: Bool
    let unit: EnergyUnit

    var body: some View {
        Section {
            Toggle("Weekly rate", isOn: rateOn)
                .disabled(isDone)
            if draft.rateMax > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text(rangeText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    PhaseRateRangeSlider(low: minBinding, high: maxBinding, bounds: bounds, sign: draft.goal == .lose ? "−" : "+")
                        .disabled(isDone)
                    endLabels
                }
                .padding(.vertical, 4)
                Stepper("From \(kgText(draft.rateMin))", value: minBinding, in: fromRange, step: 0.05)
                    .disabled(isDone)
                Stepper("To \(kgText(draft.rateMax))", value: maxBinding, in: toRange, step: 0.05)
                    .disabled(isDone)
                if let label = draft.rateLabel {
                    Label(label, systemImage: "leaf")
                        .foregroundStyle(Color.green)
                }
                if let caution = draft.rateCaution(weightKg: weightKg) {
                    Label(caution, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
            }
        } header: {
            Text(draft.goal == .lose ? "Loss per week" : "Gain per week")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        guard draft.rateMax > 0 else {
            return "Without a rate, Calculate works one out from the target weight and end date."
        }
        return "Drag either end, or use the steppers. Targets use the middle of the range: "
            + "\(CheckInSheetText.signedEnergy(draft.energyAdjustment, unit: unit)) a day."
    }

    /// "+0.15 to +0.25 kg a week · 0.19–0.31 % of your weight".
    private var rangeText: String {
        let sign = draft.goal == .lose ? "−" : "+"
        let range = draft.rateRange
        var text = "\(sign)\(Fmt.number(range.lowerBound, decimals: 2)) to \(sign)\(Fmt.number(range.upperBound, decimals: 2)) kg a week"
        if let low = WeightSignal.percent(range.lowerBound, of: weightKg),
           let high = WeightSignal.percent(range.upperBound, of: weightKg) {
            text += " · \(Fmt.number(low, decimals: 2))–\(Fmt.number(high, decimals: 2)) % of your weight"
        }
        return text
    }

    private func kgText(_ value: Double) -> String {
        "\(Fmt.number(value, decimals: 2)) kg"
    }

    /// The slider's scale for the goal: a gain 0.05–0.5 kg, a loss 0.1–1.0 kg a week, widened to
    /// take a rate set elsewhere (an import) without changing it.
    private var bounds: ClosedRange<Double> {
        PhaseRateRangeSlider.bounds(goal: draft.goal, rateMin: draft.rateMin, rateMax: draft.rateMax)
    }

    private var fromRange: ClosedRange<Double> {
        bounds.lowerBound...max(bounds.lowerBound, draft.rateMax)
    }

    private var toRange: ClosedRange<Double> {
        min(max(bounds.lowerBound, draft.rateMin), bounds.upperBound)...bounds.upperBound
    }

    /// "0.05" under the left end of the track, "0.5 kg" under the right one.
    private var endLabels: some View {
        HStack {
            Text(Fmt.number(bounds.lowerBound, decimals: 2))
            Spacer()
            Text("\(Fmt.number(bounds.upperBound, decimals: 2)) kg")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityHidden(true)
    }

    private var rateOn: Binding<Bool> {
        Binding<Bool>(get: { draft.rateMax > 0 }, set: { (on: Bool) in
            let range = on ? PhaseSheetPlan.defaultRate(for: draft.goal) : 0...0
            draft.rateMin = range.lowerBound
            draft.rateMax = range.upperBound
        })
    }

    private var minBinding: Binding<Double> {
        Binding<Double>(get: { draft.rateMin }, set: { (value: Double) in draft.rateMin = (value * 100).rounded() / 100 })
    }

    private var maxBinding: Binding<Double> {
        Binding<Double>(get: { draft.rateMax }, set: { (value: Double) in draft.rateMax = (value * 100).rounded() / 100 })
    }
}

/// Which end of the rate range a drag moves.
private enum PhaseRateThumb {
    case low, high
}

/// The weekly rate as a range with two handles on one track (`bounds`, in 0.05 steps): the
/// low end never passes the high one. A drag moves the nearer handle (when both sit on one spot,
/// the one in the drag's direction); VoiceOver adjusts each handle on its own.
private struct PhaseRateRangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    /// The track's scale (`bounds(goal:rateMin:rateMax:)`).
    let bounds: ClosedRange<Double>
    /// "+" for a gain, "−" for a loss (spoken values).
    let sign: String
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging: PhaseRateThumb?

    /// A gain 0.05–0.5 kg a week (a lean gain uses a useful part of the track), a loss 0.1–1.0 kg;
    /// widened to take a rate outside them (an imported one is never clamped).
    static func bounds(goal: WeightGoal, rateMin: Double, rateMax: Double) -> ClosedRange<Double> {
        let base: ClosedRange<Double> = goal == .lose ? 0.1...1.0 : 0.05...0.5
        let lower = rateMin > 0 ? min(base.lowerBound, rateMin) : base.lowerBound
        let upper = max(base.upperBound, rateMax)
        return lower...max(lower, upper)
    }

    private let step = 0.05
    private let thumb: CGFloat = 26

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            content(width: proxy.size.width)
        }
        .frame(height: thumb + 4)
    }

    private func content(width: CGFloat) -> some View {
        let usable: CGFloat = max(1, width - thumb)
        let lowX: CGFloat = position(low, usable: usable)
        let highX: CGFloat = position(high, usable: usable)
        let fillWidth: CGFloat = max(6, highX - lowX + 6)
        let fillStart: CGFloat = thumb / 2 + lowX - 3
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: usable, height: 6)
                .offset(x: thumb / 2)
            Capsule()
                .fill(isEnabled ? Brand.accent : Color.secondary)
                .frame(width: fillWidth, height: 6)
                .offset(x: fillStart)
            handle(.low)
                .offset(x: lowX)
            handle(.high)
                .offset(x: highX)
        }
        .frame(width: width, height: thumb + 4, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(drag(usable: usable, lowX: lowX, highX: highX))
        .accessibilityElement(children: .contain)
    }

    private func handle(_ which: PhaseRateThumb) -> some View {
        let value: Double = which == .low ? low : high
        let label: String = which == .low ? "Slowest rate" : "Fastest rate"
        let spoken: String = "\(sign)\(Fmt.number(value, decimals: 2)) kg a week"
        return Circle()
            .fill(Color.white)
            .overlay { Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
            .frame(width: thumb, height: thumb)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(spoken)
            .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
                if direction == .increment {
                    move(which, to: value + step)
                } else if direction == .decrement {
                    move(which, to: value - step)
                }
            }
    }

    private func drag(usable: CGFloat, lowX: CGFloat, highX: CGFloat) -> some Gesture {
        // Locations are in the track's own space (the frame above).
        DragGesture(minimumDistance: 2)
            .onChanged { (gesture: DragGesture.Value) in
                let which = dragging ?? nearest(to: gesture.startLocation.x - thumb / 2, lowX: lowX, highX: highX,
                                                 direction: gesture.translation.width)
                dragging = which
                move(which, to: value(at: gesture.location.x - thumb / 2, usable: usable))
            }
            .onEnded { (_: DragGesture.Value) in
                dragging = nil
            }
    }

    /// The handle nearer to `x`; on one spot, the low one for a drag to the left.
    private func nearest(to x: CGFloat, lowX: CGFloat, highX: CGFloat, direction: CGFloat) -> PhaseRateThumb {
        let toLow = abs(x - lowX), toHigh = abs(x - highX)
        if abs(toLow - toHigh) < 1 { return direction < 0 ? .low : .high }
        return toLow < toHigh ? .low : .high
    }

    private func position(_ value: Double, usable: CGFloat) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        let fraction = (min(max(value, bounds.lowerBound), bounds.upperBound) - bounds.lowerBound) / span
        return CGFloat(fraction) * usable
    }

    private func value(at x: CGFloat, usable: CGFloat) -> Double {
        let fraction = Double(min(max(x / usable, 0), 1))
        return bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
    }

    /// Snaps to 0.05 kg within the bounds, keeping the low end at or below the high one.
    private func move(_ which: PhaseRateThumb, to raw: Double) {
        let snapped = min(max((raw / step).rounded() * step, bounds.lowerBound), bounds.upperBound)
        let value = (snapped * 100).rounded() / 100
        switch which {
        case .low: if abs(value - low) > 1e-9 { low = min(value, high) }
        case .high: if abs(value - high) > 1e-9 { high = max(value, low) }
        }
    }
}

/// Target weight and body fat, the review checkpoint, the waist check and the note.
private struct PhaseSheetGoals: View {
    @Binding var draft: CoachPlan.Phase
    @Binding var reviewOn: Bool
    @Binding var reviewMin: String
    @Binding var reviewMax: String
    @Binding var targetWeight: String
    @Binding var targetFat: String
    @Binding var bodyFatCeiling: String
    let isDone: Bool

    var body: some View {
        Section {
            Group {
                PhaseSheetNumberField(title: "Target weight", text: $targetWeight, unit: "kg")
                PhaseSheetNumberField(title: "Target body fat", text: $targetFat, unit: "%")
                if draft.goal != .maintain {
                    Toggle("Review checkpoint", isOn: $reviewOn)
                    if reviewOn {
                        PhaseSheetNumberField(title: "Review from", text: $reviewMin, unit: "kg")
                        PhaseSheetNumberField(title: "Review to", text: $reviewMax, unit: "kg")
                    }
                }
                if draft.goal == .gain {
                    Stepper(waistTitle, value: $draft.maxWaistGainCm, in: 0...10, step: 0.5)
                    PhaseSheetNumberField(title: "Body-fat ceiling", text: $bodyFatCeiling, unit: "%")
                }
            }
            .disabled(isDone)
        } header: {
            Text("Goals")
        } footer: {
            Text(goalsFooter)
        }
        Section {
            TextField("Note", text: $draft.note, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("Note")
        }
    }

    private var waistTitle: String {
        guard draft.maxWaistGainCm > 0 else { return "Waist check off" }
        return "Review at waist +\(Fmt.number(draft.maxWaistGainCm, decimals: 1)) cm"
    }

    private var goalsFooter: String {
        var text = "All optional."
        if draft.goal != .maintain {
            text += " When your 7-day average reaches the review weight, Nina asks you to look back and decide how to go on."
        }
        if draft.goal == .gain {
            text += " The waist check opens the same review when your waist grows that much since the start."
            text += " So does the body-fat ceiling (empty = off, at most 60 %) once your tracked body fat reaches it."
        }
        return text
    }
}

/// A number typed into a row: "Target weight [74.5] kg".
private struct PhaseSheetNumberField: View {
    let title: String
    @Binding var text: String
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("–", text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One day type's targets: "🏋️ Gym  2,600 kcal", "P 150 · C 300 · F 70 g".
private struct PhaseSheetTargetsLine: View {
    let title: String
    let targets: DailyTargets
    let unit: EnergyUnit

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.energy(targets.energy, unit: unit))
                    .monospacedDigit()
                Text(macros)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var macros: String {
        "P \(Fmt.number(targets.protein)) · C \(Fmt.number(targets.carbs)) · F \(Fmt.number(targets.fat)) g"
    }
}

/// One day type before → after: "🏋️ Gym 2,600 → 2,300 kcal", "−75 g carbs".
private struct PhaseSheetChangeRow: View {
    let row: PhaseSheetTargetRow
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.title)
                Spacer()
                Text(energyText)
                    .monospacedDigit()
            }
            if !row.macroText.isEmpty {
                Text(row.macroText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var energyText: String {
        "\(Fmt.energy(row.before.energy, unit: unit, showUnit: false)) → \(Fmt.energy(row.after.energy, unit: unit))"
    }
}

/// The preview of calculated (or proposed) targets: maintenance, the surplus or deficit, every
/// day type before → after, and the notes.
private struct PhaseSheetCalculation: View {
    let proposal: PhaseTransition.Proposal
    let rows: [PhaseSheetTargetRow]
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PhaseSheetPlan.maintenanceLine(proposal, unit: unit))
            Text(PhaseSheetPlan.adjustmentLine(proposal, unit: unit))
                .foregroundStyle(.secondary)
            if proposal.rateDerived {
                Text("Rate worked out from your target: \(derivedRate)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        ForEach(rows) { row in
            PhaseSheetChangeRow(row: row, unit: unit)
        }
        ForEach(proposal.notes, id: \.self) { note in
            Label(note, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var derivedRate: String {
        let low = min(proposal.rateMin, proposal.rateMax), high = max(proposal.rateMin, proposal.rateMax)
        let range: ClosedRange<Double> = proposal.adjustment < 0 ? -high...(-low) : low...high
        return CheckInSheetText.range(range)
    }
}

// MARK: - Phase review

/// The review of a phase (`AppSheet.phaseReview`), opened at its review checkpoint or a ceiling,
/// its end date, or when a planned phase is due: where things stand (7-day average, rate, waist,
/// lean and fat since the start, weeks run, days on plan) and the choices – keep going, hold the
/// weight at maintenance, start the next phase now (with its targets before → after), or change
/// the end date. Every choice saves the plan and the decision (`DayMark` phase event) with one
/// Undo. Owns its NavigationStack and `.sheetFrame`.
struct PhaseReviewSheet: View {
    let phaseID: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var context: CoachContext?
    @State private var facts: PhaseReviewFacts?
    @State private var startPreview: PhaseSheetPlan.Start?
    @State private var holdPreview: PhaseSheetPlan.Start?
    @State private var changingEnd = false
    @State private var endDate = Date()
    /// The day a switch (hold, the next phase) takes effect: today once the end date was
    /// reached (as the phase-end card does), else tomorrow.
    @State private var switchDay = DayKey.today()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(facts?.mode == .start ? "Next Phase" : "Phase Review")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .task(id: app.dataVersion) { load() }
        .sheetFrame(minWidth: 540, minHeight: 560)
    }

    @ViewBuilder
    private var content: some View {
        if let facts {
            if facts.mode == .missing {
                ContentUnavailableView("Phase Not Found", systemImage: "flag.slash", description: Text(facts.message))
            } else {
                form(facts)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func form(_ facts: PhaseReviewFacts) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(facts.headline)
                        .font(.title3.weight(.semibold))
                    Text(facts.message)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            PhaseReviewStanding(facts: facts)
            if facts.needsFullSet {
                Section {
                    Text("Measure first: a full set gives this review its waist, arm and chest numbers.")
                    Button("Full Measurement", systemImage: "ruler") { app.present(.measure(.full, nil)) }
                }
            }
            choices(facts)
            Section {
                if let phase = facts.phase {
                    Button("Edit \(CheckInSheetText.phaseName(phase))", systemImage: "slider.horizontal.3") {
                        app.present(.phase(phase.id))
                    }
                }
                Button("Edit the Plan", systemImage: "list.bullet.rectangle") { app.present(.plan) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func choices(_ facts: PhaseReviewFacts) -> some View {
        switch facts.mode {
        case .start:
            startChoices(facts)
        case .review, .end, .open:
            runningChoices(facts)
        case .done, .missing:
            EmptyView()
        }
    }

    // MARK: Choices for a running phase

    private func runningChoices(_ facts: PhaseReviewFacts) -> some View {
        Section {
            if facts.mode != .open {
                PhaseReviewChoice(title: "Keep going", detail: keepDetail(facts), symbol: "arrow.forward.circle") { keep(facts) }
            }
            PhaseReviewChoice(title: "Hold my weight", detail: holdDetail(facts), symbol: "pause.circle") { hold(facts) }
            if facts.offersBridge, let next = facts.next {
                bridgeChoices(next, facts: facts)
            }
            if let next = facts.next {
                PhaseReviewChoice(title: "Start \(CheckInSheetText.phaseName(next)) now",
                                  detail: "From \(switchDayText.lowercased()), with these targets:",
                                  symbol: "flag.2.crossed") { startNext(next, facts: facts) }
                ForEach(rows(startPreview)) { row in
                    PhaseSheetChangeRow(row: row, unit: app.energyUnit)
                }
            }
            PhaseReviewChoice(title: "Change the end date", detail: endDetail(facts), symbol: "calendar") {
                changingEnd.toggle()
            }
            if changingEnd {
                DatePicker("New end", selection: $endDate, in: tomorrow.date()..., displayedComponents: .date)
                Button("Save End Date") { saveEnd(facts) }
                    .primaryActionStyle()
            }
            laterButton(facts)
        } header: {
            Text("Your choice")
        } footer: {
            Text("Each choice saves right away and can be undone from the message that follows.")
        }
    }

    /// "1 week / 2 weeks at maintenance first" before a loss phase, after a long gain phase.
    @ViewBuilder
    private func bridgeChoices(_ next: CoachPlan.Phase, facts: PhaseReviewFacts) -> some View {
        PhaseReviewChoice(title: "1 week at maintenance first", detail: bridgeDetail(next, days: 7),
                          symbol: "arrow.right.to.line") { bridge(next, days: 7, facts: facts) }
        PhaseReviewChoice(title: "2 weeks at maintenance first", detail: bridgeDetail(next, days: 14),
                          symbol: "arrow.right.to.line") { bridge(next, days: 14, facts: facts) }
    }

    // MARK: Choices for a phase that is due to start

    private func startChoices(_ facts: PhaseReviewFacts) -> some View {
        Section {
            if let phase = facts.phase {
                PhaseReviewChoice(title: "Start \(facts.name) now", detail: "From today, with these targets:", symbol: "play.circle") {
                    app.startPhase(phase.id)
                    dismiss()
                }
                ForEach(rows(startPreview)) { row in
                    PhaseSheetChangeRow(row: row, unit: app.energyUnit)
                }
                PhaseReviewChoice(title: "In a week", detail: postponeDetail(phase), symbol: "calendar.badge.clock") {
                    app.postponePhase(phase.id)
                    dismiss()
                }
            }
            laterButton(facts)
        } header: {
            Text("Your choice")
        } footer: {
            Text(facts.active == nil ? "Nothing changes until you tap." : "Until you tap, the running phase keeps its targets.")
        }
    }

    @ViewBuilder
    private func laterButton(_ facts: PhaseReviewFacts) -> some View {
        if let key = facts.cardKey {
            Button("Decide Later", systemImage: "clock") {
                app.dismissCard(key)
                dismiss()
            }
        }
    }

    // MARK: Texts

    private var tomorrow: DayKey { app.today.adding(days: 1) }

    /// "Today" / "Tomorrow".
    private var switchDayText: String { Fmt.dayTitle(switchDay, today: app.today) }

    private func keepDetail(_ facts: PhaseReviewFacts) -> String {
        if facts.mode == .end { return "No end date for now – set one any time." }
        if let target = facts.phase?.targetWeight, target > 0 { return "Same targets, on towards \(Fmt.kilograms(target))." }
        return "Same targets, same rate."
    }

    private func holdDetail(_ facts: PhaseReviewFacts) -> String {
        var text = "A maintenance phase from \(switchDayText.lowercased())"
        if let next = facts.next, let start = next.start, start > switchDay {
            text += " until \(CheckInSheetText.phaseName(next)) starts"
        }
        if let proposal = holdPreview?.proposal {
            text += ". \(PhaseSheetPlan.maintenanceLine(proposal, unit: app.energyUnit))"
        }
        return text + "."
    }

    /// "Maintenance from tomorrow, then Cut from Mon 12 May. A short break after a long gain."
    private func bridgeDetail(_ next: CoachPlan.Phase, days: Int) -> String {
        let nextStart = switchDay.adding(days: days)
        return "Maintenance from \(switchDayText.lowercased()), then \(CheckInSheetText.phaseName(next)) from \(CheckInSheetText.day(nextStart)). A short break after a long gain."
    }

    private func endDetail(_ facts: PhaseReviewFacts) -> String {
        guard let end = facts.phase?.end else { return "No end date yet." }
        return "Now \(Fmt.dayTitle(end, today: app.today))."
    }

    private func postponeDetail(_ phase: CoachPlan.Phase) -> String {
        let base = max(phase.start ?? app.today, app.today)
        return "Moves the start to \(CheckInSheetText.day(base.adding(days: 7)))."
    }

    private func rows(_ start: PhaseSheetPlan.Start?) -> [PhaseSheetTargetRow] {
        guard let start else { return [] }
        return PhaseSheetPlan.rows(plan: start.plan, before: start.before, after: start.after, fallback: app.settings.targets)
    }

    // MARK: Loading and decisions

    private func load() {
        let context = CoachContext.load(app: app, day: app.today)
        let facts = PhaseReviewFacts.load(context: context, phaseID: phaseID, heightCm: app.store.profile()?.heightCm ?? 0)
        self.context = context
        self.facts = facts
        let dayAfter = context.today.adding(days: 1, calendar: context.calendar)
        let day = facts.mode == .end ? context.today : dayAfter
        switchDay = day
        switch facts.mode {
        case .start:
            startPreview = PhaseSheetPlan.starting(phaseID, in: context.plan, on: context.today, context: context)
            holdPreview = nil
        case .review, .end, .open:
            startPreview = facts.next.map { PhaseSheetPlan.starting($0.id, in: context.plan, on: day, context: context) }
            holdPreview = facts.phase.map { PhaseSheetPlan.holding(after: $0, in: context.plan, from: day, context: context).start }
        case .done, .missing:
            startPreview = nil
            holdPreview = nil
        }
        if !changingEnd {
            let end = facts.phase?.end ?? dayAfter.adding(days: 27, calendar: context.calendar)
            endDate = max(end, dayAfter).date(calendar: context.calendar)
        }
    }

    private func keep(_ facts: PhaseReviewFacts) {
        guard let phase = facts.phase else { return }
        if facts.mode == .end {
            let plan = PhaseSheetPlan.changingEnd(phase.id, to: nil, approx: false, in: app.store.settings.plan)
            app.phaseSheetCommit(plan, events: [], message: "\(facts.name) keeps going")
        } else {
            app.phaseSheetCommit(nil, events: [(phaseID: phase.id, event: .reviewKeep)], message: "Keeping \(facts.name) going")
        }
        dismiss()
    }

    private func hold(_ facts: PhaseReviewFacts) {
        guard let phase = facts.phase else { return }
        let context = self.context ?? CoachContext.load(app: app, day: app.today)
        let result = PhaseSheetPlan.holding(after: phase, in: app.store.settings.plan, from: switchDay, context: context)
        app.phaseSheetCommit(result.start.plan,
                             events: [(phaseID: phase.id, event: .reviewHold), (phaseID: result.phaseID, event: .started)],
                             message: "Holding your weight from \(switchDayText.lowercased())", symbol: "pause.circle.fill")
        dismiss()
    }

    private func startNext(_ next: CoachPlan.Phase, facts: PhaseReviewFacts) {
        guard let phase = facts.phase else { return }
        let context = self.context ?? CoachContext.load(app: app, day: app.today)
        let start = PhaseSheetPlan.starting(next.id, in: app.store.settings.plan, on: switchDay, context: context)
        let event: PhaseEvent = facts.mode == .review ? .reviewCut : .ended
        app.phaseSheetCommit(start.plan, events: [(phaseID: phase.id, event: event), (phaseID: next.id, event: .started)],
                             message: "\(CheckInSheetText.phaseName(next)) starts \(switchDayText.lowercased())")
        dismiss()
    }

    /// A maintenance bridge from the switch day, then `next` (moved to start right after it).
    private func bridge(_ next: CoachPlan.Phase, days: Int, facts: PhaseReviewFacts) {
        guard let phase = facts.phase else { return }
        let context = self.context ?? CoachContext.load(app: app, day: app.today)
        let result = PhaseSheetPlan.bridging(after: phase, before: next, days: days, in: app.store.settings.plan,
                                             from: switchDay, context: context)
        let event: PhaseEvent = facts.mode == .review ? .reviewCut : .ended
        let weeks = days >= 14 ? "2 weeks" : "1 week"
        app.phaseSheetCommit(result.start.plan,
                             events: [(phaseID: phase.id, event: event), (phaseID: result.phaseID, event: .started)],
                             message: "\(weeks) at maintenance, then \(CheckInSheetText.phaseName(next))",
                             symbol: "pause.circle.fill")
        dismiss()
    }

    private func saveEnd(_ facts: PhaseReviewFacts) {
        guard let phase = facts.phase else { return }
        let end = DayKey(date: endDate)
        let plan = PhaseSheetPlan.changingEnd(phase.id, to: end, approx: false, in: app.store.settings.plan)
        var events: [(phaseID: String, event: PhaseEvent)] = []
        if facts.mode == .review { events.append((phaseID: phase.id, event: .reviewKeep)) }
        app.phaseSheetCommit(plan, events: events, message: "\(facts.name) now ends \(Fmt.shortDay(end))", symbol: "calendar")
        dismiss()
    }
}

/// "Where you stand": weeks run, 7-day average, change since the start, rate and status, the
/// review weight, waist, arm and chest, lean and fat mass, and days on plan.
private struct PhaseReviewStanding: View {
    let facts: PhaseReviewFacts

    private var summary: WeightSignal.Summary { facts.summary }

    var body: some View {
        Section {
            if let weekText {
                LabeledContent("Week", value: weekText)
            }
            LabeledContent("7-day average", value: averageText)
            if let since = summary.sinceStart {
                LabeledContent("Since the start", value: changeText(since))
            }
            if summary.phaseID != nil {
                LabeledContent("Rate") {
                    rateView
                }
            }
            if let checkpoint = summary.checkpoint {
                LabeledContent("Review weight", value: Fmt.kilograms(checkpoint))
            }
            girthRows
            compositionRows
            if facts.checkInDays > 0 {
                LabeledContent("Days on plan", value: CheckInSheetText.count(facts.onPlanDays, of: facts.checkInDays))
            }
        } header: {
            Text("Where you stand")
        } footer: {
            Text("Changes since the phase start. Tape and body-fat changes within the measuring error read \"no clear change\".")
        }
    }

    @ViewBuilder
    private var girthRows: some View {
        if let waist = facts.waist {
            LabeledContent(waist.site.title, value: girthText(waist))
        }
        if let chest = facts.chest {
            LabeledContent(chest.site.title, value: girthText(chest))
        }
        if let arm = facts.arm {
            LabeledContent(arm.site.title, value: girthText(arm))
        }
    }

    @ViewBuilder
    private var compositionRows: some View {
        if let composition = facts.composition {
            LabeledContent("Lean mass", value: massText(composition.lean, withinError: composition.isLeanWithinError))
            LabeledContent("Fat mass", value: massText(composition.fat, withinError: composition.isFatWithinError))
            if let share = composition.leanShare {
                LabeledContent("Lean share of the gain", value: Fmt.percent(share))
            }
        }
    }

    private var rateView: some View {
        HStack(spacing: 8) {
            Text(summary.rate.value.map { CheckInSheetText.rate($0) } ?? "Not enough data yet")
                .monospacedDigit()
            if let status = summary.status {
                Chip(text: status.title, tint: CheckInSheetStyle.tint(CheckInVerdict(status)))
            }
        }
    }

    /// "Week 9 of 19" of the running phase.
    private var weekText: String? {
        let phase = facts.mode == .start ? facts.active : facts.phase
        guard let phase, phase.isStarted, let week = phase.week(on: facts.today) else { return nil }
        guard let weeks = phase.weeks() else { return "\(week)" }
        return "\(week) of \(weeks)"
    }

    private var averageText: String {
        if let value = summary.average.value { return Fmt.kilograms(value) }
        return summary.average.prompt ?? "Not enough weigh-ins yet"
    }

    private func changeText(_ change: WeightSignal.Change) -> String {
        "\(CheckInSheetText.signedKg(change.kilograms)) (\(CheckInSheetText.signedPercent(change.percent)))"
    }

    private func girthText(_ change: GirthChange) -> String {
        let value = CheckInSheetText.signedCm(change.change)
        return change.isClear ? value : "\(value) · \(GirthTrend.noClearChange)"
    }

    private func massText(_ kilograms: Double, withinError: Bool) -> String {
        let value = CheckInSheetText.signedKg(kilograms)
        return withinError ? "\(value) · \(CompositionChange.withinErrorText)" : value
    }
}

/// A choice button with a line of detail.
private struct PhaseReviewChoice: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
