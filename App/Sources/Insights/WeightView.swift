import SwiftUI
import SwiftData
import Charts
import BinisoftKit
import NinaCore

/// All weigh-ins (Progress → Body → All weigh-ins): the ones typed in Nina and, when allowed,
/// the ones from Apple Health (a scale or another app). Health weigh-ins are read live on this
/// device, marked with a heart and not editable; Nina's open the weigh-in sheet on tap and
/// swipe to delete with Undo.
struct WeightView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<WeightEntry> { $0.deletedAt == nil }, sort: \WeightEntry.time, order: .reverse)
    private var entries: [WeightEntry]

    private struct Row: Identifiable {
        let id: String
        let day: DayKey
        let time: Date
        let kilograms: Double
        let bodyFat: Double
        let note: String
        let entry: WeightEntry?
    }

    /// Nina's weigh-ins and the live Health ones (never stored), newest first.
    private var rows: [Row] {
        var rows: [Row] = entries.map { entry in
            Row(id: entry.uuid.uuidString, day: entry.dayKey, time: entry.time, kilograms: entry.kilograms,
                bodyFat: entry.bodyFat, note: entry.note, entry: entry)
        }
        let dayStartHour = app.settings.dayStartHour
        for (index, sample) in app.health.weightSamples.enumerated() {
            rows.append(Row(id: "health-\(index)-\(sample.date.timeIntervalSince1970)",
                            day: DayKey(date: sample.date, dayStartHour: dayStartHour), time: sample.date,
                            kilograms: sample.kilograms, bodyFat: 0, note: "", entry: nil))
        }
        return rows.sorted { $0.time > $1.time }
    }

    var body: some View {
        let rows = self.rows
        List {
            Section {
                ForEach(rows) { row in
                    rowView(row)
                }
            } footer: {
                if !rows.isEmpty {
                    Text(footer)
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No weigh-ins yet", systemImage: "scalemass")
                } description: {
                    Text("Weigh yourself in the morning, after the bathroom, before breakfast – the 7-day average does the rest.")
                } actions: {
                    Button("Log Weight") { app.sheet = .weight(nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Weigh-ins")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { app.sheet = .weight(nil) } label: { Label("Log Weight", systemImage: "plus") }
            }
        }
    }

    private var footer: String {
        app.health.readsWeight
            ? "♥ = from Apple Health: read on this device, never stored or synced by Nina. Change those in the Health app."
            : "Allow Apple Health in Settings to include the weigh-ins from your scale."
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if let entry = row.entry {
            Button {
                app.sheet = .weight(entry)
            } label: {
                WeightRowContent(day: row.day, today: app.today, kilograms: row.kilograms, detail: detail(row), isHealth: false)
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash(entry) }
            }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { app.sheet = .weight(entry) }
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash(entry) }
            }
        } else {
            WeightRowContent(day: row.day, today: app.today, kilograms: row.kilograms, detail: detail(row), isHealth: true)
        }
    }

    /// "07:12 · Salty, Poor sleep · 20.1 % body fat · note", "07:12 · Apple Health".
    private func detail(_ row: Row) -> String {
        var parts = [Fmt.time(row.time)]
        if row.entry == nil { parts.append("Apple Health") }
        let tags = WeightSignal.Tag.parse(row.note).map(\.title)
        if !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        if row.bodyFat > 0 { parts.append(BodyPageText.percent(row.bodyFat) + " body fat") }
        let note = HealthWeightSync.noteWithoutImportTag(WeightSignal.Tag.note(row.note, setting: []))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if HealthWeightSync.isImported(note: row.note) { parts.append("Imported") }
        if !note.isEmpty, note.lowercased() != "import" { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// One weigh-in row: day, detail line, kilograms, a heart for Apple Health.
private struct WeightRowContent: View {
    let day: DayKey
    let today: DayKey
    let kilograms: Double
    let detail: String
    let isHealth: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dayTitle(day, today: today))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Fmt.kilograms(kilograms))
                .monospacedDigit()
            if isHealth {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.caption)
                    .accessibilityLabel("From Apple Health")
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// "Delete Now" in Recently Deleted always asks first: it can't be undone.
private struct TrashPurgeRequest: Identifiable {
    let id = UUID()
    let title: String
    let purge: () -> Void
}

/// Recently Deleted: entries, foods, meals, routines, water, weigh-ins, body measurements and
/// progress photos stay 30 days. App only (the watch's store has no photos).
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt != nil }, sort: \LogEntry.time, order: .reverse) private var entries: [LogEntry]
    @Query(filter: #Predicate<Food> { $0.deletedAt != nil }) private var foods: [Food]
    @Query(filter: #Predicate<Recipe> { $0.deletedAt != nil }) private var recipes: [Recipe]
    @Query(filter: #Predicate<PlanRule> { $0.deletedAt != nil }, sort: \PlanRule.minutes) private var rules: [PlanRule]
    @Query(filter: #Predicate<WaterLog> { $0.deletedAt != nil }, sort: \WaterLog.time, order: .reverse)
    private var water: [WaterLog]
    @Query(filter: #Predicate<WeightEntry> { $0.deletedAt != nil }, sort: \WeightEntry.time, order: .reverse)
    private var weights: [WeightEntry]
    @Query(filter: #Predicate<BodyMeasurement> { $0.deletedAt != nil }, sort: \BodyMeasurement.time, order: .reverse)
    private var measurements: [BodyMeasurement]
    @Query(filter: #Predicate<ProgressPhoto> { $0.deletedAt != nil }, sort: \ProgressPhoto.time, order: .reverse)
    private var photos: [ProgressPhoto]
    /// "Empty" asks first: it can't be undone, and weigh-ins and measurements can't be typed again.
    @State private var confirmEmpty = false
    /// The "Delete Now" waiting for its confirmation.
    @State private var purgeRequest: TrashPurgeRequest?

    private var isEmpty: Bool {
        entries.isEmpty && foods.isEmpty && recipes.isEmpty && rules.isEmpty && water.isEmpty && weights.isEmpty
            && measurements.isEmpty && photos.isEmpty
    }

    var body: some View {
        List {
            if !entries.isEmpty { entriesSection }
            if !foods.isEmpty { foodsSection }
            if !recipes.isEmpty { recipesSection }
            if !rules.isEmpty { routinesSection }
            if !water.isEmpty { waterSection }
            if !weights.isEmpty { weightsSection }
            if !measurements.isEmpty { measurementsSection }
            if !photos.isEmpty { photosSection }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView("Recently Deleted is empty", systemImage: "trash", description: Text("Deleted entries, foods, meals, routines, water, weigh-ins, measurements and photos stay here for 30 days."))
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty", role: .destructive) { confirmEmpty = true }
                    .disabled(isEmpty)
            }
        }
        .confirmationDialog("Delete everything in Recently Deleted for good?", isPresented: $confirmEmpty,
                            titleVisibility: .visible) {
            Button("Delete All", role: .destructive, action: emptyTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(emptyMessage)
        }
        .confirmationDialog(purgeRequest?.title ?? "Delete for good?", isPresented: isAskingToPurge,
                            titleVisibility: .visible, presenting: purgeRequest) { request in
            Button("Delete Now", role: .destructive) { request.purge() }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var isAskingToPurge: Binding<Bool> {
        Binding<Bool>(
            get: { purgeRequest != nil },
            set: { (isShown: Bool) in if !isShown { purgeRequest = nil } }
        )
    }

    /// Asks before `purge` deletes something for good.
    private func ask(_ title: String, purge: @escaping () -> Void) {
        purgeRequest = TrashPurgeRequest(title: title, purge: purge)
    }

    private func emptyTrash() {
        let store = app.store
        store.purge(entries)
        store.purge(foods)
        store.purge(recipes)
        store.purge(rules)
        store.purge(water)
        store.purge(weights)
        store.purge(measurements)
        store.purge(photos)
    }

    /// "3 diary entries, 2 weigh-ins and 1 measurement can't be brought back."
    private var emptyMessage: String {
        let counts: [(count: Int, one: String, many: String)] = [
            (entries.count, "diary entry", "diary entries"),
            (foods.count, "food", "foods"),
            (recipes.count, "meal or recipe", "meals and recipes"),
            (rules.count, "routine", "routines"),
            (water.count, "water log", "water logs"),
            (weights.count, "weigh-in", "weigh-ins"),
            (measurements.count, "measurement", "measurements"),
            (photos.count, "photo", "photos"),
        ]
        let parts: [String] = counts.filter { $0.count > 0 }.map { "\($0.count) \($0.count == 1 ? $0.one : $0.many)" }
        guard let last = parts.last else { return "This can't be undone." }
        guard parts.count > 1 else { return last + " can't be brought back." }
        let first: String = parts.dropLast().joined(separator: ", ")
        return first + " and " + last + " can't be brought back."
    }

    private var entriesSection: some View {
        Section("Diary") {
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.displayName)
                        Text("\(Fmt.dayTitle(entry.dayKey, today: app.today)) · \(app.settings.meal(entry.meal).name) · \(daysLeft(entry.deletedAt)) days left")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.energy(entry.energy, unit: app.energyUnit)).foregroundStyle(.secondary)
                }
                .trashActions(restore: { app.store.restore([entry]) },
                              deleteNow: { ask("Delete \u{201C}\(entry.displayName)\u{201D} for good?") { app.store.purge([entry]) } })
            }
        }
    }

    private var foodsSection: some View {
        Section("Foods") {
            ForEach(foods) { food in
                Text(food.name)
                    .trashActions(restore: { app.store.restore([food]) },
                                  deleteNow: { ask("Delete \u{201C}\(food.name)\u{201D} for good?") { app.store.purge([food]) } })
            }
        }
    }

    private var recipesSection: some View {
        Section("Meals & Recipes") {
            ForEach(recipes) { recipe in
                Text(recipe.displayName)
                    .trashActions(restore: { app.store.restore([recipe]) },
                                  deleteNow: { ask("Delete \u{201C}\(recipe.displayName)\u{201D} for good?") { app.store.purge([recipe]) } })
            }
        }
    }

    /// Deleted routines: Restore brings the routine back and plans its next meals again.
    private var routinesSection: some View {
        Section("Routines") {
            ForEach(rules) { rule in
                VStack(alignment: .leading) {
                    Text(rule.title.isEmpty ? "Routine" : rule.title)
                    Text("\(app.settings.meal(rule.meal).name) · \(Fmt.clock(rule.minutes)) · \(rule.days.summary) · \(daysLeft(rule.deletedAt)) days left")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .trashActions(restore: { restore(rule) },
                              deleteNow: { ask("Delete this routine for good?") { app.store.purge([rule]) } })
            }
        }
    }

    /// Deleted water: a glass taken back with "−" stays here too.
    private var waterSection: some View {
        Section("Water") {
            ForEach(water) { log in
                HStack {
                    Text(Fmt.milliliters(log.amount))
                    Spacer()
                    Text("\(Fmt.dayTitle(log.dayKey, today: app.today)) · \(daysLeft(log.deletedAt)) days left")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .trashActions(restore: { app.store.restore([log]) },
                              deleteNow: { ask("Delete \(Fmt.milliliters(log.amount)) of water for good?") { app.store.purge([log]) } })
            }
        }
    }

    /// Deleted weigh-ins: Restore also puts the weight back into Apple Health (`app.restore`).
    private var weightsSection: some View {
        Section("Weigh-ins") {
            ForEach(weights) { weight in
                VStack(alignment: .leading) {
                    Text(Fmt.kilograms(weight.kilograms))
                    Text("\(Fmt.dayTitle(weight.dayKey, today: app.today)) · \(daysLeft(weight.deletedAt)) days left")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .trashActions(restore: { app.restore(weight) },
                              deleteNow: { ask("Delete this weigh-in for good?") { app.store.purge([weight]) } })
            }
        }
    }

    /// Deleted tape measurements and body-fat values: restore or delete for good.
    private var measurementsSection: some View {
        Section("Measurements") {
            ForEach(measurements) { measurement in
                VStack(alignment: .leading) {
                    Text(BodyDetailsText.title(measurement))
                    Text("\(Fmt.dayTitle(measurement.dayKey, today: app.today)) · \(daysLeft(measurement.deletedAt)) days left")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .trashActions(restore: { app.store.restore([measurement]) },
                              deleteNow: { ask("Delete this measurement for good?") { app.store.purge([measurement]) } })
            }
        }
    }

    /// Deleted progress photos: restore or delete for good. The thumbnails stay blurred while the
    /// photo lock is on.
    private var photosSection: some View {
        let isLocked: Bool = BodyPhotoLock.shared.isLocked
        return Section("Photos") {
            ForEach(photos) { photo in
                HStack(spacing: 12) {
                    BodyPhotoImageView(photo: photo)
                        .bodyPhotoLocked(isLocked)
                        .frame(width: 36, height: 48)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading) {
                        Text(BodyPhotoText.title(photo, today: app.today))
                        Text("\(daysLeft(photo.deletedAt)) days left")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .trashActions(restore: { app.store.restore([photo]) },
                              deleteNow: { ask("Delete this photo for good?") { app.store.purge([photo]) } })
            }
        }
    }

    private func restore(_ rule: PlanRule) {
        let store = app.store
        store.restore([rule])
        store.materializePlans(today: app.today)
    }

    private func daysLeft(_ date: Date?) -> Int {
        guard let date else { return 30 }
        return TrashPolicy(keepDays: 30).daysLeft(deletedAt: date)
    }
}

private extension View {
    /// Restore (leading swipe, context menu) and Delete Now (trailing swipe, context menu). Delete
    /// Now never fires on a full swipe and asks first (`deleteNow` shows the question).
    func trashActions(restore: @escaping () -> Void, deleteNow: @escaping () -> Void) -> some View {
        self
            .swipeActions(edge: .leading) {
                Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                    .tint(Brand.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete Now", systemImage: "trash", role: .destructive, action: deleteNow)
            }
            .contextMenu {
                Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                Button("Delete Now", systemImage: "trash", role: .destructive, action: deleteNow)
            }
    }
}

/// Search everything: foods, meals and the whole diary ("when did I last have sushi?").
struct GlobalSearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var foods: [FoodRecord] = []
    @State private var history: [LogEntry] = []
    @State private var historyCount = 0
    /// The query the results above belong to: "No Results" waits until they caught up.
    @State private var searchedQuery = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List {
            if !query.isEmpty {
                foodsSection
                historySection
            }
        }
        .overlay { emptyState }
        .searchable(text: $query, prompt: "Foods, diary, #tags")
        .searchFocused($isSearchFocused)
        .navigationTitle("Search")
        .task(id: "\(query)|\(app.dataVersion)") {
            await search()
        }
        #if os(macOS)
        .onAppear { isSearchFocused = true }
        #endif
    }

    @ViewBuilder
    private var foodsSection: some View {
        if !foods.isEmpty {
            Section("Foods & meals") {
                ForEach(foods) { record in
                    Button {
                        app.sheet = .food(record)
                    } label: {
                        FoodRow(record: record, language: app.language, unit: app.energyUnit, usage: app.library.usage(of: record.ref))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            Section("In your diary (\(historyCount))") {
                ForEach(history) { entry in
                    Button {
                        app.show(day: entry.dayKey)
                    } label: {
                        historyRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyRow(_ entry: LogEntry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName)
                Text("\(Fmt.dayTitle(entry.dayKey, today: app.today)) · \(app.settings.meal(entry.meal).name)\(entry.amountDescription.map { " · " + $0 } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.energy(entry.energy, unit: app.energyUnit)).foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    /// What "New Food" names the food; empty for a #tag search, which looks for no food.
    private var newFoodName: String {
        let name = query.trimmingCharacters(in: .whitespaces)
        return name.hasPrefix("#") ? "" : name
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search \(AppInfo.name)", systemImage: "magnifyingglass",
                                   description: Text("Foods, meals and everything in your diary – names, notes and #tags."))
        } else if searchedQuery == query, foods.isEmpty, history.isEmpty {
            ContentUnavailableView {
                Label("No Results for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
            } description: {
                Text("No food, meal or diary entry matches. Check the spelling, or create the food.")
            } actions: {
                if !newFoodName.isEmpty {
                    Button("New Food") { app.sheet = .newFood(FoodDraft(name: newFoodName, nutrients: .zero)) }
                }
            }
        }
    }

    /// After a short pause in typing: the foods once per query, and the diary on a background
    /// context (two years of entries), so typing never waits for it.
    private func search() async {
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            foods = []
            history = []
            historyCount = 0
            searchedQuery = text
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let found = app.library.search(text, limit: 8)
        var ids: [UUID] = []
        if let needle = DiaryEntryEdits.searchNeedle(text) {
            ids = await GlobalDiarySearch.matches(needle, in: app.container,
                                                  from: app.today.adding(days: -730), through: app.today.adding(days: 14))
        }
        guard !Task.isCancelled else { return }
        foods = found
        historyCount = ids.count
        history = GlobalDiarySearch.entries(Array(ids.prefix(60)), in: app.container.mainContext)
        searchedQuery = text
    }
}

/// The diary part of Search. The scan runs on its own context off the main thread and hands back
/// the matches' ids, newest first; the list then loads only the ones it shows.
private enum GlobalDiarySearch {
    static func matches(_ needle: String, in container: ModelContainer, from start: DayKey, through end: DayKey) async -> [UUID] {
        let first = start.rawValue, last = end.rawValue
        let scan = Task.detached(priority: .userInitiated) { () -> [UUID] in
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<LogEntry>(
                predicate: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.time, order: .reverse)]
            )
            let entries = (try? context.fetch(descriptor)) ?? []
            var found: [UUID] = []
            for entry in entries {
                if Task.isCancelled { return [] }
                if DiaryEntryEdits.matches(needle, name: entry.name, note: entry.note, tags: entry.tags, brand: entry.brand) {
                    found.append(entry.uuid)
                }
            }
            return found
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    /// The entries behind the ids, newest first, from the main context.
    @MainActor
    static func entries(_ ids: [UUID], in context: ModelContext) -> [LogEntry] {
        guard !ids.isEmpty else { return [] }
        let wanted = ids
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { wanted.contains($0.uuid) },
            sortBy: [SortDescriptor(\.time, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
