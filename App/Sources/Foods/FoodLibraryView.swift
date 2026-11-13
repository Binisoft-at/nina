import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// iPhone: Foods and Meals & Recipes share a tab.
struct FoodsHomeView: View {
    @State private var page: Page = .foods

    enum Page: String, CaseIterable, Identifiable {
        case foods, recipes
        var id: String { rawValue }
        var title: String { self == .foods ? "Foods" : "Meals & Recipes" }
    }

    var body: some View {
        Group {
            switch page {
            case .foods: FoodLibraryView()
            case .recipes: RecipesView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $page) {
                ForEach(Page.allCases) { page in Text(page.title).tag(page) }
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

/// Every food, grouped, sorted and filtered the way you want – the settings are remembered.
struct FoodLibraryView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("nina.foods.grouping") private var grouping: FoodGrouping = .category
    @AppStorage("nina.foods.sorting") private var sorting: FoodSorting = .name
    @AppStorage("nina.foods.scope") private var scope: FoodScope = .all
    @State private var query = ""
    @State private var categories: Set<FoodCategory> = []
    @State private var highlights: Set<FoodHighlight> = []
    @State private var tags: Set<String> = []
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

    private func sorted(_ records: [FoodRecord]) -> [FoodRecord] {
        let language = app.language
        switch sorting {
        case .name:
            return query.isEmpty ? records.sorted { $0.displayName(language).localizedCaseInsensitiveCompare($1.displayName(language)) == .orderedAscending } : records
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

    private var groups: [FoodGroup] {
        let records = filtered
        switch grouping {
        case .none:
            return [FoodGroup(title: "", records: sorted(records))]
        case .category:
            let byCategory = Dictionary(grouping: records, by: \.category)
            return FoodCategory.allCases.compactMap { category in
                guard let list = byCategory[category], !list.isEmpty else { return nil }
                return FoodGroup(title: "\(category.emoji) \(category.title)", records: sorted(list))
            }
        case .brand:
            let byBrand = Dictionary(grouping: records) { $0.brand.isEmpty ? "No brand" : $0.brand }
            return byBrand.keys.sorted().map { FoodGroup(title: $0, records: sorted(byBrand[$0] ?? [])) }
        case .tag:
            var result: [FoodGroup] = []
            for tag in allTags {
                let list = records.filter { $0.tags.contains(tag) }
                if !list.isEmpty { result.append(FoodGroup(title: "#" + tag, records: sorted(list))) }
            }
            let untagged = records.filter { $0.tags.isEmpty }
            if !untagged.isEmpty { result.append(FoodGroup(title: "No tag", records: sorted(untagged))) }
            return result
        case .letter:
            let language = app.language
            let byLetter = Dictionary(grouping: records) { record -> String in
                let first = SearchText.normalize(record.displayName(language)).prefix(1).uppercased()
                return first.isEmpty ? "#" : first
            }
            return byLetter.keys.sorted().map { FoodGroup(title: $0, records: sorted(byLetter[$0] ?? [])) }
        }
    }

    private var activeFilterCount: Int { categories.count + highlights.count + tags.count }

    var body: some View {
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
                        NavigationLink(value: record) {
                            FoodRow(record: record, language: app.language, unit: app.energyUnit,
                                    usage: library.usage(of: record.ref), showsHighlights: sorting == .protein || !highlights.isEmpty)
                        }
                        .swipeActions(edge: .leading) {
                            Button(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star") {
                                app.toggleFavorite(record)
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Log", systemImage: "plus") {
                                app.log(record, amount: record.initialAmount(language: app.language), day: app.selectedDay,
                                        meal: app.settings.suggestedMeal().id)
                            }
                            .tint(Brand.accent)
                        }
                        .contextMenu { FoodActions(record: record) }
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
        .overlay {
            if filtered.isEmpty {
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
                app.store.setHidden(record, true)
                app.toasts.show("Hidden. Show it again in Settings → Foods.", symbol: "eye.slash")
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
