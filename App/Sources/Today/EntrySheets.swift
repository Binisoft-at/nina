import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The Entry Editor's fields, so "Discard changes?" can compare them with how they started.
private struct EntryEditorFields: Equatable {
    var name: String
    var amount: AmountText
    var meal: String
    var date: Date
    var status: EntryStatus
    var note: String
    var tags: String
    var energy: String
    var protein: String
    var carbs: String
    var fat: String

    init(_ entry: LogEntry) {
        let values = entry.values
        name = entry.displayName
        amount = entry.amount
        meal = entry.meal
        date = entry.time
        status = entry.entryStatus
        note = entry.note
        tags = entry.tagList.joined(separator: ", ")
        energy = EntryEditorNumber.text(values.energy, decimals: 0)
        protein = values[.protein].map { EntryEditorNumber.text($0, decimals: 1) } ?? ""
        carbs = values[.carbs].map { EntryEditorNumber.text($0, decimals: 1) } ?? ""
        fat = values[.fat].map { EntryEditorNumber.text($0, decimals: 1) } ?? ""
    }

    /// The quick entry's number fields by nutrient (`DiaryEntryEdits.quickNutrients`).
    var quickTexts: [Nutrient: String] {
        [.energy: energy, .protein: protein, .carbs: carbs, .fat: fat]
    }
}

/// Numbers in the editor's fields the way the keyboard types them: the person's decimal
/// separator ("12,5" in Austria), no grouping, no trailing zeros – editing never mixes "." and ",".
private enum EntryEditorNumber {
    static func text(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "" }
        let text = value.formatted(.number.precision(.fractionLength(0...max(0, decimals))).grouping(.never))
        // A locale with its own digits would show text Nina can't read back: plain digits then.
        return NumberText.parse(text) != nil ? text : NumberText.plain(value, decimals: decimals)
    }
}

/// Edit an entry: amount (nutrients follow), meal, day, time, eaten/planned, note, tags.
struct EntryEditor: View {
    let entry: LogEntry

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var fields: EntryEditorFields
    @State private var confirmDiscard = false
    /// The fields as the editor opened: changes ask before they're thrown away.
    private let initial: EntryEditorFields

