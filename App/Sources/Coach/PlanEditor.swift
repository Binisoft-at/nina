import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The plan editor, "My Plan" (Settings → Goals & Plan → My Plan, F15): phases, day types with
/// their targets in the running phase, daily checks, measuring and adjustments, protein per meal,
/// the long-term goal, notes from the plan, pausing, and "Import from My AI", "Export" and "Copy
/// for My AI".
///
/// No NavigationStack of its own: it is pushed from Settings (Goals & Plan), shown as a tab of the
/// Mac Settings window, and wrapped in one for `AppSheet.plan` and `.planGoal`. `showsDone`: a
/// Done button (as a sheet). `initialRoute`: a page pushed once when it first appears. Every
/// change is saved with `app.updatePlan` (toast with Undo); the pages for one part save when you
/// go back. The phase sheet and the import open from here (not through `app.sheet`),
/// so the editor stays underneath and they also work in the Mac Settings window.
struct PlanEditorView: View {
    let showsDone: Bool
    var initialRoute: PlanEditorRoute? = nil
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: PlanEditorSheet?
    @State private var pushed: PlanEditorRoute?
    @State private var openedInitialRoute = false
    @State private var naming: PlanEditorNaming = .dayType
    @State private var isNaming = false
    @State private var newName = ""
    @State private var exportText = ""
    @State private var proteinRatio: String?
    /// "Turn on coach reminders?" after the plan was first set up here.
    @State private var askReminders = false
    /// The plan when the phase sheet opened: closing it may have set the plan up.
    @State private var planBeforeSheet: CoachPlan?
    /// A started phase about to be deleted ("Delete Lean Gain?").
    @State private var deletingPhase: CoachPlan.Phase?
    @AppStorage("nina.coach.copyIncludesHealth") private var copyIncludesHealth = false

    private var plan: CoachPlan { app.settings.plan }
    /// Export, Copy Export and Copy for My AI carry Apple Health weights only when switched on
    /// (iPhone and iPad).
    private var includesHealth: Bool {
        #if os(iOS)
        copyIncludesHealth
        #else
        false
        #endif
    }
    private var today: DayKey { app.today }

