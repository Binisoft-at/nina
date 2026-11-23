import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

/// Import & Export: a backup of everything with a restore; one setup prompt for another AI that
/// writes goals & settings, foods, meals & recipes and the weight & body history at once, plus each
/// format on its own (goals & settings, foods, meals & recipes, diary, weight & body) with its
/// prompt, paste, a file picker or a drop, a preview before anything changes, and an export.
/// Importing the same file again updates instead of duplicating, and only what the file changed.
struct ImportView: View {
    let initialKind: ImportKind?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ImportKind = .foods
    @State private var text = ""
    /// A file read in (or dropped): shown by name instead of in the text field.
    @State private var loadedFile: ImportLoadedFile?
    @State private var previews: [ImportPreview] = []
    /// Blocks of the AI's answer that weren't recognised.
    @State private var unrecognised: [String] = []
    @State private var isReading = false
    @State private var setupCopied = false
    @State private var promptCopied = false
    /// The prompts, made when the format or the data changes (not on every keystroke).
    @State private var setupPrompt = ""
    @State private var formatPrompt = ""
    @State private var picker: ImportPicker = .csv
    @State private var showFilePicker = false
    @State private var exportFile: CSVFile?
    @State private var exportName = ""
    @State private var problem: String?
    /// What went wrong with a backup or a restore (shown in the backup section).
    @State private var backupProblem: String?
    /// Body values of a settings preview the person unticked (`SettingsChange.key`).
    @State private var untickedBody: Set<String> = []
    /// Diary rows from the last 14 days also go to Apple Health (off: they likely are there already).
    @State private var writeToHealth = false
    /// "Turn on coach reminders?" after an import that set up the plan.
    @State private var askReminders = false
    // Back up & restore.
    @State private var backupFolder: URL?
    @State private var isBackingUp = false
    @State private var restore: ImportRestore?
    @State private var useBackupProfile = false
    /// What went wrong choosing the automatic backup's folder.
    @State private var autoBackupProblem: String?
    @AppStorage(ImportBackupFiles.photosKey) private var includePhotos = true
    @AppStorage(ImportBackupFiles.lastKey) private var lastBackup: Double = 0

    var body: some View {
        NavigationStack {
            form
                .formStyle(.grouped)
                .navigationTitle("Import & Export")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
                .fileImporter(isPresented: $showFilePicker, allowedContentTypes: picker.types) { result in
                    picked(result)
                }
                .fileExporter(isPresented: isExporting, document: exportFile, contentType: .commaSeparatedText,
                              defaultFilename: exportName) { result in
                    if case .failure(let error) = result { problem = error.localizedDescription }
                }
                .fileMover(isPresented: isMovingBackup, file: backupFolder) { result in
                    backupMoved(result)
                }
                .dropDestination(for: ImportDroppedText.self) { items, _ in
                    let handled = dropped(items)
                    return handled
                }
                .onChange(of: kind) { _, _ in
                    promptCopied = false
                }
                .onChange(of: app.pendingImport) { _, _ in
                    // Only while this sheet stays open. When the app closes it to open Import &
                    // Export again for the file (or this one sits in My Plan), the new sheet picks
                    // the file up – taking it here would lose it with this sheet.
                    if case .importData? = app.sheet { pickUpPendingImport() }
                }
                .task(id: ImportPromptKey(kind: kind, version: app.dataVersion)) {
                    makePrompts()
                }
                .coachRemindersPrompt(isPresented: $askReminders) { dismiss() }
                .onAppear {
                    if let initialKind { kind = initialKind }
                    pickUpPendingImport()
                }
        }
        .sheetFrame(minWidth: 600, minHeight: 540)
    }

    private var form: some View {
        Form {
            if backupFirst { backupSections }
            setupSection
            formatSection
            importSection
            previewSections
            if let problem {
                Section { Text(problem).foregroundStyle(.red) }
            }
            exportSection
            if !backupFirst { backupSections }
        }
    }

