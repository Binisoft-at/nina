import SwiftUI
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

/// Import & Export: the person's own file, the AI import (prompt → CSV → preview → import) and a
/// CSV export. Everything is read on the device; importing the same file again updates.
struct ImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var plan: ImportPlan<ItemDraft>?
    @State private var showFilePicker = false
    @State private var exportFile: CSVFile?
    @State private var promptCopied = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose a CSV File…", systemImage: "doc") { showFilePicker = true }
                } header: {
                    Text("Your file")
                } footer: {
                    Text("Columns: \(ItemCSV.header.joined(separator: ", ")). Only title is needed. The file is read on this device.")
                }

                Section {
                    Button(promptCopied ? "Prompt Copied" : "Copy Prompt for Another AI",
                           systemImage: promptCopied ? "checkmark" : "doc.on.doc") {
                        let folders = app.store.folders().map(\.displayName)
                        Clipboard.copy(ItemCSV.prompt(appName: AppInfo.name, existingFolders: folders).text)
                        promptCopied = true
                    }
                    TextField("Paste the CSV the AI wrote", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .font(.callout.monospaced())
                    Button("Preview", systemImage: "eye") { preview(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("AI import")
                } footer: {
                    Text("1. Copy the prompt. 2. Paste it with your notes, screenshots or spreadsheet into any AI. 3. Paste its CSV here, preview, import.")
                }

                if let plan {
                    Section {
                        Text(plan.summary)
                            .font(.headline)
                        ForEach(Array(plan.entries.prefix(8).enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text(entry.record.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(label(for: entry.action))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if plan.entries.count > 8 {
                            Text("… and \(plan.entries.count - 8) more")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(plan.skipped, id: \.self) { reason in
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("Import", systemImage: "square.and.arrow.down") { apply(plan) }
                            .disabled(!plan.hasChanges)
                    } header: {
                        Text("Preview")
                    } footer: {
                        Text("Nothing changes until you tap Import. Importing again updates instead of duplicating.")
                    }
                }

                if let problem {
                    Section {
                        Text(problem).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Export Everything as CSV", systemImage: "square.and.arrow.up") {
                        exportFile = CSVFile(text: app.store.exportCSV())
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Edit the file anywhere and import it again: rows keep their id, so items are updated.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import & Export")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                load(result)
            }
            .fileExporter(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
                          document: exportFile,
                          contentType: .commaSeparatedText,
                          defaultFilename: "\(AppInfo.name) export") { result in
                if case .failure(let error) = result { problem = error.localizedDescription }
            }
            .onAppear {
                if let url = app.pendingImport {
                    app.pendingImport = nil
                    load(.success(url))
                }
            }
        }
        .sheetFrame(minWidth: 540, minHeight: 620)
    }

    private func label(for action: ImportPlan<ItemDraft>.Action) -> String {
        switch action {
        case .create: "new"
        case .update: "update"
        case .unchanged: "same"
        }
    }

    private func preview(_ text: String) {
        problem = nil
        plan = app.store.importPlan(for: text)
        if plan?.entries.isEmpty == true, plan?.skipped.isEmpty == true {
            problem = "No rows found. The first line must be the header (\(ItemCSV.header.joined(separator: ",")))."
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
                preview(content)
            } catch {
                problem = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                AppLog.warning(problem ?? "", category: "import")
            }
        case .failure(let error):
            problem = error.localizedDescription
        }
    }

    private func apply(_ plan: ImportPlan<ItemDraft>) {
        let result = app.store.apply(plan)
        app.toasts.show("Imported: \(result.created) new, \(result.updated) updated", symbol: "square.and.arrow.down")
        dismiss()
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
