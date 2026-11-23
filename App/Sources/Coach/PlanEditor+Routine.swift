import SwiftUI
import BinisoftKit
import NinaCore

// The plan editor's pages for measuring, adjustments, protein per meal and the long-term goal.
// Each edits a copy and saves it when you go back (one toast with Undo).

/// Weigh-in time and morning cutoff, the check-in weekday, weekly and full-set tape sites and the
/// full-set interval, two readings, the body-fat method and interval, the side and the thigh landmark.
struct PlanEditorMeasuringView: View {
    @Environment(AppModel.self) private var app
    @State private var routine = CoachPlan.Routine()
    @State private var original: CoachPlan.Routine?

    var body: some View {
        Form {
            timesSection
            weeklySection
            fullSection
            bodyFatSection
            optionsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Measuring")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private var timesSection: some View {
        Section {
            DatePicker("Weigh-in reminder", selection: clock($routine.weighInMinutes), displayedComponents: .hourAndMinute)
            DatePicker("Morning weights until", selection: clock($routine.morningCutoffMinutes), displayedComponents: .hourAndMinute)
            Picker("Weekly check-in", selection: $routine.checkInWeekday) {
                ForEach(1...7, id: \.self) { (weekday: Int) in
                    Text(PlanEditorMeasuringView.weekdayNames[weekday - 1]).tag(weekday)
                }
            }
        } header: {
            Text("Weigh-in and Check-in")
        } footer: {
            Text("Weigh-ins before the cutoff count as morning weights: after the bathroom, before eating or drinking. The weekly sites are due on the check-in day.")
        }
    }

    private var weeklySection: some View {
        Section {
            ForEach(BodySite.mainSites) { (site: BodySite) in
                Toggle(site.title, isOn: siteBinding(site, in: $routine.weeklySites))
            }
        } header: {
            Text("Every Week")
        } footer: {
            Text("Usually the waist: one reading, a second one when it moved more than 1 cm.")
        }
    }

    private var fullSection: some View {
        Section {
            Stepper(fullEveryTitle, value: $routine.fullEveryWeeks, in: 1...26)
            Toggle("Two readings per site", isOn: $routine.twoReadings)
            ForEach(BodySite.mainSites) { (site: BodySite) in
                Toggle(site.title, isOn: siteBinding(site, in: $routine.fullSites))
            }
        } header: {
            Text("Full Set")
        } footer: {
            Text("Also when a phase starts or ends and at its review weight. A full set counts as that week's weekly measurement.")
        }
    }

    private var bodyFatSection: some View {
        Section {
            Picker("Method", selection: $routine.bodyFatMethod) {
                Text("Automatic").tag(BodyMethod?.none)
                ForEach(BodyMethod.allCases) { (method: BodyMethod) in
                    Text(method.title).tag(BodyMethod?.some(method))
                }
            }
            Stepper(bodyFatEveryTitle, value: $routine.bodyFatEveryWeeks, in: 1...52)
        } header: {
            Text("Body Fat")
        } footer: {
            Text("Pick one method you can repeat under the same conditions. Automatic follows the most accurate method with at least two values.")
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("Side", selection: $routine.side) {
                ForEach(BodySide.allCases) { (side: BodySide) in
                    Text(PlanEditorMeasuringView.sideTitle(side)).tag(side)
                }
            }
            TextField("Thigh landmark, e.g. 20 cm above the kneecap", text: $routine.thighMark)
        } header: {
            Text("Arm, Thigh and Calf")
        } footer: {
            Text("Always the same side and the same spot. Without a landmark the thigh is measured halfway between hip crease and kneecap.")
        }
    }

    private var fullEveryTitle: String { PlanEditorMeasuringView.everyTitle(routine.fullEveryWeeks) }
    private var bodyFatEveryTitle: String { PlanEditorMeasuringView.everyTitle(routine.bodyFatEveryWeeks) }

    /// "Every week", "Every 4 weeks".
    static func everyTitle(_ weeks: Int) -> String { weeks == 1 ? "Every week" : "Every \(weeks) weeks" }

    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func sideTitle(_ side: BodySide) -> String {
        switch side {
        case .right: "Right"
        case .left: "Left"
        case .both: "Both"
        }
    }

    private func clock(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: { () -> Date in DayKey.today().date(minutes: minutes.wrappedValue) },
            set: { (date: Date) in minutes.wrappedValue = ClockTime.minutes(of: date) }
        )
    }