    /// Opened from Settings or the Mac menu (no format asked for): the backup comes first.
    private var backupFirst: Bool { initialKind == nil }

    // MARK: Sections

    @ViewBuilder
    private var backupSections: some View {
        ImportBackupSection(includePhotos: $includePhotos, lastBackup: newestBackup, isWorking: isBackingUp, problem: backupProblem,
                            onBackUp: { makeBackup() }, onRestore: { chooseBackup() })
        if let restore {
            ImportRestoreSection(restore: restore, useBackupProfile: $useBackupProfile, onRestore: { restoreBackup() },
                                 onCancel: { self.restore = nil })
        }
        ImportAutoBackupSection(onChooseFolder: { chooseAutoBackupFolder() }, problem: autoBackupProblem)
    }

    /// This device's newest backup, saved by hand or automatically (seconds since 1970).
    private var newestBackup: Double {
        max(lastBackup, ImportAutoBackup.shared.state.lastSuccess?.timeIntervalSince1970 ?? 0)
    }

    private var setupSection: some View {
        Section {
            Button(setupCopied ? "Setup Prompt Copied – Paste It into Any AI" : "Copy the Setup Prompt",
                   systemImage: setupCopied ? "checkmark" : "sparkles") {
                Clipboard.copy(setupPrompt.isEmpty ? ImportPrompts.setup(app: app) : setupPrompt)
                setupCopied = true
            }
            ShareLink(item: setupPrompt) {
                Label("Share the Setup Prompt", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Set Up Nina with Your AI").info(ImportInfo.setupTitle, ImportInfo.setup)
        } footer: {
            Text("Paste the prompt into ChatGPT, Claude or any AI and add a few lines about you: age, height, weight, goal, training, meal times, the foods and meals you eat (label photos work too) and, if you like, past weigh-ins or a DEXA or body-scan report. Paste its whole answer below – everything is imported in one go, with a preview first.")
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $kind) {
                ForEach(ImportKind.allCases) { kind in Text(kind.shortTitle).tag(kind) }
            }
            .pickerStyle(.segmented)
            Text(kind.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .info(kind.title, ImportInfo.format(kind))
        }
    }

    private var importSection: some View {
        Section {
            Button(promptCopied ? "\(kind.shortTitle) Prompt Copied – Paste It into Any AI" : "Copy the \(kind.shortTitle) Prompt",
                   systemImage: promptCopied ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(formatPrompt.isEmpty ? ImportPrompts.format(kind, app: app) : formatPrompt)
                promptCopied = true
            }
            ShareLink(item: formatPrompt) {
                Label("Share the \(kind.shortTitle) Prompt", systemImage: "square.and.arrow.up")
            }
            pasteArea
            importButtons
        } header: {
            Text("Import").info(ImportInfo.importTitle, ImportInfo.importText)
        } footer: {
            Text(importFooter)
        }
    }

    @ViewBuilder
    private var pasteArea: some View {
        if let loadedFile {
            HStack {
                Label(loadedFile.title, systemImage: "doc.text")
                    .lineLimit(1)
                Spacer()
                Button("Clear", systemImage: "xmark.circle.fill") { clear() }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        } else {
            TextField("Paste what the AI wrote (one or more CSV blocks)", text: $text, axis: .vertical)
                .lineLimit(4...12)
                .font(.callout.monospaced())
        }
    }

    private var importButtons: some View {
        HStack {
            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in pasted(strings) }
            }
            .labelStyle(.titleAndIcon)
            if loadedFile == nil, hasText {
                Button("Preview", systemImage: "eye") { makePreview(text) }
            }
            Spacer()
            Button("Choose a File…", systemImage: "doc") {
                picker = .csv
                showFilePicker = true
            }
        }
        .buttonStyle(.borderless)
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var importFooter: String {
        #if os(macOS)
        return "1. Copy the prompt. 2. Paste it into ChatGPT, Claude or any AI together with your notes, label photos, screenshots or an export. 3. Paste its answer here, or drop the CSV file it made on this window, check the preview, import. Everything is read on this Mac."
        #else
        return "1. Copy the prompt. 2. Paste it into ChatGPT, Claude or any AI together with your notes, label photos, screenshots or an export. 3. Tap Paste (or choose the CSV file it made), check the preview, import. Everything is read on this device."
        #endif
    }

    @ViewBuilder
    private var previewSections: some View {
        if isReading {
            Section {
                HStack {
                    ProgressView()
                    Text("Reading…").foregroundStyle(.secondary)
                }
            }
        }
        if !unrecognised.isEmpty {
            Section {
                ForEach(unrecognised, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Not Recognised").info(ImportInfo.unrecognisedTitle, ImportInfo.unrecognised)
            }
        }
        ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
            if let settings = preview.settings {
                ImportSettingsPreview(summary: preview.summary, result: settings.result, notes: preview.skipped,
                                      unticked: $untickedBody)
            } else {
                ImportRowsPreview(preview: preview, offerHealth: offerHealth(preview), writeToHealth: $writeToHealth)
            }
        }
        if !previews.isEmpty {
            Section {
                importButtonRow
            } footer: {
                Text(importButtonFooter)
            }
        }
    }

    /// Import (All), with the ⓘ about Undo right beside it (not inside the button).
    private var importButtonRow: some View {
        HStack {
            Button(previews.count > 1 ? "Import All" : "Import") { apply() }
                .primaryActionStyle()
                .disabled(!previews.contains { $0.hasChanges(excluding: untickedBody) })
            InfoButton(ImportInfo.undoTitle, ImportInfo.undo)
        }
    }

    private var importButtonFooter: String {
        #if os(macOS)
        return "Nothing changes until you click Import. Importing again updates instead of duplicating, and only what the file changed."
        #else
        return "Nothing changes until you tap Import. Importing again updates instead of duplicating, and only what the file changed."
        #endif
    }

    /// Diary rows from the last 14 days while Nina writes meals to Apple Health.
    private func offerHealth(_ preview: ImportPreview) -> Bool {
        preview.kind == .diary && preview.recentRows > 0 && app.health.isAvailable && app.health.options.contains(.writeDiary)
    }

    private var exportSection: some View {
        Section {
            ForEach(ImportKind.allCases) { kind in
                ImportExportMenu(kind: kind, onSave: { export(kind) }, onCopy: { copyExport(kind) })
            }
        } header: {
            Text("Export").info(ImportInfo.exportTitle, ImportInfo.export)
        } footer: {
            Text("Same formats as the import, with every value Nina stores. Edit a file in Numbers (in Excel: Data → From Text/CSV, with the barcode column as Text) and import it again: rows keep their id, so they are updated – and only what you changed changes.")
        }
    }

    // MARK: Prompts

    private func makePrompts() {
        setupPrompt = ImportPrompts.setup(app: app)
        formatPrompt = ImportPrompts.format(kind, app: app)
    }

    // MARK: Reading

    private func makePreview(_ text: String) {
        problem = nil
        untickedBody = []
        unrecognised = []
        writeToHealth = false
        isReading = true
        let selected = kind
        Task {
            let split = await Task.detached(priority: .userInitiated) { ImportBundle.split(text) }.value
            var parts = split.parts.map { (kind: $0.kind, text: $0.text) }
            if parts.isEmpty {
                parts = [(kind: selected, text: ImportBundle.fallbackText(text))]
            } else if parts.count == 1, let only = parts.first {
                kind = only.kind
            }
            // Settings first, then foods, so meals, recipes and the diary find the foods of the
            // same answer.
            var built: [ImportPreview] = []
            var foods = Set<String>()
            for part in parts.sorted(by: { order($0.kind) < order($1.kind) }) {
                let preview = await ImportPreview.make(kind: part.kind, text: part.text, app: app, bundleFoods: foods)
                foods.formUnion(preview.foodNames)
                built.append(preview)
            }
            previews = built
            unrecognised = split.parts.isEmpty ? [] : split.unrecognised
            isReading = false
            if built.allSatisfy({ $0.lines.isEmpty && $0.skipped.isEmpty && $0.wishes.isEmpty }) {
                problem = "Nothing found to import. The first line of each part must be the header the prompt describes."
            }
        }
    }

    private func pasted(_ strings: [String]) {
        guard let pasted = strings.first, !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadedFile = nil
        text = pasted
        makePreview(pasted)
    }

    private func dropped(_ items: [ImportDroppedText]) -> Bool {
        guard let item = items.first, !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        use(ImportLoadedFile(name: item.name, text: item.text))
        return true
    }

    private func use(_ file: ImportLoadedFile) {
        loadedFile = file
        text = ""
        AppLog.info("Import file read: \(file.name)", category: "import")
        makePreview(file.text)
    }

    private func clear() {
        loadedFile = nil
        text = ""
        previews = []
        unrecognised = []
        problem = nil
    }

    private func picked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            switch picker {
            case .csv: load(url)
            case .backup: readBackup(url)
            case .backupFolder: autoBackupProblem = ImportAutoBackup.shared.choose(url, app: app)
            }
        case .failure(let error):
            switch picker {
            case .csv: problem = error.localizedDescription
            case .backup: backupProblem = error.localizedDescription
            case .backupFolder: autoBackupProblem = error.localizedDescription
            }
        }
    }

