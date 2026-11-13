import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

enum AppTab: Hashable {
    case items, done, search
}

/// Mac sidebar.
enum SidebarItem: Hashable {
    case items, done, trash
}

/// What a list shows.
enum ItemFilter: Hashable {
    case open, done, trash

    var title: String {
        switch self {
        case .open: "Items"
        case .done: "Done"
        case .trash: "Recently Deleted"
        }
    }
}

/// Every sheet the app can show. One place, so any screen (and the tour) can open any sheet.
enum AppSheet: Identifiable {
    case create
    case newItem(Folder?)
    case editItem(Item)
    case newFolder
    case renameFolder(Folder)
    case importData
    case settings

    var id: String {
        switch self {
        case .create: "create"
        case .newItem: "new-item"
        case .editItem(let item): "edit-" + item.uuid.uuidString
        case .newFolder: "new-folder"
        case .renameFolder(let folder): "rename-" + folder.uuid.uuidString
        case .importData: "import"
        case .settings: "settings"
        }
    }
}

struct TourRequest: Identifiable {
    let id = UUID()
    let steps: [TourStep<NinaTourSnapshot>]
}

/// App-wide UI state shared by all windows. The tour's practice page gets its own instance on
/// its own in-memory store (`isSandbox`), so nothing done there touches real data.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let mode: StorageMode
    let sync: SyncMonitor
    let toasts: ToastCenter
    let launch: LaunchOptions
    let isSandbox: Bool

    var tab: AppTab = .items
    var sidebar: SidebarItem? = .items
    var sheet: AppSheet?
    var tour: TourRequest?
    /// iPhone: Recently Deleted is pushed from the Items menu.
    var showTrash = false
    /// The practice page's model while the tour is open: menu commands act there.
    var tourModel: AppModel?
    /// A CSV opened from Files / "Open in" – the import sheet picks it up.
    var pendingImport: URL?

    init(container: ModelContainer, mode: StorageMode, launch: LaunchOptions = .current, isSandbox: Bool = false) {
        self.container = container
        self.mode = mode
        self.launch = launch
        self.isSandbox = isSandbox
        self.sync = SyncMonitor(mode: isSandbox ? .demo : mode, appName: AppInfo.name)
        self.toasts = ToastCenter()
        guard !isSandbox else { return }
        applyLaunchOptions()
        if !launch.isDemo { store.purgeExpired() }
    }

    var store: ItemStore { ItemStore(context: container.mainContext) }

    /// Where menu commands act: the practice page during the tour, otherwise this model.
    var commandTarget: AppModel { tourModel ?? self }

    // MARK: Actions with Undo

    func toggle(_ item: Item) {
        store.toggle(item)
    }

    func trash(_ items: [Item]) {
        guard !items.isEmpty else { return }
        let trashed = store.trash(items)
        let label = trashed.count == 1 ? "Deleted \u{201C}\(trashed[0].displayTitle)\u{201D}" : "Deleted \(trashed.count) items"
        toasts.show(label, symbol: "trash.fill") { [weak self] in
            self?.store.restore(trashed)
        }
    }

    func trash(_ folder: Folder) {
        let items = store.trash(folder)
        toasts.show("Deleted folder \u{201C}\(folder.displayName)\u{201D}", symbol: "trash.fill") { [weak self] in
            self?.store.restore(folder, items: items)
        }
    }

    func restore(_ items: [Item]) {
        store.restore(items)
        toasts.show(items.count == 1 ? "Restored" : "Restored \(items.count) items", symbol: "arrow.uturn.backward")
    }

    // MARK: Tour

    /// Opens the tour once after install, and the What's new steps after an update that added some.
    func offerTourIfNeeded() {
        guard !isSandbox, !launch.isDemo, tour == nil else { return }
        let steps = TourSchedule().stepsToOffer(NinaTour.catalog)
        guard !steps.isEmpty else { return }
        AppLog.info("Tour offered (\(steps.count) steps)", category: "tour")
        tour = TourRequest(steps: steps)
    }

    /// Replay from Settings or Help → Nina Tour. A sheet has to close first.
    func startTour() {
        guard sheet != nil else {
            tour = TourRequest(steps: NinaTour.catalog.allSteps)
            return
        }
        sheet = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.tour = TourRequest(steps: NinaTour.catalog.allSteps)
        }
    }

    /// A CSV opened from Files or another app.
    func open(_ url: URL) {
        AppLog.info("Opened \(url.lastPathComponent)", category: "import")
        pendingImport = url
        sheet = .importData
    }

    func finishTour() {
        TourSchedule().markSeen(NinaTour.catalog)
        tour = nil
        tourModel = nil
    }

    // MARK: Launch arguments (screenshots in CI)

    /// `-Demo -DemoScreen <name>` opens a screen; `-Tour` / `-TourStep <id>` open the tour.
    private func applyLaunchOptions() {
        if launch.resetTour { TourSchedule().reset() }
        switch launch.screen {
        case "done":
            tab = .done
            sidebar = .done
        case "trash":
            sidebar = .trash
            showTrash = true
        case "search":
            tab = .search
        case "create":
            sheet = .create
        case "new":
            sheet = .newItem(nil)
        case "edit":
            if let first = store.items().first { sheet = .editItem(first) }
        case "import":
            sheet = .importData
        case "settings":
            sheet = .settings
        default:
            break
        }
        if launch.startTour { startTour() }
    }
}
