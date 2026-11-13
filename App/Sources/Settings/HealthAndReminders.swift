import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

#if os(iOS)
/// What Nina shares with Apple Health on this iPhone.
struct HealthSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            if !app.health.isAvailable {
                Section {
                    Text("Apple Health isn't available on this device.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(HealthService.Option.allCases, id: \.self) { option in
                        Toggle(option.title, isOn: Binding(
                            get: { app.health.isOn(option) },
                            set: { on in Task { await app.health.set(option, on, container: app.container) } }
                        ))
                    }
                } header: {
                    Text("Share with Apple Health")
                } footer: {
                    Text("Meals are written as food entries with every nutrient (energy, protein, carbs, fat, fiber, sugar, vitamins …). Edits and deletions in Nina update Health. iOS asks you once per kind of data.")
                }
                if app.health.isOn(.activity) {
                    Section {
                        LabeledContent("Active energy today", value: Fmt.energy(app.health.activeEnergyToday, unit: app.energyUnit))
                        Picker("Add to my budget", selection: Binding(get: { app.settings.activityBonusShare }, set: { value in
                            app.updateSettings { $0.activityBonusShare = value }
                        })) {
                            Text("Nothing").tag(0.0)
                            Text("Half").tag(0.5)
                            Text("All").tag(1.0)
                        }
                    } footer: {
                        Text("Watches tend to overestimate burned calories, so adding half is the usual choice.")
                    }
                }
                Section {
                    if let last = app.health.lastSync {
                        LabeledContent("Last sync", value: last.formatted(.relative(presentation: .named)))
                    }
                    if let error = app.health.lastError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await app.health.syncNow(container: app.container)
                            await app.health.refreshReadings()
                        }
                    }
                } footer: {
                    Text("Only this iPhone writes to Health, so entries logged on your Mac or watch appear in Health once this iPhone has synced them. Health data is never stored in Nina's iCloud.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Apple Health")
    }
}
#endif

/// Reminders for planned meals and for meals you tend to forget.
struct RemindersView: View {
    @Environment(AppModel.self) private var app
    @State private var planned = NotificationScheduler.shared.plannedEnabled
    @State private var meals = NotificationScheduler.shared.reminderMeals
    @State private var delay = NotificationScheduler.shared.reminderDelay

    var body: some View {
        Form {
            Section {
                Toggle("Ask about planned meals", isOn: $planned)
            } footer: {
                Text("At the planned time: \u{201C}Lunch planned – eaten?\u{201D} with ✓ Eaten and Skipped right in the notification, also on your Apple Watch.")
            }
            Section {
                ForEach(app.settings.meals) { slot in
                    Toggle("\(slot.emoji) \(slot.name) (\(Fmt.clock(slot.minutes + delay)))", isOn: Binding(
                        get: { meals.contains(slot.id) },
                        set: { on in if on { meals.insert(slot.id) } else { meals.remove(slot.id) } }
                    ))
                }
                Picker("After the usual time", selection: $delay) {
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            } header: {
                Text("Remind me if nothing is logged")
            } footer: {
                Text("A reminder only comes when that meal is still empty – once you log, it's gone.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reminders")
        .onChange(of: planned) { _, _ in apply() }
        .onChange(of: meals) { _, _ in apply() }
        .onChange(of: delay) { _, _ in apply() }
    }

    private func apply() {
        let scheduler = NotificationScheduler.shared
        scheduler.plannedEnabled = planned
        scheduler.reminderMeals = meals
        scheduler.reminderDelay = delay
        Task {
            if planned || !meals.isEmpty { _ = await scheduler.requestAuthorization() }
            scheduler.reschedule(context: app.container.mainContext, settings: app.settings)
        }
    }
}
