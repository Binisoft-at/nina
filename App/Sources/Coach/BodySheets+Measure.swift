import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Tape measurements (`AppSheet.measure`): the weekly sites, the full set (from the plan's routine,
/// the defaults without a plan) or one site. A new session is a pager with one site per page
/// (BodySheets+Pager.swift): a start page with the measuring guide, conditions, time and note,
/// then each site with its outline drawing, one big number showing last time's value, ±0.1
/// buttons and the change since then; "Skip" bottom left, "Next: Chest" bottom right and "Done"
/// on the last page, which saves the session with an Undo toast. A record edits in one form.
/// One reading per site for the weekly sites (a second when it moved more than 1 cm), two per
/// site in a full set (a third when they differ by more than 0.5 cm; the mean or median is
/// saved). Conditions are set from the time (morning and fasted before the cutoff with nothing
/// eaten yet), the tape estimate of body fat shows live when the sites and the height are known.
/// Owns its NavigationStack and `.sheetFrame`.
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
    /// After a new full set: the photo session follows (device-only, remembered).
    @AppStorage(BodyPhotoKeys.afterFullSet) private var thenPhotos = true
    @State private var context: BodySheetTapeContext?
    /// The pager's page (a new session).
    @State private var page: BodySheetMeasurePage = .start
    @FocusState private var focus: BodySheetMeasureFocus?

    /// `site` measures that one site on its own (the same as `mode: .site(site)`).
    init(mode: MeasureMode, record: BodyMeasurement?, site: BodySite? = nil) {
        let resolved: MeasureMode = site.map { MeasureMode.site($0) } ?? mode
        self.mode = resolved
        self.record = record
        var readings: [BodySite: [String]] = [:]
        if let record {
            for (site, value) in record.bodyValues.sites { readings[site] = [BodySheetNumber.cm(value)] }
        }
        _current = State(initialValue: resolved)
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
        sites.map { siteState($0) }
    }

    /// One site's fields: its readings, the last value, what to say about them.
    private func siteState(_ site: BodySite) -> BodySheetSiteState {
        let texts = readings[site] ?? []
        guard let context else {
            return BodySheetSiteState(site: site, texts: texts, base: 1, twoReadings: false, previous: nil,
                                      recheck: false, day: app.today, calendar: Calendar.current)
        }
        return context.state(for: site, texts: texts, base: twoReadings ? 2 : 1, twoReadings: twoReadings,
                             recheck: record == nil, day: context.day(for: time))
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

    /// Something typed in a new session (a swipe down then doesn't throw it away).
    private var hasEntries: Bool {
        guard record == nil else { return false }
        return readings.values.contains { (list: [String]) -> Bool in
            list.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    private var sex: Sex { context?.sex ?? app.settings.body.sex }

    private var title: String {
        if record != nil { return "Measurements" }
        if current == .full { return "Full Measurement" }
        if sites.count == 1 { return siteTitle(sites[0]) }
        if let site = current.site { return site.base.title }
        return "Measurements"
    }

    /// "Arm (right)"
    private func siteTitle(_ site: BodySite) -> String {
        context?.title(for: site) ?? site.title
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .inlineNavigationTitle()
                .toolbar { toolbar }
                .onAppear(perform: load)
                .onChange(of: time) { _, _ in setAutomaticConditions() }
        }
        .interactiveDismissDisabled(hasEntries)
        .sheetFrame(minWidth: 480, minHeight: 680)
    }

    @ViewBuilder
    private var content: some View {
        if record != nil {
            form
        } else if context != nil {
            pagerView
        } else {
            Color.groupedBackground
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if showsToolbarSave {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    /// The pager's last page has Done at the bottom instead. On the Mac the pager has no Save up
    /// top: Return there would save the session after the first site, so Return goes to the
    /// bottom bar's Next and Done.
    private var showsToolbarSave: Bool {
        if record != nil { return true }
        #if os(macOS)
        return false
        #else
        return page != pager.lastPage
        #endif
    }

    /// Editing a record: one form with every site.
    private var form: some View {
        Form {
            guideSection
            sitesSection
            estimateSection
            BodySheetConditionsSection(conditions: $conditions, sex: sex) { conditionsEdited = true }
            detailsSection
            deleteSection
        }
        .formStyle(.grouped)
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
        if current != .full { return "Your weekly sites, one reading each." }
        return twoReadings
            ? "Every site, two readings each – a third when they differ by more than 0.5 cm."
            : "Every site, one reading each."
    }

    // MARK: Pager (a new session)

    private var pager: BodySheetPager { BodySheetPager(sites: sites) }

    private var pagerView: some View {
        VStack(spacing: 0) {
            pages
            bottomBar
        }
        .background(Color.groupedBackground)
        .onChange(of: page) { _, new in pageChanged(to: new) }
    }

    @ViewBuilder
    private var pages: some View {
        #if os(iOS)
        TabView(selection: $page) {
            ForEach(pager.pages, id: \.self) { item in
                pageView(item)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        pageView(page)
            .id(page)
        #endif
    }

    @ViewBuilder
    private func pageView(_ item: BodySheetMeasurePage) -> some View {
        switch item {
        case .start:
            startPage
        case .site(let site):
            sitePage(site)
        }
    }

    /// The measuring guide, conditions, time and note (and the set to measure).
    private var startPage: some View {
        Form {
            if current.site == nil { modeSection }
            guideSection
            if sites.isEmpty { noSitesSection }
            BodySheetConditionsSection(conditions: $conditions, sex: sex) { conditionsEdited = true }
            detailsSection
        }
        .formStyle(.grouped)
    }

    private var noSitesSection: some View {
        Section {
            Text("There are no sites in this set. Choose them in My Plan under Measuring.")
                .foregroundStyle(.secondary)
        }
    }

    private func sitePage(_ site: BodySite) -> some View {
        BodySheetSitePage(state: siteState(site), title: siteTitle(site),
                          hint: context?.hint(for: site) ?? site.landmark, sites: sites,
                          measured: Set(merged.keys), conditions: BodySheetConditions.shortText(conditions),
                          estimate: site == sites.last ? estimateLine : nil, texts: texts(for: site),
                          formula: $chosenFormula, focus: $focus,
                          showStart: { go(to: .start, focusing: false) })
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let site = invalidSite {
                Button("Check \(siteTitle(site)) – that value looks off") { go(to: .site(site), focusing: true) }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            HStack(spacing: 12) {
                leadingButtons
                Spacer(minLength: 8)
                Button(action: next) {
                    Text(nextTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .primaryActionStyle()
                .disabled(nextIsDisabled)
                #if os(macOS)
                .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var leadingButtons: some View {
        #if os(macOS)
        if let previous = pager.previous(before: page) {
            Button("Back") { go(to: previous, focusing: false) }
                .buttonStyle(.glass)
        }
        #endif
        if let site = page.site {
            Button("Skip") { skip(site) }
                .buttonStyle(.glass)
                .accessibilityHint("Leaves \(siteTitle(site)) out of this session.")
        }
    }

    /// On the last page: a site elsewhere whose value is off (Done waits for it).
    private var invalidSite: BodySite? {
        guard page == pager.lastPage else { return nil }
        return states.first { $0.isInvalid && $0.site != page.site }?.site
    }

    private var nextStep: BodySheetNextStep {
        guard let site = page.site else { return pager.step(after: page) }
        let focused: Int? = focus?.site == site ? focus?.index : nil
        return pager.step(after: page, texts: readings[site] ?? [], fieldCount: siteState(site).fieldCount,
                          focusedIndex: focused)
    }

    /// "2nd Reading", "Next: Chest", "Done" (or "Next: Body Fat" when the assessment follows).
    private var nextTitle: String {
        switch nextStep {
        case .reading(let index):
            return BodySheetReadings.readingTitle(index)
        case .page(let target):
            guard let site = target.site else { return "Next" }
            return "Next: \(siteTitle(site))"
        case .done:
            if offersPhotos && thenPhotos { return "Next: Photos" }
            return offersAssessment && thenAssessment ? "Next: Body Fat" : "Done"
        }
    }

    private var nextIsDisabled: Bool {
        if case .done = nextStep { return !canSave }
        return false
    }

    // MARK: Pager actions

    private func next() {
        switch nextStep {
        case .reading(let index):
            if let site = page.site { focus = BodySheetMeasureFocus(site: site, index: index) }
        case .page(let target):
            go(to: target, focusing: true)
        case .done:
            save()
        }
    }

    /// Skip: the site is left out (its readings cleared), on to the next one.
    private func skip(_ site: BodySite) {
        readings[site] = nil
        guard let target = pager.next(after: .site(site)) else { return }
        go(to: target, focusing: true)
    }

    private func go(to target: BodySheetMeasurePage, focusing: Bool) {
        withAnimation { page = target }
        guard let site = target.site else {
            focus = nil
            return
        }
        if focusing { requestFocus(on: site) }
    }

    /// A swipe to another site keeps the keypad up on the new page; the start page closes it.
    private func pageChanged(to new: BodySheetMeasurePage) {
        guard let site = new.site else {
            focus = nil
            return
        }
        if let focused = focus, focused.site != site { requestFocus(on: site) }
    }

    /// The keypad on a site's big number once its page has slid in.
    private func requestFocus(on site: BodySite, after milliseconds: Int = 350) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard page == .site(site) else { return }
            focus = BodySheetMeasureFocus(site: site, index: 0)
        }
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

    // MARK: Sites (editing a record)

    private var sitesSection: some View {
        Section {
            ForEach(states, id: \.site) { state in
                BodySheetSiteRow(state: state, title: siteTitle(state.site),
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
                Text(line.footer)
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

    // MARK: When, note, delete

    private var detailsSection: some View {
        Section {
            DatePicker("When", selection: $time)
            TextField("Note", text: $note, prompt: Text("Note"), axis: .vertical)
            if offersAssessment {
                Toggle("Then add body fat", isOn: $thenAssessment)
            }
            if offersPhotos {
                Toggle("Then add progress photos", isOn: $thenPhotos)
            }
        } footer: {
            if offersAssessment {
                Text("A body-fat check is due as well.")
            }
        }
    }

    /// A new full set can be followed by progress photos (BodyPhotosSession.swift); not in the tour.
    private var offersPhotos: Bool {
        record == nil && current == .full && !app.isSandbox
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
        // The demo (screenshots) opens on the first site without the keypad. The tour's practice
        // page opens on the first site too ("type your waist") and leaves the guide for the first
        // real measurement.
        let isDemo = app.launch.isDemo
        let firstTime = !guideSeen && !isDemo && !app.isSandbox
        showsGuide = firstTime
        if !app.isSandbox { guideSeen = true }
        setAutomaticConditions(loaded)
        if record == nil {
            let first = BodySheetPager(sites: loaded.sites(for: current)).firstPage(showsGuide: firstTime)
            page = first
            if let site = first.site, !isDemo { requestFocus(on: site, after: 600) }
        }
        context = loaded
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
        focus = nil
        let draft = BodyMeasurementDraft(day: context.day(for: time), time: time, kind: .tape, values: draftValues,
                                         conditions: conditionsText,
                                         note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        let saved = app.saveMeasurement(draft, editing: record)
        let assessmentFollows = offersAssessment && thenAssessment
        if offersPhotos, thenPhotos {
            app.present(.photos(.session(BodyPhotoStart(measurementID: saved.uuid, thenAssessment: assessmentFollows))))
        } else if assessmentFollows {
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
