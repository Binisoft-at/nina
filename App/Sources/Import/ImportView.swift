import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

/// Import & Export: one setup prompt for another AI that writes goals & settings, foods and meals &
/// recipes at once, plus each format on its own (goals & settings, foods, meals & recipes, diary) with
/// its prompt, a file picker, a preview before anything changes, and an export. Importing the same
/// file again updates instead of duplicating.
struct ImportView: View {
    let initialKind: ImportKind?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ImportKind = .foods
    @State private var text = ""
    @State private var previews: [ImportPreview] = []
    @State private var setupCopied = false
    @State private var showFilePicker = false
    @State private var exportFile: CSVFile?
    @State private var exportName = ""
    @State private var promptCopied = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(setupCopied ? "Setup Prompt Copied – Paste It into Any AI" : "Copy the Setup Prompt",
                           systemImage: setupCopied ? "checkmark" : "sparkles") {
                        Clipboard.copy(setupText)
                        setupCopied = true
                    }
                    ShareLink(item: setupText) {
                        Label("Share the Setup Prompt", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Set Up Nina with Your AI")
                } footer: {
                    Text("Paste the prompt into ChatGPT, Claude or any AI and add a few lines about you: age, height, weight, goal, training, meal times, the foods and meals you eat (label photos work too). Paste its whole answer below – goals, settings, foods and meals are imported in one go, with a preview first.")
                }

                Section {
                    Picker("Format", selection: $kind) {
                        ForEach(ImportKind.allCases) { kind in Text(kind.shortTitle).tag(kind) }
                    }
                    .pickerStyle(.segmented)
                    Text(kind.subtitle).font(.callout).foregroundStyle(.secondary)
                }

                Section {
                    Button(promptCopied ? "Prompt Copied – Paste It into Any AI" : "Copy the Prompt for Another AI",
                           systemImage: promptCopied ? "checkmark" : "doc.on.doc") {
                        Clipboard.copy(promptText)
                        promptCopied = true
                    }
                    ShareLink(item: promptText) {
                        Label("Share the Prompt", systemImage: "square.and.arrow.up")
                    }
                    TextField("Paste what the AI wrote (one or more CSV blocks)", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .font(.callout.monospaced())
                    HStack {
                        Button("Preview", systemImage: "eye") { makePreview(text) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button("Choose a File…", systemImage: "doc") { showFilePicker = true }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Import")
                } footer: {
                    Text("1. Copy the prompt. 2. Paste it into ChatGPT, Claude or any AI together with your notes, label photos, screenshots or an export. 3. Paste the CSV it writes here (or save it as a file), preview, import. Everything is read on this device.")
                }

                ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
                    Section {
                        Text(preview.summary).font(.headline)
                        ForEach(preview.lines.prefix(preview.visibleLines)) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(line.title).lineLimit(1)
                                    if !line.detail.isEmpty {
                                        Text(line.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(line.action).font(.caption).foregroundStyle(line.action == "new" ? Brand.accent : .secondary)
                            }
                        }
                        if preview.lines.count > preview.visibleLines {
                            Text("… and \(preview.lines.count - preview.visibleLines) more").foregroundStyle(.secondary)
                        }
                        ForEach(preview.skipped.prefix(8), id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.orange)
                        }
                        if !preview.wishes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nina can't store these yet").font(.subheadline.weight(.semibold))
                                ForEach(preview.wishes, id: \.self) { wish in
                                    Text("• " + wish).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Preview · \(preview.kind.title)")
                    }
                }
                if !previews.isEmpty {
                    Section {
                        Button(previews.count > 1 ? "Import All" : "Import", systemImage: "square.and.arrow.down") { apply() }
                            .primaryActionStyle()
                            .disabled(!previews.contains(where: \.hasChanges))
                    } footer: {
                        Text("Nothing changes until you tap Import. Importing again updates instead of duplicating.")
                    }
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.red) }
                }

                Section {
                    Button("Export Goals & Settings (CSV)", systemImage: "target") { export(.settings) }
                    Button("Export Foods (CSV)", systemImage: "carrot") { export(.foods) }
                    Button("Export Diary (CSV)", systemImage: "book") { export(.diary) }
                    Button("Export Meals & Recipes (CSV)", systemImage: "frying.pan") { export(.recipes) }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Same formats as the import: edit the file anywhere and import it again – rows keep their id, so they are updated.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import & Export")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .tabSeparatedText]) { result in
                load(result)
            }
            .fileExporter(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                          document: exportFile, contentType: .commaSeparatedText, defaultFilename: exportName) { result in
                if case .failure(let error) = result { problem = error.localizedDescription }
            }
            .onChange(of: kind) { _, _ in
                promptCopied = false
            }
            .onAppear {
                if let initialKind { kind = initialKind }
                if let url = app.pendingImport {
                    app.pendingImport = nil
                    load(.success(url))
                }
            }
        }
        .sheetFrame(minWidth: 600, minHeight: 720)
    }

    private var setupText: String {
        let store = app.store
        let tags = Array(Set(store.foods().flatMap(\.tagList))).sorted()
        return SetupPrompt.text(appName: AppInfo.name, currentSettings: SettingsCSV.export(app.settingsState), existingTags: tags,
                                existingRecipes: store.recipes().map(\.displayName))
    }

    private var promptText: String {
        let store = app.store
        switch kind {
        case .settings:
            return SettingsCSV.prompt(appName: AppInfo.name, current: SettingsCSV.export(app.settingsState))
        case .foods:
            let tags = Array(Set(store.foods().flatMap(\.tagList))).sorted()
            return FoodCSV.prompt(appName: AppInfo.name, existingTags: tags).text
        case .diary:
            return DiaryCSV.prompt(appName: AppInfo.name, mealNames: app.settings.meals.map(\.name)).text
        case .recipes:
            return RecipeCSV.prompt(appName: AppInfo.name, existingNames: store.recipes().map(\.displayName)).text
        }
    }

    // MARK: Preview and import

    private func makePreview(_ text: String) {
        problem = nil
        let parts = ImportBundle.parts(text)
        if parts.isEmpty {
            previews = [ImportPreview.make(kind: kind, text: text, app: app)]
        } else {
            if parts.count == 1, let only = parts.first { kind = only.kind }
            previews = parts.map { ImportPreview.make(kind: $0.kind, text: $0.text, app: app) }
        }
        if previews.allSatisfy({ $0.lines.isEmpty && $0.skipped.isEmpty && $0.wishes.isEmpty }) {
            problem = "Nothing found to import. The first line of each part must be the header the prompt describes."
        }
    }

    private func load(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = CSV.decode(try Data(contentsOf: url))
                text = content
                AppLog.info("Import file read: \(url.lastPathComponent)", category: "import")
                makePreview(content)
            } catch {
                problem = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        case .failure(let error):
            problem = error.localizedDescription
        }
    }

    private func apply() {
        var summaries: [String] = []
        // Settings first, then foods, so meals and recipes find foods imported in the same go.
        for preview in previews.sorted(by: { order($0.kind) < order($1.kind) }) where preview.hasChanges {
            summaries.append(preview.apply(app: app))
            app.refresh()
        }
        app.toasts.show(summaries.joined(separator: " · "), symbol: "square.and.arrow.down.fill")
        dismiss()
    }

    private func order(_ kind: ImportKind) -> Int {
        ImportKind.allCases.firstIndex(of: kind) ?? 0
    }

    private func export(_ kind: ImportKind) {
        let store = app.store
        let text: String
        switch kind {
        case .settings:
            text = SettingsCSV.export(app.settingsState)
        case .foods:
            text = FoodCSV.export(store.foods().filter { !$0.isHidden || $0.catalogID.isEmpty }.map { ($0.key, $0.draft) })
        case .diary:
            let entries = store.entries(from: DayKey(year: 2000, month: 1, day: 1), through: app.today.adding(days: 366))
            text = DiaryCSV.export(entries.map { ($0.key, $0.draft) })
        case .recipes:
            text = RecipeCSV.export(store.recipes().map(\.draft))
        }
        exportName = "\(AppInfo.name) \(kind.title) \(app.today.rawValue)"
        exportFile = CSVFile(text: text)
    }
}

