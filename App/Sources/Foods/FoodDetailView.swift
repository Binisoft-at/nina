import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Everything about a food: nutrition per 100 g and per portion, highlights explained, portions,
/// how often you eat it, tags, and where the values come from.
struct FoodDetailView: View {
    let record: FoodRecord
    let mode: FoodPickMode
    var showsDone = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var meal = ""
    @State private var portion: AmountText?
    @State private var tagText = ""
    @State private var editingTags = false

    /// The live version (favourite and tags change while the page is open).
    private var current: FoodRecord { app.library.record(record.ref) ?? record }

    var body: some View {
        let food = current
        Form {
            Section {
                HStack(spacing: 14) {
                    CategoryBadge(category: food.category, emoji: food.emoji, size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.displayName(app.language)).font(.title2.weight(.semibold))
                        if let other = food.secondaryName(app.language) {
                            Text(other).foregroundStyle(.secondary)
                        }
                        Text([food.brand, food.category.title].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HighlightBadges(highlights: food.highlights)
                if mode.isLogging {
                    NavigationLink {
                        PortionView(record: food, mode: .log(day: app.selectedDay, meal: meal), day: app.selectedDay, meal: $meal) { _ in }
                    } label: {
                        Label("Log This Food", systemImage: "plus.circle.fill")
                            .foregroundStyle(Brand.accent)
                    }
                }
            }

            Section {
                Picker("Show for", selection: Binding(get: { portion?.unitLabel ?? "" }, set: { label in
                    portion = portionOptions.first { $0.unitLabel == label }
                })) {
                    Text("100 \(food.unit == .serving ? "servings" : food.unit.symbol)").tag("")
                    ForEach(portionOptions, id: \.unitLabel) { option in
                        Text(Fmt.amount(option)).tag(option.unitLabel)
                    }
                }
                NutritionLabel(record: food, amount: portion, unit: app.energyUnit)
                let shares = food.nutrients.macroShares
                Text("Energy from protein / carbs / fat: \(shares.percentText) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Nutrition")
            }

            if !food.highlights.isEmpty {
                Section("Why these badges") {
                    ForEach(food.highlights, id: \.self) { highlight in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.title).font(.subheadline.weight(.semibold))
                            Text(highlight.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let usage = app.library.usage(of: food.ref) {
                Section("Your history") {
                    LabeledContent("Logged", value: "\(usage.count)× in the last 6 months")
                    if let last = usage.lastUsed {
                        LabeledContent("Last time", value: last.formatted(.relative(presentation: .named)))
                    }
                    if usage.lastAmount > 0, food.unit != .serving {
                        LabeledContent("Usually", value: "\(Fmt.number(usage.lastAmount.rounded())) \(food.unit.symbol)")
                    }
                }
            }

            Section {
                if food.tags.isEmpty, !editingTags {
                    Button("Add Tags", systemImage: "number") { startEditingTags(food) }
                } else if editingTags {
                    TextField("breakfast, high-protein, quick", text: $tagText)
                        .onSubmit { saveTags() }
                    Button("Save Tags") { saveTags() }
                } else {
                    HStack {
                        ForEach(food.tags, id: \.self) { tag in Chip(text: "#" + tag, tint: Brand.accent) }
                        Spacer()
                        Button("Edit") { startEditingTags(food) }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Tags")
            } footer: {
                Text("Group and filter foods by your own labels in the Foods tab.")
            }

            Section {
                Button(food.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: food.isFavorite ? "star.slash" : "star") {
                    app.toggleFavorite(food)
                }
                if food.ref.kind != .recipe {
                    Button(food.recordID == nil ? "Customize (Your Own Values or Portions)" : "Edit Food", systemImage: "pencil") {
                        let editable = app.store.personalize(food)
                        app.store.save()
                        app.present(.editFood(editable))
                    }
                    Button("Save as New Food…", systemImage: "plus.square.on.square") {
                        var draft = FoodDraft(name: food.name + " (copy)", nameDE: food.nameDE, brand: food.brand, category: food.category,
                                              tags: food.tags, unit: food.unit == .milliliter ? .milliliter : .gram, nutrients: food.nutrients,
                                              servings: food.servings)
                        draft.isFavorite = false
                        app.present(.newFood(draft))
                    }
                }
                if food.ref.kind == .catalog {
                    Button("Hide from Search", systemImage: "eye.slash") {
                        app.store.setHidden(food, true)
                        dismiss()
                    }
                }
                if let id = food.recordID, food.ref.kind == .food, let own = app.store.food(id) {
                    Button("Delete Food", systemImage: "trash", role: .destructive) {
                        app.trash(own)
                        dismiss()
                    }
                }
            }

            Section {
                Text(sourceText(food))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(food.displayName(app.language))
        .inlineNavigationTitle()
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if meal.isEmpty { meal = app.settings.suggestedMeal().id }
            if portion == nil { portion = portionOptions.first }
        }
    }

    private var portionOptions: [AmountText] {
        let food = current
        var options = food.servings.map {
            AmountText(quantity: 1, unitLabel: $0.label(app.language), unitAmount: $0.amount, baseUnit: food.unit)
        }
        if food.usualAmount > 0, !food.servings.contains(where: { abs($0.amount - food.usualAmount) < 0.5 }), food.unit != .serving {
            options.insert(AmountText(quantity: food.usualAmount.rounded(), unitLabel: food.unit.symbol, unitAmount: 1, baseUnit: food.unit), at: 0)
        }
        var seen = Set<String>()
        return options.filter { seen.insert($0.unitLabel).inserted }
    }

    private func startEditingTags(_ food: FoodRecord) {
        tagText = food.tags.joined(separator: ", ")
        editingTags = true
    }

    private func saveTags() {
        let tags = tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        app.store.setTags(current, tags)
        editingTags = false
    }

    private func sourceText(_ food: FoodRecord) -> String {
        switch food.source {
        case .catalog:
            if food.ref.rawValue.hasPrefix("usda:") {
                return "Values: USDA National Nutrient Database for Standard Reference (SR28), public domain. ID \(food.ref.rawValue.dropFirst(5))."
            }
            return "Values: typical values for this kind of product (labels or a recipe calculation from USDA ingredients). Customize it to use your product's label."
        case .barcode: return "Your food, from Open Food Facts (ODbL) – values entered by the community."
        case .imported: return "Your food, imported from a CSV file."
        case .recipe: return "Your recipe; values are the sum of its ingredients."
        case .custom: return "Your own food."
        }
    }
}
