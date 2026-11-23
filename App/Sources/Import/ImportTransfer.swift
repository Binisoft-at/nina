import SwiftUI
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

// Getting files in and out of Import & Export: the export texts, a CSV file for the save panel,
// a share file that is only made when the person shares, and what can be dropped on the sheet.

/// The export of each format, as a file and as text.
@MainActor
enum ImportExports {
    /// The whole format as Nina stores it: every row with its id (the record's uuid, so importing
    /// the file again updates instead of duplicating) and every nutrient a row has.
    static func text(_ kind: ImportKind, app: AppModel) -> String {
        let store = app.store
        switch kind {
        case .settings:
            return settingsText(app)
        case .foods:
            let foods = store.foods().filter { !$0.isHidden || $0.catalogID.isEmpty }
            return FoodCSV.export(foods.map { (ImportColumns.idKey($0.uuid), $0.draft) })
        case .diary:
            let entries = store.entries(from: DayKey(year: 2000, month: 1, day: 1), through: app.today.adding(days: 366))
            return DiaryCSV.export(entries.map { (ImportColumns.idKey($0.uuid), $0.draft) }, meals: app.settings.meals)
        case .recipes:
            return RecipeCSV.exportWithAllNutrients(store.recipes().map(\.draft))
        case .measurements:
            return store.bodyHistoryExport()
        }
    }

    /// The current goals, settings and the whole coach plan (the active phase's numbers as of
    /// today). A weight from Apple Health only with "Include Apple Health weights" (My Plan) on.
    static func settingsText(_ app: AppModel) -> String {
        SettingsCSV.export(app.exportSettingsState(includeHealth: PlanEditorData.includesHealth), today: app.today)
    }

    /// "Nina Diary 2030-01-07".
    static func fileName(_ kind: ImportKind, app: AppModel) -> String {
        "\(AppInfo.name) \(kind.title) \(app.today.rawValue)"
    }

    /// UTF-8 with a byte order mark, so Excel shows umlauts right (Nina's import skips the mark).
    nonisolated static func fileData(_ text: String) -> Data {
        Data("\u{FEFF}".utf8) + Data(text.utf8)
    }

    static func symbol(_ kind: ImportKind) -> String {
        switch kind {
        case .settings: "target"
        case .foods: "carrot"
        case .diary: "book"
        case .recipes: "frying.pan"
        case .measurements: "figure"
        }
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
        text = CSV.decode(configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: ImportExports.fileData(text))
    }
}

/// An export for the share sheet, written only when the person shares it.
struct ImportShareFile: Transferable {
    let kind: ImportKind
    let app: AppModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { (file: ImportShareFile) in
            let url = try await file.write()
            return SentTransferredFile(url)
        }
    }

    /// The export in a temporary folder, named like the saved file.
    func write() async throws -> URL {
        let made: (text: String, name: String) = await MainActor.run {
            (ImportExports.text(kind, app: app), ImportExports.fileName(kind, app: app))
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(made.name + ".csv")
        try ImportExports.fileData(made.text).write(to: url)
        return url
    }
}

/// A CSV, TSV or text file (or text) dropped on Import & Export.
struct ImportDroppedText: Transferable {
    let name: String
    let text: String

    init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    init(file: URL) throws {
        name = file.lastPathComponent
        text = CSV.decode(try Data(contentsOf: file))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .commaSeparatedText) { (received: ReceivedTransferredFile) in
            try ImportDroppedText(file: received.file)
        }
        FileRepresentation(importedContentType: .tabSeparatedText) { (received: ReceivedTransferredFile) in
            try ImportDroppedText(file: received.file)
        }
        DataRepresentation(importedContentType: .plainText) { (data: Data) in
            ImportDroppedText(name: "", text: CSV.decode(data))
        }
    }
}

/// A file read into Import & Export: shown as "name · 6,000 rows" instead of filling the text field.
struct ImportLoadedFile: Equatable {
    let name: String
    let text: String

    /// Lines with something in them, without the header.
    var rows: Int {
        max(0, text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.count - 1)
    }

    var title: String {
        let count = rows
        let label = name.isEmpty ? "Dropped text" : name
        return "\(label) · \(count == 1 ? "1 row" : "\(count.formatted()) rows")"
    }
}
