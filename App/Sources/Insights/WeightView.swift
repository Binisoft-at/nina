import SwiftUI
import SwiftData
import Charts
import BinisoftKit
import NinaCore

/// Weigh-ins (typed in Nina, plus Apple Health's if allowed) with the trend line.
struct WeightView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<WeightEntry> { $0.deletedAt == nil }, sort: \WeightEntry.time, order: .reverse)
    private var entries: [WeightEntry]

    private struct Row: Identifiable {
        let id: String
        let day: DayKey
        let kilograms: Double
        let entry: WeightEntry?
    }

    private var rows: [Row] {
        var byDay: [DayKey: Row] = [:]
        for (day, kilograms) in app.health.weights {
            byDay[day] = Row(id: "health-\(day.rawValue)", day: day, kilograms: kilograms, entry: nil)
        }
        for entry in entries {
            byDay[entry.dayKey] = Row(id: entry.uuid.uuidString, day: entry.dayKey, kilograms: entry.kilograms, entry: entry)
        }
        return byDay.values.sorted { $0.day > $1.day }
    }

    var body: some View {
        let rows = self.rows
        let weights = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0.kilograms) })
        let trend = Insights.weightTrend(weights, through: app.today)
        List {
            if !rows.isEmpty {
                Section {
                    Chart {
                        ForEach(trend.suffix(120), id: \.day) { point in
                            if !point.weight.isNaN {
                                PointMark(x: .value("Day", point.day.date(), unit: .day), y: .value("Weight", point.weight))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                                    .symbolSize(16)
                            }
                            if let value = point.trend {
                                LineMark(x: .value("Day", point.day.date(), unit: .day), y: .value("Trend", value))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Brand.accent)
                            }
                        }
                        if app.settings.targetWeight > 0 {
                            RuleMark(y: .value("Target", app.settings.targetWeight))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    if let latest = trend.last?.trend {
                        LabeledContent("Trend weight", value: Fmt.kilograms(latest))
                    }
                    if app.settings.targetWeight > 0, let latest = trend.last?.trend {
                        LabeledContent("To your target", value: Fmt.kilograms(latest - app.settings.targetWeight))
                    }
                }
            }
            Section {
                ForEach(rows) { row in
                    HStack {
                        Text(Fmt.dayTitle(row.day, today: app.today))
                        Spacer()
                        Text(Fmt.kilograms(row.kilograms)).monospacedDigit()
                        if row.entry == nil {
                            Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                                .help("From Apple Health")
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        if let entry = row.entry { app.sheet = .weight(entry) }
                    }
                    .swipeActions {
                        if let entry = row.entry {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                let trashed = app.store.trash([entry])
                                app.toasts.show("Weigh-in deleted", symbol: "trash.fill") { app.store.restore(trashed) }
                            }
                        }
                    }
                }
            } header: {
                Text("Weigh-ins")
            } footer: {
                Text(app.health.readsWeight ? "♥ = from Apple Health (read on this device, never synced by Nina)." : "Allow Apple Health in Settings to include the weigh-ins from your scale.")
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No weigh-ins yet", systemImage: "scalemass")
                } description: {
                    Text("Weigh yourself in the morning, after the bathroom, before breakfast – the trend does the rest.")
                } actions: {
                    Button("Log Weight") { app.sheet = .weight(nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Weight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { app.sheet = .weight(nil) } label: { Label("Log Weight", systemImage: "plus") }
            }
        }
    }
}

struct WeightEditor: View {
    let entry: WeightEntry?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kilograms: String
    @State private var bodyFat: String
    @State private var date: Date
    @State private var note: String
    @FocusState private var focused: Bool

    init(entry: WeightEntry?) {
        self.entry = entry
        _kilograms = State(initialValue: entry.map { NumberText.plain($0.kilograms, decimals: 1) } ?? "")
        _bodyFat = State(initialValue: (entry?.bodyFat ?? 0) > 0 ? NumberText.plain(entry?.bodyFat ?? 0, decimals: 1) : "")
        _date = State(initialValue: entry?.time ?? Date())
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $kilograms)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .focused($focused)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Body fat (optional)", text: $bodyFat)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%").foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date)
                    TextField("Note", text: $note)
                }
                if let entry {
                    Section {
                        Button("Delete Weigh-in", systemImage: "trash", role: .destructive) {
                            let trashed = app.store.trash([entry])
                            app.toasts.show("Weigh-in deleted", symbol: "trash.fill") { app.store.restore(trashed) }
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry == nil ? "Log Weight" : "Weigh-in")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(NumberText.parse(kilograms) == nil)
                }
            }
            .onAppear { focused = entry == nil }
        }
        .sheetFrame(minWidth: 420, minHeight: 360)
    }

    private func save() {
        guard let kg = NumberText.parse(kilograms), kg > 20, kg < 400 else { return }
        let fat = NumberText.parse(bodyFat) ?? 0
        let day = DayKey(date: date)
        if let entry {
            app.store.update(entry, kilograms: kg, day: day, bodyFat: fat, note: note)
        } else {
            app.store.addWeight(kg, day: day, time: date, bodyFat: fat, note: note)
            app.toasts.show("Weight \(Fmt.kilograms(kg)) saved", symbol: "scalemass.fill")
        }
        Task { await app.health.writeWeight(kg, date: date) }
        dismiss()
    }
}

/// Recently Deleted: entries, foods and meals stay 30 days.
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<LogEntry> { $0.deletedAt != nil }, sort: \LogEntry.time, order: .reverse) private var entries: [LogEntry]
    @Query(filter: #Predicate<Food> { $0.deletedAt != nil }) private var foods: [Food]
    @Query(filter: #Predicate<Recipe> { $0.deletedAt != nil }) private var recipes: [Recipe]

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
        }
        .overlay {
            if entries.isEmpty, foods.isEmpty, recipes.isEmpty {
                ContentUnavailableView("Recently Deleted is empty", systemImage: "trash", description: Text("Deleted entries, foods and meals stay here for 30 days."))
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty", role: .destructive) {
                    app.store.purge(entries)
                    app.store.purge(foods)
                    app.store.purge(recipes)
                }
                .disabled(entries.isEmpty && foods.isEmpty && recipes.isEmpty)
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
