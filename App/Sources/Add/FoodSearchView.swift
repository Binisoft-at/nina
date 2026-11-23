import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// Logging: search ~1,000 foods plus your own, or type a whole meal ("2 eggs, 1 toast and 200 ml
/// milk") and log it in one go. Also used to pick ingredients for meals and recipes. A food that
/// isn't there is created and logged without leaving the sheet.
struct FoodSearchView: View {
    let mode: FoodPickMode

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scope: Scope = .all
    @State private var meal: String
    @State private var day: DayKey
    @State private var path: [FoodSearchRoute] = []
    @State private var matches: [QuickMatch] = []
    /// The text `matches` were made from: a picked alternative survives library updates.
    @State private var matchedText = ""
    /// The list below the search field, worked out once per search (not on every redraw).
    @State private var results: [FoodRecord] = []
    /// How many of `results` lead as "Mostly at breakfast" (the Recent list for the meal being
    /// logged); 0 = one plain list.
    @State private var mealFirst = 0
    @State private var isQuick = false
    /// The search the shown results belong to (`searchKey`).
    @State private var shownKey = ""
    /// Mac: the result Return opens and ⌘Return adds; ↑ and ↓ move it.
    @State private var highlighted: FoodRef?
    @State private var added = 0
    /// "+18 g protein to reach 35" for the meal being logged to (with a protein minimum).
    @State private var proteinHint: String? = nil
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

    private var library: FoodLibrary { app.library }

    /// Everything the results depend on (the meal only while the Recent list shows: it sorts it).
    private var searchKey: String {
        let recentsMeal = text.trimmingCharacters(in: .whitespaces).isEmpty ? meal : ""
        return "\(text)\u{1}\(scope.rawValue)\u{1}\(library.version)\u{1}\(app.language.rawValue)\u{1}\(recentsMeal)"
    }