    init(entry: LogEntry) {
        self.entry = entry
        let fields = EntryEditorFields(entry)
        _fields = State(initialValue: fields)
        initial = fields
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
    private var isDirty: Bool { fields != initial }

    /// The day the entry will count for: its own day until the date in the picker changes.
    private var editedDay: DayKey {
        DiaryEntryEdits.editedDay(stored: entry.dayKey, originalTime: initial.date, newTime: fields.date,
                                  dayStartHour: app.settings.dayStartHour)
    }

    private var previewValues: NutrientValues {
        if isQuick { return quickValues ?? entry.values }
        let old = entry.totalAmount
        guard old > 0 else { return entry.values }
        return entry.values.scaled(by: fields.amount.total / old)
    }

    /// The quick entry's numbers: untouched fields keep the stored values exactly; nil while a
    /// changed field doesn't read as a number (Save waits).
    private var quickValues: NutrientValues? {
        DiaryEntryEdits.quickNutrients(entry.values, typed: fields.quickTexts, initial: initial.quickTexts)
    }

    private var canSave: Bool { !isQuick || quickValues != nil }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                if isQuick {
                    quickSection
                } else {
                    Section {
                        AmountPicker(record: record, language: app.language, amount: $fields.amount)
                    } header: {
                        Text("Amount")
                            .info(LogInfo.amount.title, LogInfo.amount.text)
                    }
                }
                Section {
                    NutritionPreview(values: previewValues, targets: app.settings.targets(for: editedDay), unit: app.energyUnit)
                }
                whenSection
                noteSection
                actionsSection
            }
            .formStyle(.grouped)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle("Edit Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .sheetFrame(minWidth: 520, minHeight: 560)
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                CategoryBadge(category: entry.foodCategory, emoji: entry.foodEmoji, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: $fields.name)
                        .font(.headline)
                    if !entry.brand.isEmpty {
                        Text(entry.brand).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var quickSection: some View {
        Section {
            numberRow("Energy (kcal)", text: $fields.energy, startText: initial.energy, isEnergy: true)
            numberRow("Protein (g)", text: $fields.protein, startText: initial.protein, isEnergy: false)
            numberRow("Carbs (g)", text: $fields.carbs, startText: initial.carbs, isEnergy: false)
            numberRow("Fat (g)", text: $fields.fat, startText: initial.fat, isEnergy: false)
        } header: {
            Text("Nutrition")
        } footer: {
            if quickValues == nil {
                Text("Fix the numbers in red to save.")
                    .foregroundStyle(.red)
            }
        }
    }

    private var whenSection: some View {
        Section {
            Picker("Meal", selection: $fields.meal) {
                ForEach(app.settings.meals) { slot in
                    Text("\(slot.emoji) \(slot.name)").tag(slot.id)
                }
            }
            DatePicker("When", selection: $fields.date)
            LabeledContent {
                Picker("Status", selection: $fields.status) {
                    Text("Eaten").tag(EntryStatus.eaten)
                    Text("Planned").tag(EntryStatus.planned)
                    Text("Skipped").tag(EntryStatus.skipped)
                }
                .labelsHidden()
            } label: {
                Text("Status")
                    .info(LogInfo.status.title, LogInfo.status.text)
            }
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Note", text: $fields.note, axis: .vertical)
                .lineLimit(1...4)
            TextField("Tags, separated by commas", text: $fields.tags)
        } footer: {
            Text("Tags group entries in Search and Nutrition, e.g. \u{201C}restaurant\u{201D} or \u{201C}cheat day\u{201D}.")
        }
    }

    private var actionsSection: some View {
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

    /// A number field named for VoiceOver ("Protein (g)"), red once a change doesn't read as a
    /// number.
    private func numberRow(_ title: String, text: Binding<String>, startText: String, isEnergy: Bool) -> some View {
        let typed: String = text.wrappedValue
        let isInvalid: Bool = typed != startText && DiaryEntryEdits.quickValue(typed, isEnergy: isEnergy) == nil
        return HStack {
            Text(title)
            Spacer()
            TextField(title, text: text, prompt: Text("0"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isInvalid ? Color.red : Color.primary)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 100)
        }
    }

    private func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        let store = app.store
        if isQuick {
            guard let values = quickValues else { return }
            if values != entry.values { store.setNutrients(entry, values) }
        } else if fields.amount != entry.amount {
            store.update(entry, amount: fields.amount)
        }
        let tagList = fields.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if TagText.join(tagList) != entry.tags { store.setTags([entry], tagList) }
        store.update(entry, name: fields.name, meal: fields.meal, day: editedDay, time: fields.date, note: fields.note,
                     status: fields.status)
        dismiss()
    }
}

/// Copy entries to any day, as eaten or planned – or move them there ("Move to Day…": same time
/// of day, Undo in the toast).
struct CopyEntriesView: View {
    let entries: [LogEntry]
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Move instead of copy (`TodayEntrySheetMode`, set by "Move to Day…").
    @State private var isMove: Bool
    @State private var date = Date()
    @State private var planned = false
    @State private var keepMeals = true
    @State private var meal = "lunch"
    @State private var isSetUp = false

    init(entries: [LogEntry]) {
        self.entries = entries
        _isMove = State(initialValue: TodayEntrySheetMode.opensToMove)
    }

    /// The diary day the picked date stands for.
    private var targetDay: DayKey {
        DayKey(date: date, dayStartHour: app.settings.dayStartHour)
    }

    /// Moving to where the entries already are changes nothing.
    private var changesSomething: Bool {
        guard isMove else { return true }
        let day = targetDay
        return entries.contains { $0.dayKey != day || (!keepMeals && $0.meal != meal) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    if !isMove {
                        Toggle("As planned (confirm later)", isOn: $planned)
                    }
                    Toggle("Keep their meals", isOn: $keepMeals)
                    if !keepMeals {
                        Picker("Meal", selection: $meal) {
                            ForEach(app.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                        }
                    }
                } footer: {
                    Text(footer)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isMove ? "Move to Day" : "Copy to Day")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isMove ? "Move" : "Copy", action: apply)
                        .disabled(!changesSomething)
                }
            }
            .onAppear(perform: setUp)
            .onDisappear { TodayEntrySheetMode.opensToMove = false }
        }
        .sheetFrame(minWidth: 420, minHeight: 340)
    }

    /// "3 entries · 1,240 kcal"; a move adds that the times of day stay.
    private var footer: String {
        let energy = entries.map(\.energy).reduce(0, +)
        let summary = "\(entries.count) \(entries.count == 1 ? "entry" : "entries") · \(Fmt.energy(energy, unit: app.energyUnit))"
        return isMove ? summary + " · same time of day" : summary
    }

    /// Starts on the diary's today (at noon, so a late day start never shifts the date) and on the
    /// entries' own meal.
    private func setUp() {
        guard !isSetUp else { return }
        isSetUp = true
        date = app.today.date(minutes: 12 * 60)
        if let first = entries.first, app.settings.meals.contains(where: { $0.id == first.meal }) {
            meal = first.meal
        } else if let slot = app.settings.meals.first {
            meal = slot.id
        }
    }

    private func apply() {
        let day = targetDay
        if isMove {
            app.todayMove(entries, to: day, meal: keepMeals ? nil : meal)
        } else {
            app.copy(entries, to: day, meal: keepMeals ? nil : meal, status: planned ? .planned : .eaten)
        }
        dismiss()
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
                    Text(entries.count == 1
                         ? "Log this food again with one tap from any meal's + menu or the search."
                         : "Log all \(entries.count) foods again with one tap from any meal's + menu or the search.")
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
            }
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
