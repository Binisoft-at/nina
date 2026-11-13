import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Create or edit a food from its label: per 100 g (or 100 ml), the EU label nutrients, more on
/// request, household portions, barcode, tags. Warns when the calories don't fit the macros.
struct FoodEditor: View {
    let food: Food?

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
    @FocusState private var nameFocused: Bool

    init(food: Food?, draft: FoodDraft?) {
        self.food = food
        let source = food?.draft ?? draft ?? FoodDraft(name: "", nutrients: NutrientValues())
        _name = State(initialValue: source.name)
        _nameDE = State(initialValue: source.nameDE)
        _brand = State(initialValue: source.brand)
        _category = State(initialValue: source.category)
        _isLiquid = State(initialValue: source.unit == .milliliter)
        var texts: [Nutrient: String] = [:]
        for nutrient in Nutrient.allCases where nutrient != .sodium {
            if let value = source.nutrients[nutrient], !(source.nutrients.isEmpty) {
                texts[nutrient] = NumberText.plain(value, decimals: nutrient == .energy ? 0 : 2)
            }
        }
        if draft != nil, food == nil, source.nutrients == .zero { texts = [:] }
        _values = State(initialValue: texts)
        _salt = State(initialValue: source.nutrients.salt.map { NumberText.plain($0, decimals: 2) } ?? "")
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
        NavigationStack {
            Form {
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
                    nutrientField(.fiber, title: "Fibre", unit: "g")
                    nutrientField(.protein, title: "Protein", unit: "g")
                    numberRow("Salt", text: $salt, unit: "g")
                    if showMore {
                        ForEach(Nutrient.allCases.filter { !Nutrient.label.contains($0) }, id: \.self) { nutrient in
                            nutrientField(nutrient, title: nutrient.title, unit: nutrient.measure.symbol)
                        }
                    }
                    Button(showMore ? "Fewer Nutrients" : "More Nutrients (Vitamins, Minerals …)") {
                        withAnimation { showMore.toggle() }
                    }
                } header: {
                    Text("Nutrition per 100 \(unitSymbol)")
                } footer: {
                    if let atwaterWarning {
                        Label(atwaterWarning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Copy the values from the label. Empty fields count as unknown, not zero.")
                    }
                }

                Section {
                    ForEach(servings) { serving in
                        HStack {
                            Text(serving.en)
                            Spacer()
                            Text("\(Fmt.number(serving.amount, decimals: 1)) \(unitSymbol)").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { servings.remove(atOffsets: $0) }
                    .onMove { servings.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("slice, pack, glass …", text: $newServingName)
                        TextField(unitSymbol, text: $newServingAmount)
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
                    }
                } header: {
                    Text("Portions")
                } footer: {
                    Text("The first portion is offered first when you log it. Grams and ml always work.")
                }

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
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear { if food == nil, name.isEmpty { nameFocused = true } }
        }
        .sheetFrame(minWidth: 560, minHeight: 720)
    }

    private func nutrientField(_ nutrient: Nutrient, title: String, unit: String, indent: Bool = false) -> some View {
        numberRow(title, text: Binding(get: { values[nutrient] ?? "" }, set: { values[nutrient] = $0 }), unit: unit, indent: indent)
    }

    private func numberRow(_ title: String, text: Binding<String>, unit: String, indent: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(indent ? .secondary : .primary)
                .padding(.leading, indent ? 14 : 0)
            Spacer()
            TextField("–", text: text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 90)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
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
        if food == nil {
            app.present(.food(saved.record))
        } else {
            dismiss()
        }
    }
}
