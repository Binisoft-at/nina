import SwiftUI
import BinisoftKit
import NinaCore

/// The weekly check-in of the week starting on `week` (a Monday) (`AppSheet.checkIn`), in four
/// steps of about two minutes (F11): 1. Your week – the 7-day average, the changes and the rate
/// as a corridor bar with the target band; 2. Waist – typed right here (the full set when one is
/// due), done when measured this morning; 3. How it went, with the optional ratings and a note;
/// 4. Next week – the verdict with its one reason and the proposal: Apply from tomorrow (Undo
/// restores the plan), Not now, or Edit the step, and Copy for My AI. A week already saved opens
/// read-only from its snapshot, with Redo. Leaving for a full measurement set keeps the answers
/// (`CheckInSheetDraft`). Owns its NavigationStack and `.sheetFrame`.
struct CheckInSheet: View {
    let week: DayKey
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var facts: CheckInSheetFacts?
    @State private var redo = false
    @State private var prefilled = false
    @State private var ratings = CheckInRatings()
    @State private var note = ""
    @State private var step: Double = 0
    @State private var editingStep = false
    /// The live check-in's step: 0 Your week, 1 Waist, 2 How it went, 3 Next week.
    @State private var page = 0
    /// The waist typed on the Waist step (a second reading when the first moved more than 1 cm).
    @State private var waistFirst = ""
    @State private var waistSecond = ""
    /// Saved, applied or left for a full set: closing keeps no draft of its own.
    @State private var finished = false
    @AppStorage("nina.coach.copyIncludesHealth") private var copyIncludesHealth = false