    var body: some View {
        Form {
            bodySection
            if plan.isSetUp {
                phasesSection
                dayTypesSection
                checksSection
                routineSections
                notesSection
                PlanEditorPauseSection()
            } else {
                setUpSection
            }
            aiSection
            historySection
        }
        .formStyle(.grouped)
        .navigationTitle("My Plan")
        .inlineNavigationTitle()
        .toolbar {
            if showsDone {
                // Every change is saved as it is made: Esc closes it on the Mac.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: deletingPhase) { phase in
            Button("Delete Phase", role: .destructive) { PlanEditorData.deletePhase(phase.id, app: app) }
            Button("Cancel", role: .cancel) {}
        } message: { phase in
            Text(PlanEditorData.deleteMessage(for: phase))
        }
        .navigationDestination(item: $pushed) { (route: PlanEditorRoute) in
            destination(route)
        }
        .sheet(item: $sheet, onDismiss: sheetClosed) { (sheet: PlanEditorSheet) in
            sheetContent(sheet)
                .environment(app)
                .modelContainer(app.container)
        }
        .alert(naming.title, isPresented: $isNaming) {
            TextField(naming.placeholder, text: $newName)
            Button("Add") { add() }
            Button("Cancel", role: .cancel) {}
        }
        .coachRemindersPrompt(isPresented: $askReminders)
        .task(id: app.dataVersion) {
            exportText = PlanEditorData.exportText(app: app, includeHealth: includesHealth)
            proteinRatio = PlanEditorData.proteinRatio(app: app)
        }
        .onChange(of: copyIncludesHealth) { _, _ in
            exportText = PlanEditorData.exportText(app: app, includeHealth: includesHealth)
        }
        .onAppear(perform: openInitialRoute)
        // In the Mac Settings window its Undo toasts show here (in a sheet, the sheet shows them).
        .ownToasts(app.toasts)
    }

    /// Once, not again when that page goes back to the editor.
    private func openInitialRoute() {
        guard let initialRoute, !openedInitialRoute else { return }
        openedInitialRoute = true
        pushed = initialRoute
    }

    // MARK: Sections

    private var bodySection: some View {
        Section {
            NavigationLink {
                GoalsView(showsDone: false, showsPlanLink: false)
            } label: {
                LabeledContent {
                    Text(bodySummary)
                } label: {
                    Label("Body & Calculator", systemImage: "figure")
                }
            }
        } footer: {
            if !app.settings.hasBody {
                Text("Add your height and birth year – they're needed for the tape estimate, FFMI and the calorie formula.")
            }
        }
    }

    private var bodySummary: String {
        let settings = app.settings
        guard settings.hasBody else { return "Height and birth year needed" }
        return "\(Fmt.number(settings.body.heightCm)) cm · \(settings.body.age) years"
    }

    private var setUpSection: some View {
        Section {
            Text("A plan adds phases with dates, day types with their own calories, daily checks, a measuring routine and a weekly check-in. Without one, Nina works as before.")
                .font(.callout)
                .foregroundStyle(.secondary)
            // Title only: in a form row the icon would take the button's own colour.
            Button("Set Up My Plan", systemImage: "sparkles", action: setUp)
                .labelStyle(.titleOnly)
                .primaryActionStyle()
            Button("Add a Phase", systemImage: "flag") { openPhase(nil) }
        } header: {
            Text("Your Plan")
        } footer: {
            Text("Set Up My Plan starts one phase today from your goal; Add a Phase lets you describe it first. Both turn your training days into day types, with the calories you have now. Or let your AI write the whole plan: Import from My AI, below.")
        }
    }

    private var phasesSection: some View {
        Section {
            ForEach(sortedPhases) { (phase: CoachPlan.Phase) in
                phaseRow(phase)
            }
            Button("Add a Phase", systemImage: "plus") { openPhase(nil) }
        } header: {
            Text("Phases")
        } footer: {
            Text(PlanEditorWording.phasesFooter)
        }
    }

    private var sortedPhases: [CoachPlan.Phase] {
        let today = self.today
        return plan.phases.sorted { ($0.start ?? today) < ($1.start ?? today) }
    }

    private func phaseRow(_ phase: CoachPlan.Phase) -> some View {
        let isActive = plan.activePhase(on: today)?.id == phase.id
        return Button {
            openPhase(phase.id)
        } label: {
            PlanEditorPhaseRow(name: PlanEditorData.phaseName(phase),
                               status: PlanEditorData.phaseStatus(phase, plan: plan, today: today),
                               detail: PlanEditorData.phaseDetail(phase), isActive: isActive)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(phase) }
        }
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { openPhase(phase.id) }
            Button(PlanEditorView.deleteLabel(phase), systemImage: "trash", role: .destructive) { requestDelete(phase) }
        }
    }

    /// "Delete…" where a question follows (a started phase), else "Delete".
    private static func deleteLabel(_ phase: CoachPlan.Phase) -> String {
        phase.isStarted ? "Delete…" : "Delete"
    }

    /// A phase that has started asks first (its targets go with it); a planned one goes with Undo.
    private func requestDelete(_ phase: CoachPlan.Phase) {
        if phase.isStarted {
            deletingPhase = phase
        } else {
            PlanEditorData.deletePhase(phase.id, app: app)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding<Bool>(get: { deletingPhase != nil }, set: { (shown: Bool) in if !shown { deletingPhase = nil } })
    }

    private var deleteTitle: String {
        "Delete \(deletingPhase.map { PlanEditorData.phaseName($0) } ?? "this phase")?"
    }

    /// The plan as it was before each change, to restore one.
    private var historySection: some View {
        Section {
            NavigationLink {
                PlanEditorHistoryView()
            } label: {
                Label("Earlier Versions", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("Nina keeps the plan as it was before a change (up to 30 versions), so you can go back.")
        }
    }

    private var dayTypesSection: some View {
        Section {
            if plan.activePhase(on: today) != nil {
                NavigationLink {
                    PlanEditorBaselineView()
                } label: {
                    LabeledContent(baselineTitle, value: baselineText)
                }
            }
            ForEach(plan.dayTypes) { (type: CoachPlan.DayType) in
                NavigationLink {
                    PlanEditorDayTypeView(typeID: type.id)
                } label: {
                    PlanEditorDayTypeRow(title: PlanEditorData.typeLabel(type), schedule: PlanEditorData.scheduleText(type),
                                         targets: PlanEditorData.typeTargetsText(type, plan: plan, day: today, unit: app.energyUnit))
                }
            }
            Button("Add a Day Type…", systemImage: "plus") { startNaming(.dayType) }
                .disabled(plan.dayTypes.count >= PlanEdits.maxDayTypes)
        } header: {
            Text("Day Types")
        } footer: {
            PlanEditorWeekFooter(plan: plan, day: today, unit: app.energyUnit,
                                 note: "Up to 4 kinds of day with their own calories, like Gym, Tennis and Rest. Target changes start today.")
        }
    }

    private var baselineTitle: String {
        plan.dayTypes.isEmpty ? "Daily targets" : "Baseline"
    }

    private var baselineText: String {
        guard let baseline = plan.revision(on: today)?.baseline else { return "Your daily targets" }
        return Fmt.energy(baseline.energy, unit: app.energyUnit)
    }

    private var checksSection: some View {
        Section {
            ForEach(plan.checks) { (check: CoachPlan.Check) in
                NavigationLink {
                    PlanEditorCheckView(checkID: check.id)
                } label: {
                    PlanEditorTitleRow(title: [check.emoji, check.name].filter { !$0.isEmpty }.joined(separator: " "),
                                       detail: PlanEditorData.checkDetail(check, plan: plan, settings: app.settings))
                }
            }
            Button("Add a Daily Check…", systemImage: "plus") { startNaming(.check) }
        } header: {
            Text("Daily Checks")
        } footer: {
            Text("What your plan names, like a supplement: a pill on Today to tick off. Nina never suggests one.")
        }
    }

    @ViewBuilder
    private var routineSections: some View {
        Section {
            NavigationLink {
                PlanEditorMeasuringView()
            } label: {
                PlanEditorTitleRow(title: "Measuring", detail: PlanEditorData.routineSummary(plan.routine))
            }
            NavigationLink {
                PlanEditorAdjustView()
            } label: {
                PlanEditorTitleRow(title: "Adjustments", detail: PlanEditorData.adjustSummary(plan.adjust))
            }
        } header: {
            Text("Measuring & Check-in")
        } footer: {
            Text("Weigh-in time, tape sites, body fat and the weekly check-in, and how calories are adjusted after it.")
        }
        Section {
            NavigationLink {
                PlanEditorProteinView()
            } label: {
                LabeledContent("Protein per Meal", value: PlanEditorData.proteinSummary(plan.protein, settings: app.settings))
            }
        } footer: {
            if let proteinRatio { Text(proteinRatio) }
        }
        Section {
            NavigationLink {
                PlanEditorLongTermView()
            } label: {
                LabeledContent("Long-Term Goal", value: PlanEditorData.longTermSummary(plan.longTerm))
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !plan.notes.isEmpty {
            Section {
                ForEach(Array(plan.notes.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    PlanEditorNoteRow(text: item.element) {
                        PlanEditorData.deleteNote(at: item.offset, text: item.element, app: app)
                    }
                }
            } header: {
                Text("Notes from My Plan")
            } footer: {
                Text(PlanEditorWording.notesFooter)
            }
        }
    }

    private var aiSection: some View {
        Section {
            Button("Import from My AI", systemImage: "square.and.arrow.down") { sheet = .importSettings }
            ShareLink(item: exportText) {
                Label("Export Goals & Plan", systemImage: "square.and.arrow.up")
            }
            .disabled(exportText.isEmpty)
            Button("Copy Export", systemImage: "doc.on.doc") { copyExport() }
            Button("Copy for My AI", systemImage: "sparkles") { copyForAI() }
            #if os(iOS)
            Toggle("Include Apple Health weights", isOn: $copyIncludesHealth)
            #endif
        } header: {
            Text("Your AI")
        } footer: {
            Text(aiFooter)
        }
    }

    private var aiFooter: String {
        let text = "Import from My AI reads the settings file your AI wrote, with a preview first. Export writes your goals and the whole plan in that format. Copy for My AI adds your last 4 weeks and body numbers and asks for an answer you can import."
        #if os(iOS)
        return text + " Export, Copy Export and Copy for My AI include weights from Apple Health only when you switch them on."
        #else
        return text
        #endif
    }

    // MARK: Actions

    @ViewBuilder
    private func destination(_ route: PlanEditorRoute) -> some View {
        switch route {
        case .dayType(let id): PlanEditorDayTypeView(typeID: id)
        case .check(let id): PlanEditorCheckView(checkID: id)
        case .longTerm: PlanEditorLongTermView()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PlanEditorSheet) -> some View {
        switch sheet {
        case .phase(let id): PhaseSheet(phaseID: id)
        case .importSettings: ImportView(initialKind: .settings)
        }
    }

    /// "Set Up My Plan", then "Turn on coach reminders?" once per device.
    private func setUp() {
        let change = PlanEditorData.setUp(app: app)
        offerReminders(before: change.before, after: change.after)
    }

    /// Opens the phase sheet (nil = a new phase); a first phase sets the plan up.
    private func openPhase(_ id: String?) {
        planBeforeSheet = PlanEditorData.storedPlan(app)
        sheet = .phase(id)
    }

    /// After the phase sheet: ask about coach reminders when it set the plan up. (The import asks
    /// itself, so it isn't checked here.)
    private func sheetClosed() {
        guard let before = planBeforeSheet else { return }
        planBeforeSheet = nil
        offerReminders(before: before, after: PlanEditorData.storedPlan(app))
    }

    private func offerReminders(before: CoachPlan, after: CoachPlan) {
        guard !app.isSandbox, !app.launch.isDemo,
              NotificationScheduler.shared.shouldOfferCoachReminders(before: before, after: after) else { return }
        askReminders = true
    }

    private func startNaming(_ kind: PlanEditorNaming) {
        naming = kind
        newName = ""
        isNaming = true
    }

    /// Adds the named day type or check, then opens it.
    private func add() {
        let route: PlanEditorRoute?
        switch naming {
        case .dayType:
            route = PlanEditorData.addDayType(named: newName, app: app).map { PlanEditorRoute.dayType($0) }
        case .check:
            route = .check(PlanEditorData.addCheck(named: newName, app: app))
        }
        guard let route else { return }
        Task { @MainActor in
            // Let the alert close before the page is pushed.
            try? await Task.sleep(for: .milliseconds(350))
            pushed = route
        }
    }

    private func copyExport() {
        Clipboard.copy(exportText)
        app.toasts.show("Goals & plan copied", symbol: "doc.on.doc.fill")
    }

    private func copyForAI() {
        Clipboard.copy(PlanEditorData.aiText(app: app, includeHealth: includesHealth))
        app.toasts.show("Copied – paste it into your AI", symbol: "doc.on.clipboard.fill")
    }
}

/// A page pushed from the plan editor right after adding its item.
enum PlanEditorRoute: Hashable {
    case dayType(String)
    case check(String)
    case longTerm
}

/// The sheets the plan editor opens itself (one at a time).
enum PlanEditorSheet: Identifiable {
    /// `PhaseSheet` (nil = a new phase).
    case phase(String?)
    /// The goals & settings import (`ImportView`).
    case importSettings

    var id: String {
        switch self {
        case .phase(let id): "phase-" + (id ?? "new")
        case .importSettings: "import-settings"
        }
    }
}

/// What the "Add …" alert names.
enum PlanEditorNaming {
    case dayType, check

    var title: String { self == .dayType ? "New Day Type" : "New Daily Check" }
    var placeholder: String { self == .dayType ? "Name, e.g. Gym" : "Name, e.g. Creatine" }
}
