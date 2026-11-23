import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The week ahead: planned meals per day, routines that plan themselves, and quick ways to plan.
/// Planned food shows dimmed in the diary and counts once confirmed – logging becomes one tap.
/// Built from `app.today` (with "Day starts at"), so its seven days move on with the day.
struct PlanView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        PlanWeekView(today: app.today)
            .id(app.today)
    }
}

/// The Plan page for one diary day: its seven days and their planned foods are fetched for it.
private struct PlanWeekView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<PlanRule> { $0.deletedAt == nil }, sort: \PlanRule.minutes) private var rules: [PlanRule]
    @Query private var planned: [LogEntry]
    private let today: DayKey
    private let days: [DayKey]

    init(today: DayKey) {
        self.today = today
        let end = today.adding(days: 6)
        days = DayKey.range(today, through: end)
        let first = today.rawValue, last = end.rawValue
        _planned = Query(filter: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil && $0.status == "planned" },
                         sort: [SortDescriptor(\LogEntry.day), SortDescriptor(\LogEntry.time), SortDescriptor(\LogEntry.sortOrder)])
    }

    var body: some View {
        List {
            if app.settings.plan.isSetUp { myPlanSection }
            daysSection
            routinesSection
            quickSection
        }
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.sheet = .planRule(nil, recipe: nil)
                } label: {
                    Label("New Routine", systemImage: "plus")
                }
            }
        }
    }

    // MARK: My Plan

    /// The coach plan (phases, day types, checks) from the tab named Plan.
    private var myPlanSection: some View {
        Section {
            Button {
                app.sheet = .plan
            } label: {
                PlanMyPlanRow(detail: planLine)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Lean gain · week 4 of 15" – the running phase, else what the plan holds.
    private var planLine: String {
        let plan = app.settings.plan
        if let running = plan.activePhase(on: today) {
            // "Running · week 4 of 15" → "week 4 of 15"; without weeks just "running".
            let status: String = PlanEditorData.phaseStatus(running, plan: plan, today: today)
            let prefix = "Running · "
            let detail: String = status.hasPrefix(prefix) ? String(status.dropFirst(prefix.count)) : status.lowercased()
            return "\(PlanEditorData.phaseName(running)) · \(detail)"
        }
        return "Phases, day types and daily checks"
    }

    // MARK: The next 7 days

    private var daysSection: some View {
        Section {
            ForEach(days) { day in
                dayRow(day)
            }
        } header: {
            Text("Next 7 days")
        } footer: {
            Text(daysFooter)
        }
    }

    private func dayRow(_ day: DayKey) -> some View {
        let entries = planned.filter { $0.day == day.rawValue }
        return Button {
            app.show(day: day)
        } label: {
            DayPlanRow(day: day, today: today, entries: entries)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !entries.isEmpty {
                Button("Confirm All as Eaten", systemImage: "checkmark.circle") { app.confirm(entries) }
                Button("Remove Plan", systemImage: "trash", role: .destructive) { app.trash(entries) }
            }
        }
    }

    private var daysFooter: String {
        #if os(macOS)
        return "Click a day to open it. Planned foods count once you click ✓ next to them – or answer the reminder."
        #else
        return "Tap a day to open it. Planned foods count once you tap ✓ next to them – or answer the reminder."
        #endif
    }

    // MARK: Routines

    private var routinesSection: some View {
        Section {
            ForEach(rules) { rule in
                routineRow(rule)
            }
            Button("New Routine", systemImage: "plus.circle") { app.sheet = .planRule(nil, recipe: nil) }
        } header: {
            Text("Routines")
        } footer: {
            Text("A routine plans a saved meal on chosen weekdays, e.g. your usual breakfast Mon–Fri at 7:30.")
        }
    }

    private func routineRow(_ rule: PlanRule) -> some View {
        RoutineRow(rule: rule)
            .contentShape(.rect)
            .onTapGesture { app.sheet = .planRule(rule, recipe: nil) }
            .contextMenu {
                Button("Edit…", systemImage: "pencil") { app.sheet = .planRule(rule, recipe: nil) }
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash(rule) }
            }
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash(rule) }
            }
    }

    // MARK: Plan quickly

    private var quickSection: some View {
        Section("Plan quickly") {
            Button("Plan Tomorrow Like Today", systemImage: "calendar.badge.plus") {
                planTomorrowLikeToday()
            }
            Button("Plan the Week Like Last Week", systemImage: "calendar") {
                app.planLikeLastWeek(Array(days.dropFirst()))
            }
        }
    }

    /// Today's foods (not the skipped ones) planned for tomorrow; a routine's meal that tomorrow
    /// already has stays out.
    private func planTomorrowLikeToday() {
        let todays = app.store.entries(on: today).filter { $0.entryStatus != .skipped }
        guard !todays.isEmpty else {
            app.toasts.show("Nothing logged today yet", symbol: "info.circle")
            return
        }
        app.copy(todays, to: today.adding(days: 1), status: .planned)
    }
}

