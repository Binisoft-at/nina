import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Settings: goals, diary preferences, Apple Health, reminders, appearance, help, iCloud & data,
/// import/export, the app log, about.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var hintsReset = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    GoalsView(showsDone: false)
                } label: {
                    LabeledContent {
                        Text(Fmt.energy(app.settings.targets.energy, unit: app.energyUnit))
                    } label: {
                        Label("Goals", systemImage: "target")
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
                Picker("Energy in", selection: Binding(get: { app.settings.energyUnit }, set: { value in
                    app.updateSettings { $0.energyUnit = value.rawValue }
                })) {
                    Text("kcal").tag(EnergyUnit.kcal)
                    Text("kJ").tag(EnergyUnit.kJ)
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

            Section("Appearance") {
                AppearancePicker()
            }

            Section {
                Button("Replay the Tour", systemImage: "graduationcap") { app.startTour() }
                Button(hintsReset ? "Hints Come Back at the Next Launch" : "Show Hints Again", systemImage: "lightbulb") {
                    BinisoftTips.requestReset()
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
                Button("Import & Export…", systemImage: "square.and.arrow.up.on.square") { app.present(.importData(nil)) }
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

    private var dataSections: [DataSection] {
        var sections = DataSection.standard(appName: AppInfo.name, dataNoun: "diary, foods and meals")
        sections.insert(DataSection("Apple Health", [
            DataFact("heart.fill", "Written to Health, on this iPhone", "If you allow it, \(AppInfo.name) writes what you eat and drink to Apple Health on this iPhone. Health keeps it in its own encrypted store."),
            DataFact("scalemass", "Read live, never synced by \(AppInfo.name)", "Weight and active energy from Health are read on each device when needed and never stored in \(AppInfo.name)'s iCloud."),
        ]), at: 1)
        sections.insert(DataSection("Barcodes", [
            DataFact("barcode.viewfinder", "Open Food Facts", "Scanning sends only the barcode number to Open Food Facts to look the product up. Nothing about you is sent."),
        ]), at: 2)
        return sections
    }
}

/// Goals: the calculator with every step explained, your targets, training days and priorities.
struct GoalsView: View {
    let showsDone: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sex: Sex = .unspecified
    @State private var birthYear = 1990
    @State private var height = 172.0
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
    @State private var loaded = false

    private var profile: BodyProfile {
        BodyProfile(sex: sex, age: GoalCalculator.age(birthYear: birthYear), heightCm: height, weightKg: weight,
                    activity: activity, goal: goal, ratePerWeek: rate)
    }

    private var plan: GoalPlan { GoalCalculator.plan(profile, split: split) }

    var body: some View {
        Form {
            Section {
                Picker("Sex (for the formula)", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Born \(String(birthYear))", value: $birthYear, in: 1920...2015)
                Stepper("Height \(Fmt.number(height)) cm", value: $height, in: 120...230)
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
                Picker("Goal", selection: $goal) {
                    ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
                }
                if goal != .maintain {
                    Picker("Pace", selection: $rate) {
                        Text("0.25 kg per week").tag(0.25)
                        Text("0.5 kg per week").tag(0.5)
                        Text("0.75 kg per week").tag(0.75)
                        if goal == .lose { Text("1 kg per week").tag(1.0) }
                    }
                    Stepper(targetWeight > 0 ? "Target weight \(Fmt.number(targetWeight, decimals: 1)) kg" : "Target weight (optional)",
                            value: $targetWeight, in: 0...250, step: 0.5)
                }
                Picker("Macro split", selection: $split) {
                    ForEach(MacroSplit.presets) { preset in
                        Text("\(preset.name) · \(Int(preset.protein * 100))/\(Int(preset.carbs * 100))/\(Int(preset.fat * 100))").tag(preset)
                    }
                }
            } header: {
                Text("Calculate for me")
            } footer: {
                Text("The standard method dietitians use (Mifflin–St Jeor). Every step with your numbers below.")
            }

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
                Button("Use These Targets", systemImage: "checkmark.circle.fill") {
                    targets = plan.targets
                    saveAll()
                    app.toasts.show("Goal set: \(Fmt.energy(plan.targets.energy, unit: app.energyUnit))", symbol: "target")
                }
                .primaryActionStyle()
            } header: {
                Text("How it's calculated")
            }

            Section {
                targetRow("Calories", value: $targets.energy, unit: app.energyUnit.symbol, step: 50)
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

            Section {
                Toggle("Different targets on training days", isOn: $trainingOn)
                if trainingOn {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { weekday in
                            Button {
                                trainingDays.toggle(weekday)
                            } label: {
                                Text(String(Weekdays.shortNames[weekday - 1].prefix(2)))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .foregroundStyle(trainingDays.days.contains(weekday) ? Color.white : .primary)
                                    .background(trainingDays.days.contains(weekday) ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                                                in: .rect(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Stepper("+\(Fmt.number(trainingExtra)) kcal, mostly carbs", value: $trainingExtra, in: 50...1500, step: 50)
                }
            } header: {
                Text("Training days")
            } footer: {
                Text("On these weekdays your calories go up and the extra comes 70 % from carbs, 30 % from protein.")
            }

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

            #if os(iOS)
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
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(showsDone ? "Done" : "Save") {
                    saveAll()
                    if showsDone { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear { if loaded, !showsDone { saveAll() } }
    }

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

    private func load() {
        guard !loaded else { return }
        let settings = app.settings
        let stored = app.store.profile()
        sex = settings.body.sex
        birthYear = (stored?.birthYear ?? 0) > 0 ? stored?.birthYear ?? 1990 : 1990
        height = settings.body.heightCm
        weight = app.store.weights().last?.kilograms ?? app.health.latestWeight ?? settings.body.weightKg
        activity = settings.body.activity
        goal = settings.body.goal
        rate = settings.body.ratePerWeek > 0 ? settings.body.ratePerWeek : 0.5
        split = settings.macroSplit
        targets = settings.targets
        trainingOn = settings.trainingTargets != nil
        if !settings.trainingDays.isEmpty { trainingDays = settings.trainingDays }
        if let training = settings.trainingTargets { trainingExtra = max(50, training.energy - settings.targets.energy) }
        focus = settings.focus
        bonus = settings.activityBonusShare
        targetWeight = settings.targetWeight
        loaded = true
    }

    private func saveAll() {
        let training: DailyTargets? = trainingOn ? {
            var copy = targets
            copy.energy += trainingExtra
            copy.carbs += (trainingExtra * 0.7 / 4).rounded()
            copy.protein += (trainingExtra * 0.3 / 4).rounded()
            return copy
        }() : nil
        app.updateSettings { profile in
            profile.sex = sex.rawValue
            profile.birthYear = birthYear
            profile.heightCm = height
            profile.activity = activity.rawValue
            profile.goal = goal.rawValue
            profile.ratePerWeek = rate
            profile.macroSplit = split.id
            profile.targets = targets.encoded
            profile.trainingTargets = training?.encoded ?? ""
            profile.trainingDays = trainingOn ? trainingDays.encoded : ""
            profile.focusNutrients = focus.map(\.rawValue).joined(separator: ",")
            profile.activityBonusShare = bonus
            profile.targetWeight = targetWeight
        }
    }
}

/// The meals of the day: names, emoji and usual times; own meals like "Jause" or "Pre-workout".
struct MealsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var meals: [MealSlot] = []

    var body: some View {
        Form {
            Section {
                ForEach($meals) { $slot in
                    HStack {
                        TextField("🍽️", text: $slot.emoji)
                            .frame(width: 36)
                            .multilineTextAlignment(.center)
                        TextField("Name", text: $slot.name)
                        DatePicker("Time", selection: Binding(
                            get: { DayKey.today().date(minutes: slot.minutes) },
                            set: { slot.minutes = ClockTime.minutes(of: $0) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                    .deleteDisabled(slot.isBuiltIn)
                }
                .onDelete { meals.remove(atOffsets: $0) }
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
    }

    private func save() {
        let cleaned = meals.map { slot -> MealSlot in
            var copy = slot
            if copy.name.trimmingCharacters(in: .whitespaces).isEmpty { copy.name = MealSlot.defaults.first { $0.id == slot.id }?.name ?? "Meal" }
            if copy.emoji.isEmpty { copy.emoji = "🍽️" }
            return copy
        }
        guard cleaned != app.settings.meals else { return }
        app.updateSettings { $0.meals = MealSlot.encode(cleaned) }
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
