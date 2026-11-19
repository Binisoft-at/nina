import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Edit an entry: amount (nutrients follow), meal, day, time, eaten/planned, note, tags.
struct EntryEditor: View {
    let entry: LogEntry

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: AmountText
    @State private var meal: String
    @State private var date: Date
    @State private var status: EntryStatus
    @State private var note: String
    @State private var tags: String
    @State private var quickEnergy: String
    @State private var quickProtein: String
    @State private var quickCarbs: String
    @State private var quickFat: String

    init(entry: LogEntry) {
        self.entry = entry
        let values = entry.values
        _name = State(initialValue: entry.displayName)
        _amount = State(initialValue: entry.amount)
        _meal = State(initialValue: entry.meal)
        _date = State(initialValue: entry.time)
        _status = State(initialValue: entry.entryStatus)
        _note = State(initialValue: entry.note)
        _tags = State(initialValue: entry.tagList.joined(separator: ", "))
        _quickEnergy = State(initialValue: NumberText.plain(values.energy, decimals: 0))
        _quickProtein = State(initialValue: values[.protein].map { NumberText.plain($0, decimals: 1) } ?? "")
        _quickCarbs = State(initialValue: values[.carbs].map { NumberText.plain($0, decimals: 1) } ?? "")
        _quickFat = State(initialValue: values[.fat].map { NumberText.plain($0, decimals: 1) } ?? "")
    }

    /// The food behind the entry, for portions; a synthetic record from the entry itself otherwise.
    private var record: FoodRecord {
        if let found = app.library.record(entry.ref), entry.totalAmount > 0 { return found }
        let total = max(entry.totalAmount, 0.0001)
        let per = entry.base.basis / total
        return FoodRecord(ref: entry.ref, name: entry.displayName, category: entry.foodCategory, unit: entry.base,
                          nutrients: entry.values.scaled(by: per),
                          servings: entry.amount.isBaseUnit ? [] : [Serving(en: entry.unitLabel, amount: entry.unitAmount)])
    }

    private var isQuick: Bool { entry.isQuickEntry && entry.totalAmount <= 0 }

    private var previewValues: NutrientValues {
        if isQuick { return quickValues }
        let old = entry.totalAmount
        guard old > 0 else { return entry.values }
        return entry.values.scaled(by: amount.total / old)
    }

    private var quickValues: NutrientValues {
        var values = entry.values
        values[.energy] = NumberText.parse(quickEnergy) ?? 0
        values[.protein] = NumberText.parse(quickProtein) ?? 0
        values[.carbs] = NumberText.parse(quickCarbs) ?? 0
        values[.fat] = NumberText.parse(quickFat) ?? 0
        return values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryBadge(category: entry.foodCategory, emoji: entry.foodEmoji, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $name)
                                .font(.headline)
                            if !entry.brand.isEmpty {
                                Text(entry.brand).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if isQuick {
                    Section("Nutrition") {
                        numberRow("Energy (kcal)", text: $quickEnergy)
                        numberRow("Protein (g)", text: $quickProtein)
                        numberRow("Carbs (g)", text: $quickCarbs)
                        numberRow("Fat (g)", text: $quickFat)
                    }
                } else {
                    Section("Amount") {
                        AmountPicker(record: record, language: app.language, amount: $amount)
                    }
                }
                Section {
                    NutritionPreview(values: previewValues, targets: app.settings.targets(for: DayKey(date: date)), unit: app.energyUnit)
                }
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(app.settings.meals) { slot in
                            Text("\(slot.emoji) \(slot.name)").tag(slot.id)
                        }
                    }
                    DatePicker("When", selection: $date)
                    Picker("Status", selection: $status) {
                        Text("Eaten").tag(EntryStatus.eaten)
                        Text("Planned").tag(EntryStatus.planned)
                        Text("Skipped").tag(EntryStatus.skipped)
                    }
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Tags, separated by commas", text: $tags)
                } footer: {
                    Text("Tags group entries in Search and Insights, e.g. \u{201C}restaurant\u{201D} or \u{201C}cheat day\u{201D}.")
                }
                Section {
                    Button("Log Again Now", systemImage: "arrow.clockwise") {
                        app.logAgain([entry])
                        dismiss()
                    }
                    Button("Save as Meal…", systemImage: "square.and.arrow.down.on.square") {
                        app.present(.saveAsMeal([entry]))
                    }
                    if let food = app.library.record(entry.ref) {
                        Button("Food Details", systemImage: "info.circle") { app.present(.food(food)) }
                    }
                    Button("Delete Entry", systemImage: "trash", role: .destructive) {
                        app.trash([entry])
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .sheetFrame(minWidth: 520, minHeight: 680)
    }

    private func numberRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 100)
        }
    }

    private func save() {
        let store = app.store
        if isQuick {
            store.setNutrients(entry, quickValues)
        } else if amount != entry.amount {
            store.update(entry, amount: amount)
        }
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if TagText.join(tagList) != entry.tags { store.setTags([entry], tagList) }
        store.update(entry, name: name, meal: meal, day: DayKey(date: date, dayStartHour: app.settings.dayStartHour),
                     time: date, note: note, status: status)
        dismiss()
    }
}

