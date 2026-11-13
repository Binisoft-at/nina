import SwiftUI
import SwiftData
import TipKit
import BinisoftKit

/// Items, Done and Recently Deleted. Content sits on plain list rows; glass is left to the bars.
struct ItemListView: View {
    let filter: ItemFilter

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }, sort: \Item.sortOrder)
    private var live: [Item]
    @Query(filter: #Predicate<Item> { $0.deletedAt != nil }, sort: [SortDescriptor(\Item.deletedAt, order: .reverse)])
    private var trashed: [Item]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var folders: [Folder]

    private var rows: [Item] {
        switch filter {
        case .open: live.filter { !$0.isDone }
        case .done: live.filter(\.isDone)
        case .trash: trashed
        }
    }

    var body: some View {
        @Bindable var app = app
        list
            .overlay {
                if rows.isEmpty { emptyState }
            }
            .navigationTitle(filter.title)
            .toolbar { toolbar }
            #if os(iOS)
            .navigationDestination(isPresented: $app.showTrash) {
                ItemListView(filter: .trash)
            }
            #endif
    }

    // MARK: List

    private var list: some View {
        List {
            switch filter {
            case .open:
                if !rows.isEmpty {
                    TipView(NinaTips.SwipeTip())
                }
                section(nil, rows.filter { $0.liveFolder == nil })
                ForEach(folders) { folder in
                    section(folder, rows.filter { $0.liveFolder?.uuid == folder.uuid })
                }
            case .done:
                ForEach(rows) { item in row(item) }
            case .trash:
                Section {
                    ForEach(rows) { item in trashRow(item) }
                } footer: {
                    if !rows.isEmpty {
                        Text("Items stay here for 30 days, then they are deleted for good.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ folder: Folder?, _ items: [Item]) -> some View {
        if folder != nil || !items.isEmpty {
            Section {
                ForEach(items) { item in row(item) }
                    .onMove { source, destination in
                        app.store.move(items, from: source, to: destination)
                    }
            } header: {
                if let folder {
                    Text(folder.displayName)
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") { app.sheet = .renameFolder(folder) }
                            Button("Delete Folder", systemImage: "trash", role: .destructive) { app.trash(folder) }
                        }
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        ItemRow(item: item) { app.toggle(item) }
            .onTapGesture { app.sheet = .editItem(item) }
            .swipeActions(edge: .leading) {
                Button(item.isDone ? "Not Done" : "Done", systemImage: item.isDone ? "circle" : "checkmark") {
                    app.toggle(item)
                }
                .tint(Brand.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash([item]) }
            }
            .contextMenu {
                Button("Edit…", systemImage: "pencil") { app.sheet = .editItem(item) }
                Button(item.isDone ? "Mark as Not Done" : "Mark as Done", systemImage: "checkmark.circle") { app.toggle(item) }
                if !folders.isEmpty {
                    Menu("Move to Folder", systemImage: "folder") {
                        Button("No Folder") { app.store.update(item, title: item.title, notes: item.notes, folder: nil) }
                        ForEach(folders) { folder in
                            Button(folder.displayName) { app.store.update(item, title: item.title, notes: item.notes, folder: folder) }
                        }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { app.trash([item]) }
            }
    }

    private func trashRow(_ item: Item) -> some View {
        ItemRow(item: item, onToggle: nil)
            .swipeActions(edge: .leading) {
                Button("Restore", systemImage: "arrow.uturn.backward") { app.restore([item]) }
                    .tint(Brand.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([item]) }
            }
            .contextMenu {
                Button("Restore", systemImage: "arrow.uturn.backward") { app.restore([item]) }
                Button("Delete Now", systemImage: "trash", role: .destructive) { app.store.purge([item]) }
            }
    }

    // MARK: Empty states – always offer to import the person's own data

    @ViewBuilder
    private var emptyState: some View {
        switch filter {
        case .open:
            EmptyStateView(
                title: live.isEmpty ? "Nothing here yet" : "All done",
                message: live.isEmpty ? "Add your first item, or bring over the list you already have." : "Everything is checked off. Add something new or import a list.",
                symbol: "checklist",
                createTitle: "New Item",
                onCreate: { app.sheet = .newItem(nil) },
                onImport: { app.sheet = .importData }
            )
        case .done:
            EmptyStateView(title: "Nothing done yet", message: "Items you check off show up here.",
                           symbol: "checkmark.circle", onImport: { app.sheet = .importData })
        case .trash:
            EmptyStateView(title: "Recently Deleted is empty", message: "Deleted items stay here for 30 days.",
                           symbol: "trash", onImport: { app.sheet = .importData })
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if filter == .trash {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty", role: .destructive) { app.store.purge(rows) }
                    .disabled(rows.isEmpty)
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.sheet = .create
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .popoverTip(NinaTips.CreateTip())
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("New Folder…", systemImage: "folder.badge.plus") { app.sheet = .newFolder }
                    Button("Recently Deleted", systemImage: "trash") { app.showTrash = true }
                    Divider()
                    if !app.isSandbox {
                        Button("\(AppInfo.name) Tour", systemImage: "graduationcap") { app.startTour() }
                    }
                    Button("Settings", systemImage: "gear") { app.sheet = .settings }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            #endif
        }
    }
}

/// One row: check circle, title, first line of the notes.
struct ItemRow: View {
    let item: Item
    let onToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.isDone ? Brand.accent : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isDone ? "Mark as not done" : "Mark as done")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                if let notes = item.notesPreview {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .sensoryFeedback(.success, trigger: item.isDone) { _, done in done }
    }
}

/// Full-text search over every live item.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }, sort: \Item.sortOrder)
    private var items: [Item]
    @State private var text = ""

    private var results: [Item] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(needle) || $0.notes.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        List(results) { item in
            ItemRow(item: item) { app.toggle(item) }
                .onTapGesture { app.sheet = .editItem(item) }
        }
        .overlay {
            if text.isEmpty {
                ContentUnavailableView("Search \(AppInfo.name)", systemImage: "magnifyingglass",
                                       description: Text("Titles and notes of every item."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: text)
            }
        }
        .searchable(text: $text, prompt: "Search items")
        .navigationTitle("Search")
    }
}