    /// Reads a CSV (coordinated, so a file that is only in iCloud Drive is downloaded first).
    /// `received`: another app sent it to Nina; its copy in Documents/Inbox is removed once read
    /// (a file the person picks is never removed, wherever it is).
    private func load(_ url: URL, received: Bool = false) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            use(ImportLoadedFile(name: url.lastPathComponent, text: CSV.decode(try ImportBackupFolder.read(url))))
            if received { ImportInbox.removeCopy(url) }
        } catch {
            problem = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// A CSV opened from Files or Finder while this sheet is open.
    private func pickUpPendingImport() {
        guard let url = app.pendingImport else { return }
        app.pendingImport = nil
        load(url, received: true)
    }

    // MARK: Importing

    private func apply() {
        var summaries: [String] = []
        var settingsUndo: SettingsImportUndo?
        var rowsUndo = ImportRowsUndo()
        let planBefore = app.settings.plan
        // Settings first, then foods, so meals and recipes find foods imported in the same go.
        for preview in previews.sorted(by: { order($0.kind) < order($1.kind) }) where preview.hasChanges(excluding: untickedBody) {
            let applied = preview.apply(app: app, excluding: untickedBody, writeToHealth: !offerHealth(preview) || writeToHealth)
            summaries.append(applied.summary)
            if let undo = applied.undo { settingsUndo = undo }
            rowsUndo.merge(applied.rows)
            app.refresh()
        }
        let message = summaries.joined(separator: " · ")
        if settingsUndo != nil || !rowsUndo.isEmpty {
            // One Undo for everything the toast lists: new foods, entries and recipes go to the
            // trash, changed ones get their values back, then the goals, settings and plan are put
            // back and the body records and the weight taken away.
            let model = app
            let rows = rowsUndo
            let settings = settingsUndo
            app.toasts.show(message, symbol: "square.and.arrow.down.fill") { [weak model] in
                guard let store = model?.store else { return }
                rows.undo(store: store)
                if let settings { store.undo(settings) }
            }
        } else {
            app.toasts.show(message, symbol: "square.and.arrow.down.fill")
        }
        if !app.isSandbox, !app.launch.isDemo,
           NotificationScheduler.shared.shouldOfferCoachReminders(before: planBefore, after: app.settings.plan) {
            askReminders = true // the answer closes the sheet
        } else {
            dismiss()
        }
    }

    private func order(_ kind: ImportKind) -> Int {
        ImportKind.allCases.firstIndex(of: kind) ?? 0
    }

    // MARK: Exporting

    private var isExporting: Binding<Bool> {
        Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } })
    }

    private func export(_ kind: ImportKind) {
        exportName = ImportExports.fileName(kind, app: app)
        exportFile = CSVFile(text: ImportExports.text(kind, app: app))
    }

    private func copyExport(_ kind: ImportKind) {
        Clipboard.copy(ImportExports.text(kind, app: app))
        app.toasts.show("\(kind.title) copied", symbol: "doc.on.doc.fill")
    }

    // MARK: Back up and restore

    private var isMovingBackup: Binding<Bool> {
        Binding(get: { backupFolder != nil }, set: { if !$0 { finishBackup() } })
    }

    private func makeBackup() {
        backupProblem = nil
        isBackingUp = true
        let photos = includePhotos
        Task {
            do {
                backupFolder = try await ImportBackupFiles.write(app: app, includePhotos: photos)
            } catch {
                backupProblem = "The backup couldn't be written: \(error.localizedDescription)"
            }
            isBackingUp = false
        }
    }

    private func backupMoved(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            lastBackup = Date().timeIntervalSince1970
            AppLog.info("Backup saved: \(url.lastPathComponent)", category: "backup")
            app.toasts.show("Backup saved: \(url.lastPathComponent)", symbol: "externaldrive.fill")
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { backupProblem = "The backup wasn't saved: \(error.localizedDescription)" }
        }
        finishBackup()
    }

    private func finishBackup() {
        ImportBackupFiles.cleanUp(backupFolder)
        backupFolder = nil
    }

    private func chooseBackup() {
        backupProblem = nil
        picker = .backup
        showFilePicker = true
    }

    private func chooseAutoBackupFolder() {
        autoBackupProblem = nil
        picker = .backupFolder
        showFilePicker = true
    }

    private func readBackup(_ url: URL) {
        isBackingUp = true
        restore = nil
        useBackupProfile = false
        Task {
            do {
                let folder = try await Task.detached(priority: .userInitiated) { try ImportBackupFolder(url: url) }.value
                let store = app.store
                let existing = store.backupExisting()
                let current = store.profile()?.backupRecord
                let plan = await Task.detached(priority: .userInitiated) {
                    BackupRestorePlan(folder.records, existing: existing, currentProfile: current)
                }.value
                restore = ImportRestore(folder: folder, plan: plan)
            } catch let error as NinaBackup.ReadError {
                backupProblem = error.message
            } catch {
                backupProblem = "The backup couldn't be read: \(error.localizedDescription)"
            }
            isBackingUp = false
        }
    }

    private func restoreBackup() {
        guard let restore else { return }
        let folder = restore.folder
        let scoped = folder.url.startAccessingSecurityScopedResource()
        let undo = app.store.restoreBackup(restore.plan, useBackupProfile: useBackupProfile) { record in folder.photo(record) }
        if scoped { folder.url.stopAccessingSecurityScopedResource() }
        app.refresh()
        self.restore = nil
        guard !undo.isEmpty else {
            app.toasts.show("Nothing to restore – Nina has everything in this backup")
            return
        }
        var message = undo.count == 1 ? "Restored 1 record" : "Restored \(undo.count.formatted()) records"
        if undo.missingPhotos > 0 { message += undo.missingPhotos == 1 ? " · 1 photo missing" : " · \(undo.missingPhotos) photos missing" }
        let model = app
        app.toasts.show(message, symbol: "clock.arrow.circlepath") { [weak model] in
            guard let model else { return }
            model.store.undo(undo)
            model.refresh()
        }
        dismiss()
    }
}

