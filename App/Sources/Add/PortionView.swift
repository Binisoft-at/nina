import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// How much of a food: amount with its unit, live nutrition against the day, meal and
/// "plan for later". The Add button floats on Liquid Glass.
struct PortionView: View {
    let record: FoodRecord
    let mode: FoodPickMode
    let day: DayKey
    @Binding var meal: String
    var onAdded: (Int) -> Void

    @Environment(AppModel.self) private var app
    @State private var amount: AmountText
    @State private var planLater = false
    @State private var time = Date()
    @State private var showsLabel = false

    init(record: FoodRecord, mode: FoodPickMode, day: DayKey, meal: Binding<String>, onAdded: @escaping (Int) -> Void) {
        self.record = record
        self.mode = mode
        self.day = day
        _meal = meal
        self.onAdded = onAdded
        _amount = State(initialValue: record.initialAmount(language: .english))
    }

    private var values: NutrientValues { record.nutrients(forAmount: amount.total) }
    private var recipe: Recipe? {
        guard record.ref.kind == .recipe, let id = record.recordID else { return nil }
        return app.store.recipe(id)
    }
    private var isSavedMeal: Bool { recipe?.recipeKind == .meal }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CategoryBadge(category: record.category, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.displayName(app.language))
                            .font(.title3.weight(.semibold))
                        if let other = record.secondaryName(app.language) {
                            Text(other).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !record.brand.isEmpty {
                            Text(record.brand).font(.caption).foregroundStyle(.secondary)
                        }
                        HighlightBadges(highlights: record.highlights)
                    }
                    Spacer()
                    Button {
                        app.toggleFavorite(record)
                    } label: {
                        Image(systemName: record.isFavorite || app.library.record(record.ref)?.isFavorite == true ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Favorite")
                }
            }

            if let recipe, isSavedMeal {
                Section("In this meal") {
                    ForEach(recipe.sortedItems) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(Fmt.amount(item.amount)).foregroundStyle(.secondary)
                            Text(Fmt.energy(item.values.energy, unit: app.energyUnit)).monospacedDigit()
                        }
                    }
                }
            } else {
                Section("Amount") {
                    AmountPicker(record: record, language: app.language, amount: $amount)
                }
            }

            Section {
                NutritionPreview(values: isSavedMeal ? record.nutrients : values, targets: app.settings.targets(for: day), unit: app.energyUnit)
                DisclosureGroup("Nutrition facts", isExpanded: $showsLabel) {
                    NutritionLabel(record: record, amount: isSavedMeal ? nil : amount, unit: app.energyUnit)
                }
            }

            if mode.isLogging {
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(app.settings.meals) { slot in
                            Text("\(slot.emoji) \(slot.name)").tag(slot.id)
                        }
                    }
                    Toggle("Plan for later", isOn: $planLater)
                    if planLater {
                        DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(planLater ? "Planned foods show dimmed and count once you tap ✓." : "Logged to \(Fmt.dayTitle(day, today: app.today).lowercased()).")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isSavedMeal ? "Saved Meal" : "Amount")
        .inlineNavigationTitle()
        .safeAreaInset(edge: .bottom) {
            Button(action: add) {
                Label(addTitle, systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            amount = record.initialAmount(language: app.language)
            if let slot = app.settings.meals.first(where: { $0.id == meal }) {
                time = day.date(minutes: slot.minutes)
            }
        }
    }

    private var addTitle: String {
        let energy = Fmt.energy(isSavedMeal ? record.nutrients.energy : values.energy, unit: app.energyUnit)
        switch mode {
        case .log: return planLater ? "Plan · \(energy)" : "Add · \(energy)"
        case .pick: return "Add to Meal · \(energy)"
        }
    }

    private func add() {
        switch mode {
        case .log:
            let status: EntryStatus = planLater ? .planned : .eaten
            if let recipe, isSavedMeal {
                app.logRecipe(recipe, day: day, meal: meal, status: status)
            } else {
                app.log(record, amount: amount, day: day, meal: meal, time: planLater ? combined(time) : nil, status: status)
            }
            onAdded(1)
        case .pick(let onPick):
            onPick(RecipeLine(record: record, amount: isSavedMeal ? AmountText(quantity: 1, unitLabel: BaseUnit.serving.symbol, unitAmount: 1, baseUnit: .serving) : amount,
                              language: app.language))
            onAdded(1)
        }
    }

    /// The chosen clock time on the entry's day.
    private func combined(_ clock: Date) -> Date {
        day.date(minutes: ClockTime.minutes(of: clock))
    }
}

