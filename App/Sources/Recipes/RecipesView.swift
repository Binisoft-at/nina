import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Saved meals (logged as their foods in one tap) and recipes (logged by portion).
struct RecipesView: View {
    @Environment(AppModel.self) private var app
    @Query(RecipesView.listed) private var recipes: [Recipe]
    /// Kept per window while you switch between sidebar sections (Mac) or Foods and Meals (iPhone).
    @SceneStorage("nina.recipes.query") private var query = ""

    /// Not deleted, in the person's order, then by name. Spelled out with explicit types: as one
    /// inline `@Query(filter:sort:)` expression the compiler gives up type-checking it.
    private static var listed: FetchDescriptor<Recipe> {
        let notDeleted = #Predicate<Recipe> { $0.deletedAt == nil }
        let byOrder = SortDescriptor<Recipe>(\.sortOrder)
        let byName = SortDescriptor<Recipe>(\.name)
        return FetchDescriptor<Recipe>(predicate: notDeleted, sortBy: [byOrder, byName])
    }

    private var filtered: [Recipe] {
        let needle = SearchText.normalize(query)
        guard !needle.isEmpty else { return recipes }
        return recipes.filter { recipe in
            SearchText.normalize(recipe.name + " " + recipe.sortedItems.map(\.name).joined(separator: " ") + " " + recipe.tags).contains(needle)
        }
    }

