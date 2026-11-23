import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// iPhone: Foods and Meals & Recipes share a tab. Which one shows lives in `AppModel`, so links,
/// the tour and launch screens can open Meals & Recipes directly.
struct FoodsHomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.foodsPage {
            case .foods: FoodLibraryView()
            case .recipes: RecipesView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $app.foodsPage) {
                ForEach(FoodsPage.allCases) { page in Text(page.title).tag(page) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }
}

enum FoodGrouping: String, CaseIterable, Identifiable {
    case category, brand, tag, letter, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .category: "Category"
        case .brand: "Brand"
        case .tag: "Tag"
        case .letter: "First Letter"
        case .none: "No Groups"
        }
    }
}

enum FoodSorting: String, CaseIterable, Identifiable {
    case name, mostUsed, recent, lightest, richest, protein
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .mostUsed: "Most Logged"
        case .recent: "Recently Logged"
        case .lightest: "Fewest Calories"
        case .richest: "Most Calories"
        case .protein: "Most Protein per Calorie"
        }
    }
}

enum FoodScope: String, CaseIterable, Identifiable {
    case all, favorites, mine, catalog
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        case .mine: "My Foods"
        case .catalog: "Built-in"
        }
    }
}

/// Every food, grouped, sorted and filtered the way you want – the settings are remembered, the
/// search and the filter chips per window (they survive switching sidebar sections).
struct FoodLibraryView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("nina.foods.grouping") private var grouping: FoodGrouping = .category
    @AppStorage("nina.foods.sorting") private var sorting: FoodSorting = .name
    @AppStorage("nina.foods.scope") private var scope: FoodScope = .all
    @SceneStorage("nina.foods.query") private var query = ""
    /// The filter chips as text ("c:fruit", "h:highProtein", "t:breakfast", one per line).
    @SceneStorage("nina.foods.filters") private var storedFilters = ""
    @State private var categories: Set<FoodCategory> = []
    @State private var highlights: Set<FoodHighlight> = []
    @State private var tags: Set<String> = []
    @State private var restoredFilters = false
    @State private var showFilters = false

    private var library: FoodLibrary { app.library }

    private var allTags: [String] {
        Array(Set(library.records.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filtered: [FoodRecord] {
        let base = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? library.records.filter { $0.ref.kind != .recipe }
            : library.search(query, limit: 400).filter { $0.ref.kind != .recipe }
        return base.filter { record in
            switch scope {
            case .all: break
            case .favorites: guard record.isFavorite else { return false }
            case .mine: guard record.recordID != nil else { return false }
            case .catalog: guard record.ref.kind == .catalog else { return false }
            }
            if !categories.isEmpty, !categories.contains(record.category) { return false }
            if !highlights.isEmpty, !highlights.isSubset(of: Set(record.highlights)) { return false }
            if !tags.isEmpty, tags.isDisjoint(with: Set(record.tags)) { return false }
            return true
        }
    }

    /// `order`: each food's place in the A–Z list (worked out once per library rebuild).
    private func sorted(_ records: [FoodRecord], order: [FoodRef: Int]) -> [FoodRecord] {
        switch sorting {
        case .name:
            guard query.isEmpty else { return records }
            return records.sorted { (lhs: FoodRecord, rhs: FoodRecord) -> Bool in
                let left: Int = order[lhs.ref] ?? Int.max
                let right: Int = order[rhs.ref] ?? Int.max
                return left < right
            }
        case .mostUsed:
            return records.sorted { (library.usage(of: $0.ref)?.count ?? 0) > (library.usage(of: $1.ref)?.count ?? 0) }
        case .recent:
            return records.sorted { (library.usage(of: $0.ref)?.lastUsed ?? .distantPast) > (library.usage(of: $1.ref)?.lastUsed ?? .distantPast) }
        case .lightest:
            return records.sorted { $0.energyPer100 < $1.energyPer100 }
        case .richest:
            return records.sorted { $0.energyPer100 > $1.energyPer100 }
        case .protein:
            return records.sorted { $0.proteinPer100kcal > $1.proteinPer100kcal }
        }
    }

    struct FoodGroup: Identifiable {
        let title: String
        let records: [FoodRecord]
        var id: String { title }
    }

    /// The list's sections: filtered, grouped and sorted once per redraw.
    private var groups: [FoodGroup] {
        let records = filtered
        let order = sorting == .name && query.isEmpty ? library.nameOrder() : [:]
        switch grouping {
        case .none:
            return [FoodGroup(title: "", records: sorted(records, order: order))]
        case .category:
            let byCategory = Dictionary(grouping: records, by: \.category)
            return FoodCategory.allCases.compactMap { category in
                guard let list = byCategory[category], !list.isEmpty else { return nil }
                return FoodGroup(title: "\(category.emoji) \(category.title)", records: sorted(list, order: order))
            }
        case .brand:
            let byBrand = Dictionary(grouping: records) { $0.brand.isEmpty ? "No brand" : $0.brand }
            return byBrand.keys.sorted().map { FoodGroup(title: $0, records: sorted(byBrand[$0] ?? [], order: order)) }
        case .tag:
            var result: [FoodGroup] = []
            for tag in allTags {
                let list = records.filter { $0.tags.contains(tag) }
                if !list.isEmpty { result.append(FoodGroup(title: "#" + tag, records: sorted(list, order: order))) }
            }
            let untagged = records.filter { $0.tags.isEmpty }
            if !untagged.isEmpty { result.append(FoodGroup(title: "No tag", records: sorted(untagged, order: order))) }
            return result
        case .letter:
            let language = app.language
            let byLetter = Dictionary(grouping: records) { record -> String in
                let first = SearchText.normalize(record.displayName(language)).prefix(1).uppercased()
                return first.isEmpty ? "#" : first
            }
            return byLetter.keys.sorted().map { FoodGroup(title: $0, records: sorted(byLetter[$0] ?? [], order: order)) }
        }
    }

    private var activeFilterCount: Int { categories.count + highlights.count + tags.count }

    var body: some View {
        let groups = self.groups
        list(groups)
            .overlay {
                if groups.allSatisfy(\.records.isEmpty) { emptyOverlay }
            }
            .searchable(text: $query, prompt: "Search \(library.records.count) foods")
            .navigationTitle("Foods")
            .navigationDestination(for: FoodRecord.self) { record in
                FoodDetailView(record: record, mode: .log(day: app.selectedDay, meal: nil))
            }
            .toolbar { toolbar }
            .sheet(isPresented: $showFilters) {
                FoodFilterSheet(categories: $categories, highlights: $highlights, tags: $tags, scope: $scope, allTags: allTags)
            }
            .onAppear(perform: restoreFilters)
            .onChange(of: filterText) { _, text in
                if restoredFilters { storedFilters = text }
            }
    }

    private func list(_ groups: [FoodGroup]) -> some View {
        List {
            if activeFilterCount > 0 || scope != .all {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if scope != .all {
                                Button { scope = .all } label: { Chip(text: scope.title, symbol: "xmark", tint: Brand.accent, isSelected: true) }
                                    .buttonStyle(.plain)
                            }
                            ForEach(Array(categories), id: \.self) { category in
                                Button { categories.remove(category) } label: { Chip(text: "\(category.emoji) \(category.title)", symbol: "xmark", tint: Brand.accent, isSelected: true) }
                                    .buttonStyle(.plain)
                            }
                            ForEach(Array(highlights), id: \.self) { highlight in
                                Button { highlights.remove(highlight) } label: { Chip(text: highlight.title, symbol: "xmark", tint: Brand.accent, isSelected: true) }
                                    .buttonStyle(.plain)
                            }
                            ForEach(Array(tags), id: \.self) { tag in
                                Button { tags.remove(tag) } label: { Chip(text: "#" + tag, symbol: "xmark", tint: Brand.accent, isSelected: true) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.records) { record in
                        row(record)
                    }
                } header: {
                    if !group.title.isEmpty {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Text("\(group.records.count)")
                        }
                    }
                }
            }
        }
    }

    /// Swipe right logs (as on Today and in Meals & Recipes), swipe left marks a favorite.
    private func row(_ record: FoodRecord) -> some View {
        NavigationLink(value: record) {
            FoodRow(record: record, language: app.language, unit: app.energyUnit,
                    usage: library.usage(of: record.ref), showsHighlights: sorting == .protein || !highlights.isEmpty)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Log", systemImage: "plus") {
                app.log(record, amount: record.initialAmount(language: app.language), day: app.selectedDay,
                        meal: app.settings.suggestedMeal().id)
            }
            .tint(Brand.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star") {
                app.toggleFavorite(record)
            }
            .tint(.yellow)
        }
        .contextMenu { FoodActions(record: record) }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if library.records.isEmpty {
            EmptyStateView(title: "No foods yet", message: "Create your first food, or import the list you already have.",
                           symbol: "carrot", createTitle: "New Food", onCreate: { app.sheet = .newFood(nil) },
                           onImport: { app.sheet = .importData(.foods) })
        } else {
            ContentUnavailableView {
                Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try fewer filters, or create the food.")
            } actions: {
                Button("Clear Filters") { clearFilters() }
                Button("New Food") { app.sheet = .newFood(FoodDraft(name: query, nutrients: .zero)) }
            }
        }
    }

    // MARK: Filters kept per window

    private var filterText: String {
        let lines = categories.map { "c:" + $0.rawValue } + highlights.map { "h:" + $0.rawValue } + tags.map { "t:" + $0 }
        return lines.sorted().joined(separator: "\n")
    }

    private func restoreFilters() {
        guard !restoredFilters else { return }
        restoredFilters = true
        for line in storedFilters.split(separator: "\n").map(String.init) {
            let value = String(line.dropFirst(2))
            if line.hasPrefix("c:"), let category = FoodCategory(rawValue: value) {
                categories.insert(category)
            } else if line.hasPrefix("h:"), let highlight = FoodHighlight(rawValue: value) {
                highlights.insert(highlight)
            } else if line.hasPrefix("t:"), !value.isEmpty {
                tags.insert(value)
            }
        }
    }

    private func clearFilters() {
        categories = []
        highlights = []
        tags = []
        scope = .all
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Show", selection: $scope) {
                    ForEach(FoodScope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                Picker("Group by", selection: $grouping) {
                    ForEach(FoodGrouping.allCases) { grouping in Text(grouping.title).tag(grouping) }
                }
                .pickerStyle(.menu)
                Picker("Sort by", selection: $sorting) {
                    ForEach(FoodSorting.allCases) { sorting in Text(sorting.title).tag(sorting) }
                }
                .pickerStyle(.menu)
                Divider()
                Button("Filters…", systemImage: "line.3.horizontal.decrease.circle") { showFilters = true }
                if activeFilterCount > 0 || scope != .all {
                    Button("Clear Filters", systemImage: "xmark.circle") { clearFilters() }
                }
            } label: {
                Label("View Options", systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Food…", systemImage: "square.and.pencil") { app.sheet = .newFood(nil) }
                #if os(iOS)
                Button("Scan a Barcode…", systemImage: "barcode.viewfinder") { app.sheet = .scanBarcode(day: app.selectedDay, meal: nil) }
                #endif
                Button("Import Foods…", systemImage: "square.and.arrow.down") { app.sheet = .importData(.foods) }
            } label: {
                Label("New Food", systemImage: "plus")
            } primaryAction: {
                app.sheet = .newFood(nil)
            }
        }
    }
}