/// Which files the file picker offers: a CSV, a backup folder to restore, or the folder for the
/// automatic backups.
enum ImportPicker {
    case csv, backup, backupFolder

    var types: [UTType] {
        switch self {
        case .csv: [.commaSeparatedText, .plainText, .text, .tabSeparatedText]
        case .backup, .backupFolder: [.folder]
        }
    }
}

/// Files another app sends to Nina ("Open in Nina", AirDrop, Mail) arrive as copies in
/// Documents/Inbox – which Files shows under On My iPhone → Nina, next to the backups.
enum ImportInbox {
    /// Removes `url` once it is read when it is such a copy (never anything else).
    static func removeCopy(_ url: URL) {
        guard url.isFileURL,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath().path(percentEncoded: false)
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        guard path.hasPrefix(inbox.hasSuffix("/") ? inbox : inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
        AppLog.info("Removed the received copy of \(url.lastPathComponent)", category: "import")
    }
}

/// When the prompts are made again: another format, or changed data.
struct ImportPromptKey: Hashable {
    let kind: ImportKind
    let version: Int
}

/// The prompts for another AI, with what Nina already has (tags, own foods, recipes, meals and
/// the current settings).
@MainActor
enum ImportPrompts {
    static func setup(app: AppModel) -> String {
        let store = app.store
        let foods = store.foods()
        return SetupPrompt.text(appName: AppInfo.name, currentSettings: ImportExports.settingsText(app), existingTags: tags(foods),
                                existingRecipes: store.recipes().map(\.displayName), existingFoods: ownFoods(foods))
    }