    var body: some View {
        List {
            let favorites = filtered.filter(\.isFavorite)
            if !favorites.isEmpty {
                Section("Favorites") { ForEach(favorites) { row($0) } }
            }
            let meals = filtered.filter { $0.recipeKind == .meal && !$0.isFavorite }
            if !meals.isEmpty {
                Section {
                    ForEach(meals) { row($0) }
                } header: {
                    Text("Meals")
                } footer: {
                    Text("A meal logs all its foods at once – perfect for the breakfast you eat every day.")
                }
            }
            let cooked = filtered.filter { $0.recipeKind == .recipe && !$0.isFavorite }
            if !cooked.isEmpty {
                Section {
                    ForEach(cooked) { row($0) }
                } header: {
                    Text("Recipes")
                } footer: {
                    Text("A recipe is cooked once and logged by portion or by weight.")
                }
            }
        }
        .overlay {
            if recipes.isEmpty {
                EmptyStateView(title: "No meals or recipes yet",
                               message: "Save what you eat together as a meal, or add a recipe – then log it with one tap.",
                               symbol: "frying.pan", createTitle: "New Meal",
                               onCreate: { app.sheet = .recipe(nil, kind: .meal) },
                               onImport: { app.sheet = .importData(.recipes) })
            }
        }
        .searchable(text: $query, prompt: "Search meals and recipes")
        .navigationTitle("Meals & Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Meal…", systemImage: "takeoutbag.and.cup.and.straw") { app.sheet = .recipe(nil, kind: .meal) }
                    Button("New Recipe…", systemImage: "frying.pan") { app.sheet = .recipe(nil, kind: .recipe) }
                    Button("Import…", systemImage: "square.and.arrow.down") { app.sheet = .importData(.recipes) }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        let record = recipe.record
        let perServing = record.nutrients(forAmount: record.initialAmount(language: app.language).total).energy
        return Button {
            app.sheet = .recipe(recipe, kind: recipe.recipeKind)
        } label: {
            HStack(spacing: 12) {
                Text(recipe.symbol)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(Color.teal.opacity(0.15), in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(recipe.displayName)
                        if recipe.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    Text(recipe.sortedItems.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.energy(recipe.recipeKind == .meal ? recipe.totals.energy : perServing, unit: app.energyUnit))
                        .font(.subheadline.monospacedDigit())
                    Text(recipe.recipeKind == .meal ? Self.foodCount(recipe.sortedItems.count) : "per serving")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .swipeActions(edge: .leading) {
            Button("Log", systemImage: "plus") { logNow(recipe) }
                .tint(Brand.accent)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { app.trash(recipe) }
        }
        .contextMenu {
            Menu("Log to", systemImage: "plus") {
                ForEach(app.settings.meals) { slot in
                    Button("\(slot.emoji) \(slot.name)") { app.logRecipe(recipe, day: app.selectedDay, meal: slot.id) }
                }
            }
            Button("Plan as Routine…", systemImage: "calendar.badge.clock") { app.sheet = .planRule(nil, recipe: recipe) }
            Button(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
                app.store.setFavorite(recipe.record, !recipe.isFavorite)
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                app.store.saveRecipe(nil, name: recipe.displayName + " (copy)", kind: recipe.recipeKind, emoji: recipe.emoji,
                                     servings: recipe.servings, totalWeight: recipe.totalWeight, notes: recipe.notes,
                                     defaultMeal: recipe.defaultMeal, lines: recipe.sortedItems.map(RecipeLine.init(item:)))
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { app.trash(recipe) }
        }
    }

    /// "1 food", "3 foods"
    private static func foodCount(_ count: Int) -> String {
        count == 1 ? "1 food" : "\(count) foods"
    }

    private func logNow(_ recipe: Recipe) {
        let meal = recipe.defaultMeal.isEmpty ? app.settings.suggestedMeal().id : recipe.defaultMeal
        app.logRecipe(recipe, day: app.selectedDay, meal: meal)
    }
}

/// Create or edit a meal or recipe: its foods with amounts, totals, portions, notes.
struct RecipeEditor: View {
    let recipe: Recipe?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var kind: RecipeKind
    @State private var lines: [RecipeLine]
    @State private var servings: Double
    @State private var cookedWeight: String
    @State private var notes: String
    @State private var defaultMeal: String
    @State private var showPicker = false
    @State private var editingLine: RecipeLine?
    @State private var confirmDiscard = false
    /// What the editor opened with: Cancel and a swipe down ask before throwing changes away.
    @State private var original: RecipeEditorSnapshot

    init(recipe: Recipe?, kind: RecipeKind) {
        self.recipe = recipe
        // One value per field, used for the field and for the snapshot (one plain expression each).
        let initialName: String = recipe?.name ?? ""
        let initialEmoji: String = recipe?.emoji ?? ""
        let initialKind: RecipeKind = recipe?.recipeKind ?? kind
        let initialLines: [RecipeLine] = recipe?.sortedItems.map(RecipeLine.init(item:)) ?? []
        let defaultServings: Double = kind == .recipe ? 4 : 1
        let initialServings: Double = recipe?.servings ?? defaultServings
        let totalWeight: Double = recipe?.totalWeight ?? 0
        let initialCooked: String = totalWeight > 0 ? NumberText.plain(totalWeight, decimals: 0) : ""
        let initialNotes: String = recipe?.notes ?? ""
        let initialMeal: String = recipe?.defaultMeal ?? ""
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: initialEmoji)
        _kind = State(initialValue: initialKind)
        _lines = State(initialValue: initialLines)
        _servings = State(initialValue: initialServings)
        _cookedWeight = State(initialValue: initialCooked)
        _notes = State(initialValue: initialNotes)
        _defaultMeal = State(initialValue: initialMeal)
        let opened = RecipeEditorSnapshot(name: initialName, emoji: initialEmoji, kind: initialKind, lines: initialLines,
                                          servings: initialServings, cookedWeight: initialCooked, notes: initialNotes,
                                          defaultMeal: initialMeal)
        _original = State(initialValue: opened)
    }

    private var isDirty: Bool {
        RecipeEditorSnapshot(name: name, emoji: emoji, kind: kind, lines: lines, servings: servings, cookedWeight: cookedWeight,
                             notes: notes, defaultMeal: defaultMeal) != original
    }

    private var totals: NutrientValues { NutrientValues.sum(lines.map(\.nutrients)) }
    private var rawWeight: Double { lines.filter { $0.amount.baseUnit != .serving }.map(\.amount.total).reduce(0, +) }
    private var weight: Double { NumberText.parse(cookedWeight) ?? rawWeight }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("🍲", text: $emoji)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .onChange(of: emoji) { _, value in if value.count > 1 { emoji = String(value.suffix(1)) } }
                        TextField(kind == .meal ? "Name, e.g. Usual breakfast" : "Name, e.g. Chili con carne", text: $name)
                            .font(.headline)
                    }
                    LabeledContent {
                        Picker("Type", selection: $kind) {
                            Text("Meal").tag(RecipeKind.meal)
                            Text("Recipe").tag(RecipeKind.recipe)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } label: {
                        Text("Type")
                            .info(RecipeEditorInfo.kind.title, RecipeEditorInfo.kind.text)
                    }
                } footer: {
                    Text(kind == .meal ? "Logging a meal adds each food separately – you can still change one later." : "Logging a recipe adds one entry: a portion or a weight of the cooked dish.")
                }

                Section {
                    ForEach(lines) { line in
                        Button {
                            editingLine = line
                        } label: {
                            HStack(spacing: 10) {
                                CategoryBadge(category: line.category, emoji: FoodEmoji.emoji(for: [line.name], category: line.category), size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.name).foregroundStyle(.primary)
                                    Text(Fmt.amount(line.amount)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Fmt.energy(line.nutrients.energy, unit: app.energyUnit))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add Food", systemImage: "plus.circle.fill") { showPicker = true }
                } header: {
                    Text("Foods")
                }

                if kind == .recipe {
                    Section {
                        Stepper("Makes \(AmountText.quantity(servings)) \(servings == 1 ? "serving" : "servings")", value: $servings, in: 1...40, step: 1)
                        HStack {
                            Text("Cooked weight")
                                .info(RecipeEditorInfo.cookedWeight.title, RecipeEditorInfo.cookedWeight.text)
                            Spacer()
                            TextField("Cooked weight", text: $cookedWeight,
                                      prompt: Text(rawWeight > 0 ? Fmt.number(rawWeight.rounded()) : "optional"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(maxWidth: 90)
                            Text("g").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Weigh the pot after cooking (minus the pot) to log by weight – water evaporates, so raw weights overstate portions.")
                    }
                }

                Section("Totals") {
                    LabeledContent(kind == .meal ? "Whole meal" : "Whole recipe", value: Fmt.energy(totals.energy, unit: app.energyUnit))
                    if kind == .recipe {
                        LabeledContent("Per serving", value: Fmt.energy(totals.energy / max(servings, 1), unit: app.energyUnit))
                        if weight > 0 {
                            LabeledContent("Per 100 g", value: Fmt.energy(totals.energy / weight * 100, unit: app.energyUnit))
                        }
                    }
                    HStack {
                        ForEach(Nutrient.macros, id: \.self) { nutrient in
                            VStack(alignment: .leading) {
                                Text(nutrient.shortTitle).font(.caption).foregroundStyle(.secondary)
                                Text(Fmt.nutrient(kind == .recipe ? totals.value(nutrient) / max(servings, 1) : totals.value(nutrient), nutrient))
                                    .font(.subheadline.monospacedDigit())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Section {
                    Picker("Usually at", selection: $defaultMeal) {
                        Text("Any meal").tag("")
                        ForEach(app.settings.meals) { slot in Text("\(slot.emoji) \(slot.name)").tag(slot.id) }
                    }
                    TextField(kind == .recipe ? "Preparation, notes" : "Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...8)
                }

                if let recipe {
                    Section {
                        Button("Log Now", systemImage: "plus.circle") {
                            save(close: false)
                            app.logRecipe(recipe, day: app.selectedDay, meal: defaultMeal.isEmpty ? app.settings.suggestedMeal().id : defaultMeal)
                            dismiss()
                        }
                        Button("Plan as Routine…", systemImage: "calendar.badge.clock") {
                            save(close: false)
                            app.present(.planRule(nil, recipe: recipe))
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            app.trash(recipe)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(recipe == nil ? (kind == .meal ? "New Meal" : "New Recipe") : name)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(close: true) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || lines.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                FoodSearchView(mode: .pick { line in lines.append(line) })
                    .environment(app)
            }
            .sheet(item: $editingLine) { line in
                LineAmountEditor(line: line) { updated in
                    if let index = lines.firstIndex(where: { $0.id == updated.id }) { lines[index] = updated }
                }
                .environment(app)
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .sheetFrame(minWidth: 560, minHeight: 560)
    }

    private func save(close: Bool) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !lines.isEmpty else { return }
        let cooked = NumberText.parse(cookedWeight) ?? 0
        app.store.saveRecipe(recipe, name: name, kind: kind, emoji: emoji, servings: servings, totalWeight: kind == .recipe ? cooked : 0,
                             notes: notes, defaultMeal: defaultMeal, lines: lines)
        if close {
            app.toasts.show("Saved \u{201C}\(name)\u{201D}", symbol: "checkmark.circle.fill")
            dismiss()
        }
    }
}

/// The ⓘ texts of the recipe editor: meal or recipe, and the cooked weight.
private enum RecipeEditorInfo {
    static let kind: (title: String, text: String) = (
        "Meal or recipe",
        "A meal is foods you eat together, like your usual breakfast: logging it adds each food. A recipe is a dish you "
            + "cook once and eat in portions: logging it adds one entry, by serving or by weight."
    )

    static let cookedWeight: (title: String, text: String) = (
        "Cooked weight",
        "Weigh the finished dish without the pot, so a weighed portion counts right. Cooking changes the weight (water "
            + "cooks off, pasta and rice soak it up); without it Nina uses the raw ingredients' weight."
    )
}

/// What the recipe editor's fields held when it opened.
private struct RecipeEditorSnapshot: Equatable {
    var name: String
    var emoji: String
    var kind: RecipeKind
    var lines: [RecipeLine]
    var servings: Double
    var cookedWeight: String
    var notes: String
    var defaultMeal: String
}

/// Change one ingredient's amount (its nutrients follow).
struct LineAmountEditor: View {
    let line: RecipeLine
    let onSave: (RecipeLine) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var amount: AmountText

    init(line: RecipeLine, onSave: @escaping (RecipeLine) -> Void) {
        self.line = line
        self.onSave = onSave
        _amount = State(initialValue: line.amount)
    }

    private var record: FoodRecord {
        if let found = app.library.record(line.ref) { return found }
        let total = max(line.amount.total, 0.0001)
        return FoodRecord(ref: line.ref, name: line.name, category: line.category, unit: line.amount.baseUnit,
                          nutrients: line.nutrients.scaled(by: line.amount.baseUnit.basis / total),
                          servings: line.amount.isBaseUnit ? [] : [Serving(en: line.amount.unitLabel, amount: line.amount.unitAmount)])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(line.name) {
                    AmountPicker(record: record, language: app.language, amount: $amount)
                }
                Section {
                    NutritionPreview(values: record.nutrients(forAmount: amount.total), targets: app.settings.targets, unit: app.energyUnit)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Amount")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = line
                        updated.amount = amount
                        updated.nutrients = record.nutrients(forAmount: amount.total)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
        .sheetFrame(minWidth: 460, minHeight: 420)
    }
}