/// Context menu for a food anywhere.
struct FoodActions: View {
    let record: FoodRecord
    @Environment(AppModel.self) private var app

    /// Hides a catalog food from search, with Undo (it comes back under Settings → Hidden Foods too).
    @MainActor
    static func hide(_ record: FoodRecord, app: AppModel) {
        app.store.setHidden(record, true)
        app.refresh()
        app.toasts.show("Hidden from search. Settings \u{2192} Hidden Foods.", symbol: "eye.slash") {
            app.store.setHidden(record, false)
            app.refresh()
        }
    }

    var body: some View {
        Button("Log \(Fmt.amount(record.initialAmount(language: app.language)))", systemImage: "plus") {
            app.log(record, amount: record.initialAmount(language: app.language), day: app.selectedDay, meal: app.settings.suggestedMeal().id)
        }
        Button(record.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: record.isFavorite ? "star.slash" : "star") {
            app.toggleFavorite(record)
        }
        if record.ref.kind != .recipe {
            Button(record.recordID == nil ? "Customize…" : "Edit…", systemImage: "pencil") {
                let food = app.store.personalize(record)
                app.store.save()
                app.sheet = .editFood(food)
            }
        }
        if record.ref.kind == .catalog {
            Button("Hide from Search", systemImage: "eye.slash") {
                Self.hide(record, app: app)
            }
        }
        if record.ref.kind == .food, let id = record.recordID {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                if let food = app.store.food(id) { app.trash(food) }
            }
        }
    }
}

