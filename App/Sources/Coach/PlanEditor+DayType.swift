import SwiftUI
import BinisoftKit
import NinaCore

/// One day type: name and emoji, its schedule (fixed weekdays, flexible n per week, or the default
/// for all other days) and its targets in the running phase ("Same as baseline" or its own, in
/// grams or %). Saved when you go back; changed targets start today (a new revision).
struct PlanEditorDayTypeView: View {
    let typeID: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var plan = CoachPlan()
    @State private var type = CoachPlan.DayType(id: "", name: "", schedule: .flexible)
    @State private var original: CoachPlan.DayType?
    @State private var ownTargets = false
    @State private var originalOwn = false
    @State private var targets = DailyTargets.standard
    @State private var originalTargets = DailyTargets.standard
    @State private var loaded = false
    @State private var deleted = false

    var body: some View {
        Form {
            if loaded {
                nameSection
                scheduleSection
                targetsSection
                PlanEditorHealthWorkoutsSection(workouts: $type.workouts)
                deleteSection
            } else {
                Text("This day type isn't in your plan any more.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private var title: String {
        let name = type.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Day Type" : name
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Name", text: $type.name)
            TextField("Emoji", text: $type.emoji)
        } footer: {
            Text(emojiHint)
        }
    }

    private var emojiHint: String {
        let suggested = CoachPlan.DayType.suggestedEmoji(for: type.name)
        guard type.emoji.trimmingCharacters(in: .whitespaces).isEmpty, !suggested.isEmpty else {
            return "One emoji, shown on Today and in the week strip."
        }
        return "Without an emoji Nina shows \(suggested)."
    }

    private var scheduleSection: some View {
        Section {
            Picker("Schedule", selection: $type.schedule) {
                ForEach(scheduleOptions) { (option: CoachPlan.Schedule) in
                    Text(scheduleTitle(option)).tag(option)
                }
            }
            scheduleDetail
        } header: {
            Text("When")
        } footer: {
            Text(scheduleFooter)
        }
    }

    @ViewBuilder
    private var scheduleDetail: some View {
        switch type.schedule {
        case .fixed:
            PlanEditorWeekdayChips(days: $type.weekdays)
        case .flexible:
            Stepper(perWeekTitle, value: $type.perWeek, in: 0...7)
        case .default:
            EmptyView()
        }
    }

    private var perWeekTitle: String {
        type.perWeek > 0 ? "About \(type.perWeek) per week" : "No weekly count"
    }

    /// The default schedule only while no other day type is the default.
    private var scheduleOptions: [CoachPlan.Schedule] {
        let otherDefault = plan.dayTypes.contains { $0.id != typeID && $0.schedule == .default }
        return CoachPlan.Schedule.allCases.filter { $0 != .default || !otherDefault || type.schedule == .default }
    }

    private func scheduleTitle(_ schedule: CoachPlan.Schedule) -> String {
        switch schedule {
        case .fixed: "Fixed weekdays"
        case .flexible: "Flexible"
        case .default: "All other days"
        }
    }

    private var scheduleFooter: String {
        switch type.schedule {
        case .fixed:
            "On these weekdays. When two day types share a weekday, the first in the list wins."
        case .flexible:
            PlanEditorWording.flexibleFooter
        case .default:
            "Every day no other day type claims – usually Rest."
        }
    }

    @ViewBuilder
    private var targetsSection: some View {
        if let phase = plan.activePhase(on: app.today) {
            Section {
                Toggle("Same as baseline", isOn: sameAsBaseline)
                if ownTargets {
                    PlanEditorTargetsFields(targets: $targets, weightKg: app.settings.bodyWeightKg ?? 0)
                }
            } header: {
                Text("Targets in \(PlanEditorData.phaseName(phase))")
            } footer: {
                PlanEditorWeekFooter(plan: draftPlan, day: app.today, unit: app.energyUnit,
                                     note: "Changes start today; earlier days keep their targets.")
            }
        } else {
            Section {
                Text("Targets per day type belong to a phase. Start a phase to set them.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sameAsBaseline: Binding<Bool> {
        Binding<Bool>(get: { !ownTargets }, set: { (same: Bool) in ownTargets = !same })
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Day Type", systemImage: "trash", role: .destructive) {
                deleted = true
                PlanEditorData.deleteDayType(typeID, app: app)
                dismiss()
            }
        } footer: {
            Text("Days you marked with it go back to the schedule. Daily checks only on these days are due every day again.")
        }
    }

    /// The plan with this page's changes, for the live week line.
    private var draftPlan: CoachPlan {
        let updated = PlanEdits.updatingDayType(type, in: plan)
        return PlanEdits.settingTargets(ownTargets ? targets : nil, forType: typeID, in: updated, on: app.today)
    }

    // MARK: Loading and saving

    private func load() {
        guard !loaded else { return }
        let stored = PlanEditorData.storedPlan(app)
        guard let found = stored.dayType(id: typeID) else { return }
        plan = stored
        type = found
        original = found
        let own = stored.revision(on: app.today)?.byType[typeID]
        ownTargets = own != nil
        originalOwn = own != nil
        targets = own ?? PlanEditorData.startingTargets(plan: stored, app: app)
        originalTargets = targets
        loaded = true
    }

    private func save() {
        guard loaded, !deleted, let original else { return }
        let targetsChanged = ownTargets != originalOwn || (ownTargets && targets != originalTargets)
        guard type != original || targetsChanged else { return }
        PlanEditorData.saveDayType(type, targets: ownTargets ? targets : nil, targetsChanged: targetsChanged, app: app)
        self.original = type
        originalOwn = ownTargets
        originalTargets = targets
    }
}

/// The running phase's baseline: the targets of days without their own (all days without day types).
struct PlanEditorBaselineView: View {
    @Environment(AppModel.self) private var app
    @State private var targets = DailyTargets.standard
    @State private var original: DailyTargets?
    @State private var phaseName = ""

    var body: some View {
        Form {
            if original != nil {
                Section {
                    PlanEditorTargetsFields(targets: $targets, weightKg: app.settings.bodyWeightKg ?? 0)
                } header: {
                    Text("Targets in \(phaseName)")
                } footer: {
                    Text("For days without targets of their own. Changes start today; earlier days keep their targets.")
                }
            } else {
                Text("Targets belong to a phase. Start a phase to set them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Baseline")
        .inlineNavigationTitle()
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private func load() {
        guard original == nil else { return }
        let plan = PlanEditorData.storedPlan(app)
        guard let phase = plan.activePhase(on: app.today) else { return }
        phaseName = PlanEditorData.phaseName(phase)
        targets = PlanEditorData.startingTargets(plan: plan, app: app)
        original = targets
    }

    private func save() {
        guard let original, targets != original else { return }
        PlanEditorData.saveBaseline(targets, app: app)
        self.original = targets
    }
}
