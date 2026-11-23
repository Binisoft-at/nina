import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

// The body sheets: the weigh-in (here), tape measurements (BodySheets+Measure.swift) and body-fat
// assessments (BodySheets+Assessment.swift). Each owns its NavigationStack and `.sheetFrame`.
// The glue they share (no SwiftUI) is in BodySheets+Logic.swift.

/// The weigh-in sheet (`AppSheet.weight`): nil logs a new weigh-in, an entry edits it. The last
/// weight is prefilled as one big number with ±0.1 steps; body fat, note, reason tags and the
/// time sit behind "More". A weight outside 25–300 kg or more than 3 kg from the 7-day average
/// asks "Did you mean …?" before it is saved. Takes `app.pendingWeighIn` (from nina://weigh) as
/// the number and clears it.
struct WeighInSheet: View {
    let entry: WeightEntry?
    /// The weigh-in came from an import: its note keeps the import tag on save, hidden in the field.
    private let isImported: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var bodyFat: String
    @State private var note: String
    @State private var time: Date
    @State private var showsMore: Bool
    @State private var context: BodySheetWeighInContext?
    @State private var check: BodySheetWeightCheck?
    @FocusState private var focused: Bool

    init(entry: WeightEntry?) {
        self.entry = entry
        isImported = entry.map { HealthWeightSync.isImported(note: $0.note) } ?? false
        let fat = entry?.bodyFat ?? 0
        let note = HealthWeightSync.editableNote(entry?.note ?? "")
        _text = State(initialValue: entry.map { BodySheetNumber.text($0.kilograms) } ?? "")
        _bodyFat = State(initialValue: fat > 0 ? BodySheetNumber.text(fat) : "")
        _note = State(initialValue: note)
        _time = State(initialValue: entry?.time ?? Date())
        _showsMore = State(initialValue: fat > 0 || !note.isEmpty)
    }

    private var kilograms: Double? { BodySheetNumber.parse(text) }

    private var bodyFatValue: Double? { BodySheetNumber.parse(bodyFat) }

    /// Body fat typed but not a number or outside 2–70 %.
    private var bodyFatIsInvalid: Bool {
        if BodySheetNumber.isInvalid(bodyFat) { return true }
        guard let value = bodyFatValue else { return false }
        return !BodySheetAssessment.bodyFatRange.contains(value)
    }

    /// The warning of the last Save tap, while the number is still the one it was about.
    private var shownCheck: BodySheetWeightCheck? {
        guard let check, let kilograms, abs(check.kilograms - kilograms) < 0.001 else { return nil }
        return check
    }

    var body: some View {
        NavigationStack {
            Form {
                numberSection
                if let shownCheck { checkSection(shownCheck) }
                moreSection
                if entry != nil { deleteSection }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "Weigh In" : "Weigh-in")
            .inlineNavigationTitle()
            .toolbar { toolbar }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
        .sheetFrame(minWidth: 420, minHeight: 440)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .disabled(kilograms == nil || bodyFatIsInvalid)
        }
    }

    // MARK: The number

    private var numberSection: some View {
        Section {
            HStack(spacing: 12) {
                stepButton(-0.1, symbol: "minus", label: "Minus 0.1 kg")
                numberField
                    .frame(maxWidth: .infinity)
                stepButton(0.1, symbol: "plus", label: "Plus 0.1 kg")
            }
            .padding(.vertical, 6)
        } footer: {
            Text(numberFooter)
        }
    }