/// Categories, highlights and tags to filter by.
struct FoodFilterSheet: View {
    @Binding var categories: Set<FoodCategory>
    @Binding var highlights: Set<FoodHighlight>
    @Binding var tags: Set<String>
    @Binding var scope: FoodScope
    let allTags: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    Picker("Show", selection: $scope) {
                        ForEach(FoodScope.allCases) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Highlights") {
                    ForEach(FoodHighlight.allCases, id: \.self) { highlight in
                        Toggle(isOn: binding(highlight, in: $highlights)) {
                            VStack(alignment: .leading) {
                                Text(highlight.title)
                                Text(highlight.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Categories") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(FoodCategory.allCases) { category in
                            Button {
                                if categories.contains(category) { categories.remove(category) } else { categories.insert(category) }
                            } label: {
                                Chip(text: "\(category.emoji) \(category.title)", tint: Brand.accent, isSelected: categories.contains(category))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !allTags.isEmpty {
                    Section("Tags") {
                        ForEach(allTags, id: \.self) { tag in
                            Toggle("#" + tag, isOn: binding(tag, in: $tags))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        categories = []
                        highlights = []
                        tags = []
                        scope = .all
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .sheetFrame(minWidth: 480, minHeight: 560)
    }

    private func binding<T: Hashable>(_ value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
            }
        )
    }
}
