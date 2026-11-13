import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The interactive tour: the real Items screen on a throwaway practice store, with the coach card
/// on top. Each step watches the page and ticks itself off once you've done what it describes.
struct TourView: View {
    let steps: [TourStep<NinaTourSnapshot>]
    /// The real app's model: its menu commands are pointed at the practice page meanwhile.
    let host: AppModel
    let onFinish: () -> Void

    @State private var sandbox: AppModel?

    var body: some View {
        Group {
            if let sandbox {
                PracticePage(steps: steps, startAt: host.launch.tourStep, onFinish: onFinish)
                    .environment(sandbox)
                    .modelContainer(sandbox.container)
                    .modifier(AppChrome(app: sandbox))
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard sandbox == nil else { return }
            let model = AppModel(container: Persistence.practiceStore(), mode: .demo, isSandbox: true)
            sandbox = model
            host.tourModel = model
        }
        .onDisappear { host.tourModel = nil }
    }
}

private struct PracticePage: View {
    let steps: [TourStep<NinaTourSnapshot>]
    let startAt: String?
    let onFinish: () -> Void

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil }, sort: \Item.sortOrder)
    private var items: [Item]
    @Query(filter: #Predicate<Item> { $0.deletedAt != nil })
    private var trashed: [Item]
    @Query(filter: #Predicate<Folder> { $0.deletedAt == nil })
    private var folders: [Folder]

    var body: some View {
        NavigationStack {
            // Inside the stack, so the coach sits below the navigation bar and the + stays reachable.
            ItemListView(filter: .open)
                .tourCoach(steps: steps, snapshot: snapshot, startAt: startAt, onClose: onFinish)
        }
    }

    private var snapshot: NinaTourSnapshot {
        var snapshot = NinaTourSnapshot()
        snapshot.itemCount = items.count
        snapshot.doneCount = items.filter(\.isDone).count
        snapshot.trashedCount = trashed.count
        snapshot.folderCount = folders.count
        snapshot.order = items.filter { !$0.isDone }.map(\.uuid.uuidString)
        if case .create = app.sheet { snapshot.isCreateOpen = true }
        if case .editItem = app.sheet { snapshot.isEditorOpen = true }
        return snapshot
    }
}