/// Copy entries to any day, as eaten or planned.
struct CopyEntriesView: View {
    let entries: [LogEntry]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var planned = false
    @State private var keepMeals = true
    @State private var meal = "lunch"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    Toggle("As planned (confirm later)", isOn: $planned)
                    Toggle("Keep their meals", isOn: $keepMeals)
                    if !keepMeals {
                        Picker("Meal", selection: $meal) {
                            ForEach(app.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                        }
                    }
                } footer: {
                    let energy = entries.map(\.energy).reduce(0, +)
                    Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(Fmt.energy(energy, unit: app.energyUnit))")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Copy to Day")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        let day = DayKey(date: date)
                        let copies = app.store.copy(entries, to: day, meal: keepMeals ? nil : meal, status: planned ? .planned : .eaten)
                        app.toasts.show("Copied \(copies.count) to \(Fmt.dayTitle(day, today: app.today).lowercased())", symbol: "doc.on.doc.fill") {
                            app.store.purge(copies)
                        }
                        dismiss()
                    }
                }
            }
        }
        .sheetFrame(minWidth: 420, minHeight: 340)
    }
}

/// Save diary entries as a meal for one-tap logging (and routines).
struct SaveAsMealView: View {
    let entries: [LogEntry]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var planRoutine = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Usual breakfast", text: $name)
                        .focused($focused)
                } footer: {
                    Text("Log all \(entries.count) foods again with one tap from any meal's + menu or the search.")
                }
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.displayName)
                            Spacer()
                            Text(Fmt.energy(entry.energy, unit: app.energyUnit)).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Plan it as a routine next", isOn: $planRoutine)
                } footer: {
                    Text("A routine puts this meal into your diary on chosen weekdays as planned – you just confirm it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save as Meal")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let meal = entries.first?.meal ?? "snack"
                        let recipe = app.store.saveAsMeal(entries, name: name.isEmpty ? "My meal" : name, defaultMeal: meal)
                        app.toasts.show("Saved \u{201C}\(recipe.displayName)\u{201D}", symbol: "square.and.arrow.down.fill")
                        if planRoutine {
                            app.present(.planRule(nil, recipe: recipe))
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                focused = true
                if name.isEmpty, let first = entries.first { name = "My \(app.settings.meal(first.meal).name.lowercased())" }
            }
        }
        .sheetFrame(minWidth: 460, minHeight: 480)
    }
}

/// Every nutrient of a day against the targets (or the EU reference intakes), plus where the
/// calories came from.
struct DayNutritionView: View {
    let day: DayKey
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [LogEntry]

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil })
    }

    var body: some View {
        let eaten = entries.filter(\.isEaten)
        let totals = NutrientValues.sum(eaten.map(\.values))
        let targets = app.settings.targets(for: day)
        List {
            Section {
                ForEach(app.settings.meals) { slot in
                    let energy = eaten.filter { $0.meal == slot.id }.map(\.energy).reduce(0, +)
                    if energy > 0 {
                        HStack {
                            Text("\(slot.emoji) \(slot.name)")
                            Spacer()
                            Text(Fmt.energy(energy, unit: app.energyUnit)).monospacedDigit()
                            Text(totals.energy > 0 ? Fmt.percent(energy / totals.energy) : "")
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Calories by meal")
            } footer: {
                let shares = totals.macroShares
                Text("Energy from protein / carbs / fat: \(shares.percentText) %")
            }
            nutrientSection("Energy & macros", [.energy, .protein, .carbs, .sugar, .fiber, .fat], totals: totals, targets: targets)
            nutrientSection("Fats", Nutrient.fats, totals: totals, targets: targets)
            nutrientSection("Minerals", Nutrient.minerals, totals: totals, targets: targets)
            nutrientSection("Vitamins", Nutrient.vitamins, totals: totals, targets: targets)
            nutrientSection("Other", [.alcohol, .caffeine, .water], totals: totals, targets: targets)
            Section {
                Text("Targets are yours where you set them (Goals & Plan); the others are the EU reference intakes for an average adult. Values a food doesn't list count as unknown, so vitamins and minerals are minimums.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Nutrients · \(Fmt.dayTitle(day, today: app.today))")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    @ViewBuilder
    private func nutrientSection(_ title: String, _ nutrients: [Nutrient], totals: NutrientValues, targets: DailyTargets) -> some View {
        Section(title) {
            ForEach(nutrients, id: \.self) { nutrient in
                let value = totals[nutrient]
                let target = targets.target(for: nutrient)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(nutrient == .water ? "Water in food" : nutrient.title)
                        Spacer()
                        Text(Fmt.nutrient(value, nutrient, unit: app.energyUnit))
                            .monospacedDigit()
                        if let target, target > 0, nutrient != .water {
                            Text("/ \(Fmt.nutrient(target, nutrient, unit: app.energyUnit))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if let target, target > 0, let value, nutrient != .water {
                        ProgressView(value: min(value / target, 1))
                            .tint(nutrient.isLimit && value > target ? Color.orange : NutrientStyle.color(nutrient))
                    }
                    if nutrient == .sodium, let value {
                        Text("= \(Fmt.salt(fromSodium: value)) salt").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