/// What an import will do, for all three formats, with lookups for rows without nutrition.
struct ImportPreview {
    struct Line: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let action: String
    }

    let kind: ImportKind
    let lines: [Line]
    let skipped: [String]
    let summary: String
    let hasChanges: Bool
    private var foodPlan: ImportPlan<FoodDraft>?
    private var diaryPlan: ImportPlan<DiaryDraft>?
    private var recipePlan: ImportPlan<RecipeDraft>?
    private var settings: (result: SettingsResult, previous: SettingsState)?
    /// What the AI found that Nina can't store yet.
    var wishes: [String] = []

    /// Every changed setting is shown; rows of other files up to ten.
    var visibleLines: Int { kind == .settings ? 50 : 10 }

    @MainActor
    static func make(kind: ImportKind, text: String, app: AppModel) -> ImportPreview {
        let store = app.store
        func label(_ action: ImportPlan<FoodDraft>.Action) -> String {
            switch action {
            case .create: "new"
            case .update: "update"
            case .unchanged: "same"
            }
        }
        switch kind {
        case .settings:
            let previous = app.settingsState
            let draft = SettingsCSV.parse(text)
            let result = SettingsCSV.apply(draft, to: previous, year: Calendar.current.component(.year, from: Date()))
            let lines = result.changes.map { Line(title: $0.title, detail: "\($0.old) → \($0.new)", action: "change") }
            let summary = result.hasChanges ? "\(result.changes.count) setting\(result.changes.count == 1 ? "" : "s") change" : "Your settings already match"
            return ImportPreview(kind: kind, lines: lines, skipped: draft.skipped + result.notes, summary: summary, hasChanges: result.hasChanges,
                                 settings: (result, previous), wishes: draft.wishes)
        case .foods:
            var existing: [String: FoodDraft] = [:]
            for food in store.foods() {
                for key in ImportColumns.lookupKeys(forKey: food.key) { existing[key] = food.draft }
            }
            let plan = FoodCSV.plan(text, existing: existing)
            let lines = plan.entries.map { entry in
                Line(title: entry.record.name, detail: "\(Fmt.energy(entry.record.nutrients.energy, unit: app.energyUnit)) per 100 \(entry.record.unit.symbol)",
                     action: label(entry.action))
            }
            return ImportPreview(kind: kind, lines: lines, skipped: plan.skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                                 foodPlan: plan)
        case .diary:
            var existing: [String: DiaryDraft] = [:]
            let all = store.entries(from: DayKey(year: 2000, month: 1, day: 1), through: app.today.adding(days: 366)).filter { !$0.importKey.isEmpty }
            for entry in all {
                for key in ImportColumns.lookupKeys(forKey: entry.key) { existing[key] = entry.draft }
            }
            let plan = DiaryCSV.plan(text, existing: existing)
            let lines = plan.entries.map { entry -> Line in
                let draft = entry.record
                let lookup = draft.needsLookup ? (app.library.bestMatch(draft.name).map { "looked up: \($0.displayName(app.language))" } ?? "not found – skipped") : Fmt.energy(draft.nutrients.energy, unit: app.energyUnit)
                return Line(title: draft.name, detail: "\(draft.day.rawValue) · \(draft.meal) · \(lookup)", action: label(entry.action == .create ? .create : (entry.action == .update ? .update : .unchanged)))
            }
            return ImportPreview(kind: kind, lines: lines, skipped: plan.skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                                 diaryPlan: plan)
        case .recipes:
            var existing: [String: RecipeDraft] = [:]
            for recipe in store.recipes() { existing[RecipeCSV.key(forName: recipe.displayName)] = recipe.draft }
            let plan = RecipeCSV.plan(text, existing: existing)
            let lines = plan.entries.map { entry in
                Line(title: entry.record.name, detail: "\(entry.record.kind.title) · \(entry.record.items.count) foods",
                     action: label(entry.action == .create ? .create : (entry.action == .update ? .update : .unchanged)))
            }
            return ImportPreview(kind: kind, lines: lines, skipped: plan.skipped, summary: plan.summary, hasChanges: plan.hasChanges,
                                 recipePlan: plan)
        }
    }

    /// Applies the plan; returns the toast text.
    @MainActor
    func apply(app: AppModel) -> String {
        let store = app.store
        var created = 0
        var updated = 0
        var skipped = 0
        if let settings {
            store.applySettings(settings.result, previous: settings.previous, day: app.today)
            AppLog.info("Import settings: \(settings.result.changes.count) changes", category: "import")
            return settings.result.changes.count == 1 ? "1 setting changed" : "\(settings.result.changes.count) settings changed"
        }
        if let plan = foodPlan {
            var byKey: [String: Food] = [:]
            for food in store.foods() {
                for key in ImportColumns.lookupKeys(forKey: food.key) { byKey[key] = food }
            }
            for entry in plan.entries where entry.action != .unchanged {
                let food = store.saveFood(entry.record, editing: entry.action == .update ? byKey[entry.key] : nil, source: .imported)
                if entry.action == .create {
                    food.importKey = entry.key
                    created += 1
                } else {
                    updated += 1
                }
            }
        }
        if let plan = diaryPlan {
            var byKey: [String: LogEntry] = [:]
            for entry in store.entries(from: DayKey(year: 2000, month: 1, day: 1), through: app.today.adding(days: 366)) where !entry.importKey.isEmpty {
                for key in ImportColumns.lookupKeys(forKey: entry.key) { byKey[key] = entry }
            }
            for row in plan.entries where row.action != .unchanged {
                let draft = row.record
                let meal = MealSlot.matching(draft.meal, in: app.settings.meals)?.id ?? "snack"
                let time = draft.minutes.map { draft.day.date(minutes: $0) } ?? draft.day.date(minutes: app.settings.meal(meal).minutes)
                var values = draft.nutrients
                var foodRef = ""
                var category = FoodCategory.other
                if draft.needsLookup {
                    guard let food = app.library.bestMatch(draft.name) else {
                        skipped += 1
                        continue
                    }
                    let amount = draft.amount > 0 ? draft.amount : QuickParser.amount(
                        for: QuickItem(original: draft.name, quantity: draft.quantity, unit: QuickParser.unit(for: SearchText.normalize(draft.unitLabel)), query: draft.name),
                        food: food).amount
                    values = food.nutrients(forAmount: amount)
                    foodRef = food.ref.rawValue
                    category = food.category
                }
                let entry = (row.action == .update ? byKey[row.key] : nil) ?? {
                    let created = LogEntry(day: draft.day, time: time, meal: meal, name: draft.name)
                    store.context.insert(created)
                    return created
                }()
                entry.day = draft.day.rawValue
                entry.time = time
                entry.meal = meal
                entry.name = draft.name
                entry.brand = draft.brand
                if !foodRef.isEmpty {
                    entry.foodRef = foodRef
                    entry.category = category.rawValue
                }
                entry.quantity = draft.amount > 0 ? draft.amount : draft.quantity
                entry.unitLabel = draft.amount > 0 ? draft.unit.symbol : (draft.unitLabel.isEmpty ? BaseUnit.serving.symbol : draft.unitLabel)
                entry.unitAmount = draft.amount > 0 ? 1 : 0
                entry.baseUnit = draft.amount > 0 ? draft.unit.rawValue : BaseUnit.serving.rawValue
                entry.nutrients = values.encoded
                entry.note = draft.note
                entry.status = draft.status.rawValue
                entry.source = "import"
                entry.importKey = row.key
                entry.touch()
                if row.action == .create { created += 1 } else { updated += 1 }
            }
            store.save()
        }
        if let plan = recipePlan {
            var byName: [String: Recipe] = [:]
            for recipe in store.recipes() { byName[RecipeCSV.key(forName: recipe.displayName)] = recipe }
            for row in plan.entries where row.action != .unchanged {
                let draft = row.record
                var lines: [RecipeLine] = []
                for item in draft.items {
                    if !item.needsLookup {
                        let amount = AmountText(quantity: item.amount > 0 ? item.amount : item.quantity,
                                                unitLabel: item.amount > 0 ? item.unit.symbol : (item.unitLabel.isEmpty ? BaseUnit.serving.symbol : item.unitLabel),
                                                unitAmount: item.amount > 0 ? 1 : 0, baseUnit: item.amount > 0 ? item.unit : .serving)
                        lines.append(RecipeLine(name: item.name, ref: .none, category: .other, amount: amount, nutrients: item.nutrients))
                    } else if let food = app.library.bestMatch(item.name) {
                        let quick = QuickParser.amount(for: QuickItem(original: item.name, quantity: item.amount > 0 ? item.amount : item.quantity,
                                                                      unit: item.amount > 0 ? .mass(1) : QuickParser.unit(for: SearchText.normalize(item.unitLabel)),
                                                                      query: item.name), food: food)
                        let amount = AmountText(quantity: quick.amount, unitLabel: food.unit.symbol, unitAmount: 1, baseUnit: food.unit)
                        lines.append(RecipeLine(record: food, amount: amount, language: app.language))
                    } else {
                        skipped += 1
                    }
                }
                guard !lines.isEmpty else { continue }
                store.saveRecipe(row.action == .update ? byName[row.key] : nil, name: draft.name, kind: draft.kind, emoji: "",
                                 servings: draft.servings, totalWeight: draft.totalWeight, notes: draft.notes, lines: lines)
                if row.action == .create { created += 1 } else { updated += 1 }
            }
        }
        AppLog.info("Import \(kind.rawValue): \(created) new, \(updated) updated, \(skipped) skipped", category: "import")
        var text = "Imported: \(created) new, \(updated) updated"
        if skipped > 0 { text += ", \(skipped) not found" }
        return text
    }
}

/// A CSV for the system's save panel / Files.
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
