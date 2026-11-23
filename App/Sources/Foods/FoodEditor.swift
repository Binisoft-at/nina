import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Create or edit a food from its label: per 100 g (or 100 ml), the EU label nutrients, more on
/// request, household portions, barcode, tags. Warns when the calories don't fit the macros.
/// Opened as its own sheet, or pushed inside the log sheet (`onCreated`): "not found → create it →
/// log it" then stays in one place.
struct FoodEditor: View {
    let food: Food?
    /// Set when the editor is pushed inside the log or barcode sheet: Save hands the new food
    /// over (the sheet shows its amount page next) instead of opening the food's page.
    let onCreated: ((FoodRecord) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var nameDE: String
    @State private var brand: String
    @State private var category: FoodCategory
    @State private var isLiquid: Bool
    @State private var values: [Nutrient: String]
    @State private var salt: String
    @State private var servings: [Serving]
    @State private var barcode: String
    @State private var tags: String
    @State private var isFavorite: Bool
    @State private var notes: String
    @State private var showMore = false
    @State private var newServingName = ""
    @State private var newServingAmount = ""
    /// The fields as they opened (after the energy is shown in the chosen unit): Cancel and a
    /// swipe down ask before throwing changes away.
    @State private var original: FoodEditorSnapshot?
    @State private var confirmDiscard = false
    @FocusState private var nameFocused: Bool
    @FocusState private var field: FoodEditorField?
    /// The stored calories (kcal): shown in the energy unit on appear.
    private let initialEnergy: Double?

    init(food: Food?, draft: FoodDraft?, onCreated: ((FoodRecord) -> Void)? = nil) {
        self.food = food
        self.onCreated = onCreated
        let source = food?.draft ?? draft ?? FoodDraft(name: "", nutrients: NutrientValues())
        _name = State(initialValue: source.name)
        _nameDE = State(initialValue: source.nameDE)
        _brand = State(initialValue: source.brand)
        _category = State(initialValue: source.category)
        _isLiquid = State(initialValue: source.unit == .milliliter)
        var texts: [Nutrient: String] = [:]
        for nutrient in Nutrient.allCases where nutrient != .sodium && nutrient != .energy {
            if let value = source.nutrients[nutrient], !(source.nutrients.isEmpty) {
                texts[nutrient] = Fmt.editableNumber(value, decimals: 2)
            }
        }
        let isBlank = draft != nil && food == nil && source.nutrients == .zero
        if isBlank { texts = [:] }
        initialEnergy = isBlank || source.nutrients.isEmpty ? nil : source.nutrients[.energy]
        _values = State(initialValue: texts)
        _salt = State(initialValue: isBlank ? "" : source.nutrients.salt.map { Fmt.editableNumber($0, decimals: 2) } ?? "")
        _servings = State(initialValue: source.servings)
        _barcode = State(initialValue: source.barcode)
        _tags = State(initialValue: source.tags.joined(separator: ", "))
        _isFavorite = State(initialValue: source.isFavorite)
        _notes = State(initialValue: source.notes)
    }

    private var unitSymbol: String { isLiquid ? "ml" : "g" }

    private var nutrients: NutrientValues {
        var result = NutrientValues()
        for (nutrient, text) in values {
            guard let value = NumberText.parse(text) else { continue }
            result[nutrient] = nutrient == .energy ? app.energyUnit.kilocalories(from: value) : value
        }
        if let saltValue = NumberText.parse(salt) {
            result[.sodium] = NutrientValues.sodium(fromSalt: saltValue)
        }
        for nutrient in [Nutrient.protein, .carbs, .fat] where result[nutrient] == nil && result[.energy] != nil {
            result[nutrient] = 0
        }
        return result
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nutrients[.energy] != nil
    }

    private var snapshot: FoodEditorSnapshot {
        FoodEditorSnapshot(name: name, nameDE: nameDE, brand: brand, category: category, isLiquid: isLiquid, values: values,
                           salt: salt, servings: servings, barcode: barcode, tags: tags, isFavorite: isFavorite, notes: notes,
                           newServingName: newServingName, newServingAmount: newServingAmount)
    }

    private var isDirty: Bool {
        guard let original else { return false }
        return snapshot != original
    }

    /// The label's kcal should be close to 4·protein + 4·carbs + 9·fat (+ 7·alcohol, + 2·fiber).
    private var atwaterWarning: String? {
        let n = nutrients
        guard let energy = n[.energy], energy > 20 else { return nil }
        let expected = n.energyFromMacros + 2 * n.value(.fiber)
        guard expected > 0 else { return nil }
        let difference = abs(energy - expected)
        guard difference > max(25, energy * 0.2) else { return nil }
        return "The macros add up to about \(Fmt.energy(expected, unit: app.energyUnit)), not \(Fmt.energy(energy, unit: app.energyUnit)). Worth a second look at the label."
    }

    var body: some View {
        if onCreated != nil {
            editor
                .navigationBarBackButtonHidden(true)
        } else {
            NavigationStack { editor }
                .sheetFrame(minWidth: 560, minHeight: 560)
        }
    }

    private var editor: some View {
        form
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
            .inlineNavigationTitle()
            .toolbar { toolbar }
            .onAppear(perform: prefill)
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
    }

    private var form: some View {
        Form {
            namesSection
            nutritionSection
            portionsSection
            moreSection
            if let food, food.catalogID.isEmpty {
                Section {
                    Button("Delete Food", systemImage: "trash", role: .destructive) {
                        app.trash(food)
                        dismiss()
                    }
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var namesSection: some View {
        Section {
            TextField("Name", text: $name)
                .focused($nameFocused)
            TextField("German name (optional)", text: $nameDE)
            TextField("Brand (optional)", text: $brand)
            Picker("Category", selection: $category) {
                ForEach(FoodCategory.allCases) { category in
                    Text("\(category.emoji) \(category.title)").tag(category)
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            Picker("Values per", selection: $isLiquid) {
                Text("100 g").tag(false)
                Text("100 ml").tag(true)
            }
            .pickerStyle(.segmented)
            nutrientField(.energy, title: "Energy", unit: app.energyUnit.symbol)
            nutrientField(.fat, title: "Fat", unit: "g")
            nutrientField(.saturatedFat, title: "of which saturates", unit: "g", indent: true)
            nutrientField(.carbs, title: "Carbohydrate", unit: "g")
            nutrientField(.sugar, title: "of which sugars", unit: "g", indent: true)
            nutrientField(.fiber, title: "Fiber", unit: "g")
            nutrientField(.protein, title: "Protein", unit: "g")
            numberRow("Salt", text: $salt, unit: "g", focus: .salt)
            if showMore {
                ForEach(Self.extraNutrients, id: \.self) { nutrient in
                    nutrientField(nutrient, title: nutrient.title, unit: nutrient.measure.symbol)
                }
            }
            Button(showMore ? "Fewer Nutrients" : "More Nutrients (Vitamins, Minerals …)") {
                withAnimation { showMore.toggle() }
            }
        } header: {
            Text("Nutrition per 100 \(unitSymbol)")
                .info(FoodEditorInfo.label.title, FoodEditorInfo.label.text)
        } footer: {
            if let atwaterWarning {
                Label(atwaterWarning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Text("Copy the values from the label. Empty fields count as unknown, not zero.")
            }
        }
    }

    private var portionsSection: some View {
        Section {
            ForEach(servings) { serving in
                HStack {
                    Text(PortionLabel.display(serving.en, baseUnit: isLiquid ? .milliliter : .gram))
                    Spacer()
                    Text("\(Fmt.number(serving.amount, decimals: 1)) \(unitSymbol)").foregroundStyle(.secondary)
                }
            }
            .onDelete { servings.remove(atOffsets: $0) }
            .onMove { servings.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                TextField("slice, pack, glass …", text: $newServingName)
                TextField("Portion size", text: $newServingAmount, prompt: Text(unitSymbol))
                    .labelsHidden()
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
                Button {
                    addServing()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newServingName.isEmpty || NumberText.parse(newServingAmount) == nil)
                .accessibilityLabel("Add Portion")
            }
        } header: {
            Text("Portions")
                .info(FoodEditorInfo.portions.title, FoodEditorInfo.portions.text)
        } footer: {
            Text("The first portion is offered first when you log it. Grams and ml always work.")
        }
    }

    private var moreSection: some View {
        Section {
            TextField("Barcode (optional)", text: $barcode)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            TextField("Tags, separated by commas", text: $tags)
            Toggle("Favorite", isOn: $isFavorite)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save).disabled(!canSave)
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            Button("Previous", systemImage: "chevron.up") { moveFocus(by: -1) }
                .disabled(field == nil || field == fieldOrder.first)
            Button("Next", systemImage: "chevron.down") { moveFocus(by: 1) }
                .disabled(field == fieldOrder.last)
            Spacer()
            Button("Done") {
                field = nil
                nameFocused = false
            }
        }
        #endif
    }

    // MARK: Fields

    private static var extraNutrients: [Nutrient] {
        Nutrient.allCases.filter { !Nutrient.label.contains($0) }
    }

    /// The number fields in label order, for Previous and Next above the keyboard.
    private var fieldOrder: [FoodEditorField] {
        var order: [FoodEditorField] = [.nutrient(.energy), .nutrient(.fat), .nutrient(.saturatedFat), .nutrient(.carbs),
                                        .nutrient(.sugar), .nutrient(.fiber), .nutrient(.protein), .salt]
        if showMore { order += Self.extraNutrients.map { FoodEditorField.nutrient($0) } }
        return order
    }

    private func moveFocus(by step: Int) {
        let order = fieldOrder
        guard let current = field, let index = order.firstIndex(of: current) else {
            field = order.first
            return
        }
        let next = index + step
        guard order.indices.contains(next) else { return }
        field = order[next]
    }

    private func nutrientField(_ nutrient: Nutrient, title: String, unit: String, indent: Bool = false) -> some View {
        numberRow(title, text: Binding(get: { values[nutrient] ?? "" }, set: { values[nutrient] = $0 }), unit: unit,
                  focus: .nutrient(nutrient), indent: indent)
    }

    private func numberRow(_ title: String, text: Binding<String>, unit: String, focus: FoodEditorField, indent: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(indent ? .secondary : .primary)
                .padding(.leading, indent ? 14 : 0)
            Spacer()
            TextField(title, text: text, prompt: Text("–"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .focused($field, equals: focus)
                .frame(maxWidth: 90)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    // MARK: Actions

    /// Shows the stored kcal in the chosen energy unit (a kJ field read back as kJ), once, and
    /// remembers the fields for the "Discard changes?" question.
    private func prefill() {
        guard original == nil else { return }
        if let initialEnergy {
            values[.energy] = NumberText.energyField(kilocalories: initialEnergy, unit: app.energyUnit)
        }
        original = snapshot
        if food == nil, name.isEmpty { nameFocused = true }
    }

    private func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func addServing() {
        guard let amount = NumberText.parse(newServingAmount), amount > 0, !newServingName.isEmpty else { return }
        servings.append(Serving(en: newServingName, amount: amount))
        newServingName = ""
        newServingAmount = ""
    }

    private func save() {
        guard canSave else { return }
        if !newServingName.isEmpty { addServing() }
        let draft = FoodDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            nameDE: nameDE,
            brand: brand,
            category: category,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            unit: isLiquid ? .milliliter : .gram,
            nutrients: nutrients,
            servings: servings,
            barcode: barcode.filter(\.isNumber),
            isFavorite: isFavorite,
            notes: notes
        )
        let saved = app.store.saveFood(draft, editing: food, source: barcode.isEmpty ? .custom : .barcode)
        app.refresh()
        app.toasts.show(food == nil ? "Saved \u{201C}\(saved.name)\u{201D}" : "Updated \u{201C}\(saved.name)\u{201D}", symbol: "checkmark.circle.fill")
        guard food == nil else {
            dismiss()
            return
        }
        if let onCreated {
            onCreated(saved.record)
        } else {
            app.present(.food(saved.record))
        }
    }
}

/// The ⓘ texts of the food editor: the label's values and the portions.
private enum FoodEditorInfo {
    static let label: (title: String, text: String) = (
        "Label values",
        "Type the kcal and grams from the label's \u{201C}per 100 g\u{201D} column (per 100 ml for drinks), not the "
            + "per-portion one. If the label only lists a portion, divide each value by the portion's weight and "
            + "multiply by 100."
    )

    static let portions: (title: String, text: String) = (
        "Portions",
        "Add the sizes you eat, like a 30 g slice or a 250 ml glass, so logging takes one tap. Nina works out a "
            + "portion's values from the label values above."
    )
}

/// A number field of the food editor (the keyboard's Previous and Next go through them in label order).
private enum FoodEditorField: Hashable {
    case nutrient(Nutrient)
    case salt
}

/// What the editor's fields held when it opened.
private struct FoodEditorSnapshot: Equatable {
    var name: String
    var nameDE: String
    var brand: String
    var category: FoodCategory
    var isLiquid: Bool
    var values: [Nutrient: String]
    var salt: String
    var servings: [Serving]
    var barcode: String
    var tags: String
    var isFavorite: Bool
    var notes: String
    var newServingName: String
    var newServingAmount: String
}
