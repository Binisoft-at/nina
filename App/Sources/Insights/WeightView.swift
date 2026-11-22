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

/// Recently Deleted: entries, foods, meals, weigh-ins and body measurements stay 30 days.
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt != nil }, sort: \LogEntry.time, order: .reverse) private var entries: [LogEntry]
    @Query(filter: #Predicate<Food> { $0.deletedAt != nil }) private var foods: [Food]
    @Query(filter: #Predicate<Recipe> { $0.deletedAt != nil }) private var recipes: [Recipe]
    @Query(filter: #Predicate<WeightEntry> { $0.deletedAt != nil }, sort: \WeightEntry.time, order: .reverse)
    private var weights: [WeightEntry]
    @Query(filter: #Predicate<BodyMeasurement> { $0.deletedAt != nil }, sort: \BodyMeasurement.time, order: .reverse)
    private var measurements: [BodyMeasurement]
    /// "Empty" asks first: it can't be undone, and weigh-ins and measurements can't be typed again.
    @State private var confirmEmpty = false

    private var isEmpty: Bool {
        entries.isEmpty && foods.isEmpty && recipes.isEmpty && weights.isEmpty && measurements.isEmpty
    }

    var body: some View {
        List {
            if !entries.isEmpty {
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
                        .swipeActions(edge: .leading) {
                            Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([entry]) }.tint(Brand.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([entry]) }
                        }
                        .contextMenu {
                            Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([entry]) }
                            Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([entry]) }
                        }
                    }
                }
            }
            if !foods.isEmpty {
                Section("Foods") {
                    ForEach(foods) { food in
                        Text(food.name)
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([food]) }.tint(Brand.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([food]) }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([food]) }
                            }
                    }
                }
            }
            if !recipes.isEmpty {
                Section("Meals & Recipes") {
                    ForEach(recipes) { recipe in
                        Text(recipe.displayName)
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([recipe]) }.tint(Brand.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([recipe]) }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([recipe]) }
                            }
                    }
                }
            }
            if !weights.isEmpty {
                weightsSection
            }
            if !measurements.isEmpty {
                measurementsSection
            }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView("Recently Deleted is empty", systemImage: "trash", description: Text("Deleted entries, foods, meals, weigh-ins and measurements stay here for 30 days."))
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
    }

    private func emptyTrash() {
        let store = app.store
        store.purge(entries)
        store.purge(foods)
        store.purge(recipes)
        store.purge(weights)
        store.purge(measurements)
    }

    /// "3 diary entries, 2 weigh-ins and 1 measurement can't be brought back."
    private var emptyMessage: String {
        let counts: [(count: Int, one: String, many: String)] = [
            (entries.count, "diary entry", "diary entries"),
            (foods.count, "food", "foods"),
            (recipes.count, "meal or recipe", "meals and recipes"),
            (weights.count, "weigh-in", "weigh-ins"),
            (measurements.count, "measurement", "measurements"),
        ]
        let parts: [String] = counts.filter { $0.count > 0 }.map { "\($0.count) \($0.count == 1 ? $0.one : $0.many)" }
        guard let last = parts.last else { return "This can't be undone." }
        guard parts.count > 1 else { return last + " can't be brought back." }
        let first: String = parts.dropLast().joined(separator: ", ")
        return first + " and " + last + " can't be brought back."
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
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") { app.restore(weight) }.tint(Brand.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([weight]) }
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") { app.restore(weight) }
                    Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([weight]) }
                }
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
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([measurement]) }.tint(Brand.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([measurement]) }
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") { app.store.restore([measurement]) }
                    Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([measurement]) }
                }
            }
        }
    }

    private func daysLeft(_ date: Date?) -> Int {
        guard let date else { return 30 }
        return TrashPolicy(keepDays: 30).daysLeft(deletedAt: date)
    }
}

/// Search everything: foods, meals and the whole diary ("when did I last have sushi?").
struct GlobalSearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var history: [LogEntry] = []

    var body: some View {
        List {
            if !query.isEmpty {
                let foods = app.library.search(query, limit: 8)
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
                if !history.isEmpty {
                    Section("In your diary (\(history.count))") {
                        ForEach(history.prefix(60)) { entry in
                            Button {
                                app.show(day: entry.dayKey)
                            } label: {
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
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search \(AppInfo.name)", systemImage: "magnifyingglass",
                                       description: Text("Foods, meals and everything in your diary – names, notes and #tags."))
            }
        }
        .searchable(text: $query, prompt: "Foods, diary, #tags")
        .navigationTitle("Search")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            history = searchDiary(query)
        }
    }

    private func searchDiary(_ text: String) -> [LogEntry] {
        let needle = SearchText.normalize(text.replacingOccurrences(of: "#", with: ""))
        guard needle.count >= 2 else { return [] }
        let entries = app.store.entries(from: app.today.adding(days: -730), through: app.today.adding(days: 14))
        return entries.filter { entry in
            SearchText.normalize(entry.name + " " + entry.note + " " + entry.tags + " " + entry.brand).contains(needle)
        }
        .sorted { $0.time > $1.time }
    }
}