    static func format(_ kind: ImportKind, app: AppModel) -> String {
        let store = app.store
        switch kind {
        case .settings:
            return SettingsCSV.prompt(appName: AppInfo.name, current: ImportExports.settingsText(app))
        case .foods:
            let foods = store.foods()
            return FoodCSV.prompt(appName: AppInfo.name, existingTags: tags(foods), existingFoods: ownFoods(foods)).text
        case .diary:
            return DiaryCSV.prompt(appName: AppInfo.name, mealNames: app.settings.meals.map(\.name)).text
        case .recipes:
            return RecipeCSV.prompt(appName: AppInfo.name, existingNames: store.recipes().map(\.displayName)).text
        case .measurements:
            return BodyHistoryCSV.prompt(appName: AppInfo.name).text
        }
    }

    private static func tags(_ foods: [Food]) -> [String] {
        Array(Set(foods.flatMap(\.tagList))).sorted()
    }

    /// The person's own foods (not personalised catalog foods), most recently changed first.
    private static func ownFoods(_ foods: [Food]) -> [String] {
        foods.filter { $0.catalogID.isEmpty }.sorted { $0.modifiedAt > $1.modifiedAt }.map(\.name)
    }
}

/// One format's export: save as a file, share or copy.
private struct ImportExportMenu: View {
    @Environment(AppModel.self) private var app
    let kind: ImportKind
    let onSave: () -> Void
    let onCopy: () -> Void