    /// A site on or off; new ones go to the end, so the order of the measure sheet stays.
    private func siteBinding(_ site: BodySite, in sites: Binding<[BodySite]>) -> Binding<Bool> {
        Binding<Bool>(
            get: { sites.wrappedValue.contains(site) },
            set: { (isOn: Bool) in
                var list = sites.wrappedValue.filter { $0 != site }
                if isOn { list.append(site) }
                sites.wrappedValue = list
            }
        )
    }

    private func load() {
        guard original == nil else { return }
        let stored = PlanEditorData.storedPlan(app).routine
        routine = stored
        original = stored
    }

    private func save() {
        guard let original, routine != original else { return }
        PlanEditorData.saveRoutine(routine, app: app)
        self.original = routine
    }
}

/// How the weekly check-in adjusts calories: the step, the window and the lock.
struct PlanEditorAdjustView: View {
    @Environment(AppModel.self) private var app
    @State private var adjust = CoachPlan.Adjust()
    @State private var original: CoachPlan.Adjust?

    var body: some View {
        Form {
            Section {
                Stepper(smallestTitle, value: $adjust.stepMin, in: 50...300, step: 25)
                Stepper(largestTitle, value: $adjust.stepMax, in: 50...400, step: 25)
            } header: {
                Text("Step")
            } footer: {
                Text("One change moves every day type by the same calories, so the differences between them stay.")
            }
            Section {
                Stepper(firstTitle, value: $adjust.windowMinDays, in: 7...28, step: 7)
                Stepper(windowTitle, value: $adjust.windowMaxDays, in: 7...42, step: 7)
                Stepper(lockTitle, value: $adjust.lockDays, in: 0...42, step: 7)
            } header: {
                Text("Timing")
            } footer: {
                Text("A change is only proposed after two check-ins in a row outside your range, when you logged most days – and you always decide.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Adjustments")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private var smallestTitle: String { "At least \(Fmt.number(adjust.stepMin)) kcal" }
    private var largestTitle: String { "At most \(Fmt.number(adjust.stepMax)) kcal" }
    private var firstTitle: String { "Weigh-ins over \(adjust.windowMinDays) days first" }
    private var windowTitle: String { "Looks back up to \(adjust.windowMaxDays) days" }
    private var lockTitle: String { adjust.lockDays > 0 ? "\(adjust.lockDays) days between changes" : "No pause between changes" }

    private func load() {
        guard original == nil else { return }
        let stored = PlanEditorData.storedPlan(app).adjust
        adjust = stored
        original = stored
    }

    private func save() {
        guard let original, adjust != original else { return }
        PlanEditorData.saveAdjust(adjust, app: app)
        self.original = adjust
    }
}

/// Protein per eating occasion: the minimum and maximum per meal, how many a day, and which meals count.
struct PlanEditorProteinView: View {
    @Environment(AppModel.self) private var app
    @State private var protein = CoachPlan.Protein()
    @State private var original: CoachPlan.Protein?

    var body: some View {
        Form {
            Section {
                Stepper(minimumTitle, value: $protein.mealMin, in: 0...100, step: 5)
                Stepper(maximumTitle, value: $protein.mealMax, in: 0...150, step: 5)
                Stepper(countTitle, value: $protein.count, in: 0...8)
            } footer: {
                Text(automaticHint)
            }
            Section {
                ForEach(app.settings.meals) { (meal: MealSlot) in
                    Toggle("\(meal.emoji) \(meal.name)", isOn: mealBinding(meal.id))
                }
            } header: {
                Text("Meals That Count")
            } footer: {
                Text("None ticked: every meal counts. A meal header shows a protein pill, filled once it reaches the minimum.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Protein per Meal")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private var minimumTitle: String {
        protein.mealMin > 0 ? "At least \(Fmt.number(protein.mealMin)) g a meal" : "Minimum: automatic"
    }

    private var maximumTitle: String {
        protein.mealMax > 0 ? "At most \(Fmt.number(protein.mealMax)) g" : "No maximum"
    }

    private var countTitle: String {
        protein.count > 0 ? "\(protein.count) protein meal\(protein.count == 1 ? "" : "s") a day" : "One per meal that counts"
    }

    private var automaticHint: String {
        let weight = app.settings.bodyWeightKg ?? 0
        let automatic = CoachPlan.Protein().minimum(weightKg: weight)
        guard automatic > 0 else { return "Automatic: 0.4 g per kg body weight per meal." }
        return "Automatic: 0.4 g per kg body weight – \(Fmt.number(automatic)) g a meal for you."
    }

    private func mealBinding(_ id: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { protein.meals.contains(id) },
            set: { (isOn: Bool) in
                var meals = protein.meals.filter { $0 != id }
                if isOn { meals.append(id) }
                protein.meals = meals
            }
        )
    }

    private func load() {
        guard original == nil else { return }
        let stored = PlanEditorData.storedPlan(app).protein
        protein = stored
        original = stored
    }

    private func save() {
        guard let original, protein != original else { return }
        PlanEditorData.saveProtein(protein, app: app)
        self.original = protein
    }
}

/// The long-term body goal: weight, body fat, waist, an optional date and a note in your words.
struct PlanEditorLongTermView: View {
    @Environment(AppModel.self) private var app
    @State private var goal = CoachPlan.LongTerm()
    @State private var original: CoachPlan.LongTerm?
    @State private var hasDate = false
    @State private var date = Date()

    var body: some View {
        Form {
            Section {
                PlanEditorAmountRow(title: "Weight", value: $goal.weightKg, unit: "kg", decimals: 1)
                PlanEditorAmountRow(title: "Body fat", value: $goal.bodyFat, unit: "%", decimals: 1)
                PlanEditorAmountRow(title: "Waist", value: $goal.waistCm, unit: "cm", decimals: 1)
            } footer: {
                Text("0 = no goal for that number. This is separate from the target weight of your current phase.")
            }
            Section {
                Toggle("By a date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                TextField("In your words, e.g. leaner and stronger", text: $goal.note, axis: .vertical)
            }
            issuesSection
        }
        .formStyle(.grouped)
        .navigationTitle("Long-Term Goal")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private var issues: [BodyGoalIssue] { BodyGoalIssue.check(goal, sex: app.settings.body.sex) }

    @ViewBuilder
    private var issuesSection: some View {
        if !issues.isEmpty {
            Section {
                ForEach(issues) { (issue: BodyGoalIssue) in
                    Label(issue.message, systemImage: issue.isWarning ? "exclamationmark.triangle" : "xmark.octagon")
                        .foregroundStyle(issue.isWarning ? Color.orange : Color.red)
                }
            } footer: {
                Text("A goal with a number out of range isn't saved.")
            }
        }
    }

    private var edited: CoachPlan.LongTerm {
        var copy = goal
        copy.date = hasDate ? DayKey(date: date) : nil
        return copy
    }

    private func load() {
        guard original == nil else { return }
        let stored = PlanEditorData.storedPlan(app).longTerm
        goal = stored
        original = stored
        hasDate = stored.date != nil
        if let day = stored.date { date = day.date() }
    }

    private func save() {
        let updated = edited
        guard let original, updated != original else { return }
        if issues.contains(where: { !$0.isWarning }) {
            app.toasts.show("Long-term goal not saved – a number is out of range", symbol: "exclamationmark.triangle.fill")
            return
        }
        PlanEditorData.saveLongTerm(updated, app: app)
        self.original = updated
    }
}