    private var lastPage: Int { CheckInSheetFacts.pageTitles.count - 1 }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Weekly Check-in")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isEditing ? "Cancel" : "Close", action: close)
                    }
                    if canSaveFromToolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveWithoutProposal() }
                        }
                    }
                }
        }
        .task(id: app.dataVersion) { load() }
        // Closed before it was saved (Cancel, a swipe down): the answers wait for the next open.
        .onDisappear(perform: keepDraft)
        // Saving the waist and Copy for My AI keep the sheet open: their messages show in the
        // sheet's toast host (SheetContent).
        .sheetFrame(minWidth: 520, minHeight: 560)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let facts {
            if let saved = facts.saved, !redo {
                savedForm(facts, saved: saved)
            } else {
                switch facts.state {
                case .ready:
                    liveForm(facts)
                case .noPlan:
                    CheckInCalmView(title: "No Plan Yet", symbol: "checklist",
                                    message: "The weekly check-in compares your week with a plan: a phase with a weekly rate and your daily targets. Set one up, and your first check-in comes a week later.",
                                    button: "Set Up Your Plan", action: openPlan)
                case .noPhase:
                    CheckInCalmView(title: "No Phase Running", symbol: "flag",
                                    message: "Check-ins start once a phase is running. Start one in your plan, and Nina looks at each week with you from then on.",
                                    button: "Open My Plan", action: openPlan)
                case .paused:
                    CheckInCalmView(title: "Coaching Is Paused", symbol: "pause.circle",
                                    message: "This week is paused, so there's nothing to check. Enjoy the break – Nina picks up again when the pause ends.",
                                    button: "Open My Plan", action: openPlan)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func liveForm(_ facts: CheckInSheetFacts) -> some View {
        Form {
            CheckInStepHeader(page: page, note: headerNote(facts))
            pageContent(facts)
        }
        .formStyle(.grouped)
        // A new step starts at its top.
        .id(page)
        // Back and Next stay at the bottom edge, outside the scrolling steps.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CheckInPager(page: page, lastPage: lastPage, onBack: back, onNext: { next(facts) })
        }
    }

    @ViewBuilder
    private func pageContent(_ facts: CheckInSheetFacts) -> some View {
        switch page {
        case 0:
            CheckInWeightSection(facts: facts)
        case 1:
            CheckInWaistStep(facts: facts, first: $waistFirst, second: $waistSecond,
                             onSave: { saveWaist(facts) }, onFullSet: measureFullSet)
        case 2:
            CheckInHowItWent(facts: facts, unit: app.energyUnit)
            CheckInFeelings(ratings: $ratings, note: $note)
        default:
            CheckInNextWeek(facts: facts, unit: app.energyUnit, step: $step, editing: $editingStep,
                            followUp: followUpTitle(facts),
                            onApply: { apply(facts) }, onKeep: { commit(facts, decision: .kept) },
                            onSave: { commit(facts, decision: nil) }, onFollowUp: { followUp(facts) },
                            onCopy: copyForAI)
        }
    }

    /// What a check-in without a proposal leads to: the phase review once the review weight is
    /// reached, the phase sheet when the phase has no weekly rate.
    private func followUpTitle(_ facts: CheckInSheetFacts) -> String? {
        guard facts.phase != nil else { return nil }
        switch facts.result.rule {
        case .checkpoint: return "Save and Review Phase"
        case .noRate: return "Save and Set a Rate"
        default: return nil
        }
    }

    private func followUp(_ facts: CheckInSheetFacts) {
        guard let phase = facts.phase else { return }
        app.checkInCommit(facts.evaluation, ratings: ratings, note: note, waist: facts.waist?.value, decision: nil, delta: 0)
        finished = true
        CheckInSheetDraft.byWeek[week] = nil
        app.present(facts.result.rule == .checkpoint ? .phaseReview(phase.id) : .phase(phase.id))
    }

    private func savedForm(_ facts: CheckInSheetFacts, saved: CheckInSnapshot) -> some View {
        Form {
            CheckInSavedSections(facts: facts, saved: saved, unit: app.energyUnit, note: facts.savedNote,
                                 canRedo: facts.state == .ready, onRedo: startRedo, onCopy: copyForAI)
        }
        .formStyle(.grouped)
    }

    // MARK: State

    /// The live form is open (not the saved view or a calm message).
    private var isEditing: Bool {
        guard let facts, facts.state == .ready else { return false }
        return facts.saved == nil || redo
    }

    /// Without a proposal the toolbar saves on the last step; with one the decision buttons do.
    /// Not on a Mac that misses the Apple Health weigh-ins (the check-in belongs on the iPhone).
    private var canSaveFromToolbar: Bool {
        guard isEditing, page == lastPage, let facts else { return false }
        return !facts.result.hasProposal && !facts.needsPhoneForWeighIns
    }

    private func load() {
        let context = CoachContext.load(app: app, day: app.today)
        let loaded = CheckInSheetFacts.load(context: context, week: week, store: app.store)
        facts = loaded
        guard !prefilled else { return }
        prefilled = true
        step = abs(loaded.result.delta)
        if let draft = CheckInSheetDraft.byWeek[week] {
            // Back from a full measurement set, Cancel or a swipe down: the answers so far. Used
            // once; closing again keeps what the sheet holds then (`keepDraft`).
            CheckInSheetDraft.byWeek[week] = nil
            ratings = draft.ratings
            note = draft.note
            redo = draft.redo
            page = min(max(0, draft.page), lastPage)
        } else {
            ratings = loaded.saved?.ratings ?? CheckInRatings()
            note = loaded.savedNote
        }
    }

    // MARK: Steps

    private func back() {
        var target = max(0, page - 1)
        if target == 1, facts?.skipsWaistStep == true { target = 0 }
        page = target
    }

    /// The next step; a waist typed but not saved yet is saved on the way.
    private func next(_ facts: CheckInSheetFacts) {
        if page == 1, !facts.waistMeasuredToday,
           CheckInSheetFacts.waistEntry(waistFirst, waistSecond, site: facts.waistSite, previous: facts.lastWaist?.value).value != nil {
            saveWaist(facts)
        }
        // Measured this morning: the Waist step is skipped and shown as done.
        var target = min(lastPage, page + 1)
        if target == 1, facts.skipsWaistStep { target = 2 }
        page = target
    }

    private func startRedo() {
        redo = true
        page = 0
    }

    /// Once the Waist step was skipped (measured today): says so under the step title.
    private func headerNote(_ facts: CheckInSheetFacts) -> String? {
        guard page > 1, facts.skipsWaistStep else { return nil }
        return "Waist measured today – step 2 is done"
    }

    // MARK: Actions

    private func apply(_ facts: CheckInSheetFacts) {
        let size = step > 0 ? step : abs(facts.result.delta)
        let delta = facts.deltaSign * size
        let decision: CheckInDecision = abs(delta - facts.result.delta) < 0.5 ? .applied : .edited
        app.checkInCommit(facts.evaluation, ratings: ratings, note: note, waist: facts.waist?.value, decision: decision,
                          delta: delta)
        finished = true
        CheckInSheetDraft.byWeek[week] = nil
        dismiss()
    }

    private func commit(_ facts: CheckInSheetFacts, decision: CheckInDecision?) {
        app.checkInCommit(facts.evaluation, ratings: ratings, note: note, waist: facts.waist?.value, decision: decision,
                          delta: 0)
        finished = true
        CheckInSheetDraft.byWeek[week] = nil
        dismiss()
    }

    private func saveWithoutProposal() {
        guard let facts else { return }
        commit(facts, decision: nil)
    }

    /// Cancel keeps what was entered for the next open (`keepDraft`); Close leaves a saved week
    /// as it is.
    private func close() {
        dismiss()
    }

    /// A live check-in closed before it was saved keeps its answers in memory (ratings, note,
    /// step) when any were given or a step was left, so the next open resumes there.
    private func keepDraft() {
        guard !finished else { return }
        guard isEditing, let facts else {
            CheckInSheetDraft.byWeek[week] = nil
            return
        }
        let changed = page > 0 || ratings != (facts.saved?.ratings ?? CheckInRatings()) || note != facts.savedNote
        CheckInSheetDraft.byWeek[week] = changed ? CheckInSheetDraft(ratings: ratings, note: note, page: page, redo: redo) : nil
    }

    private func openPlan() {
        app.present(.plan)
    }

    /// Saves the typed waist (a tape record of this morning, with Undo); the step then shows it as done.
    private func saveWaist(_ facts: CheckInSheetFacts) {
        let entry = CheckInSheetFacts.waistEntry(waistFirst, waistSecond, site: facts.waistSite, previous: facts.lastWaist?.value)
        guard let value = entry.value else { return }
        app.checkInSaveWaist(value, site: facts.waistSite)
        waistFirst = ""
        waistSecond = ""
    }

    /// The full set closes this sheet: the answers so far wait in memory until it opens again.
    private func measureFullSet() {
        finished = true
        CheckInSheetDraft.byWeek[week] = CheckInSheetDraft(ratings: ratings, note: note, page: page, redo: redo)
        app.present(.measure(.full, nil))
    }

    /// "Copy for My AI": the plan, the last 4 weeks and the body numbers as text (Apple Health
    /// weigh-ins only when switched on in the plan editor).
    private func copyForAI() {
        #if os(iOS)
        let includeHealth = copyIncludesHealth
        #else
        let includeHealth = false
        #endif
        Clipboard.copy(PlanEditorData.aiText(app: app, includeHealth: includeHealth))
        app.toasts.show("Copied – paste it into your AI", symbol: "doc.on.clipboard.fill")
    }
}

// MARK: - Steps

/// "Step 2 of 4 · Waist" with a bar of four segments (and a note on a skipped step).
private struct CheckInStepHeader: View {
    let page: Int
    let note: String?

    private var titles: [String] { CheckInSheetFacts.pageTitles }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(page + 1) of \(titles.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(titles[min(max(0, page), titles.count - 1)])
                    .font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(0..<titles.count, id: \.self) { (index: Int) in
                        Capsule()
                            .fill(index <= page ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                            .frame(height: 4)
                    }
                }
                if let note {
                    Label(note, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Back and Next, pinned under the steps (on the last step only Back: its decision buttons are
/// part of the step).
private struct CheckInPager: View {
    let page: Int
    let lastPage: Int
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        if page > 0 || page < lastPage {
            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back", systemImage: "chevron.left", action: onBack)
                        .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                if page < lastPage {
                    nextButton
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    /// "Next" with its chevron after the word, white on the green button.
    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 4) {
                Text("Next")
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.white)
        }
        .primaryActionStyle()
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Style

/// The check-in colours: the same words always get the same colour (in range green, slower or
/// faster orange, off track red).
enum CheckInSheetStyle {
    static func tint(_ verdict: CheckInVerdict) -> Color {
        switch verdict {
        case .inRange: return Color.green
        case .slower, .faster: return Color.orange
        case .offTarget: return Color.red
        case .gathering: return Color.secondary
        case .checkpoint: return Brand.accent
        }
    }

    static func tint(_ status: CheckInStatus) -> Color {
        switch status {
        case .onTrack: return Color.green
        case .watch: return Color.orange
        case .offTrack: return Color.red
        }
    }

    static func tint(_ grade: AdherenceGrade) -> Color {
        switch grade {
        case .good: return Color.green
        case .watch: return Color.orange
        case .off: return Color.red
        }
    }
}

// MARK: - Sections

/// "How it went": logged days, calories in range, protein, checks, the weekly grade.
private struct CheckInHowItWent: View {
    let facts: CheckInSheetFacts
    let unit: EnergyUnit

    private var week: AdherenceSummary { facts.week }

    var body: some View {
        Section {
            energyRows
            proteinRows
        } header: {
            Text("How it went")
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private var energyRows: some View {
        if let grade = week.grade {
            LabeledContent("This week") {
                Chip(text: grade.title, tint: CheckInSheetStyle.tint(grade), isSelected: true)
            }
        }
        LabeledContent("Days logged", value: CheckInSheetText.count(week.loggedDays, of: week.days))
        LabeledContent("Days on plan", value: CheckInSheetText.count(week.onPlanDays, of: week.days))
        LabeledContent("Calories in range", value: CheckInSheetText.count(week.kcalDays, of: week.days))
        if week.loggedDays > 0 {
            LabeledContent("Average eaten", value: ofText(week.averageIntake, week.averageTarget))
        }
        if week.byType.count > 1 {
            ForEach(week.byType) { average in
                LabeledContent(typeTitle(average), value: typeValue(average))
            }
        }
    }

    @ViewBuilder
    private var proteinRows: some View {
        LabeledContent("Protein days", value: CheckInSheetText.count(week.proteinDays, of: week.days))
        if let ratio = facts.proteinRatio {
            LabeledContent("Protein target", value: ratio)
        }
        if week.proteinMealsTarget > 0 {
            LabeledContent("Protein meals", value: CheckInSheetText.count(week.proteinMeals, of: week.proteinMealsTarget))
        }
        if week.loggedDays > 0, week.averageFiberTarget > 0 {
            LabeledContent("Fiber", value: "\(Fmt.number(week.averageFiber.rounded())) of \(Fmt.grams(week.averageFiberTarget))")
        }
        if week.averageWaterTarget > 0 {
            LabeledContent("Water", value: "\(Fmt.volume(week.averageWater)) of \(Fmt.volume(week.averageWaterTarget))")
        }
        ForEach(week.checks) { tally in
            LabeledContent(checkTitle(tally), value: CheckInSheetText.count(tally.done, of: tally.due))
        }
        ForEach(week.flexible) { tally in
            LabeledContent(CheckInSheetText.dayType(tally.typeID, plan: facts.plan, empty: "Days"),
                           value: CheckInSheetText.count(tally.count, of: tally.planned))
        }
    }

    private var footer: String {
        var text = "The 7 days before your check-in. On plan = logged, calories in range (±10 %, at least ±150 kcal) and protein reached."
        if week.pausedDays > 0 { text += " \(week.pausedDays) paused \(week.pausedDays == 1 ? "day is" : "days are") left out." }
        return text
    }

    private func ofText(_ value: Double, _ target: Double) -> String {
        "\(Fmt.energy(value, unit: unit, showUnit: false)) of \(Fmt.energy(target, unit: unit))"
    }

    private func typeTitle(_ type: AdherenceSummary.TypeAverage) -> String {
        CheckInSheetText.dayType(type.typeID, plan: facts.plan, empty: "Other") + " days"
    }

    private func typeValue(_ type: AdherenceSummary.TypeAverage) -> String {
        guard type.loggedDays > 0 else { return "not logged" }
        return "avg " + ofText(type.averageIntake, type.averageTarget)
    }

    private func checkTitle(_ tally: AdherenceSummary.CheckTally) -> String {
        var name = tally.checkID
        if let check = facts.plan.check(id: tally.checkID) {
            let title = check.name.isEmpty ? check.id : check.name
            name = check.emoji.isEmpty ? title : "\(check.emoji) \(title)"
        }
        return tally.isOptional ? "\(name) (optional)" : name
    }
}

/// The week's rate as a corridor bar (F11 step 1): the phase's range as a band, the tolerance
/// as its lighter edges, and the rate as a dot in the status colour, with both ends of the range
/// labelled ("+0.15", "+0.25").
private struct CheckInRateBar: View {
    let rate: Double
    let range: ClosedRange<Double>
    let tolerance: Double
    let tint: Color
    /// The status words ("In range", "Slower than planned"); nil while gathering.
    let status: String?

    private let height: CGFloat = 44

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            bar(width: proxy.size.width)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The kg/week the bar spans: the range with its tolerance and the rate, plus 0.1 each side.
    private var domain: ClosedRange<Double> {
        let low = min(range.lowerBound - tolerance, rate) - 0.1
        let high = max(range.upperBound + tolerance, rate) + 0.1
        return low...max(high, low + 0.01)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        let fraction = min(max((value - domain.lowerBound) / span, 0), 1)
        return CGFloat(fraction) * width
    }

    private func bar(width: CGFloat) -> some View {
        let outerLow = x(range.lowerBound - tolerance, width: width)
        let outerHigh = x(range.upperBound + tolerance, width: width)
        let innerLow = x(range.lowerBound, width: width)
        let innerHigh = x(range.upperBound, width: width)
        let dot = x(rate, width: width)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: width, height: 10)
                .offset(y: 5)
            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(width: max(2, outerHigh - outerLow), height: 10)
                .offset(x: outerLow, y: 5)
            Rectangle()
                .fill(Color.green.opacity(0.6))
                .frame(width: max(2, innerHigh - innerLow), height: 10)
                .offset(x: innerLow, y: 5)
            Circle()
                .fill(tint)
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                .frame(width: 20, height: 20)
                .offset(x: min(max(0, dot - 10), width - 20))
            labels(low: innerLow, high: innerHigh, width: width)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// Both ends of the range under the band; one "+0.15 to +0.25" when they're too close.
    @ViewBuilder
    private func labels(low: CGFloat, high: CGFloat, width: CGFloat) -> some View {
        if high - low < 56 {
            label("\(lowText) to \(highText)", at: (low + high) / 2, width: width)
        } else {
            label(lowText, at: low, width: width)
            label(highText, at: high, width: width)
        }
    }

    private func label(_ text: String, at center: CGFloat, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .position(x: min(max(center, 24), max(24, width - 24)), y: 34)
    }

    private var lowText: String { CheckInSheetText.signedNumber(range.lowerBound) }
    private var highText: String { CheckInSheetText.signedNumber(range.upperBound) }

    private var accessibilityText: String {
        var text = "Rate \(CheckInSheetText.signedNumber(rate)) kg a week. Your range \(lowText) to \(highText) kg a week."
        if let status { text += " \(status)." }
        return text
    }
}


/// Step 1, "Your week": the 7-day average, the changes, the rate against the range with the
/// status words Progress uses (and as a corridor bar), the window and the gathering line.
private struct CheckInWeightSection: View {
    let facts: CheckInSheetFacts

    private var summary: WeightSignal.Summary { facts.summary }
    private var rate: WeightSignal.Rate { summary.rate }

    var body: some View {
        Section {
            LabeledContent("7-day average", value: averageText)
            if let change = summary.weeklyChange {
                LabeledContent("Change vs last week", value: changeText(change, decimals: 2))
            }
            if let since = summary.sinceStart {
                LabeledContent("Since the phase start", value: changeText(since))
            }
            LabeledContent("Rate") {
                rateView
            }
            if let value = rate.value, let range = facts.rateRange {
                CheckInRateBar(rate: value, range: range, tolerance: facts.plan.adjust.tolerance, tint: statusTint,
                               status: summary.status?.title)
                    .padding(.vertical, 4)
            }
            if let planned = facts.plannedRange {
                LabeledContent("Planned", value: planned)
            }
            LabeledContent("Window", value: windowText)
            LabeledContent("Mornings weighed", value: CheckInSheetText.count(facts.mornings, of: 7))
            if let line = facts.gatheringLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Weight")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let rule = "A rate needs \(rate.minimumDays) days and \(rate.minimumWeighIns) morning weigh-ins. Weigh-ins with a reason tag stay out of it."
        #if os(macOS)
        return rule + " Weigh-ins from Apple Health count on iPhone and iPad only."
        #else
        return rule
        #endif
    }

    private var rateView: some View {
        HStack(spacing: 8) {
            Text(rateText)
                .monospacedDigit()
            if let status = summary.status {
                Chip(text: status.title, tint: CheckInSheetStyle.tint(CheckInVerdict(status)))
            }
        }
    }

    private var averageText: String {
        if let value = summary.average.value { return Fmt.kilograms(value) }
        return summary.average.prompt ?? "Not enough weigh-ins yet"
    }

    private var statusTint: Color {
        guard let status = summary.status else { return Color.secondary }
        return CheckInSheetStyle.tint(CheckInVerdict(status))
    }

    private var rateText: String {
        guard let value = rate.value else { return "Not enough data yet" }
        return CheckInSheetText.rate(value)
    }

    private var windowText: String {
        "\(rate.window.days()) days · \(rate.weighIns) weigh-ins"
    }

    /// The week's change with two decimals, as the Body page shows it; the change since the phase
    /// start with one. The share of body weight is left out below 0.05 %.
    private func changeText(_ change: WeightSignal.Change, decimals: Int = 1) -> String {
        CheckInSheetText.weightChange(change, decimals: decimals)
    }
}

/// Step 2, "Waist": typed right here. Done (and skipped) when the waist was measured today; the
/// full set instead when one is due; otherwise one field, and a second when the reading moved
/// more than 1 cm since last time. The tape and body-fat hints follow.
private struct CheckInWaistStep: View {
    let facts: CheckInSheetFacts
    @Binding var first: String
    @Binding var second: String
    let onSave: () -> Void
    let onFullSet: () -> Void

    private var entry: (fields: Int, value: Double?) {
        CheckInSheetFacts.waistEntry(first, second, site: facts.waistSite, previous: facts.lastWaist?.value)
    }

    var body: some View {
        Section {
            rows
        } header: {
            Text(facts.waistSite.title)
        } footer: {
            Text(footer)
        }
        if !facts.bodyHints.isEmpty {
            CheckInHintsSection(hints: facts.bodyHints)
        }
    }

    @ViewBuilder
    private var rows: some View {
        if facts.waistMeasuredToday, let waist = facts.waist {
            CheckInWaistDone(facts: facts, waist: waist)
            if facts.fullSetDue {
                Button("Full Measurement", systemImage: "ruler", action: onFullSet)
            }
        } else if facts.fullSetDue {
            Text("A full measurement set is due – it takes your waist along with the other sites.")
            Button("Full Measurement", systemImage: "ruler", action: onFullSet)
        } else {
            entryRows
        }
    }

    @ViewBuilder
    private var entryRows: some View {
        if let waist = facts.waist {
            LabeledContent("Measured \(Fmt.shortDay(waist.day))", value: CheckInWaistText.cm(waist.value))
        }
        CheckInWaistField(title: entry.fields > 1 ? "First reading" : "Today", text: $first)
        if entry.fields > 1 {
            CheckInWaistField(title: "Second reading", text: $second)
            Text("That's more than 1 cm from last time – measure once more to be sure.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if entry.value == nil, !(first.isEmpty && second.isEmpty) {
            Text(rangeHint)
                .font(.footnote)
                .foregroundStyle(Color.orange)
        }
        Button("Save Waist", systemImage: "checkmark.circle.fill", action: onSave)
            .disabled(entry.value == nil)
    }

    /// "Enter a number from 40 to 200 cm."
    private var rangeHint: String {
        let range = facts.waistSite.plausibleRange
        return "Enter a number from \(Fmt.number(range.lowerBound)) to \(Fmt.number(range.upperBound)) cm."
    }

    private var footer: String {
        if facts.waistMeasuredToday { return "Done for this week." }
        if facts.fullSetDue {
            return "Your answers so far are kept – open the check-in again after measuring."
        }
        var text = "In the morning before eating, relaxed, at the same spot each time."
        if let last = facts.lastWaist {
            text += " Last time: \(CheckInWaistText.cm(last.value)) on \(Fmt.shortDay(last.day))."
        }
        return text + " No tape at hand? Skip with Next."
    }
}

/// The waist measured today: its value, the change since the reading before and a note when it
/// wasn't a morning, fasted reading.
private struct CheckInWaistDone: View {
    let facts: CheckInSheetFacts
    let waist: GirthReading

    var body: some View {
        Label("Measured today", systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.green)
        LabeledContent(facts.waistSite.title, value: CheckInWaistText.cm(waist.value))
        if let change = facts.waistChange {
            LabeledContent("Since \(Fmt.shortDay(change.from.day))", value: CheckInWaistText.change(change))
        }
        if !waist.isStandard {
            Text("Not a morning, fasted reading – it stays out of your trends.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A typed waist reading: "Today [84.5] cm".
private struct CheckInWaistField: View {
    let title: String
    @Binding var text: String

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
                Text("cm")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Hints from the tape and body fat (waist guard, waist note, lean share): never a change.
private struct CheckInHintsSection: View {
    let hints: [String]

    var body: some View {
        Section {
            ForEach(hints, id: \.self) { (hint: String) in
                Label(hint, systemImage: "lightbulb")
            }
        } header: {
            Text("Worth knowing")
        } footer: {
            Text("Only hints: your targets change only when you choose.")
        }
    }
}

private enum CheckInWaistText {
    /// "84.5 cm"
    static func cm(_ value: Double) -> String {
        "\(Fmt.number(value, decimals: 1)) cm"
    }

    /// "+1.2 cm", with "no clear change" within the site's MDC.
    static func change(_ change: GirthChange) -> String {
        let value = CheckInSheetText.signedCm(change.change)
        return change.isClear ? value : "\(value) · \(GirthTrend.noClearChange)"
    }
}

/// The optional 1–5 ratings and a free note.
private struct CheckInFeelings: View {
    @Binding var ratings: CheckInRatings
    @Binding var note: String

    var body: some View {
        Section {
            ForEach(CheckInRatings.keys, id: \.self) { key in
                CheckInRatingRow(title: CheckInSheetText.rating(key), value: binding(key))
            }
            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("How you felt")
        } footer: {
            Text(footer)
        }
    }

    private func binding(_ key: String) -> Binding<Int?> {
        Binding<Int?>(get: { ratings[key] }, set: { ratings[key] = $0 })
    }

    private var footer: String {
        #if os(macOS)
        return "1 = very low, 5 = very high. All optional – click a number again to clear it."
        #else
        return "1 = very low, 5 = very high. All optional – tap a number again to clear it."
        #endif
    }
}

private struct CheckInRatingRow: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { score in
                    scoreButton(score)
                }
            }
        }
        // Five circles in one row: the text grows only so far.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// A 30 pt circle with a 40 × 44 pt tap area (the circles stay 10 pt apart; five 44 pt
    /// squares and the title don't fit an iPhone row).
    private func scoreButton(_ score: Int) -> some View {
        let isOn = value == score
        return Button {
            value = isOn ? nil : score
        } label: {
            Text("\(score)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 30, height: 30)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: .circle)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(score) of 5")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "Next week": the verdict and its reason, the proposal with every day type's new targets,
/// and the decision (Apply from tomorrow, Not now, Edit the step) – or Save without a proposal.
private struct CheckInNextWeek: View {
    let facts: CheckInSheetFacts
    let unit: EnergyUnit
    @Binding var step: Double
    @Binding var editing: Bool
    /// A button that saves and opens what comes next (the phase review, the phase sheet).
    let followUp: String?
    let onApply: () -> Void
    let onKeep: () -> Void
    let onSave: () -> Void
    let onFollowUp: () -> Void
    /// "Copy for My AI".
    let onCopy: () -> Void

    private var result: CheckInResult { facts.result }
    private var delta: Double { facts.deltaSign * (step > 0 ? step : abs(result.delta)) }

    var body: some View {
        Section {
            verdictRow
            Text(reasonText)
            ForEach(result.notes, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            dueRows
        } header: {
            Text("Next week")
        }
        if result.hasProposal {
            proposalSection
            decisionSection
        } else {
            if facts.needsPhoneForWeighIns {
                CheckInPhoneOnlySection()
            } else {
                Section {
                    if let followUp {
                        Button(followUp, systemImage: "arrow.right.circle.fill", action: onFollowUp)
                            .primaryActionStyle()
                            .labelStyle(.titleOnly)
                        Button("Save Check-in", systemImage: "checkmark.circle", action: onSave)
                    } else {
                        Button("Save Check-in", systemImage: "checkmark.circle.fill", action: onSave)
                            .primaryActionStyle()
                            .labelStyle(.titleOnly)
                    }
                } footer: {
                    Text("Your targets stay as they are.")
                }
            }
        }
        CheckInCopySection(onCopy: onCopy)
    }

    private var verdictRow: some View {
        HStack {
            Chip(text: result.verdict.title, tint: CheckInSheetStyle.tint(result.verdict), isSelected: true)
            Spacer()
            Text(result.status.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckInSheetStyle.tint(result.status))
        }
    }

    /// The measurements due in the coming week.
    @ViewBuilder
    private var dueRows: some View {
        if let due = facts.nextFull {
            LabeledContent("Full measurement", value: dueText(due))
        }
        if let due = facts.nextAssessment {
            LabeledContent("Body-fat assessment", value: dueText(due))
        }
    }

    private func dueText(_ due: BodySchedule.Due) -> String {
        due.day <= facts.evaluation.today ? "Due now" : CheckInSheetText.day(due.day)
    }

    /// The engine's sentence; while gathering, the Weight section already says when.
    private var reasonText: String {
        result.rule == .gathering ? "No change yet – keep weighing in each morning." : result.reason
    }

    private var proposalSection: some View {
        Section {
            LabeledContent("Change", value: "\(CheckInSheetText.signedEnergy(delta, unit: unit)) a day")
            ForEach(facts.evaluation.preview(delta)) { change in
                CheckInTypeChangeRow(title: CheckInSheetText.dayType(change.typeID, plan: facts.plan, empty: "Every day"),
                                     change: change, unit: unit)
            }
            if editing {
                Picker("Step", selection: $step) {
                    ForEach(facts.stepOptions, id: \.self) { size in
                        Text(CheckInSheetText.signedEnergy(facts.deltaSign * size, unit: unit)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Proposal")
        } footer: {
            Text(proposalFooter)
        }
    }

    private var proposalFooter: String {
        let macros = facts.phase?.goal == .lose ? "carbs and fat" : "carbs"
        return "From tomorrow, \(CheckInSheetText.day(facts.evaluation.applyFrom)), for every day type. Protein stays; the change goes into \(macros)."
    }

    private var decisionSection: some View {
        Section {
            Button("Apply from Tomorrow", systemImage: "checkmark.circle.fill", action: onApply)
                .primaryActionStyle()
                .labelStyle(.titleOnly)
            Button("Not Now", systemImage: "hand.raised", action: onKeep)
            if facts.stepOptions.count > 1 {
                Button(editing ? "Keep This Step" : "Edit Step", systemImage: "slider.horizontal.3") {
                    editing.toggle()
                }
            }
        } footer: {
            Text(decisionFooter)
        }
    }

    private var decisionFooter: String {
        #if os(macOS)
        return "Nothing changes until you click. Undo puts your previous targets back."
        #else
        return "Nothing changes until you tap. Undo puts your previous targets back."
        #endif
    }
}

/// On a Mac whose check-in misses morning weigh-ins: they most likely come from Apple Health,
/// which only the iPhone and iPad read. Saving here would record a "Gathering data" week.
private struct CheckInPhoneOnlySection: View {
    var body: some View {
        Section {
            Label("Do this check-in on your iPhone", systemImage: "iphone")
                .font(.headline)
            Text("Weigh-ins from Apple Health count on iPhone and iPad only, so this Mac sees too few of them to judge your week.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// One day type before → after a change: "🏋️ Gym 2,600 → 2,700 kcal", "+25 g carbs".
private struct CheckInTypeChangeRow: View {
    let title: String
    let change: CheckInEngine.TypeChange
    let unit: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(energyText)
                    .monospacedDigit()
            }
            if !macroText.isEmpty {
                Text(macroText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var energyText: String {
        "\(Fmt.energy(change.before.energy, unit: unit, showUnit: false)) → \(Fmt.energy(change.after.energy, unit: unit))"
    }

    private var macroText: String {
        CheckInSheetText.macroChange(protein: change.proteinChange, carbs: change.carbsChange, fat: change.fatChange)
    }
}

/// A saved week, read-only from its snapshot (Health weights recomputed live), with Redo.
private struct CheckInSavedSections: View {
    let facts: CheckInSheetFacts
    let saved: CheckInSnapshot
    let unit: EnergyUnit
    let note: String
    let canRedo: Bool
    let onRedo: () -> Void
    let onCopy: () -> Void

    var body: some View {
        Section {
            if let verdict = saved.verdict {
                LabeledContent("Verdict") {
                    Chip(text: verdict.title, tint: CheckInSheetStyle.tint(verdict), isSelected: true)
                }
            }
            LabeledContent("Decision", value: decisionText)
        } header: {
            Text("Saved for \(CheckInSheetText.day(saved.day))")
        }
        Section {
            LabeledContent("7-day average", value: average.map { Fmt.kilograms($0) } ?? "–")
            if let change = weeklyChange {
                LabeledContent("Change vs last week", value: CheckInSheetText.signedKg(change, decimals: 2))
            }
            if let rate {
                LabeledContent("Rate", value: CheckInSheetText.rate(rate))
            }
            if let weighIns = saved.weighIns {
                LabeledContent("Morning weigh-ins", value: "\(weighIns)")
            }
            if let waist = saved.waist {
                LabeledContent("Waist", value: "\(Fmt.number(waist, decimals: 1)) cm")
            }
        } header: {
            Text("Weight and body")
        }
        Section {
            if let days = saved.days {
                LabeledContent("Days logged", value: CheckInSheetText.count(saved.logged ?? 0, of: days))
                LabeledContent("Days on plan", value: CheckInSheetText.count(saved.onPlan ?? 0, of: days))
                if let protein = saved.proteinDays {
                    LabeledContent("Protein days", value: CheckInSheetText.count(protein, of: days))
                }
            }
            if let eaten = saved.kcalAvg, let target = saved.kcalTarget {
                LabeledContent("Average eaten",
                               value: "\(Fmt.energy(eaten, unit: unit, showUnit: false)) of \(Fmt.energy(target, unit: unit))")
            }
            if let meals = saved.proteinMeals, let target = saved.proteinMealsTarget {
                LabeledContent("Protein meals", value: CheckInSheetText.count(meals, of: target))
            }
        } header: {
            Text("How it went")
        }
        if !saved.ratings.isEmpty || !note.isEmpty {
            Section {
                if !saved.ratings.isEmpty {
                    Text(CheckInSheetText.ratings(saved.ratings))
                }
                if !note.isEmpty {
                    Text(note)
                }
            } header: {
                Text("How you felt")
            }
        }
        if !facts.bodyHints.isEmpty {
            CheckInHintsSection(hints: facts.bodyHints)
        }
        CheckInCopySection(onCopy: onCopy)
        if canRedo {
            Section {
                Button("Redo Check-in", systemImage: "arrow.counterclockwise", action: onRedo)
            } footer: {
                Text("Goes through this week again and saves over it. Targets you already changed stay as they are.")
            }
        }
    }

    private var decisionText: String {
        if let delta = saved.deltaKcal, delta != 0, saved.decision == .applied || saved.decision == .edited {
            return CheckInSheetText.signedEnergy(delta, unit: unit)
        }
        let text = saved.decisionText
        return text.isEmpty ? "Saved" : text
    }

    /// The saved numbers; with Health weights they weren't stored, so they come from the live signal.
    private var average: Double? {
        saved.usesHealthWeights ? facts.summary.average.value : saved.avg7
    }

    private var weeklyChange: Double? {
        if saved.usesHealthWeights { return facts.summary.weeklyChange?.kilograms }
        guard let now = saved.avg7, let before = saved.prevAvg7 else { return nil }
        return now - before
    }

    private var rate: Double? {
        saved.usesHealthWeights ? facts.summary.rate.value : saved.rate
    }
}

/// "Copy for My AI" (F16): plain text on the clipboard, nothing sent anywhere.
private struct CheckInCopySection: View {
    let onCopy: () -> Void

    var body: some View {
        Section {
            Button("Copy for My AI", systemImage: "doc.on.clipboard", action: onCopy)
        } footer: {
            Text("Your plan, the last 4 weeks and your body numbers as text to paste into your AI. Its answer can be imported in My Plan.")
        }
    }
}

/// A calm explanation with one button (no plan, no phase running, a paused week).
private struct CheckInCalmView: View {
    let title: String
    let symbol: String
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button(button, action: action)
                .primaryActionStyle()
        }
    }
}
