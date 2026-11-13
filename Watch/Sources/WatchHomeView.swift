import SwiftUI
import SwiftData
import BinisoftKit

/// Open items: tap to check off, add one by voice or keyboard.
struct WatchHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil && !$0.isDone }, sort: \Item.sortOrder)
    private var open: [Item]

    private var store: ItemStore { ItemStore(context: context) }

    var body: some View {
        List {
            TextFieldLink(prompt: Text("New item")) {
                Label("Add", systemImage: "plus")
                    .foregroundStyle(Brand.accent)
            } onSubmit: { text in
                let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { store.addItem(title: title) }
            }
            if open.isEmpty {
                Text("All done")
                    .foregroundStyle(.secondary)
            }
            ForEach(open) { item in
                Button {
                    withAnimation { store.toggle(item) }
                } label: {
                    Label(item.displayTitle, systemImage: "circle")
                }
            }
        }
        .navigationTitle(AppInfo.name)
    }
}
