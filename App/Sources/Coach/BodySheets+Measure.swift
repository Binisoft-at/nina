import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Tape measurements (`AppSheet.measure`): the weekly sites or the full set from the plan's
/// routine (the defaults without a plan); a record edits it. One reading per site for the weekly
/// sites (a second when it moved more than 1 cm), two per site in a full set (a third when they
/// differ by more than 0.5 cm; the mean or median is saved). Conditions are set from the time
/// (morning and fasted before the cutoff with nothing eaten yet), the tape estimate of body fat
/// shows live when the sites and the height are known. Owns its NavigationStack and `.sheetFrame`.
struct MeasureSheet: View {
    let mode: MeasureMode
    let record: BodyMeasurement?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nina.coach.measureGuideSeen") private var guideSeen = false
    /// The tape-estimate formula people with sex "Prefer not to say" picked (device-only).
    @AppStorage("nina.coach.navyFormula") private var chosenFormula = ""
    @State private var current: MeasureMode
    @State private var readings: [BodySite: [String]]
    @State private var time: Date
    @State private var conditions: [BodyCondition]
    @State private var conditionsEdited: Bool
    @State private var note: String
    @State private var showsGuide = false
    @State private var thenAssessment = true
    @State private var context: BodySheetTapeContext?

    init(mode: MeasureMode, record: BodyMeasurement?) {
        self.mode = mode
        self.record = record
        var readings: [BodySite: [String]] = [:]
        if let record {
            for (site, value) in record.bodyValues.sites { readings[site] = [BodySheetNumber.cm(value)] }
        }
        _current = State(initialValue: mode)
        _readings = State(initialValue: readings)
        _time = State(initialValue: record?.time ?? Date())
        _conditions = State(initialValue: record.map { BodySheetConditions.parse($0.conditions) } ?? [.morning, .fasted])
        _conditionsEdited = State(initialValue: record != nil)
        _note = State(initialValue: record?.note ?? "")
    }

    // MARK: Derived

    private var sites: [BodySite] {
        context?.sites(for: current, keeping: record?.bodyValues) ?? []
    }

    /// Two readings per site: a new full set with the routine's two-readings rule.
    private var twoReadings: Bool {
        record == nil && current == .full && (context?.routine.twoReadings ?? true)
    }

    private var states: [BodySheetSiteState] {
        guard let context else { return [] }
        let day = context.day(for: time)
        let base = twoReadings ? 2 : 1
        return sites.map { site in
            context.state(for: site, texts: readings[site] ?? [], base: base, twoReadings: twoReadings,
                          recheck: record == nil, day: day)
        }
    }

    private var merged: [BodySite: Double] {
        var values: [BodySite: Double] = [:]
        for state in states {
            if let value = state.merged { values[state.site] = value }
        }
        return values
    }

    private var draftValues: BodyValues {
        BodySheetReadings.values(base: record?.bodyValues ?? BodyValues(), merged: merged, sites: sites)
    }

    private var conditionsText: String {
        BodySheetConditions.encode(conditions, keeping: record.map { BodySheetConditions.unknownTags($0.conditions) } ?? [])
    }

    private var canSave: Bool {
        let all = states
        return all.contains { $0.merged != nil } && !all.contains { $0.isInvalid }
    }

    private var sex: Sex { context?.sex ?? app.settings.body.sex }

