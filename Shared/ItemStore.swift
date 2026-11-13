import Foundation
import SwiftData
import BinisoftKit
import NinaCore

/// Every change to items and folders goes through here – ordering, timestamps, soft delete, save,
/// widget snapshot – so the rules live in one place. Views never write to the model directly.
@MainActor
struct ItemStore {
    let context: ModelContext
    var trashPolicy = TrashPolicy(keepDays: 30)

    // MARK: Reading

    /// Live items in list order.
    func items() -> [Item] {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func trashedItems() -> [Item] {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.deletedAt != nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    func folders() -> [Folder] {
        let descriptor = FetchDescriptor<Folder>(
            predicate: #Predicate<Folder> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Items

    @discardableResult
    func addItem(title: String, notes: String = "", folder: Folder? = nil) -> Item {
        let order = ListOrder.after(items().map(\.sortOrder))
        let item = Item(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: notes, sortOrder: order, folder: folder)
        context.insert(item)
        save()
        return item
    }

    func update(_ item: Item, title: String, notes: String, folder: Folder?) {
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes
        item.folder = folder
        item.touch()
        save()
    }

    func setDone(_ items: [Item], _ done: Bool) {
        let now = Date()
        for item in items where item.isDone != done {
            item.isDone = done
            item.completedAt = done ? now : nil
            item.touch(now: now)
        }
        save()
    }

    func toggle(_ item: Item) {
        setDone([item], !item.isDone)
    }

    /// List `onMove` on `rows` (the rows as shown): only the moved rows get a new order.
    func move(_ rows: [Item], from source: IndexSet, to destination: Int) {
        let changes = ListOrder.move(rows.map(\.sortOrder), from: source, to: destination)
        let now = Date()
        for (index, order) in changes where rows.indices.contains(index) {
            rows[index].sortOrder = order
            rows[index].touch(now: now)
        }
        normalizeIfNeeded()
        save()
    }

    /// Soft delete. Returns what moved to the trash, for Undo.
    @discardableResult
    func trash(_ items: [Item]) -> [Item] {
        let now = Date()
        for item in items { item.moveToTrash(now: now) }
        save()
        return items
    }

    func restore(_ items: [Item]) {
        let now = Date()
        for item in items {
            item.restoreFromTrash(now: now)
            if let folder = item.folder, folder.isInTrash { folder.restoreFromTrash(now: now) }
        }
        save()
    }

    /// Deletes for good (Recently Deleted → Delete Now).
    func purge(_ items: [Item]) {
        for item in items { context.delete(item) }
        save()
    }

    /// Empties what has been in the trash longer than the policy allows. Run at launch.
    func purgeExpired(now: Date = Date()) {
        let expired = trashedItems().filter { trashPolicy.isExpired(deletedAt: $0.deletedAt, now: now) }
        let descriptor = FetchDescriptor<Folder>(predicate: #Predicate<Folder> { $0.deletedAt != nil })
        let folders = ((try? context.fetch(descriptor)) ?? []).filter { trashPolicy.isExpired(deletedAt: $0.deletedAt, now: now) }
        guard !expired.isEmpty || !folders.isEmpty else { return }
        for item in expired { context.delete(item) }
        for folder in folders { context.delete(folder) }
        AppLog.info("Emptied \(expired.count) item(s) and \(folders.count) folder(s) from the trash", category: "store")
        save()
    }

    // MARK: Folders

    @discardableResult
    func addFolder(name: String) -> Folder {
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sortOrder: ListOrder.after(folders().map(\.sortOrder)))
        context.insert(folder)
        save()
        return folder
    }

    func rename(_ folder: Folder, to name: String) {
        folder.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.touch()
        save()
    }

    /// Moves the folder and its items to the trash. Returns the items, for Undo.
    @discardableResult
    func trash(_ folder: Folder) -> [Item] {
        let now = Date()
        let items = (folder.items ?? []).filter { $0.deletedAt == nil }
        for item in items { item.moveToTrash(now: now) }
        folder.moveToTrash(now: now)
        save()
        return items
    }

    func restore(_ folder: Folder, items: [Item]) {
        let now = Date()
        folder.restoreFromTrash(now: now)
        for item in items { item.restoreFromTrash(now: now) }
        save()
    }

    // MARK: Import and export

    /// What the app already has, under every key an item answers to.
    func existingDrafts() -> [String: ItemDraft] {
        var result: [String: ItemDraft] = [:]
        for item in items() {
            for key in ItemCSV.lookupKeys(forKey: item.key) { result[key] = item.draft }
        }
        return result
    }

    func importPlan(for text: String) -> ImportPlan<ItemDraft> {
        ItemCSV.plan(text, existing: existingDrafts())
    }

    /// Applies a previewed plan: creates new items, updates changed ones, leaves the rest.
    @discardableResult
    func apply(_ plan: ImportPlan<ItemDraft>) -> (created: Int, updated: Int) {
        var byKey: [String: Item] = [:]
        for item in items() {
            for key in ItemCSV.lookupKeys(forKey: item.key) { byKey[key] = item }
        }
        var foldersByName: [String: Folder] = [:]
        for folder in folders() { foldersByName[folder.name.lowercased()] = folder }
        func folder(named name: String) -> Folder? {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let existing = foldersByName[trimmed.lowercased()] { return existing }
            let created = Folder(name: trimmed, sortOrder: ListOrder.after(foldersByName.values.map(\.sortOrder)))
            context.insert(created)
            foldersByName[trimmed.lowercased()] = created
            return created
        }

        var created = 0
        var updated = 0
        var nextOrder = ListOrder.after(items().map(\.sortOrder))
        let now = Date()
        for entry in plan.entries {
            let draft = entry.record
            switch entry.action {
            case .unchanged:
                continue
            case .update:
                guard let item = byKey[entry.key] else { continue }
                item.title = draft.title
                item.notes = draft.notes
                item.isDone = draft.isDone
                item.completedAt = draft.isDone ? (item.completedAt ?? now) : nil
                item.folder = folder(named: draft.folder)
                item.touch(now: now)
                updated += 1
            case .create:
                let item = Item(title: draft.title, notes: draft.notes, sortOrder: nextOrder, folder: folder(named: draft.folder))
                nextOrder += 1
                item.isDone = draft.isDone
                item.completedAt = draft.isDone ? now : nil
                item.importKey = entry.key
                context.insert(item)
                created += 1
            }
        }
        AppLog.info("Import: \(created) new, \(updated) updated, \(plan.unchanged) unchanged, \(plan.skipped.count) skipped", category: "import")
        save()
        return (created, updated)
    }

    func exportCSV() -> String {
        ItemCSV.export(items().map { ($0.key, $0.draft) })
    }

    // MARK: Saving

    func summary() -> ItemSummary {
        let live = items()
        return ItemSummary.make(open: live.filter { !$0.isDone }.inListOrder.map(\.displayTitle),
                                doneCount: live.filter(\.isDone).count)
    }

    /// Saves and refreshes the widget snapshot (not for the tour's or the demo's in-memory stores).
    func save() {
        do {
            try context.save()
        } catch {
            AppLog.error("Save failed: \(error.localizedDescription)", category: "store")
        }
        if !isInMemory {
            WidgetBridge.publish(summary())
        }
    }

    private var isInMemory: Bool {
        context.container.configurations.contains { $0.isStoredInMemoryOnly }
    }

    private func normalizeIfNeeded() {
        let live = items()
        guard ListOrder.needsNormalizing(live.map(\.sortOrder)) else { return }
        for (item, order) in zip(live, ListOrder.normalized(count: live.count)) {
            item.sortOrder = order
        }
    }
}
