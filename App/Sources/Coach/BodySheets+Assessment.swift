import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// A body-fat assessment (`AssessmentSheet`, `AppSheet.assessment`); a record edits it. Body fat %
/// with how it was measured (each method, and each device, is its own series), the device for a
/// scale or BIA, optional lean and fat mass from the device, conditions, time and a note. Fat and
/// lean mass show live from the body weight around that day (the 7-day average for today).
/// Owns its NavigationStack and `.sheetFrame`.
struct AssessmentSheet: View {
    let record: BodyMeasurement?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var method: BodyMethod
    @State private var device: String
    @State private var bodyFat: String
    @State private var leanKg: String
    @State private var fatKg: String
    @State private var time: Date
    @State private var conditions: [BodyCondition]
    @State private var conditionsEdited: Bool
    @State private var note: String
    @State private var context: BodySheetAssessmentContext?
    @FocusState private var focused: Bool

    init(record: BodyMeasurement?) {
        self.record = record
        let values = record?.bodyValues ?? BodyValues()
        let method: BodyMethod = record.map { $0.bodyMethod ?? .estimate } ?? .scale
        _method = State(initialValue: BodySheetAssessment.methods.contains(method) ? method : .estimate)
        _device = State(initialValue: record?.device ?? "")
        _bodyFat = State(initialValue: values.bodyFat.map { BodySheetNumber.text($0) } ?? "")
        _leanKg = State(initialValue: values.leanKg.map { BodySheetNumber.text($0) } ?? "")
        _fatKg = State(initialValue: values.fatKg.map { BodySheetNumber.text($0) } ?? "")
        _time = State(initialValue: record?.time ?? Date())
        _conditions = State(initialValue: record.map { BodySheetConditions.parse($0.conditions) } ?? [.morning, .fasted])
        _conditionsEdited = State(initialValue: record != nil)
        _note = State(initialValue: record?.note ?? "")
    }

    // MARK: Derived

    private var bodyFatValue: Double? {
        guard let value = BodySheetNumber.parse(bodyFat), BodySheetAssessment.bodyFatRange.contains(value) else { return nil }
        return value
    }

    private var bodyFatIsInvalid: Bool {
        if BodySheetNumber.isInvalid(bodyFat) { return true }
        guard let value = BodySheetNumber.parse(bodyFat) else { return false }
        return !BodySheetAssessment.bodyFatRange.contains(value)
    }

    /// Lean or fat mass typed but not a number, or not a sensible kg value.
    private var massIsInvalid: Bool {
        [leanKg, fatKg].contains { (text: String) -> Bool in
            if BodySheetNumber.isInvalid(text) { return true }
            guard let value = BodySheetNumber.parse(text) else { return false }
            return value >= 300
        }
    }

    private var canSave: Bool { bodyFatValue != nil && !massIsInvalid }

    private var deviceName: String {
        BodySheetAssessment.usesDevice(method) ? device.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private var point: BodyCompositionPoint? {
        guard let context, let fat = bodyFatValue else { return nil }
        return context.point(bodyFat: fat, method: method, device: deviceName, leanKg: BodySheetNumber.parse(leanKg),
                             fatKg: BodySheetNumber.parse(fatKg), time: time)
    }

    private var showsDeviceValues: Bool {
        method != .estimate || !leanKg.isEmpty || !fatKg.isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                valueSection
                methodSection
                compositionSection
                if showsDeviceValues { deviceValuesSection }
                BodySheetConditionsSection(conditions: $conditions, sex: app.settings.body.sex) { conditionsEdited = true }
                detailsSection
                if record != nil { deleteSection }
            }
            .formStyle(.grouped)
            .navigationTitle("Body Fat")
            .inlineNavigationTitle()
            .toolbar { toolbar }
            .onAppear(perform: load)
            .onChange(of: time) { _, _ in setAutomaticConditions() }
            .onChange(of: method) { _, _ in methodChanged() }
        }
        .sheetFrame(minWidth: 460, minHeight: 600)
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