    var body: some View {
        Menu {
            Button("Save as File…", systemImage: "doc", action: onSave)
            ShareLink(item: ImportShareFile(kind: kind, app: app), preview: SharePreview("\(kind.title) (CSV)")) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
        } label: {
            Label("Export \(kind.title) (CSV)", systemImage: ImportExports.symbol(kind))
        }
    }
}

/// The preview of a foods, diary, meals & recipes or weight & body file.
private struct ImportRowsPreview: View {
    let preview: ImportPreview
    let offerHealth: Bool
    @Binding var writeToHealth: Bool

    var body: some View {
        Section {
            Text(preview.summary).font(.headline)
            ForEach(preview.lines.prefix(preview.visibleLines)) { line in
                ImportPreviewLine(line: line)
            }
            if preview.lines.count > preview.visibleLines {
                Text("… and \(preview.lines.count - preview.visibleLines) more").foregroundStyle(.secondary)
            }
            ForEach(preview.skipped.prefix(8), id: \.self) { reason in
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
            if offerHealth {
                Toggle(isOn: $writeToHealth) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Also Write These to Apple Health").info(ImportInfo.healthTitle, ImportInfo.health)
                        Text("\(preview.recentRows == 1 ? "1 row is" : "\(preview.recentRows) rows are") from the last 14 days. Leave it off when they come from another app that already wrote them to Health.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Preview · \(preview.kind.title)").info(ImportInfo.previewTitle, ImportInfo.preview(preview.kind))
        }
    }
}

private struct ImportPreviewLine: View {
    let line: ImportPreview.Line

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title).lineLimit(1)
                if !line.detail.isEmpty {
                    Text(line.detail).font(.caption).foregroundStyle(line.warning ? Color.orange : Color.secondary).lineLimit(1)
                }
                if !line.lookups.isEmpty {
                    Text(line.lookups).font(.caption).foregroundStyle(line.warning ? Color.orange : Color.secondary).lineLimit(3)
                }
            }
            Spacer()
            Text(line.action).font(.caption).foregroundStyle(line.action == "new" ? Brand.accent : .secondary)
        }
    }
}

