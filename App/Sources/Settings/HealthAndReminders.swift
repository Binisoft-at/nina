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
            if !app.health.isAvailable && !app.health.isDemo {
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
                    Text("Meals are written as food entries with every nutrient (energy, protein, carbs, fat, fiber, sugar, vitamins …). Edits, deletions and Undo in Nina update Health. iOS asks you once per kind of data.")
                }
                if app.health.isOn(.activity) {
                    Section {
                        LabeledContent("Active energy today", value: Fmt.energy(app.health.activeEnergyToday, unit: app.energyUnit))
                        SettingsInfoRow("Add to my budget", info: SettingsInfo.activeEnergy) {
                            Picker("Add to my budget", selection: Binding(get: { app.settings.activityBonusShare }, set: { value in
                                app.updateSettings { $0.activityBonusShare = value }
                            })) {
                                Text("Nothing").tag(0.0)
                                Text("Half").tag(0.5)
                                Text("All").tag(1.0)
                            }
                        }
                    } footer: {
                        Text("Watches tend to overestimate burned calories, so adding half is the usual choice.")
                    }
                }
                HealthBodySettingsSection()
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

/// Reminders for planned meals, for meals you tend to forget, and from the coach (this device only).
struct RemindersView: View {
    @Environment(AppModel.self) private var app
    @State private var planned = NotificationScheduler.shared.plannedEnabled
    @State private var meals = NotificationScheduler.shared.reminderMeals
    @State private var delay = NotificationScheduler.shared.reminderDelay
    @State private var coachOn = NotificationScheduler.shared.coachOnThisDevice
    @State private var coachKinds = NotificationScheduler.shared.coachKinds

    var body: some View {
        Form {
            Section {
                Toggle(plannedTitle, isOn: $planned)
            } header: {
                if !PlatformInfo.isPhone {
                    Text("Planned meals")
                }
            } footer: {
                Text(plannedFooter)
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
                Text("A reminder only comes while that meal is still empty – once you log it, on any device, it's gone. A planned meal asks its own question instead.")
            }
            ReminderCoachSection(isOn: $coachOn, kinds: $coachKinds)
        }
        .formStyle(.grouped)
        .navigationTitle("Reminders")
        .onChange(of: planned) { _, _ in apply() }
        .onChange(of: meals) { _, _ in apply() }
        .onChange(of: delay) { _, _ in apply() }
        .onChange(of: coachOn) { _, _ in applyCoach() }
        .onChange(of: coachKinds) { _, _ in applyCoach() }
        .onAppear(perform: syncCoach)
    }

    /// The iPhone asks about planned meals by default; iPad and Mac only when turned on there, so
    /// one planned meal doesn't ask on every device at once.
    private var plannedTitle: String {
        if PlatformInfo.isPhone { return "Ask about planned meals" }
        return PlatformInfo.isMac ? "Also on this Mac" : "Also on this iPad"
    }

    private var plannedFooter: String {
        let what = "At the planned time: \u{201C}Lunch planned – eaten?\u{201D} with ✓ Eaten and Skipped right in the notification"
        if PlatformInfo.isPhone { return what + ", also on your Apple Watch. Once it's answered on any device, it's gone." }
        return "Your iPhone asks \u{201C}Lunch planned – eaten?\u{201D} at the planned time (your Apple Watch shows it too). Turn this on to be asked here as well."
    }

    /// Back from the plan editor pushed below, "Turn on coach reminders?" may have been answered
    /// there: show what the device does now (not an answer of its own, see `applyCoach`).
    private func syncCoach() {
        let scheduler = NotificationScheduler.shared
        if coachOn != scheduler.coachOnThisDevice { coachOn = scheduler.coachOnThisDevice }
        if coachKinds != scheduler.coachKinds { coachKinds = scheduler.coachKinds }
    }

    private func apply() {
        let scheduler = NotificationScheduler.shared
        scheduler.plannedEnabled = planned
        scheduler.reminderMeals = meals
        scheduler.reminderDelay = delay
        let wantsCoach = coachOn && !coachKinds.isEmpty && app.settings.plan.isSetUp
        Task {
            if planned || !meals.isEmpty || wantsCoach { _ = await scheduler.requestAuthorization() }
            scheduler.reschedule(context: app.container.mainContext, settings: app.settings)
        }
    }

    /// A coach toggle changed here: it counts as the answer to "Turn on coach reminders?".
    /// Values that only caught up with the device (`syncCoach`) change nothing.
    private func applyCoach() {
        let scheduler = NotificationScheduler.shared
        guard coachOn != scheduler.coachOnThisDevice || coachKinds != scheduler.coachKinds else { return }
        scheduler.coachOnThisDevice = coachOn
        scheduler.coachKinds = coachKinds
        scheduler.coachAsked = true
        apply()
    }
}