    private var valueSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("Body fat", text: $bodyFat, prompt: Text("0.0"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Body fat in percent")
                Text(verbatim: "%")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } header: {
            Text("Body fat")
        } footer: {
            if bodyFatIsInvalid {
                Text(verbatim: "Body fat from 2 to 70 % only – a typo?")
                    .foregroundStyle(.red)
            }
        }
    }

    private var methodSection: some View {
        Section {
            Picker("Method", selection: $method) {
                ForEach(BodySheetAssessment.methods) { method in
                    Text(BodySheetAssessment.label(method)).tag(method)
                }
            }
            if BodySheetAssessment.usesDevice(method) {
                TextField("Device", text: $device, prompt: Text("Device, e.g. InBody 570"))
            }
        } header: {
            Text("How it was measured")
        } footer: {
            methodFooter
        }
    }

    private var methodFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(errorText)
            Text("Each method – and each device – is its own series; Nina never mixes or compares them.")
            if record == nil, context?.isFirst == true {
                Text(BodyFatSeries.firstUseTip)
            }
        }
    }

    private var errorText: String {
        guard method.errorBand != nil else { return "\(method.title): the error is unknown." }
        return "\(method.title): typically \(method.errorText) body-fat points either way."
    }

    @ViewBuilder
    private var compositionSection: some View {
        if let point {
            Section {
                LabeledContent("Fat mass", value: Fmt.kilograms(point.composition.fatKg))
                LabeledContent("Lean mass", value: Fmt.kilograms(point.composition.leanKg))
            } header: {
                Text("Body composition")
            } footer: {
                Text(BodySheetAssessment.weightText(point.weight))
            }
        } else if bodyFatValue != nil, context != nil {
            Section {
                Text("Log a weigh-in to see your fat and lean mass.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Body composition")
            }
        }
    }

    private var deviceValuesSection: some View {
        Section {
            BodySheetNumberRow(title: "Lean mass", unit: "kg", text: $leanKg)
            BodySheetNumberRow(title: "Fat mass", unit: "kg", text: $fatKg)
        } header: {
            Text("From the device (optional)")
        } footer: {
            Text("When your scan shows both, Nina uses them instead of working them out from your weight.")
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("When", selection: $time)
            TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Assessment", systemImage: "trash", role: .destructive) {
                if let record { app.trash(record) }
                dismiss()
            }
        }
    }

    // MARK: Loading and saving

    private func load() {
        guard context == nil else { return }
        let loaded = BodySheetAssessmentContext.load(app: app, editing: record)
        context = loaded
        guard record == nil else { return }
        method = loaded.defaultMethod
        device = loaded.devices[loaded.defaultMethod] ?? ""
        setAutomaticConditions(loaded)
        focused = true
    }

    /// A new assessment takes the device last used with the method.
    private func methodChanged() {
        guard record == nil, let context else { return }
        device = context.devices[method] ?? ""
    }

    /// Morning and fasted before the cutoff with nothing eaten logged yet, else later; only
    /// until the person taps a condition, and never for an edited record.
    private func setAutomaticConditions(_ loaded: BodySheetAssessmentContext? = nil) {
        guard !conditionsEdited, let assessment = loaded ?? self.context else { return }
        let eaten = app.store.bodySheetHasEaten(on: assessment.day(for: time), before: time)
        conditions = BodyProtocol.automatic(at: time, cutoffMinutes: assessment.cutoffMinutes, hasEaten: eaten,
                                            calendar: assessment.calendar)
    }

    private func save() {
        guard let fat = bodyFatValue, !massIsInvalid else { return }
        let assessment = context ?? BodySheetAssessmentContext.load(app: app, editing: record)
        let values = BodySheetAssessment.values(base: record?.bodyValues ?? BodyValues(), bodyFat: fat,
                                                leanKg: BodySheetNumber.parse(leanKg), fatKg: BodySheetNumber.parse(fatKg))
        let unknown = record.map { BodySheetConditions.unknownTags($0.conditions) } ?? []
        let draft = BodyMeasurementDraft(day: assessment.day(for: time), time: time, kind: .assessment, values: values,
                                         method: method, device: deviceName,
                                         conditions: BodySheetConditions.encode(conditions, keeping: unknown),
                                         note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        app.saveMeasurement(draft, editing: record)
        dismiss()
    }
}