/// "My Plan" with the running phase, at the top of the Plan tab.
private struct PlanMyPlanRow: View {
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

private struct DayPlanRow: View {
    let day: DayKey
    let today: DayKey
    let entries: [LogEntry]
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dateColumn
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.dayTitle(day, today: today)).font(.subheadline.weight(.semibold))
                if entries.isEmpty {
                    Text("Nothing planned").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(slots) { slot in
                        mealLine(slot)
                    }
                }
            }
            Spacer()
            if !entries.isEmpty {
                Text(Fmt.energy(entries.map(\.energy).reduce(0, +), unit: app.energyUnit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private var dateColumn: some View {
        VStack(spacing: 0) {
            Text(Fmt.weekdayLetter(day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(day.day)").font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(day == today ? Brand.accent : .primary)
        }
        .frame(width: 36)
    }

    /// The meals with something planned, in the order the day runs (from "Day starts at").
    private var slots: [MealSlot] {
        let start = app.settings.dayStartHour
        let used = Set(entries.map(\.meal))
        return app.settings.meals.filter { used.contains($0.id) }.sorted { a, b in
            ClockTime.diaryMinutes(a.minutes, dayStartHour: start) < ClockTime.diaryMinutes(b.minutes, dayStartHour: start)
        }
    }

    /// "🍳 Oat porridge · Blueberries" – names with commas stay readable.
    private func mealLine(_ slot: MealSlot) -> some View {
        let names = entries.filter { $0.meal == slot.id }.map(\.displayName).joined(separator: " · ")
        return Text("\(slot.emoji) \(names)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct RoutineRow: View {
    let rule: PlanRule
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Text(app.settings.meal(rule.meal).emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title).foregroundStyle(rule.isActive ? .primary : .secondary)
                Text("\(app.settings.meal(rule.meal).name) · \(Fmt.clock(rule.minutes)) · \(rule.days.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Active", isOn: Binding(get: { rule.isActive }, set: { app.setActive(rule, $0) }))
                .labelsHidden()
        }
    }
}

/// A routine: which saved meal, at which meal and time, on which weekdays.
struct PlanRuleEditor: View {
    let rule: PlanRule?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Recipe> { $0.deletedAt == nil }, sort: \Recipe.name) private var recipes: [Recipe]
    @State private var recipeID: UUID?
    @State private var meal: String
    @State private var time: Date
    @State private var weekdays: Weekdays
    @State private var notify: Bool

    init(rule: PlanRule?, recipe: Recipe?) {
        self.rule = rule
        _recipeID = State(initialValue: rule?.recipeUUID ?? recipe?.uuid)
        let meal = rule?.meal ?? (recipe?.defaultMeal.isEmpty == false ? recipe?.defaultMeal ?? "breakfast" : "breakfast")
        _meal = State(initialValue: meal)
        let minutes = rule?.minutes ?? MealSlot.defaults.first { $0.id == meal }?.minutes ?? 450
        _time = State(initialValue: DayKey.today().date(minutes: minutes))
        _weekdays = State(initialValue: rule?.days ?? .workdays)
        _notify = State(initialValue: rule?.notify ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if recipes.isEmpty {
                        Text("Save a meal first (New Meal below, or \u{201C}Save as Meal\u{201D} on diary entries). Routines plan saved meals.")
                            .foregroundStyle(.secondary)
                        Button("New Meal…") { app.present(.recipe(nil, kind: .meal)) }
                    } else {
                        Picker("Meal to plan", selection: $recipeID) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(recipes) { recipe in
                                Text("\(recipe.symbol) \(recipe.displayName)").tag(Optional(recipe.uuid))
                            }
                        }
                    }
                }
                Section {
                    Picker("At", selection: $meal) {
                        ForEach(app.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { weekday in
                            Button {
                                weekdays.toggle(weekday)
                            } label: {
                                Text(String(Weekdays.shortNames[weekday - 1].prefix(2)))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .foregroundStyle(weekdays.days.contains(weekday) ? Color.white : .primary)
                                    .background(weekdays.days.contains(weekday) ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                                in: .rect(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Toggle("Remind me to confirm", isOn: $notify)
                } footer: {
                    Text(footer)
                }
                if let rule {
                    Section {
                        Button("Delete Routine", systemImage: "trash", role: .destructive) {
                            app.trash(rule)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(rule == nil ? "New Routine" : "Routine")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(recipeID == nil || weekdays.isEmpty)
                }
            }
        }
        .sheetFrame(minWidth: 480, minHeight: 520)
    }

    private var footer: String {
        let ahead = "\(weekdays.summary). The plan appears in your diary a few days ahead."
        guard rule != nil else { return ahead }
        return ahead + " Saving a change to the meal, time or days replaces the planned meals you haven't confirmed yet."
    }

    private func save() {
        guard let recipeID, let recipe = recipes.first(where: { $0.uuid == recipeID }) else { return }
        app.saveRoutine(rule, recipe: recipe, meal: meal, minutes: ClockTime.minutes(of: time), weekdays: weekdays, notify: notify)
        dismiss()
    }
}