/// Settings > Reminders > Coach: which coach reminders this device schedules. The iPhone does by
/// default (the Apple Watch shows them too); iPad and Mac only when turned on there.
private struct ReminderCoachSection: View {
    @Environment(AppModel.self) private var app
    @Binding var isOn: Bool
    @Binding var kinds: Set<CoachReminders.Kind>

    var body: some View {
        if app.settings.plan.isSetUp {
            Section {
                Toggle(deviceTitle, isOn: $isOn)
                if isOn {
                    ForEach(CoachReminders.Kind.allCases) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            ReminderCoachRow(title: kind.title, detail: detail(for: kind))
                        }
                    }
                }
            } header: {
                Text("Coach")
                    .info(SettingsInfo.coachReminders.title, SettingsInfo.coachReminders.text)
            } footer: {
                Text(footer)
            }
        } else {
            Section {
                Text("The coach reminds you to weigh in, measure and check in once your plan is set up.")
                    .foregroundStyle(.secondary)
                // Pushed, so it also works in the Mac Settings window (a sheet would open on the main window).
                NavigationLink {
                    PlanEditorView(showsDone: false)
                } label: {
                    Label("Set Up Your Plan", systemImage: "list.bullet.clipboard")
                }
            } header: {
                Text("Coach")
            }
        }
    }

    private var deviceTitle: String {
        if PlatformInfo.isMac { return "Also on this Mac" }
        if PlatformInfo.isPhone { return "Coach reminders" }
        return "Also on this iPad"
    }

    private var footer: String {
        var text = "Nothing before 6:00 or after 21:00, and only one before 10:00. A reminder goes away once it's done – on any device. Pausing coaching pauses them; meal reminders stay."
        if !PlatformInfo.isPhone {
            text = "Your iPhone sends coach reminders (your Apple Watch shows them too). Turn this on to get them here as well. " + text
        }
        return text
    }

    private func binding(for kind: CoachReminders.Kind) -> Binding<Bool> {
        Binding(
            get: { kinds.contains(kind) },
            set: { on in
                if on { kinds.insert(kind) } else { kinds.remove(kind) }
            }
        )
    }

    /// ISO weekdays (1 = Monday), in English like the rest of the UI.
    private static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// When each one comes, from the plan.
    private func detail(for kind: CoachReminders.Kind) -> String {
        let plan = app.settings.plan
        switch kind {
        case .morning:
            return "\(Fmt.clock(plan.routine.weighInMinutes)), until you've weighed in – early checks come along"
        case .check:
            let names = plan.checks.filter(\.remind).map(\.name)
            if names.isEmpty { return "None of your checks asks for a reminder – turn it on per check in My Plan" }
            return names.joined(separator: ", ")
        case .measure:
            return "\(Fmt.clock(CoachReminders.measureEveningMinutes)), the evening before"
        case .checkIn:
            let name = Self.weekdayNames[min(7, max(1, plan.routine.checkInWeekday)) - 1]
            return "\(name), \(Fmt.clock(CoachReminders.checkInMinutes)), until it's done"
        case .phase:
            return "\(Fmt.clock(CoachReminders.phaseMinutes)) on the day, and once at your review weight"
        }
    }
}

private struct ReminderCoachRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// "Turn on coach reminders?" – asked once per device, right after a plan was first set up.
    /// Set `isPresented` when `NotificationScheduler.shared.shouldOfferCoachReminders(before:after:)`
    /// says so (the plan editor, the settings import and, on iPhone, RootView do). `onAnswer` runs
    /// after either button.
    func coachRemindersPrompt(isPresented: Binding<Bool>, onAnswer: @escaping () -> Void = {}) -> some View {
        modifier(ReminderCoachPrompt(isPresented: isPresented, onAnswer: onAnswer))
    }
}

private struct ReminderCoachPrompt: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    let onAnswer: () -> Void

    func body(content: Content) -> some View {
        content.alert("Turn on coach reminders?", isPresented: $isPresented) {
            Button("Turn On") { answer(true) }
            Button("Not Now", role: .cancel) { answer(false) }
        } message: {
            Text(message)
        }
    }

    /// The iPhone sends them by default; on iPad and Mac this adds them there as well.
    private var message: String {
        let what = "A nudge to weigh in each morning, your daily checks, the evening before a full measurement and the weekly check-in. Change them any time in Settings › Reminders."
        if PlatformInfo.isPhone { return what }
        let device = PlatformInfo.isMac ? "Mac" : "iPad"
        return "Your iPhone sends them (your Apple Watch shows them too). Turn On adds them on this \(device) as well. " + what
    }

    private func answer(_ yes: Bool) {
        let container = app.container
        let settings = app.settings
        // Answered right away, so no other screen asks again while the answer is being saved (and
        // the iPhone's own question from RootView, if it is waiting, is withdrawn).
        NotificationScheduler.shared.coachAsked = true
        app.askCoachReminders = false
        Task {
            await NotificationScheduler.shared.answerCoachReminders(yes, context: container.mainContext, settings: settings)
        }
        onAnswer()
    }
}
