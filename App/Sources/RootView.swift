import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// iPhone/iPad: tab bar (a sidebar on iPad) with a bottom accessory. Mac: split view.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        navigation
            .modifier(AppChrome(app: app))
            .modifier(TourPresenter(app: app))
            .onOpenURL { url in app.open(url) }
            .task {
                // The tour opens by itself once after install (and as "What's new" after updates).
                try? await Task.sleep(for: .milliseconds(800))
                app.offerTourIfNeeded()
            }
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        MacRoot()
        #else
        PhoneRoot()
        #endif
    }
}

#if os(iOS)
private struct PhoneRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("Items", systemImage: "checklist", value: AppTab.items) {
                NavigationStack { ItemListView(filter: .open) }
            }
            Tab("Done", systemImage: "checkmark.circle", value: AppTab.done) {
                NavigationStack { ItemListView(filter: .done) }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .minimizingTabBar()
        .tabViewBottomAccessory {
            SummaryAccessory()
        }
    }
}

/// The bottom accessory: what's going on right now, one tap to add.
private struct SummaryAccessory: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Item> { $0.deletedAt == nil && !$0.isDone }, sort: \Item.sortOrder)
    private var open: [Item]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(open.isEmpty ? "All done" : "\(open.count) open")
                    .font(.subheadline.weight(.semibold))
                if let next = open.inListOrder.first {
                    Text("Next: \(next.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                app.sheet = .newItem(nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Item")
        }
        .padding(.horizontal, 16)
    }
}
#endif

#if os(macOS)
private struct MacRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.sidebar) {
                Label("Items", systemImage: "checklist").tag(SidebarItem.items)
                Label("Done", systemImage: "checkmark.circle").tag(SidebarItem.done)
                Label("Recently Deleted", systemImage: "trash").tag(SidebarItem.trash)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            NavigationStack {
                switch app.sidebar ?? .items {
                case .items: ItemListView(filter: .open)
                case .done: ItemListView(filter: .done)
                case .trash: ItemListView(filter: .trash)
                }
            }
        }
    }
}
#endif

/// The sheets any screen can open, toasts and undo. Shared by the window and the tour's practice page.
struct AppChrome: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $app.sheet) { sheet in
                SheetContent(sheet: sheet)
                    .environment(app)
            }
            .toasts(app.toasts)
            .undoableChanges(in: app.container.mainContext)
    }
}

private struct SheetContent: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .create:
            NinaCreateSheet()
        case .newItem(let folder):
            ItemEditor(item: nil, folder: folder)
        case .editItem(let item):
            ItemEditor(item: item, folder: item.liveFolder)
        case .newFolder:
            FolderEditor(folder: nil)
        case .renameFolder(let folder):
            FolderEditor(folder: folder)
        case .importData:
            ImportView()
        case .settings:
            NavigationStack {
                SettingsView()
            }
            .sheetFrame(minWidth: 520, minHeight: 600)
        }
    }
}

/// Full screen on iPhone/iPad, a large sheet on the Mac.
struct TourPresenter: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $app.tour) { request in
            TourView(steps: request.steps, host: app) { app.finishTour() }
                .appearanceFromSettings()
        }
        #else
        content.sheet(item: $app.tour) { request in
            TourView(steps: request.steps, host: app) { app.finishTour() }
                .frame(minWidth: 760, idealWidth: 900, minHeight: 620, idealHeight: 760)
        }
        #endif
    }
}
