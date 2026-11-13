import Foundation
import BinisoftKitCore

/// One item as it travels through import and export (no database types here).
public struct ItemDraft: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var isDone: Bool
    /// Folder name; empty = no folder.
    public var folder: String

    public init(title: String, notes: String = "", isDone: Bool = false, folder: String = "") {
        self.title = title
        self.notes = notes
        self.isDone = isDone
        self.folder = folder
    }
}

/// Nina's CSV format: what "Import my data", the AI import and Export use.
/// See docs/IMPORT.md. Importing the same file twice updates instead of duplicating.
public enum ItemCSV {
    public static let columns: [AIImportPrompt.Column] = [
        .init("id", "A stable id for the row (any text, e.g. 1, 2, 3). Keep it when you change the file, so re-importing updates the item instead of adding it again."),
        .init("title", "What the item is, in my words.", required: true),
        .init("notes", "Longer text; may contain line breaks."),
        .init("done", "yes if it is done, otherwise empty or no."),
        .init("folder", "The folder (group) it belongs to; empty = no folder."),
    ]

    public static var header: [String] { columns.map(\.name) }

    public struct Parsed {
        public var rows: [(key: String, draft: ItemDraft)]
        public var skipped: [String]
    }

    /// Reads the CSV. Rows without a title are skipped with a reason. Without an `id` column the
    /// key comes from title + folder, so the same file still re-imports safely.
    public static func parse(_ text: String) -> Parsed {
        let (header, records) = CSV.records(text)
        var rows: [(key: String, draft: ItemDraft)] = []
        var skipped: [String] = []
        guard header.contains("title") else {
            return Parsed(rows: [], skipped: ["The first line needs a \u{201C}title\u{201D} column (expected: \(Self.header.joined(separator: ",")))."])
        }
        for (offset, record) in records.enumerated() {
            let line = offset + 2
            let title = (record["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                skipped.append("Row \(line): no title")
                continue
            }
            let draft = ItemDraft(
                title: title,
                notes: (record["notes"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isDone: isYes(record["done"] ?? ""),
                folder: (record["folder"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let id = (record["id"] ?? "").trimmingCharacters(in: .whitespaces)
            let key = id.isEmpty ? ImportPlan<ItemDraft>.contentKey([draft.title, draft.folder]) : "id:" + id
            rows.append((key, draft))
        }
        return Parsed(rows: rows, skipped: skipped)
    }

    /// The preview shown before anything changes.
    public static func plan(_ text: String, existing: [String: ItemDraft]) -> ImportPlan<ItemDraft> {
        let parsed = parse(text)
        return ImportPlan(incoming: parsed.rows.map { ($0.key, $0.draft) }, existing: existing, skipped: parsed.skipped)
    }

    /// Export with the keys the app stores, so editing the file and importing it again updates.
    public static func export(_ items: [(key: String, draft: ItemDraft)]) -> String {
        var table = [header]
        for (key, draft) in items {
            table.append([exportID(forKey: key), draft.title, draft.notes, draft.isDone ? "yes" : "", draft.folder])
        }
        return CSV.write(table)
    }

    /// The `id` column written for a stored key ("id:7" → "7", a content key stays as it is).
    public static func exportID(forKey key: String) -> String {
        key.hasPrefix("id:") ? String(key.dropFirst(3)) : key
    }

    /// Every key a stored item answers to: the key it was imported with and the key its exported
    /// row comes back with. Build the "existing" map with these so export → edit → import updates.
    public static func lookupKeys(forKey key: String) -> [String] {
        let exported = "id:" + exportID(forKey: key)
        return exported == key ? [key] : [key, exported]
    }

    /// The prompt behind "Copy prompt for another AI".
    public static func prompt(appName: String, existingFolders: [String]) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn the list, notes, screenshot or spreadsheet I give you into items.",
            columns: columns,
            rules: [
                "One row per item. Headings or groups in my data become the folder column.",
                "Number the id column 1, 2, 3 … unless my data already has ids.",
            ],
            existingNames: [("Folders", existingFolders)],
            exampleRows: [
                ["1", "Water the plants", "", "", "Home"],
                ["2", "Send the invoice", "Before Friday", "yes", "Work"],
            ]
        )
    }

    static func isYes(_ raw: String) -> Bool {
        ["yes", "y", "true", "1", "x", "done", "ja", "✓", "✔"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