    private var numberField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("Weight", text: $text, prompt: Text(BodySheetNumber.text(0)))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 52, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .fixedSize()
                .focused($focused)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel("Weight in kilograms")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(0.1)
                    case .decrement: step(-0.1)
                    default: break
                    }
                }
            Text("kg")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func stepButton(_ amount: Double, symbol: String, label: String) -> some View {
        Button {
            step(amount)
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.14), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func step(_ amount: Double) {
        text = BodySheetNumber.stepped(text, by: amount, fallback: context?.latest, range: BodySheetWeight.range)
    }

    /// "Last 74.2 kg · 7-day average 74.6 kg", and a nudge for an unusual reading.
    private var numberFooter: String {
        guard let context else { return " " }
        var parts: [String] = []
        if entry == nil, let latest = context.latest { parts.append("Last \(Fmt.kilograms(latest))") }
        if let average = context.signal.average(on: context.day(for: time)).value {
            parts.append("7-day average \(Fmt.kilograms(average))")
        }
        var lines = [parts.joined(separator: " · ")]
        if let standing = standingLine(context) { lines.append(standing) }
        if let kilograms, shownCheck == nil, context.isUnusual(kilograms, at: time),
           WeightSignal.Tag.parse(note).isEmpty {
            lines.append("Unusual reading – anything special? Add a reason under More.")
        }
        let footer = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        return footer.isEmpty ? " " : footer
    }

    /// With a plan: whether this weigh-in counts in the 7-day average, pace and check-in (only
    /// the first one before the morning cutoff does).
    private func standingLine(_ context: BodySheetWeighInContext) -> String? {
        guard app.settings.plan.isSetUp else { return nil }
        let day = context.day(for: time)
        switch context.signal.standing(time: time, day: day, kilograms: kilograms) {
        case .counts:
            return nil
        case .afterCutoff:
            return "After \(Fmt.clock(context.signal.cutoffMinutes)) – shown on the chart, not counted in your average."
        case .extra(let morning):
            let when = day == app.today ? "This morning's" : "That morning's"
            return "\(when) weight is already \(Fmt.kilograms(morning.kilograms)) – this one is extra, not counted in your average."
        }
    }

    // MARK: Did you mean …?

    private func checkSection(_ check: BodySheetWeightCheck) -> some View {
        Section {
            Label(checkTitle(check), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            if let suggestion = check.suggestion {
                Button("Use \(Fmt.kilograms(suggestion))") {
                    text = BodySheetNumber.text(suggestion)
                }
            }
            if !check.isOutOfRange {
                Button("Save \(Fmt.kilograms(check.kilograms)) Anyway") {
                    commit(check.kilograms)
                }
            }
        } footer: {
            Text(checkFooter(check))
        }
    }

    private func checkTitle(_ check: BodySheetWeightCheck) -> String {
        if let suggestion = check.suggestion { return "Did you mean \(Fmt.kilograms(suggestion))?" }
        return check.isOutOfRange ? "Nina takes weights from 25 to 300 kg." : "\(Fmt.kilograms(check.kilograms)) – a typo?"
    }

    private func checkFooter(_ check: BodySheetWeightCheck) -> String {
        if check.isOutOfRange { return "\(Fmt.kilograms(check.kilograms)) is outside 25–300 kg." }
        guard let reference = check.reference else { return "That's far from your recent weigh-ins." }
        let difference = Fmt.kilograms(abs(check.kilograms - reference))
        return "That's \(difference) away from your 7-day average of \(Fmt.kilograms(reference))."
    }

    // MARK: More

    private var moreSection: some View {
        Section {
            DisclosureGroup("More", isExpanded: $showsMore) {
                BodySheetNumberRow(title: "Body fat", unit: "%", text: $bodyFat)
                if bodyFatIsInvalid {
                    Text(verbatim: "Body fat from 2 to 70 % only – a typo?")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                tagsRow
                TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
                DatePicker("When", selection: $time)
            }
        }
    }

    private var tags: [WeightSignal.Tag] { WeightSignal.Tag.parse(note) }

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anything special?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .info(BodyPageInfo.unusualReading)
            BodySheetFlow(spacing: 8) {
                ForEach(WeightSignal.Tag.options(for: context?.sex ?? app.settings.body.sex)) { tag in
                    BodySheetToggleChip(title: tag.title, isOn: tags.contains(tag)) { toggle(tag) }
                }
            }
            Text("A reason goes into the note as a #tag. Tagged weigh-ins stay on the chart but don't count for your rate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ tag: WeightSignal.Tag) {
        var current = tags
        if let index = current.firstIndex(of: tag) {
            current.remove(at: index)
        } else {
            current.append(tag)
        }
        note = WeightSignal.Tag.note(note, setting: current)
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Weigh-in", systemImage: "trash", role: .destructive) {
                if let entry { app.trash(entry) }
                dismiss()
            }
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard context == nil else { return }
        let loaded = BodySheetWeighInContext.load(app: app, editing: entry)
        context = loaded
        guard entry == nil else { return }
        if let pending = app.pendingWeighIn {
            app.pendingWeighIn = nil
            let value = (pending * 10).rounded() / 10
            text = BodySheetNumber.text(value)
            check = BodySheetWeightCheck(value, sanity: loaded.sanity(value, at: time), reference: loaded.reference(at: time))
        } else if text.isEmpty, let latest = loaded.latest {
            text = BodySheetNumber.text(latest)
        } else if text.isEmpty {
            focused = true
        }
    }

    /// Save: a weight that fails the sanity check shows "Did you mean …?" first; a second Save
    /// (or "Save … Anyway") keeps a far-off weight, an out-of-range one is never saved.
    private func save() {
        guard let kilograms, !bodyFatIsInvalid else { return }
        if let shownCheck {
            if !shownCheck.isOutOfRange { commit(kilograms) }
            return
        }
        if let entry, abs(entry.kilograms - kilograms) < 0.001 {
            commit(kilograms)
            return
        }
        let loaded = context ?? BodySheetWeighInContext.load(app: app, editing: entry)
        if let found = BodySheetWeightCheck(kilograms, sanity: loaded.sanity(kilograms, at: time),
                                            reference: loaded.reference(at: time)) {
            withAnimation { check = found }
            return
        }
        commit(kilograms)
    }

    private func commit(_ kilograms: Double) {
        let day = (context ?? BodySheetWeighInContext.load(app: app, editing: entry)).day(for: time)
        let fat = bodyFatValue ?? 0
        // An imported weigh-in stays history (never written to Apple Health), whatever the field says.
        let cleanNote = HealthWeightSync.savedNote(note.trimmingCharacters(in: .whitespacesAndNewlines), imported: isImported)
        if let entry {
            app.bodySheetUpdate(entry, to: BodySheetWeighIn(kilograms: kilograms, day: day, time: time, bodyFat: fat, note: cleanNote))
        } else {
            app.logWeight(kilograms, day: day, time: time, bodyFat: fat, note: cleanNote)
        }
        dismiss()
    }
}

// MARK: - Shared pieces of the body sheets

/// A labelled number field in a form row: "Body fat … %", "Lean mass … kg".
struct BodySheetNumberRow: View {
    let title: String
    let unit: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: $text, prompt: Text("optional"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

/// A chip that switches something on and off (reason tags, conditions).
struct BodySheetToggleChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The conditions of a tape or body-fat reading as chips (morning and fasted are set
/// automatically), with whether it counts as a standard reading.
struct BodySheetConditionsSection: View {
    @Binding var conditions: [BodyCondition]
    let sex: Sex
    /// Called after a tap (the sheet then stops setting the tags from the time).
    let onEdit: () -> Void

    var body: some View {
        Section {
            BodySheetFlow(spacing: 8) {
                ForEach(BodySheetConditions.offered(for: sex)) { condition in
                    BodySheetToggleChip(title: condition.title, isOn: conditions.contains(condition)) {
                        conditions = BodySheetConditions.toggling(condition, in: conditions)
                        onEdit()
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Conditions")
                .info(BodyPageInfo.conditions)
        } footer: {
            Text(BodySheetConditions.summary(conditions))
        }
    }
}

/// Lays chips out in rows, wrapping onto the next row when one is full.
struct BodySheetFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width: CGFloat = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
