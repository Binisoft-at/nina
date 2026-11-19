import SwiftUI
import BinisoftKit
import NinaCore

/// One daily check from the plan (a supplement): name, emoji and dose; when (anytime, with a meal,
/// at a time); on which days (every day, weekdays, day types); optional, reminder, and whether it
/// can move the scale. Saved when you go back.
struct PlanEditorCheckView: View {
    let checkID: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var plan = CoachPlan()
    @State private var check = CoachPlan.Check(id: "", name: "")
    @State private var original: CoachPlan.Check?
    @State private var deleted = false

    var body: some View {
        Form {
            if original != nil {
                nameSection
                timingSection
                daysSection
                optionsSection
                deleteSection
            } else {
                Text("This check isn't in your plan any more.")
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
        let name = check.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Daily Check" : name
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Name", text: $check.name)
            TextField("Emoji", text: $check.emoji)
            TextField("Dose, e.g. 3-5 g", text: $check.dose)
        } footer: {
            Text("As your plan writes it. Nina only shows it – it never suggests a supplement or a dose.")
        }
    }

    private var timingSection: some View {
        Section("When") {
            Picker("When", selection: timingKind) {
                ForEach(PlanEditorTimingKind.allCases) { (kind: PlanEditorTimingKind) in
                    Text(kind.title).tag(kind)
                }
            }
            timingDetail
        }
    }

    @ViewBuilder
    private var timingDetail: some View {
        switch check.timing {
        case .anytime:
            EmptyView()
        case .meal:
            Picker("Meal", selection: mealID) {
                ForEach(app.settings.meals) { (meal: MealSlot) in
                    Text("\(meal.emoji) \(meal.name)").tag(meal.id)
                }
            }
        case .time:
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
        }
    }

    private var daysSection: some View {
        Section {
            Picker("Days", selection: daysKind) {
                ForEach(PlanEditorDaysKind.allCases) { (kind: PlanEditorDaysKind) in
                    Text(kind.title).tag(kind)
                }
            }
            daysDetail
        } header: {
            Text("On Which Days")
        }
    }

    @ViewBuilder
    private var daysDetail: some View {
        switch check.days {
        case .daily:
            EmptyView()
        case .weekdays:
            PlanEditorWeekdayChips(days: weekdays)
        case .dayTypes:
            ForEach(plan.dayTypes) { (type: CoachPlan.DayType) in
                Toggle(PlanEditorData.typeLabel(type), isOn: typeBinding(type.id))
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Optional", isOn: $check.isOptional)
            Toggle("Remind me", isOn: $check.remind)
            Toggle("Can move the scale", isOn: $check.affectsWeight)
        } footer: {
            Text("Optional checks never count as missed. Can move the scale (like creatine): for 28 days after the first tick, a check-in waits before calling your weight “faster than planned”.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Check", systemImage: "trash", role: .destructive) {
                deleted = true
                PlanEditorData.deleteCheck(checkID, app: app)
                dismiss()
            }
        }
    }

    // MARK: Bindings

    private var timingKind: Binding<PlanEditorTimingKind> {
        Binding<PlanEditorTimingKind>(
            get: { () -> PlanEditorTimingKind in
                switch check.timing {
                case .anytime: return .anytime
                case .meal: return .meal
                case .time: return .time
                }
            },
            set: { (kind: PlanEditorTimingKind) in
                switch kind {
                case .anytime: check.timing = .anytime
                case .meal: check.timing = .meal(app.settings.meals.first?.id ?? "breakfast")
                case .time: check.timing = .time(8 * 60)
                }
            }
        )
    }

    private var mealID: Binding<String> {
        Binding<String>(
            get: { () -> String in
                if case .meal(let id) = check.timing { return id }
                return ""
            },
            set: { (id: String) in check.timing = .meal(id) }
        )
    }

    private var time: Binding<Date> {
        Binding<Date>(
            get: { () -> Date in
                if case .time(let minutes) = check.timing { return DayKey.today().date(minutes: minutes) }
                return DayKey.today().date(minutes: 8 * 60)
            },
            set: { (date: Date) in check.timing = .time(ClockTime.minutes(of: date)) }
        )
    }

    private var daysKind: Binding<PlanEditorDaysKind> {
        Binding<PlanEditorDaysKind>(
            get: { () -> PlanEditorDaysKind in
                switch check.days {
                case .daily: return .daily
                case .weekdays: return .weekdays
                case .dayTypes: return .dayTypes
                }
            },
            set: { (kind: PlanEditorDaysKind) in
                switch kind {
                case .daily: check.days = .daily
                case .weekdays: check.days = .weekdays(Weekdays.workdays)
                case .dayTypes: check.days = .dayTypes(plan.dayTypes.first.map { [$0.id] } ?? [])
                }
            }
        )
    }

    private var weekdays: Binding<Weekdays> {
        Binding<Weekdays>(
            get: { () -> Weekdays in
                if case .weekdays(let days) = check.days { return days }
                return Weekdays([])
            },
            set: { (days: Weekdays) in check.days = .weekdays(days) }
        )
    }

    private var selectedTypes: [String] {
        if case .dayTypes(let ids) = check.days { return ids }
        return []
    }

    private func typeBinding(_ id: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { selectedTypes.contains(id) },
            set: { (isOn: Bool) in
                var ids = selectedTypes.filter { $0 != id }
                if isOn { ids.append(id) }
                check.days = .dayTypes(ids)
            }
        )
    }

    // MARK: Loading and saving

    private func load() {
        guard original == nil else { return }
        let stored = PlanEditorData.storedPlan(app)
        guard let found = stored.check(id: checkID) else { return }
        plan = stored
        check = found
        original = found
    }

    private func save() {
        guard !deleted, let original, check != original else { return }
        PlanEditorData.saveCheck(check, app: app)
        self.original = check
    }
}

/// When a check is due, as the picker shows it.
enum PlanEditorTimingKind: String, CaseIterable, Identifiable {
    case anytime, meal, time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anytime: "Anytime"
        case .meal: "With a meal"
        case .time: "At a time"
        }
    }
}

/// On which days a check is due, as the picker shows it.
enum PlanEditorDaysKind: String, CaseIterable, Identifiable {
    case daily, weekdays, dayTypes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .dayTypes: "Day types"
        }
    }
}