/// The goals & settings preview: the summary with the orange notes (rows that couldn't be used,
/// checks of what the file says), then one section per group in order – Body · Targets · Day types
/// (3) · Phases (2) · Daily checks · Measuring · Check-in · Long-term goal · Notes · Preferences ·
/// Not supported – with a switch on each of today's body values to leave it out.
private struct ImportSettingsPreview: View {
    let summary: String
    let result: SettingsResult
    let notes: [String]
    @Binding var unticked: Set<String>

    var body: some View {
        Section {
            Text(summary).font(.headline)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text(note).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Preview · \(ImportKind.settings.title)").info(ImportInfo.previewTitle, ImportInfo.settingsPreview)
        }
        ForEach(result.sections) { section in
            ImportSettingsGroup(section: section, unticked: $unticked)
        }
    }
}

private struct ImportSettingsGroup: View {
    let section: SettingsSection
    @Binding var unticked: Set<String>

    var body: some View {
        Section {
            ForEach(section.changes) { change in
                if isBodyValue(change) {
                    Toggle(isOn: binding(change.key)) {
                        ImportSettingsLine(change: change)
                    }
                } else {
                    ImportSettingsLine(change: change)
                }
            }
        } header: {
            groupHeader
        } footer: {
            if section.group == .notSupported {
                Text("Nina can't store these yet – they're only listed here.")
            } else if hasBodyValues {
                Text("Today's body values become your starting point. Switch off any you don't want saved.")
            }
        }
    }

    /// The group's title; Body with its switches gets an ⓘ.
    @ViewBuilder
    private var groupHeader: some View {
        if hasBodyValues {
            Text(section.title).info(ImportInfo.bodyValuesTitle, ImportInfo.bodyValues)
        } else {
            Text(section.title)
        }
    }

    /// The body group with today's body values, each with a switch.
    private var hasBodyValues: Bool {
        section.group == .body && section.changes.contains { isBodyValue($0) }
    }

    /// Body fat and tape values: today's baseline records, each one can be left out.
    private func isBodyValue(_ change: SettingsChange) -> Bool {
        change.group == .body && !change.key.isEmpty
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !unticked.contains(key) },
            set: { on in
                if on { unticked.remove(key) } else { unticked.insert(key) }
            }
        )
    }
}

private struct ImportSettingsLine: View {
    let change: SettingsChange

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(change.title).lineLimit(2)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(change.isRemoval ? Color.orange : Color.secondary)
                    .lineLimit(3)
            }
        }
    }

    /// "2,400 → 2,600 kcal", just the new value for something new, "removed".
    private var detail: String {
        if change.group == .notSupported { return "" }
        if change.isRemoval { return "removed" }
        if change.old.isEmpty || change.old == "–" { return change.new }
        return "\(change.old) → \(change.new)"
    }
}
