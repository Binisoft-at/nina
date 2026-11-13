import SwiftUI
import SwiftData
import BinisoftKit

/// New and edit item. Saving goes through ItemStore (timestamps, order, save).
struct ItemEditor: View {
    let item: Item?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil }, sort: \Folder.sortOrder)
    private var folders: [Folder]

    @State private var title: String
    @State private var notes: String
    @State private var folderID: UUID?
    @FocusState private var titleFocused: Bool

    init(item: Item?, folder: Folder?) {
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _folderID = State(initialValue: folder?.uuid)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                        .onSubmit(save)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Picker("Folder", selection: $folderID) {
                        Text("No Folder").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Text(folder.displayName).tag(Optional(folder.uuid))
                        }
                    }
                }
                if let item {
                    Section {
                        Button("Delete Item", systemImage: "trash", role: .destructive) {
                            app.trash([item])
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if item == nil { titleFocused = true }
            }
        }
        .sheetFrame(minWidth: 460, minHeight: 380)
    }

    private func save() {
        guard canSave else { return }
        let folder = folders.first { $0.uuid == folderID }
        if let item {
            app.store.update(item, title: title, notes: notes, folder: folder)
        } else {
            app.store.addItem(title: title, notes: notes, folder: folder)
        }
        dismiss()
    }
}

/// New folder or rename.
struct FolderEditor: View {
    let folder: Folder?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool

    init(folder: Folder?) {
        self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Home or Work", text: $name)
                    .focused($focused)
                    .onSubmit(save)
            }
            .formStyle(.grouped)
            .navigationTitle(folder == nil ? "New Folder" : "Rename Folder")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .sheetFrame(minWidth: 420, minHeight: 220)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let folder {
            app.store.rename(folder, to: name)
        } else {
            app.store.addFolder(name: name)
        }
        dismiss()
    }
}

/// The central "+": every way to create something, and importing existing data.
struct NinaCreateSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CreateSheet(
            options: [
                CreateOption(id: "item", title: "New Item", subtitle: "Something to do or remember",
                             symbol: "square.and.pencil") { app.sheet = .newItem(nil) },
                CreateOption(id: "folder", title: "New Folder", subtitle: "A group like Home or Work",
                             symbol: "folder.badge.plus", tint: .orange) { app.sheet = .newFolder },
                CreateOption(id: "import", title: "Import My Data", subtitle: "Your CSV file, or a list another AI wrote for you",
                             symbol: "square.and.arrow.down", tint: .purple, isFeatured: false) { app.sheet = .importData },
            ],
            footnote: "On the Mac and iPad, ⌘N adds an item right away."
        )
    }
}