/// EU-style nutrition table per 100 g/ml and per portion.
struct NutritionLabel: View {
    let record: FoodRecord
    var amount: AmountText?
    let unit: EnergyUnit

    var body: some View {
        let per100 = record.nutrients
        let portion = amount.map { record.nutrients(forAmount: $0.total) }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text(record.unit == .serving ? "per serving" : "per 100 \(record.unit.symbol)")
                    .font(.caption.weight(.semibold))
                    .gridColumnAlignment(.trailing)
                if let amount {
                    Text(Fmt.amount(amount))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .gridColumnAlignment(.trailing)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            row("Energy", per100[.energy], portion?[.energy], .energy, indent: false)
            row("Fat", per100[.fat], portion?[.fat], .fat, indent: false)
            row("of which saturates", per100[.saturatedFat], portion?[.saturatedFat], .saturatedFat, indent: true)
            row("Carbohydrate", per100[.carbs], portion?[.carbs], .carbs, indent: false)
            row("of which sugars", per100[.sugar], portion?[.sugar], .sugar, indent: true)
            row("Fibre", per100[.fiber], portion?[.fiber], .fiber, indent: false)
            row("Protein", per100[.protein], portion?[.protein], .protein, indent: false)
            GridRow {
                Text("Salt")
                Text(Fmt.salt(fromSodium: per100[.sodium])).monospacedDigit()
                if amount != nil {
                    Text(Fmt.salt(fromSodium: portion?[.sodium])).monospacedDigit()
                }
            }
            let extras = (Nutrient.minerals + Nutrient.vitamins + [.cholesterol, .caffeine, .alcohol]).filter { $0 != .sodium && per100[$0] != nil }
            if !extras.isEmpty {
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(extras, id: \.self) { nutrient in
                    row(nutrient.title, per100[nutrient], portion?[nutrient], nutrient, indent: false)
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: Double?, _ portion: Double?, _ nutrient: Nutrient, indent: Bool) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(indent ? .secondary : .primary)
                .padding(.leading, indent ? 12 : 0)
            Text(nutrient == .energy ? energyText(value) : Fmt.nutrient(value, nutrient)).monospacedDigit()
            if amount != nil {
                Text(nutrient == .energy ? energyText(portion) : Fmt.nutrient(portion, nutrient)).monospacedDigit()
            }
        }
    }

    private func energyText(_ kcal: Double?) -> String {
        guard let kcal else { return "–" }
        let kj = Fmt.number((kcal * EnergyUnit.kilojoulesPerKilocalorie).rounded())
        return unit == .kJ ? "\(kj) kJ" : "\(Fmt.number(kcal.rounded())) kcal"
    }
}

/// Just a number (and optionally macros) when there's no time to find the food.
struct QuickCaloriesView: View {
    let day: DayKey
    let meal: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var energy = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var chosenMeal = ""
    @FocusState private var energyFocused: Bool

    private var kilocalories: Double? {
        NumberText.parse(energy).map { app.energyUnit.kilocalories(from: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it? (optional)", text: $name)
                    HStack {
                        TextField("Energy", text: $energy)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .focused($energyFocused)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(app.energyUnit.symbol).foregroundStyle(.secondary)
                    }
                }
                Section("Macros (optional)") {
                    field("Protein", $protein)
                    field("Carbs", $carbs)
                    field("Fat", $fat)
                }
                Section {
                    Picker("Meal", selection: $chosenMeal) {
                        ForEach(app.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Quick Calories")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let kcal = kilocalories else { return }
                        var values = NutrientValues([.energy: kcal])
                        values[.protein] = NumberText.parse(protein) ?? 0
                        values[.carbs] = NumberText.parse(carbs) ?? 0
                        values[.fat] = NumberText.parse(fat) ?? 0
                        app.logQuick(name: name, nutrients: values, day: day, meal: chosenMeal)
                        dismiss()
                    }
                    .disabled(kilocalories == nil)
                }
            }
            .onAppear {
                chosenMeal = meal ?? app.settings.suggestedMeal().id
                energyFocused = true
            }
        }
        .sheetFrame(minWidth: 420, minHeight: 460)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 90)
            Text("g").foregroundStyle(.secondary)
        }
    }
}
