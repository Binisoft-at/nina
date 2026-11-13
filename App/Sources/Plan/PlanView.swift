import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The week ahead: planned meals per day, routines that plan themselves, and quick ways to plan.
/// Planned food shows dimmed in the diary and counts once confirmed – logging becomes one tap.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<PlanRule> { $0.deletedAt == nil }, sort: \PlanRule.minutes) private var rules: [PlanRule]
    @Query private var planned: [LogEntry]
    private let days: [DayKey]

    init() {
        let today = DayKey.today()
        let end = today.adding(days: 6)
        days = DayKey.range(today, through: end)
        let first = today.rawValue, last = end.rawValue
        _planned = Query(filter: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil && $0.status == "planned" },
                         sort: [SortDescriptor(\LogEntry.day), SortDescriptor(\LogEntry.time)])
    }

    var body: some View {
        List {
            Section {
                ForEach(days) { day in
                    let entries = planned.filter { $0.day == day.rawValue }
                    Button {
                        app.show(day: day)
                    } label: {
                        DayPlanRow(day: day, entries: entries)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !entries.isEmpty {
                            Button("Confirm All as Eaten", systemImage: "checkmark.circle") { app.confirm(entries) }
                            Button("Remove Plan", systemImage: "trash", role: .destructive) { app.trash(entries) }
                        }
                    }
                }
            } header: {
                Text("Next 7 days")
            } footer: {
                Text("Tap a day to open it. Planned foods count once you tap ✓ next to them – or answer the reminder.")
            }

            Section {
                ForEach(rules) { rule in
                    RoutineRow(rule: rule)
                        .contentShape(.rect)
                        .onTapGesture { app.sheet = .planRule(rule, recipe: nil) }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { app.trash(rule) }
                        }
                }
                Button("New Routine", systemImage: "plus.circle") { app.sheet = .planRule(nil, recipe: nil) }
            } header: {
                Text("Routines")
            } footer: {
                Text("A routine plans a saved meal on chosen weekdays, e.g. your usual breakfast Mon–Fri at 7:30.")
            }

            Section("Plan quickly") {
                Button("Plan Tomorrow Like Today", systemImage: "calendar.badge.plus") {
                    let todays = app.store.entries(on: app.today).filter { $0.entryStatus != .skipped }
                    guard !todays.isEmpty else {
                        app.toasts.show("Nothing logged today yet", symbol: "info.circle")
                        return
                    }
                    app.copy(todays, to: app.today.adding(days: 1), status: .planned)
                }
                Button("Plan the Week Like Last Week", systemImage: "calendar") {
                    planWeekLikeLastWeek()
                }
            }
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

    /// Copies what was eaten 7 days earlier to each of the next 7 days that has nothing planned yet.
    private func planWeekLikeLastWeek() {
        var created = 0
        for day in days.dropFirst() where !planned.contains(where: { $0.day == day.rawValue }) {
            let source = app.store.entries(on: day.adding(days: -7)).filter(\.isEaten)
            guard !source.isEmpty else { continue }
            created += app.store.copy(source, to: day, status: .planned).count
        }
        app.toasts.show(created > 0 ? "Planned \(created) foods" : "Nothing to copy from last week", symbol: "calendar.badge.plus")
    }
}

private struct DayPlanRow: View {
    let day: DayKey
    let entries: [LogEntry]
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(Fmt.weekdayLetter(day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(day.day)").font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(day == app.today ? Brand.accent : .primary)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.dayTitle(day, today: app.today)).font(.subheadline.weight(.semibold))
                if entries.isEmpty {
                    Text("Nothing planned").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(app.settings.meals) { slot in
                        let items = entries.filter { $0.meal == slot.id }
                        if !items.isEmpty {
                            Text("\(slot.emoji) \(items.map(\.displayName).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
            Toggle("Active", isOn: Binding(get: { rule.isActive }, set: { app.store.setActive(rule, $0) }))
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
                        Text("Save a meal first (+ → New Meal, or \u{201C}Save as Meal\u{201D} on diary entries). Routines plan saved meals.")
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
                    Text("\(weekdays.summary). The plan appears in your diary a few days ahead; changes to the meal apply to new days.")
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

    private func save() {
        guard let recipeID, let recipe = recipes.first(where: { $0.uuid == recipeID }) else { return }
        let store = app.store
        store.savePlanRule(rule, recipe: recipe, meal: meal, minutes: ClockTime.minutes(of: time), weekdays: weekdays,
                           notify: notify, startDay: rule?.start ?? app.today)
        store.materializePlans(today: app.today)
        app.toasts.show("Routine saved · \(weekdays.summary)", symbol: "calendar.badge.clock")
        if notify { Task { _ = await NotificationScheduler.shared.requestAuthorization() } }
        dismiss()
    }
}
