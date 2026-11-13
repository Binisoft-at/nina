import Foundation
import SwiftData
import BinisoftKit

/// A group of items ("Home", "Work"). Deleting a folder moves it and its items to the trash.
@Model
final class Folder {
    var uuid: UUID = UUID()
    var name: String = ""
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \Item.folder)
    var items: [Item]? = []

    init(name: String, sortOrder: Double = 0) {
        let now = Date()
        self.uuid = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension Folder: SoftDeletable {}

extension Folder {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
