import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Logging: search ~1,000 foods plus your own, or type a whole meal ("2 eggs, 1 toast and 200 ml
/// milk") and log it in one go. Also used to pick ingredients for meals and recipes.
struct FoodSearchView: View {
    let mode: FoodPickMode

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scope: Scope = .all
    @State private var meal: String
    @State private var day: DayKey
    @State private var path: [FoodRecord] = []
    @State private var matches: [QuickMatch] = []
    @State private var added = 0
    @FocusState private var searchFocused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case all, favorites, recent, mine, meals
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .favorites: "Favorites"
            case .recent: "Recent"
            case .mine: "Mine"
            case .meals: "Meals"
            }
        }
    }

    init(mode: FoodPickMode) {
        self.mode = mode
        switch mode {
        case .log(let day, let meal):
            _day = State(initialValue: day)
            _meal = State(initialValue: meal ?? "")
        case .pick:
            _day = State(initialValue: DayKey.today())
            _meal = State(initialValue: "")
        }
    }

    private var isQuick: Bool { FoodLibrary.looksLikeQuickAdd(text) }
    private var library: FoodLibrary { app.library }

    private var results: [FoodRecord] {
        let query = text.trimmingCharacters(in: .whitespaces)
        var list: [FoodRecord]
        if query.isEmpty {
            switch scope {
            case .all, .recent: list = library.recents(limit: 40)
            case .favorites: list = library.favorites
            case .mine: list = library.records.filter { $0.recordID != nil && $0.ref.kind != .recipe }
            case .meals: list = library.records.filter { $0.ref.kind == .recipe }
            }
        } else {
            list = library.search(query, limit: 80)
            switch scope {
            case .all: break
            case .favorites: list = list.filter(\.isFavorite)
            case .recent: list = list.filter { library.usage(of: $0.ref) != nil }
            case .mine: list = list.filter { $0.recordID != nil && $0.ref.kind != .recipe }
            case .meals: list = list.filter { $0.ref.kind == .recipe }
            }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if mode.isLogging, text.isEmpty, scope == .all {
                    savedMealsRow
                }
                if isQuick, !matches.isEmpty {
                    quickSection
                }
                Section {
                    ForEach(results) { record in
                        Button {
                            path.append(record)
                        } label: {
                            FoodRow(record: record, language: app.language, unit: app.energyUnit, usage: library.usage(of: record.ref)) {
                                quickAdd(record)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star") {
                                app.toggleFavorite(record)
                            }
                            .tint(.yellow)
                        }
                        .contextMenu {
                            Button("Add \(Fmt.amount(record.initialAmount(language: app.language)))", systemImage: "plus") { quickAdd(record) }
                            Button(record.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") { app.toggleFavorite(record) }
                        }
                    }
                } header: {
                    if !results.isEmpty { Text(resultsTitle) }
                }
                if results.isEmpty, !text.isEmpty, !isQuick {
                    ContentUnavailableView {
                        Label("No food called \u{201C}\(text)\u{201D}", systemImage: "magnifyingglass")
                    } description: {
                        Text("Create it from the label, scan its barcode, or log just the calories.")
                    }
                }
                actionsSection
            }
            .searchable(text: $text, placement: searchPlacement, prompt: "Food, or \u{201C}2 eggs and a toast\u{201D}")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { submit() }
            .onChange(of: text) { _, newValue in
                matches = FoodLibrary.looksLikeQuickAdd(newValue) ? library.quickMatches(newValue) : []
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .navigationDestination(for: FoodRecord.self) { record in
                PortionView(record: record, mode: mode, day: day, meal: $meal) { count in
                    added += count
                    finishAfterPortion()
                }
            }
            .toolbar { toolbar }
            .onAppear {
                if meal.isEmpty {
                    meal = day == app.today ? app.settings.suggestedMeal().id : "lunch"
                }
                searchFocused = true
            }
        }
        .sheetFrame(minWidth: 560, minHeight: 700)
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    private var title: String {
        switch mode {
        case .log: added > 0 ? "\(added) added" : "Log to \(app.settings.meal(meal).name)"
        case .pick: "Add Ingredient"
        }
    }

    private var resultsTitle: String {
        if !text.isEmpty { return isQuick ? "Or pick one" : "Results" }
        switch scope {
        case .all, .recent: return "Recent"
        case .favorites: return "Favorites"
        case .mine: return "Your foods"
        case .meals: return "Meals & recipes"
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var savedMealsRow: some View {
        let meals = library.records.filter { $0.ref.kind == .recipe && ($0.isFavorite || library.usage(of: $0.ref) != nil) }
        if !meals.isEmpty {
            Section("Your meals") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(meals.prefix(12)) { record in
                            Button {
                                quickAdd(record)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.displayName(app.language)).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(Fmt.energy(record.nutrients(forAmount: record.initialAmount(language: app.language).total).energy, unit: app.energyUnit))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.teal.opacity(0.14), in: .rect(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
    }

    private var quickSection: some View {
        Section {
            ForEach($matches) { $match in
                QuickMatchRow(match: $match, language: app.language, unit: app.energyUnit)
            }
            let resolved = matches.filter(\.isResolved)
            Button {
                logMatches()
            } label: {
                let energy = resolved.map(\.nutrients.energy).reduce(0, +)
                Label(resolved.count == 1 ? "Add · \(Fmt.energy(energy, unit: app.energyUnit))" : "Add All \(resolved.count) · \(Fmt.energy(energy, unit: app.energyUnit))",
                      systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .disabled(resolved.isEmpty)
            .listRowBackground(Color.clear)
        } header: {
            Text("Understood")
        } footer: {
            Text("Tap a line to pick another food. Press Return to add everything.")
        }
    }

    private var actionsSection: some View {
        Section {
            if mode.isLogging {
                Button("Quick Calories", systemImage: "bolt.fill") {
                    app.present(.quickCalories(day: day, meal: meal))
                }
                #if os(iOS)
                Button("Scan a Barcode", systemImage: "barcode.viewfinder") {
                    app.present(.scanBarcode(day: day, meal: meal))
                }
                #else
                Button("Look Up a Barcode", systemImage: "barcode") {
                    app.present(.scanBarcode(day: day, meal: meal))
                }
                #endif
            }
            Button("Create a Food", systemImage: "square.and.pencil") {
                var draft = FoodDraft(name: text.trimmingCharacters(in: .whitespaces), nutrients: .zero)
                draft.category = .other
                app.present(.newFood(draft))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(added > 0 ? "Done" : "Cancel") { dismiss() }
        }
        if mode.isLogging {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(app.settings.meals) { slot in
                            Text("\(slot.emoji) \(slot.name)").tag(slot.id)
                        }
                    }
                } label: {
                    Text("\(app.settings.meal(meal).emoji) \(app.settings.meal(meal).name)")
                }
            }
        }
    }

    // MARK: Actions

    private func quickAdd(_ record: FoodRecord) {
        let amount = record.initialAmount(language: app.language)
        switch mode {
        case .log:
            app.log(record, amount: amount, day: day, meal: meal)
            added += 1
        case .pick(let onPick):
            onPick(RecipeLine(record: record, amount: amount, language: app.language))
            dismiss()
        }
    }

    private func logMatches() {
        let resolved = matches.filter(\.isResolved)
        guard !resolved.isEmpty else { return }
        switch mode {
        case .log:
            app.logMatches(resolved, day: day, meal: meal)
            dismiss()
        case .pick(let onPick):
            for match in resolved {
                if let food = match.food, let amount = match.amountText {
                    onPick(RecipeLine(record: food, amount: amount, language: app.language))
                }
            }
            dismiss()
        }
    }

    private func submit() {
        if isQuick {
            logMatches()
        } else if let first = results.first {
            path.append(first)
        }
    }

    private func finishAfterPortion() {
        switch mode {
        case .log:
            path.removeAll()
            text = ""
        case .pick:
            dismiss()
        }
    }
}

/// One understood line of a quick add: the food it matched (tap for alternatives) and the amount.
private struct QuickMatchRow: View {
    @Binding var match: QuickMatch
    let language: FoodLanguage
    let unit: EnergyUnit

    var body: some View {
        Menu {
            if let food = match.food {
                Section("Matched") {
                    Text(food.displayName(language))
                }
            }
            if !match.alternatives.isEmpty {
                Section("Use instead") {
                    ForEach(match.alternatives) { alternative in
                        Button(alternative.displayName(language)) { choose(alternative) }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let food = match.food {
                    CategoryBadge(category: food.category, emoji: food.emoji, size: 32)
                } else {
                    Image(systemName: match.item.isEnergyOnly ? "bolt.circle.fill" : "questionmark.circle")
                        .font(.title2)
                        .foregroundStyle(match.item.isEnergyOnly ? Color.orange : Color.secondary)
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(lineTitle)
                        .foregroundStyle(match.isResolved ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    Text(lineSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if match.isResolved {
                    Text(Fmt.energy(match.nutrients.energy, unit: unit))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var lineTitle: String {
        if match.item.isEnergyOnly { return match.item.query.isEmpty ? "Quick entry" : match.item.query.capitalized }
        return match.food?.displayName(language) ?? "\u{201C}\(match.item.query)\u{201D} – not found"
    }

    private var lineSubtitle: String {
        if let amount = match.amountText { return "\(Fmt.amount(amount)) · from \u{201C}\(match.item.original)\u{201D}" }
        return match.item.original
    }

    private func choose(_ food: FoodRecord) {
        var alternatives = match.alternatives.filter { $0.ref != food.ref }
        if let current = match.food { alternatives.insert(current, at: 0) }
        match = QuickMatch(item: match.item, food: food, alternatives: alternatives, amount: QuickParser.amount(for: match.item, food: food))
    }
}