    private var title: String {
        if record != nil { return "Measurements" }
        if current == .full { return "Full Measurement" }
        return sites.count == 1 ? sites[0].title : "Measurements"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                if record == nil { modeSection }
                guideSection
                sitesSection
                estimateSection
                BodySheetConditionsSection(conditions: $conditions, sex: sex) { conditionsEdited = true }
                detailsSection
                if record != nil { deleteSection }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar { toolbar }
            .onAppear(perform: load)
            .onChange(of: time) { _, _ in setAutomaticConditions() }
        }
        .sheetFrame(minWidth: 480, minHeight: 640)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .disabled(!canSave)
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Measurements", selection: $current) {
                ForEach(MeasureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text(modeFooter)
        }
    }

    private var modeFooter: String {
        if current == .weekly { return "Your weekly sites, one reading each." }
        return twoReadings
            ? "Every site, two readings each – a third when they differ by more than 0.5 cm."
            : "Every site, one reading each."
    }

    // MARK: Guide

    private var guideSection: some View {
        Section {
            DisclosureGroup("Same conditions every time", isExpanded: $showsGuide) {
                ForEach(BodyProtocol.checklist, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
            }
        } footer: {
            Text(lastTimeText)
        }
    }

    private var lastTimeText: String {
        guard let context, let last = context.lastSession else {
            return "Measure the same way each time, so the changes you see are real."
        }
        return BodySheetReadings.lastTimeText(last, calendar: context.calendar)
    }

    // MARK: Sites

    private var sitesSection: some View {
        Section {
            ForEach(states, id: \.site) { state in
                BodySheetSiteRow(state: state, title: context?.title(for: state.site) ?? state.site.title,
                                 hint: context?.hint(for: state.site) ?? state.site.landmark, texts: texts(for: state.site))
            }
        } header: {
            Text("Centimeters")
        } footer: {
            Text("Skip a site by leaving it empty. Values to 0.1 cm.")
        }
    }

    private func texts(for site: BodySite) -> Binding<[String]> {
        Binding(get: { readings[site] ?? [] }, set: { readings[site] = $0 })
    }

    // MARK: Tape estimate

    private var estimateLine: BodySheetEstimateLine? {
        guard let context else { return nil }
        return context.estimateLine(values: draftValues, sites: sites, day: context.day(for: time), time: time,
                                    conditions: conditionsText, formula: context.formula(chosen: chosenFormula))
    }

    @ViewBuilder
    private var estimateSection: some View {
        if let line = estimateLine {
            Section {
                estimateContent(line)
            } header: {
                Text("Tape estimate")
            } footer: {
                Text(estimateFooter(line))
            }
        }
    }

    @ViewBuilder
    private func estimateContent(_ line: BodySheetEstimateLine) -> some View {
        switch line {
        case .value(let bodyFat):
            LabeledContent("Body fat") {
                Text(verbatim: "\(Fmt.number(bodyFat, decimals: 1)) %")
                    .font(.headline.monospacedDigit())
            }
        case .needsHeight:
            Text("Add your height in Goals & Plan to see a body-fat estimate from your tape values.")
                .foregroundStyle(.secondary)
        case .needsFormula:
            Picker("Formula", selection: $chosenFormula) {
                Text("Choose").tag("")
                ForEach(NavyBodyFat.Formula.allCases) { formula in
                    Text(formula.title).tag(formula.rawValue)
                }
            }
        case .needsSites(let missing):
            Text(BodySheetEstimateLine.sitesText(missing))
                .foregroundStyle(.secondary)
        case .implausible:
            Text("These values don't give a plausible estimate – a typo?")
                .foregroundStyle(.secondary)
        }
    }

    private func estimateFooter(_ line: BodySheetEstimateLine) -> String {
        switch line {
        case .value: "US Navy \(NavyBodyFat.label), worked out from your tape values and never saved."
        case .needsFormula: "The tape estimate has a formula for men and one for women. Nina remembers your choice."
        case .needsSites: "Neck and waist (women: also hip) within 12 weeks of each other."
        case .needsHeight, .implausible: "Worked out live from your tape values, never saved."
        }
    }

    // MARK: When, note, delete

    private var detailsSection: some View {
        Section {
            DatePicker("When", selection: $time)
            TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
            if offersAssessment {
                Toggle("Then add body fat", isOn: $thenAssessment)
            }
        } footer: {
            if offersAssessment {
                Text("A body-fat check is due as well.")
            }
        }
    }

    private var offersAssessment: Bool {
        record == nil && current == .full && (context?.assessmentDue ?? false)
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Measurements", systemImage: "trash", role: .destructive) {
                if let record { app.trash(record) }
                dismiss()
            }
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard context == nil else { return }
        let loaded = BodySheetTapeContext.load(app: app, editing: record)
        context = loaded
        showsGuide = !guideSeen
        guideSeen = true
        setAutomaticConditions(loaded)
    }

    /// Morning and fasted before the cutoff with nothing eaten logged yet, else later; only
    /// until the person taps a condition, and never for an edited record.
    private func setAutomaticConditions(_ loaded: BodySheetTapeContext? = nil) {
        guard !conditionsEdited, let tape = loaded ?? self.context else { return }
        let eaten = app.store.bodySheetHasEaten(on: tape.day(for: time), before: time)
        conditions = BodyProtocol.automatic(at: time, cutoffMinutes: tape.cutoffMinutes, hasEaten: eaten,
                                            calendar: tape.calendar)
    }

    private func save() {
        guard let context, canSave else { return }
        let draft = BodyMeasurementDraft(day: context.day(for: time), time: time, kind: .tape, values: draftValues,
                                         conditions: conditionsText,
                                         note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        app.saveMeasurement(draft, editing: record)
        if offersAssessment, thenAssessment {
            app.present(.assessment(nil))
        } else {
            dismiss()
        }
    }
}

/// One site: its name, where the tape goes, the reading fields and a line about them.
private struct BodySheetSiteRow: View {
    let state: BodySheetSiteState
    let title: String
    let hint: String
    @Binding var texts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            fields
            if let message = state.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(state.isInvalid ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let previous = state.previousText {
                Text(previous)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fields: some View {
        HStack(spacing: 8) {
            ForEach(0..<state.fieldCount, id: \.self) { index in
                BodySheetReadingField(text: field(index), prompt: prompt(index), label: fieldLabel(index),
                                      fallback: state.values.first ?? state.previous?.value,
                                      range: state.site.plausibleRange)
            }
        }
    }

    private func prompt(_ index: Int) -> String {
        switch index {
        case 0: state.fieldCount > 1 ? "1st" : "cm"
        case 1: "2nd"
        default: "3rd"
        }
    }

    /// "Waist in centimeters", or "Waist, reading 2" when a site has more than one field.
    private func fieldLabel(_ index: Int) -> String {
        state.fieldCount > 1 ? "\(title), reading \(index + 1)" : "\(title) in centimeters"
    }

    private func field(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < texts.count ? texts[index] : "" },
            set: { value in
                var list = texts
                while list.count <= index { list.append("") }
                list[index] = value
                texts = list
            }
        )
    }
}

/// One tape reading in cm. VoiceOver adjusts it in 0.1 cm steps (from the first reading or the
/// last value while it is empty).
private struct BodySheetReadingField: View {
    @Binding var text: String
    let prompt: String
    let label: String
    let fallback: Double?
    let range: ClosedRange<Double>

    var body: some View {
        TextField(prompt, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.title3.monospacedDigit())
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .accessibilityLabel(label)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(0.1)
                case .decrement: step(-0.1)
                default: break
                }
            }
    }

    private func step(_ amount: Double) {
        text = BodySheetNumber.stepped(text, by: amount, fallback: fallback, range: range)
    }
}