    var body: some View {
        NavigationStack(path: $path) {
            list
                .searchable(text: $text, placement: searchPlacement, prompt: "Food, or \u{201C}2 eggs and a toast\u{201D}")
                .searchFocused($searchFocused)
                .onSubmit(of: .search) { submit() }
                .task(id: searchKey) { await refreshResults() }
                .safeAreaInset(edge: .top, spacing: 0) {
                    topBar
                }
                .navigationTitle(title)
                .inlineNavigationTitle()
                .navigationDestination(for: FoodSearchRoute.self) { route in
                    destination(route)
                }
                .toolbar { toolbar }
                .onAppear(perform: start)
                .task(id: proteinHintKey) {
                    proteinHint = loadProteinHint()
                }
                #if os(macOS)
                .background { macKeys }
                #endif
        }
        .sheetFrame(minWidth: 560, minHeight: 560)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                if mode.isLogging, text.isEmpty, scope == .all {
                    savedMealsRow
                }
                if isQuick, !matches.isEmpty {
                    quickSection
                }
                resultsSection
                if results.isEmpty, !text.isEmpty, !isQuick, shownKey == searchKey {
                    notFound
                }
                actionsSection
            }
            #if os(macOS)
            .onChange(of: highlighted) { _, ref in
                if let ref { proxy.scrollTo(ref) }
            }
            #endif
        }
    }

    /// The scope picker, and the protein hint for the meal when it is below the minimum.
    private var topBar: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases) { scope in Text(scope.title).tag(scope) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 6)
            if let proteinHint {
                // On a material capsule: the list scrolls under this bar.
                Text(proteinHint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(NutrientStyle.color(.protein))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: .capsule)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    .accessibilityLabel("\(app.settings.meal(meal).name): \(proteinHint)")
            }
        }
    }

    // MARK: Protein hint

    private var proteinHintKey: String { "\(app.dataVersion)-\(day.rawValue)-\(meal)" }

    /// "+18 g protein to reach 35": what the meal still needs (planned food included) when the
    /// plan sets a protein minimum per meal and the meal counts; nil otherwise.
    private func loadProteinHint() -> String? {
        guard mode.isLogging, !meal.isEmpty, let rule = app.settings.todayCoachProteinRule, rule.counts(meal) else { return nil }
        let facts = app.store.entries(on: day).map(\.facts)
        guard let current = ProteinMeals.day(day, entries: facts, rule: rule).meal(meal) else { return nil }
        return ProteinMeals.hint(current.total, minimum: current.minimum)
    }

    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .always)
        #else
        .automatic
        #endif
    }

    /// "Log to Lunch", "Log to Dinner · Yesterday" (another day than today is always named).
    private var title: String {
        switch mode {
        case .log:
            if added > 0 { return "\(added) added" }
            let target = "Log to \(app.settings.meal(meal).name)"
            return day == app.today ? target : "\(target) · \(Fmt.dayTitle(day, today: app.today))"
        case .pick:
            return "Add Ingredient"
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

    // MARK: Results

    /// Waits ~80 ms after a keystroke (a newer one cancels this), then searches once.
    private func refreshResults() async {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty, !shownKey.isEmpty {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
        }
        updateResults()
    }

    /// Searches now if the shown results are older than the text (Return can come before the pause).
    private func updateResults() {
        let key = searchKey
        guard key != shownKey else { return }
        let quick = FoodLibrary.looksLikeQuickAdd(text)
        if text != matchedText {
            matches = quick ? library.quickMatches(text) : []
            matchedText = text
        }
        isQuick = quick
        let current = currentResults()
        results = current.records
        mealFirst = current.forMeal
        shownKey = key
        highlighted = results.first?.ref
    }

    /// The list for the current search and scope, and how many of it lead as "Mostly at …".
    private func currentResults() -> (records: [FoodRecord], forMeal: Int) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            switch scope {
            case .all, .recent: return recentResults()
            case .favorites: return (library.favorites, 0)
            case .mine: return (library.records.filter { $0.recordID != nil && $0.ref.kind != .recipe }, 0)
            case .meals: return (library.records.filter { $0.ref.kind == .recipe }, 0)
            }
        }
        let list = library.search(query, limit: 80)
        switch scope {
        case .all: return (list, 0)
        case .favorites: return (list.filter(\.isFavorite), 0)
        case .recent: return (list.filter { library.usage(of: $0.ref) != nil }, 0)
        case .mine: return (list.filter { $0.recordID != nil && $0.ref.kind != .recipe }, 0)
        case .meals: return (list.filter { $0.ref.kind == .recipe }, 0)
        }
    }

    /// Logging: the foods mostly logged at this meal first, then the rest by recency. Picking an
    /// ingredient: the most recent first.
    private func recentResults() -> (records: [FoodRecord], forMeal: Int) {
        guard mode.isLogging, !meal.isEmpty else { return (library.recents(limit: 40), 0) }
        let recents = library.recents(for: meal, limit: 40)
        return (recents.all, recents.forMeal.count)
    }

    /// The leading "Mostly at …" part of `results` (never more than there are).
    private var leadCount: Int { min(mealFirst, results.count) }

    /// "Mostly at breakfast" over the leading part.
    private var mealHint: String {
        RecentFoods.hint(for: app.settings.meal(meal))
    }

    private var highlightedRecord: FoodRecord? {
        results.first { $0.ref == highlighted }
    }

    // MARK: Sections

    @ViewBuilder
    private var resultsSection: some View {
        let lead = leadCount
        if lead > 0 {
            Section {
                ForEach(results.prefix(lead)) { record in
                    resultRow(record)
                }
            } header: {
                Text(mealHint)
            }
            Section {
                ForEach(results.dropFirst(lead)) { record in
                    resultRow(record)
                }
            } header: {
                if results.count > lead { Text(resultsTitle) }
            }
        } else {
            Section {
                ForEach(results) { record in
                    resultRow(record)
                }
            } header: {
                if !results.isEmpty { Text(resultsTitle) }
            }
        }
    }

    private func resultRow(_ record: FoodRecord) -> some View {
        Button {
            path.append(.portion(record, created: false))
        } label: {
            FoodRow(record: record, language: app.language, unit: app.energyUnit, usage: library.usage(of: record.ref)) {
                quickAdd(record)
            }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .listRowBackground(rowBackground(record))
        .id(record.ref)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Add", systemImage: "plus") { quickAdd(record) }
                .tint(Brand.accent)
        }
        .swipeActions(edge: .trailing) {
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

    /// Mac: the highlighted result (↑/↓, Return) is tinted.
    private func rowBackground(_ record: FoodRecord) -> Color? {
        #if os(macOS)
        record.ref == highlighted && results.count > 1 ? Brand.accent.opacity(0.14) : nil
        #else
        nil
        #endif
    }

    private var notFound: some View {
        ContentUnavailableView {
            Label("No food called \u{201C}\(text)\u{201D}", systemImage: "magnifyingglass")
        } description: {
            Text("Create it from the label, scan its barcode, or log just the calories.")
        }
    }

    /// Saved meals and recipes that are favourites or were logged lately; the ones mostly logged at
    /// this meal first.
    private var savedMeals: [FoodRecord] {
        let saved = library.records.filter { $0.ref.kind == .recipe && ($0.isFavorite || library.usage(of: $0.ref) != nil) }
        guard !meal.isEmpty, saved.count > 1 else { return saved }
        let order = RecentFoods.sortedForMeal(saved.map(\.ref), usage: library.usage, meal: meal)
        return order.compactMap { library.record($0) }
    }

    @ViewBuilder
    private var savedMealsRow: some View {
        let meals = savedMeals
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
                QuickMatchRow(match: $match, language: app.language, unit: app.energyUnit) { query in
                    text = query
                }
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
            Text(quickFooter)
        }
    }

    private var quickFooter: String {
        #if os(macOS)
        "Click a line to pick another food. Press Return to add everything."
        #else
        "Tap a line to pick another food. Press Return to add everything."
        #endif
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
                path.append(.newFood(LogNewFoodRequest(draft: draft)))
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: FoodSearchRoute) -> some View {
        switch route {
        case .portion(let record, let created):
            PortionView(record: record, mode: mode, day: day, meal: $meal) { count in
                added += count
                // A food created here was the one thing missing: logged, the sheet's job is done.
                if created, mode.isLogging {
                    dismiss()
                } else {
                    finishAfterPortion()
                }
            }
        case .newFood(let request):
            FoodEditor(food: nil, draft: request.draft) { record in
                path = [.portion(record, created: true)]
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

    #if os(macOS)
    /// ↑ and ↓ move the highlighted result, ⌘Return adds it (Return in the search field opens it).
    private var macKeys: some View {
        Group {
            Button("Previous Result") { moveHighlight(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Next Result") { moveHighlight(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("Add Highlighted Result") { addHighlighted() }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .disabled(!path.isEmpty)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func moveHighlight(by step: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.ref == highlighted } ?? -1
        let next = min(max(index + step, 0), results.count - 1)
        highlighted = results[next].ref
    }

    private func addHighlighted() {
        updateResults()
        if isQuick {
            logMatches()
        } else if let record = highlightedRecord ?? results.first {
            quickAdd(record)
        }
    }
    #endif

    // MARK: Actions

    private func start() {
        if meal.isEmpty { meal = suggestedMeal() }
        searchFocused = true
    }

    /// Today: the meal of the hour. Another day: the first meal with nothing logged yet there
    /// (else the meal of the hour).
    private func suggestedMeal() -> String {
        let byClock = app.settings.suggestedMeal().id
        guard day != app.today else { return byClock }
        let logged = Set(app.store.entries(on: day).map(\.meal))
        return app.settings.meals.first { !logged.contains($0.id) }?.id ?? byClock
    }

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
        updateResults()
        if isQuick {
            logMatches()
        } else if let record = highlightedRecord ?? results.first {
            path.append(.portion(record, created: false))
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

/// Where the log sheet goes: a food's amount page (`created`: a food made right here), or a new food.
private enum FoodSearchRoute: Hashable {
    case portion(FoodRecord, created: Bool)
    case newFood(LogNewFoodRequest)
}

/// A food to create inside the log or barcode sheet ("not found → create it → log it").
struct LogNewFoodRequest: Hashable {
    let id = UUID()
    let draft: FoodDraft

    static func == (lhs: LogNewFoodRequest, rhs: LogNewFoodRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One understood line of a quick add: the food it matched (tap for alternatives) and the amount.
private struct QuickMatchRow: View {
    @Binding var match: QuickMatch
    let language: FoodLanguage
    let unit: EnergyUnit
    /// A line that found nothing: search for its words instead.
    let onSearch: (String) -> Void

    var body: some View {
        Menu {
            menuContent
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var menuContent: some View {
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
        if match.food == nil, !match.item.isEnergyOnly, !match.item.query.isEmpty {
            Button("Search for \u{201C}\(match.item.query)\u{201D}", systemImage: "magnifyingglass") {
                onSearch(match.item.query)
            }
        }
    }

    private var label: some View {
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
        match = QuickMatch(item: match.item, food: food, alternatives: alternatives,
                           amount: QuickParser.amount(for: match.item, food: food), language: match.language)
    }
}
