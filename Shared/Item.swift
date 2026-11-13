import Foundation
import SwiftData
import BinisoftKit
import NinaCore

/// One entry in the list.
///
/// CloudKit rules: every attribute has a default, relationships are optional with an inverse,
/// nothing is unique. New fields are optional or have a default (older builds keep working), and
/// cloudkit/schema.ckdb gets the same field before the next TestFlight build.
@Model
final class Item {
    var uuid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var completedAt: Date?
    /// Manual position: lower = higher up.
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Soft delete ("Recently Deleted", 30 days).
    var deletedAt: Date?
    /// Key of the imported row (CSV `id` or content key) – re-importing updates instead of duplicating.
    var importKey: String = ""
    var folder: Folder?

    init(title: String, notes: String = "", sortOrder: Double = 0, folder: Folder? = nil) {
        let now = Date()
        self.uuid = UUID()
        self.title = title
        self.notes = notes
        self.sortOrder = sortOrder
        self.folder = folder
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension Item: SoftDeletable {}

extension Item {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var notesPreview: String? {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    /// The folder unless it is in the trash.
    var liveFolder: Folder? {
        guard let folder, folder.deletedAt == nil else { return nil }
        return folder
    }

    /// Key used by import and export.
    var key: String { importKey.isEmpty ? "id:" + uuid.uuidString : importKey }

    var draft: ItemDraft {
        ItemDraft(title: title, notes: notes, isDone: isDone, folder: liveFolder?.name ?? "")
    }
}

extension Array where Element == Item {
    /// The order the list shows: items without a folder first, then folder by folder.
    var inListOrder: [Item] {
        sorted { lhs, rhs in
            let left = (lhs.liveFolder == nil ? 0 : 1, lhs.liveFolder?.sortOrder ?? 0, lhs.sortOrder)
            let right = (rhs.liveFolder == nil ? 0 : 1, rhs.liveFolder?.sortOrder ?? 0, rhs.sortOrder)
            return left < right
        }
    }
}
