import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// What Settings does differently in the Mac Settings window (`SettingsWindowContent`): Import &
/// Export opens as that window's own sheet, Replay the Tour starts in the main window, and Goals
/// leaves out its link to My Plan (the window has a My Plan tab). Nil everywhere else.
struct SettingsWindowActions {
    var importData: @MainActor () -> Void
    var replayTour: @MainActor () -> Void
}

private struct SettingsWindowActionsKey: EnvironmentKey {
    static let defaultValue: SettingsWindowActions? = nil
}

extension EnvironmentValues {
    var settingsWindowActions: SettingsWindowActions? {
        get { self[SettingsWindowActionsKey.self] }
        set { self[SettingsWindowActionsKey.self] = newValue }
    }
}

/// Settings: goals & plan, diary preferences, Apple Health, reminders, Thalia, appearance, help,
/// iCloud & data, import/export, the app log, about.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.settingsWindowActions) private var windowActions
    @State private var hintsReset = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    goals
                } label: {
                    LabeledContent {
                        Text(Fmt.energy(app.settings.targets(for: app.today).energy, unit: .kcal))
                    } label: {
                        Label(windowActions == nil ? "Goals & Plan" : "Goals", systemImage: "target")
                    }
                }
                NavigationLink {
                    MealsSettingsView()
                } label: {
                    Label("Meals", systemImage: "fork.knife")
                }
            }

            Section("Diary") {
                Picker("Food names", selection: Binding(get: { app.settings.language }, set: { value in
                    app.updateSettings { $0.foodLanguage = value.rawValue }
                })) {
                    ForEach(FoodLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Picker("Day starts at", selection: Binding(get: { app.settings.dayStartHour }, set: { value in
                    app.updateSettings { $0.dayStartHour = value }
                })) {
                    Text("Midnight").tag(0)
                    ForEach(1...5, id: \.self) { hour in Text("\(hour):00").tag(hour) }
                }
                Picker("Water glass", selection: Binding(get: { app.settings.waterGlass }, set: { value in
                    app.updateSettings { $0.waterGlass = value }
                })) {
                    ForEach([150.0, 200, 250, 300, 330, 500], id: \.self) { amount in Text(Fmt.milliliters(amount)).tag(amount) }
                }
            }

            #if os(iOS)
            Section {
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    LabeledContent {
                        Text(app.health.isConnected ? "On" : "Off")
                    } label: {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                }
                NavigationLink {
                    RemindersView()
                } label: {
                    Label("Reminders", systemImage: "bell.badge")
                }
            }
            #else
            Section {
                NavigationLink {
                    RemindersView()
                } label: {
                    Label("Reminders", systemImage: "bell.badge")
                }
            }
            #endif

            #if os(macOS)
            NinaMenuBarSettingsSection()
            #endif

            ThaliaSection()

            Section {
                AppearancePicker()
            }

            Section {
                Button("Replay the Tour", systemImage: "graduationcap", action: replayTour)
                Button(hintsReset ? "Hints Come Back at the Next Launch" : "Show Hints Again", systemImage: "lightbulb") {
                    BinisoftTips.requestReset()
                    // The coach's one-time tips (Body page, measuring guide) come back too.
                    for key in ["nina.body.tip.highCarb", "nina.body.tip.glycogen", "nina.coach.measureGuideSeen"] {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                    hintsReset = true
                }
                .disabled(hintsReset)
            } header: {
                Text("Help")
            } footer: {
                Text("The tour runs on a practice day, so nothing you do there touches your diary.")
            }

            SyncStatusSection(
                monitor: app.sync,
                footer: "\(AppInfo.name) has no servers or accounts. Your diary, foods and meals sync through your own private iCloud between iPhone, iPad, Mac and Apple Watch."
            ) {
                DataLocationView(sections: dataSections, monitor: app.sync)
            }

            Section("Your data") {
                Button("Import & Export…", systemImage: "square.and.arrow.up.on.square", action: openImport)
                NavigationLink {
                    TrashView()
                } label: {
                    Label("Recently Deleted", systemImage: "trash")
                }
                NavigationLink {
                    HiddenFoodsView()
                } label: {
                    Label("Hidden Foods", systemImage: "eye.slash")
                }
            }

            Section {
                NavigationLink {
                    LogView(appName: AppInfo.name, mode: app.mode)
                } label: {
                    Label("App Log", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("If something doesn't work: App Log → Copy log, and paste it into the chat.")
            }

            Section("About") {
                LabeledContent("Version", value: AppVersion.main.display)
                LabeledContent("Storage", value: app.mode.title)
                LabeledContent("Built-in foods", value: "\(app.library.catalog.foods.count)")
                NavigationLink {
                    AboutDataView()
                } label: {
                    Text("Food data and licences")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }

    /// Goals & Plan; in the Mac Settings window just the goals (My Plan is a tab there).
    @ViewBuilder
    private var goals: some View {
        if windowActions == nil {
            GoalsView(showsDone: false)
        } else {
            GoalsView(showsDone: false, showsPlanLink: false, title: "Goals")
        }
    }

    private func replayTour() {
        if let windowActions {
            windowActions.replayTour()
        } else {
            app.startTour()
        }
    }

    private func openImport() {
        if let windowActions {
            windowActions.importData()
        } else {
            app.present(.importData(nil))
        }
    }

    /// "Where your data lives": the kit's facts with Nina's backup in place of its "CSV of
    /// everything" (Nina's CSVs don't hold photos, check-ins, water or routines).
    private var dataSections: [DataSection] {
        var sections = DataSection.standard(appName: AppInfo.name, dataNoun: "diary, foods and meals").map { section in
            DataSection(section.title, section.facts.map { fact in
                fact.title == "Export" ? Self.backupFact : fact
            })
        }
        sections.insert(DataSection("Apple Health", [
            DataFact("heart.fill", "Written to Health, on this iPhone", "If you allow it, \(AppInfo.name) writes what you eat and drink to Apple Health on this iPhone. Health keeps it in its own encrypted store."),
            DataFact("scalemass", "Read live, never synced by \(AppInfo.name)", "Weight and active energy from Health are read on each device when needed and never stored in \(AppInfo.name)'s iCloud."),
        ]), at: 1)
        sections.insert(DataSection("Barcodes", [
            DataFact("barcode.viewfinder", "Open Food Facts", "Scanning sends only the barcode number to Open Food Facts to look the product up. Nothing about you is sent."),
        ]), at: 2)
        sections.insert(DataSection("Thalia", [
            DataFact("arrow.up.forward.app", "Day values, on this device", "With Send to Thalia on, \(AppInfo.name) puts each day's calories, protein, carbs, fat and water of the last 62 days into a folder on this device that Binisoft's apps share, where Thalia picks them up and keeps them in its own iCloud. Nothing from Apple Health goes there."),
        ]), at: 3)
        return sections
    }

    private static let backupFact = DataFact(
        "externaldrive", "Back up",
        "Import & Export → Back Up Everything saves all your \(AppInfo.name) data (not Apple Health) in one file; the CSV exports cover goals & plan, foods, diary, meals and weight & body."
    )
}

/// Goals & Plan: a prominent link to the plan editor, the calculator with every step explained,
/// your targets, training days and priorities. With a running phase the goal, pace and targets
/// come from the plan: the calculator's result goes to the phase ("Use for This Phase"), and
/// saving leaves the plan's mirrored profile fields alone.
struct GoalsView: View {
    let showsDone: Bool
    /// The "My Plan" link at the top (off when the plan editor opens this page).
    let showsPlanLink: Bool
    /// The page title (default: "Goals & Plan", or "Body & Calculator" without the plan link).
    let title: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sex: Sex = .unspecified
    @State private var birthYear = 1990
    @State private var birthKnown = false
    @State private var height = 172.0
    @State private var heightKnown = false
    @State private var weight = 72.0
    @State private var activity: ActivityLevel = .light
    @State private var goal: WeightGoal = .maintain
    @State private var rate = 0.5
    @State private var split: MacroSplit = .balanced
    @State private var targets: DailyTargets = .standard
    @State private var trainingOn = false
    @State private var trainingDays = Weekdays([1, 3, 5])
    @State private var trainingExtra = 300.0
    @State private var focus: [Nutrient] = [.protein, .carbs, .fat]
    @State private var bonus = 0.0
    @State private var targetWeight = 0.0
    /// The running phase when the page was loaded: goal, pace and targets then come from the plan.
    @State private var phase: CoachPlan.Phase?
    @State private var showPlan = false
    @State private var loaded = false

    init(showsDone: Bool, showsPlanLink: Bool = true, title: String? = nil) {
        self.showsDone = showsDone
        self.showsPlanLink = showsPlanLink
        self.title = title
    }

    private var profile: BodyProfile {
        BodyProfile(sex: sex, age: GoalCalculator.age(birthYear: birthYear), heightCm: height, weightKg: weight,
                    activity: activity, goal: goal, ratePerWeek: rate)
    }

    private var plan: GoalPlan { GoalCalculator.plan(profile, split: split) }

    var body: some View {
        Form {
            if showsPlanLink {
                planSection
            }
            calculateSection
            stepsSection
            if phase == nil {
                targetsSection
                trainingSection
            }
            focusSection
            #if os(iOS)
            activitySection
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle(title ?? (showsPlanLink ? "Goals & Plan" : "Body & Calculator"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(showsDone ? "Done" : "Save") {
                    saveAll()
                    if showsDone { dismiss() }
                }
            }
        }
        .background { escapeSaves }
        .navigationDestination(isPresented: $showPlan) {
            PlanEditorView(showsDone: false)
        }
        // Loaded on every appearance: the plan editor (pushed from here) can change the plan and the body data.
        .onAppear(perform: load)
        .onDisappear { if loaded, !showsDone { saveAll() } }
        // In the Mac Settings window its toasts show here (in a sheet, the sheet shows them).
        .ownToasts(app.toasts)
    }

    /// Mac sheet: Esc saves and closes, like Done (a sheet closes on Esc only through a button).
    @ViewBuilder
    private var escapeSaves: some View {
        #if os(macOS)
        if showsDone {
            Button("Save and Close") {
                saveAll()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        #endif
    }

    // MARK: Sections

    private var planSection: some View {
        Section {
            Button {
                saveAll()
                showPlan = true
            } label: {
                GoalsPlanLink(detail: planDetail)
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Phases with dates, day types with their own calories, daily checks, measuring and a weekly check-in. Set it up here or import it from your AI.")
        }
    }

    private var planDetail: String {
        let coach = app.settings.plan
        guard coach.isSetUp else { return "Not set up yet" }
        if let running = coach.activePhase(on: app.today) {
            return "\(PlanEditorData.phaseName(running)) · \(PlanEditorData.phaseStatus(running, plan: coach, today: app.today).lowercased())"
        }
        let phases = coach.phases.count, types = coach.dayTypes.count
        return "\(phases) \(phases == 1 ? "phase" : "phases") · \(types) day \(types == 1 ? "type" : "types")"
    }

    private var calculateSection: some View {
        Section {
            Picker("Sex (for the formula)", selection: $sex) {
                ForEach(Sex.allCases) { Text($0.title).tag($0) }
            }
            Stepper(birthTitle, value: birthYearValue, in: 1920...2015)
            Stepper(heightTitle, value: heightValue, in: 120...230)
            HealthHeightHint(heightCm: heightKnown ? height : 0)
            Stepper("Weight \(Fmt.number(weight, decimals: 1)) kg", value: $weight, in: 30...250, step: 0.5)
            Picker("Activity", selection: $activity) {
                ForEach(ActivityLevel.allCases) { level in
                    VStack(alignment: .leading) {
                        Text(level.title)
                        Text(level.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            goalRows
            Picker("Macro split", selection: $split) {
                ForEach(MacroSplit.presets) { preset in
                    Text("\(preset.name) · \(Int(preset.protein * 100))/\(Int(preset.carbs * 100))/\(Int(preset.fat * 100))").tag(preset)
                }
            }
        } header: {
            Text("Calculate for me")
        } footer: {
            Text(calculateFooter)
        }
    }

    @ViewBuilder
    private var goalRows: some View {
        if let phase {
            LabeledContent("Goal and pace", value: phaseGoalText(phase))
        } else {
            Picker("Goal", selection: $goal) {
                ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
            }
            if goal != .maintain {
                Stepper(paceTitle, value: paceValue, in: 0.05...1.0, step: 0.05)
                Text(paceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(targetWeight > 0 ? "Target weight \(Fmt.number(targetWeight, decimals: 1)) kg" : "Target weight (optional)",
                        value: $targetWeight, in: 0...250, step: 0.5)
            }
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(plan.steps) { step in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Fmt.number(step.value)) \(step.unit)").monospacedDigit()
                    }
                    Text(step.formula).font(.caption).foregroundStyle(.secondary)
                }
            }
            if plan.hitFloor {
                Label("Raised to a safe minimum – going lower needs medical guidance.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(action: useCalculatedTargets) {
                // An explicit white icon: in a form row the label's icon takes the accent colour,
                // which disappears on the green button.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(phase == nil ? "Use These Targets" : "Use for This Phase")
                }
                .foregroundStyle(.white)
            }
            .primaryActionStyle()
        } header: {
            Text("How it's calculated")
        } footer: {
            if phase != nil {
                Text("From today, as your phase's baseline. Every day type moves by the same calories, so the differences between them stay.")
            }
        }
    }

    private var targetsSection: some View {
        Section {
            targetRow("Calories", value: $targets.energy, unit: "kcal", step: 50)
            targetRow("Protein", value: $targets.protein, unit: "g", step: 5)
            targetRow("Carbohydrates", value: $targets.carbs, unit: "g", step: 5)
            targetRow("Fat", value: $targets.fat, unit: "g", step: 2)
            targetRow("Fiber", value: $targets.fiber, unit: "g", step: 1)
            targetRow("Sugar (max)", value: $targets.sugarMax, unit: "g", step: 5)
            targetRow("Saturated fat (max)", value: $targets.saturatedFatMax, unit: "g", step: 1)
            targetRow("Salt (max)", value: Binding(get: { (targets.sodiumMax * 2.5 / 100).rounded() / 10 }, set: { targets.sodiumMax = $0 / 2.5 * 1000 }), unit: "g", step: 0.5)
            targetRow("Water", value: $targets.water, unit: "ml", step: 250)
            Text("Your split: \(targets.split.percentText) % of calories from protein / carbs / fat.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Your daily targets")
        } footer: {
            Text("Change any number by hand – the calculator is just a starting point.")
        }
    }

    private var trainingSection: some View {
        Section {
            Toggle("Different targets on training days", isOn: $trainingOn)
            if trainingOn {
                PlanEditorWeekdayChips(days: $trainingDays)
                Stepper("+\(Fmt.number(trainingExtra)) kcal, mostly carbs", value: $trainingExtra, in: 50...1500, step: 50)
            }
        } header: {
            Text("Training days")
        } footer: {
            Text("On these weekdays your calories go up and the extra comes 70 % from carbs, 30 % from protein. A plan's day types (My Plan) replace this.")
        }
    }

    private var focusSection: some View {
        Section {
            ForEach(Nutrient.allCases.filter { $0 != .energy && $0 != .water }, id: \.self) { nutrient in
                Button {
                    if let index = focus.firstIndex(of: nutrient) {
                        focus.remove(at: index)
                    } else if focus.count < 4 {
                        focus.append(nutrient)
                    }
                } label: {
                    HStack {
                        Text(nutrient.title).foregroundStyle(.primary)
                        Spacer()
                        if let index = focus.firstIndex(of: nutrient) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Brand.accent, in: .circle)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Shown first (your priorities)")
        } footer: {
            Text("Up to four nutrients, in this order, on Today, the watch and the widgets.")
        }
    }

    #if os(iOS)
    private var activitySection: some View {
        Section {
            Picker("Add burned calories", selection: $bonus) {
                Text("No").tag(0.0)
                Text("Half").tag(0.5)
                Text("All").tag(1.0)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Activity from Apple Health")
        } footer: {
            Text("Adds this share of today's active energy to your budget. Half is the usual choice – watches tend to overestimate.")
        }
    }
    #endif

    private func targetRow(_ title: String, value: Binding<Double>, unit: String, step: Double) -> some View {
        Stepper(value: value, in: 0...20000, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Fmt.number(value.wrappedValue, decimals: step < 1 ? 1 : 0)) \(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Body data and pace

    private var birthTitle: String { birthKnown ? "Born \(String(birthYear))" : "Birth year – not set" }
    private var heightTitle: String { heightKnown ? "Height \(Fmt.number(height)) cm" : "Height – not set" }

    private var birthYearValue: Binding<Int> {
        Binding<Int>(get: { birthYear }, set: { (year: Int) in
            birthYear = year
            birthKnown = true
        })
    }

    private var heightValue: Binding<Double> {
        Binding<Double>(get: { height }, set: { (centimeters: Double) in
            height = centimeters
            heightKnown = true
        })
    }

    private var calculateFooter: String {
        var text = "The standard method dietitians use (Mifflin–St Jeor). Every step with your numbers below."
        if phase != nil {
            text += " Goal and pace come from your running phase – change them in My Plan."
        }
        if !birthKnown || !heightKnown {
            text += "\n\nHeight and birth year are needed for the tape estimate, FFMI and the calorie formula."
        }
        return text
    }

    /// 0.05–1.0 kg a week in 0.05 steps.
    private var paceValue: Binding<Double> {
        Binding<Double>(get: { rate }, set: { (value: Double) in
            rate = min(1, max(0.05, (value * 20).rounded() / 20))
        })
    }

    private var paceTitle: String { "Pace \(Fmt.number(rate, decimals: 2)) kg a week" }

    /// "0.31 % of your weight a week · Slow (lean) gain", plus a calm caution when it's fast. The
    /// percentage uses the 7-day average (spec F2), else the weight above.
    private var paceNote: String {
        let bodyWeight: Double = app.settings.bodyWeightKg ?? weight
        var parts: [String] = []
        if let percent = WeightSignal.percent(rate, of: bodyWeight) {
            parts.append("\(Fmt.number(percent, decimals: 2)) % of your weight a week")
        }
        if let label = CoachPlan.Phase.rateLabel(goal: goal, rate: rate...rate) { parts.append(label) }
        var text = parts.joined(separator: " · ")
        if let caution = CoachPlan.Phase.rateCaution(goal: goal, rate: rate...rate, weightKg: bodyWeight) {
            text += text.isEmpty ? caution : "\n" + caution
        }
        return text
    }

    private func phaseGoalText(_ phase: CoachPlan.Phase) -> String {
        let range = phase.rateRange
        var text = "\(phase.goal.title)"
        if phase.goal != .maintain, range.upperBound > 0 {
            let low = Fmt.number(range.lowerBound, decimals: 2), high = Fmt.number(range.upperBound, decimals: 2)
            text += " · \(low == high ? low : "\(low)–\(high)") kg a week"
        }
        return text
    }

    // MARK: Loading and saving

    private func load() {
        let store = app.store
        let settings = store.settings
        let stored = store.profile()
        sex = settings.body.sex
        birthKnown = (stored?.birthYear ?? 0) > 0
        birthYear = birthKnown ? stored?.birthYear ?? 1990 : 1990
        heightKnown = (stored?.heightCm ?? 0) > 0
        height = heightKnown ? stored?.heightCm ?? 172 : 172
        weight = store.weights().last?.kilograms ?? app.health.latestWeight ?? app.settings.body.weightKg
        activity = settings.body.activity
        split = settings.macroSplit
        phase = settings.plan.activePhase(on: app.today)
        if let phase {
            goal = phase.goal
            rate = phase.rateMid > 0 ? min(1, max(0.05, phase.rateMid)) : 0.5
            targetWeight = phase.targetWeight
        } else {
            goal = settings.body.goal
            rate = settings.body.ratePerWeek > 0 ? min(1, max(0.05, settings.body.ratePerWeek)) : 0.5
            targetWeight = settings.targetWeight
        }
        targets = settings.targets
        trainingOn = settings.trainingTargets != nil
        if !settings.trainingDays.isEmpty { trainingDays = settings.trainingDays }
        if let training = settings.trainingTargets { trainingExtra = max(50, training.energy - settings.targets.energy) }
        focus = settings.focus
        bonus = settings.activityBonusShare
        loaded = true
    }

    private func useCalculatedTargets() {
        let calculated = plan.targets
        guard phase == nil else {
            saveAll()
            PlanEditorData.applyCalculated(calculated, app: app)
            return
        }
        targets = calculated
        saveAll()
        app.toasts.show("Goal set: \(Fmt.energy(calculated.energy, unit: .kcal))", symbol: "target")
    }

    /// Writes the page into the profile. With a running phase the goal, pace, target weight and
    /// targets belong to the plan (its mirror), so only the body data and preferences are written.
    /// A birth year or height that was never set stays unset.
    private func saveAll() {
        let training: DailyTargets? = trainingOn ? {
            var copy = targets
            copy.energy += trainingExtra
            copy.carbs += (trainingExtra * 0.7 / 4).rounded()
            copy.protein += (trainingExtra * 0.3 / 4).rounded()
            return copy
        }() : nil
        let followsPlan = phase != nil
        let birth: Int? = birthKnown ? birthYear : nil
        let heightCm: Double? = heightKnown ? height : nil
        app.updateSettings { profile in
            profile.sex = sex.rawValue
            if let birth { profile.birthYear = birth }
            if let heightCm { profile.heightCm = heightCm }
            profile.activity = activity.rawValue
            profile.macroSplit = split.id
            profile.focusNutrients = focus.map(\.rawValue).joined(separator: ",")
            profile.activityBonusShare = bonus
            guard !followsPlan else { return }
            profile.goal = goal.rawValue
            profile.ratePerWeek = rate
            profile.targets = targets.encoded
            profile.trainingTargets = training?.encoded ?? ""
            profile.trainingDays = trainingOn ? trainingDays.encoded : ""
            profile.targetWeight = targetWeight
        }
    }
}

/// The prominent "My Plan" link at the top of Goals & Plan.
private struct GoalsPlanLink: View {
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Brand.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("My Plan")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

/// Settings → Thalia: "Send to Thalia" on this device, when Nina last wrote the day values
/// (docs/THALIA.md). Off empties the values once; on writes them all again at once.
private struct ThaliaSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let thalia = app.thalia
        Section {
            Toggle(isOn: Binding(get: { thalia.isOn }, set: { thalia.setDeliver($0) })) {
                Label("Send to Thalia", systemImage: "arrow.up.forward.app")
            }
            Text(thalia.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("Thalia")
        } footer: {
            Text("Thalia picks up the values as soon as you open Thalia on this device.")
        }
    }
}

/// The meals of the day: names, emoji and usual times; own meals like "Jause" or "Pre-workout".
/// Deleting an own meal that entries or routines still use asks first: move them to Snacks, or
/// keep them as they are (the diary lists them under "Other meal"). The toast's Undo brings the
/// meal back, and the moved entries and routines with it.
struct MealsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var meals: [MealSlot] = []
    @State private var removal: NinaMealRemoval?

    var body: some View {
        Form {
            Section {
                ForEach($meals) { $slot in
                    MealSlotRow(slot: $slot) { requestDelete(slot.id) }
                        .deleteDisabled(slot.isBuiltIn)
                }
                .onDelete { offsets in
                    if let index = offsets.first { requestDelete(meals[index].id) }
                }
                Button("Add a Meal", systemImage: "plus") {
                    meals.append(MealSlot(id: "meal-" + UUID().uuidString.prefix(8).lowercased(), name: "Jause", emoji: "🥪", minutes: 10 * 60))
                }
            } footer: {
                Text("The four standard meals can be renamed but not removed. Times are used to suggest the meal when you log and for reminders.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Meals")
        .onAppear { meals = app.settings.meals }
        .onDisappear(perform: save)
        // An Undo (or a sync) changed the stored meals: show them, unless something here is unsaved.
        .onChange(of: app.settings.meals) { old, new in
            if meals == old { meals = new }
        }
        .confirmationDialog(removal?.question ?? "", isPresented: removalShown, titleVisibility: .visible, presenting: removal) { removal in
            Button(removal.moveTitle) { remove(removal, moving: true) }
            Button(removal.keepTitle) { remove(removal, moving: false) }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removal.detail)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
    }

    private var removalShown: Binding<Bool> {
        Binding(get: { removal != nil }, set: { shown in
            if !shown { removal = nil }
        })
    }

    /// The list as it would be saved: empty names and emoji filled in.
    private var cleaned: [MealSlot] {
        meals.map { slot -> MealSlot in
            var copy = slot
            if copy.name.trimmingCharacters(in: .whitespaces).isEmpty { copy.name = MealSlot.defaults.first { $0.id == slot.id }?.name ?? "Meal" }
            if copy.emoji.isEmpty { copy.emoji = "🍽️" }
            return copy
        }
    }

    private func save() {
        let cleaned = self.cleaned
        guard cleaned != app.settings.meals else { return }
        app.updateSettings { $0.meals = MealSlot.encode(cleaned) }
    }

    /// An unused meal goes at once (with Undo); a used one asks first.
    private func requestDelete(_ id: String) {
        guard let slot = cleaned.first(where: { $0.id == id }), !slot.isBuiltIn else { return }
        let uses = MealSlotUses(mealID: id, app: app)
        let removal = NinaMealRemoval(slot: slot, entries: uses.entries.count, routines: uses.rules.count, meals: cleaned)
        if removal.isUsed {
            self.removal = removal
        } else {
            remove(removal, moving: false)
        }
    }

    /// Deletes the meal (saving the rest of the page with it); `moving` puts its entries and
    /// routines into Snacks. One toast, whose Undo restores the list and what moved.
    private func remove(_ removal: NinaMealRemoval, moving: Bool) {
        let before = cleaned
        let after = before.filter { $0.id != removal.slot.id }
        let mealID = removal.slot.id
        var movedEntries: [LogEntry] = []
        var movedRules: [PlanRule] = []
        if moving {
            let uses = MealSlotUses(mealID: mealID, app: app)
            movedEntries = uses.entries
            movedRules = uses.rules
            let target = removal.target.id
            for rule in uses.rules {
                rule.meal = target
                rule.touch()
            }
            // Saves the routines too.
            app.store.move(uses.entries, to: target)
        }
        meals = after
        app.updateSettings { $0.meals = MealSlot.encode(after) }
        let app = self.app
        let entries = movedEntries
        let rules = movedRules
        app.toasts.show(removal.toast(moved: moving), symbol: "trash.fill") {
            // Everything that moved was in this meal.
            for rule in rules {
                rule.meal = mealID
                rule.touch()
            }
            if !entries.isEmpty { app.store.move(entries, to: mealID) }
            // Saves the routines too.
            app.updateSettings { $0.meals = MealSlot.encode(before) }
        }
    }
}

/// One meal: emoji, name, usual time; on the Mac a delete button for own meals (iPhone and iPad
/// swipe to delete).
private struct MealSlotRow: View {
    @Binding var slot: MealSlot
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("🍽️", text: $slot.emoji)
                .frame(width: 36)
                .multilineTextAlignment(.center)
            TextField("Name", text: $slot.name)
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
            #if os(macOS)
            if !slot.isBuiltIn {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete Meal")
                .accessibilityLabel("Delete \(slot.name)")
            }
            #endif
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { DayKey.today().date(minutes: slot.minutes) },
            set: { slot.minutes = ClockTime.minutes(of: $0) }
        )
    }
}

/// The live entries (eaten and planned) and routines in a meal.
@MainActor
private struct MealSlotUses {
    let entries: [LogEntry]
    let rules: [PlanRule]

    init(mealID: String, app: AppModel) {
        let key = mealID
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.meal == key && $0.deletedAt == nil })
        entries = (try? app.container.mainContext.fetch(descriptor)) ?? []
        rules = app.store.planRules().filter { $0.meal == mealID }
    }
}

/// Catalog foods hidden from search, to bring back.
struct HiddenFoodsView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Food> { $0.isHidden && $0.deletedAt == nil }) private var hidden: [Food]

    var body: some View {
        List {
            ForEach(hidden) { food in
                HStack {
                    Text(food.name)
                    Spacer()
                    Button("Show Again") {
                        food.isHidden = false
                        food.touch()
                        app.store.save()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .overlay {
            if hidden.isEmpty {
                ContentUnavailableView("No hidden foods", systemImage: "eye", description: Text("Foods you hide from search show up here."))
            }
        }
        .navigationTitle("Hidden Foods")
    }
}

/// Where the built-in food values come from.
struct AboutDataView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Built-in foods") {
                Text("\(app.library.catalog.foods.count) everyday foods with English and German names. Most values are from the USDA National Nutrient Database for Standard Reference, Release 28 (U.S. Department of Agriculture, Agricultural Research Service) – public domain. A few Austrian and German staples use typical label values or are calculated from USDA ingredients; their detail page says so.")
            }
            Section("Barcodes") {
                Text("Barcode lookups use Open Food Facts (openfoodfacts.org), a free, collaborative database. Its data is available under the Open Database License (ODbL); © Open Food Facts contributors. Values entered by volunteers can be wrong – check the package.")
            }
            Section("Methods") {
                Text("Goals: Mifflin–St Jeor equation × activity factor (PAL), ±7,700 kcal per kg. Reference intakes: EU Regulation 1169/2011. Limits for sugar, saturated fat and salt: WHO. Badges: EU nutrition claims (Regulation 1924/2006), simplified.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Food Data")
    }
}
