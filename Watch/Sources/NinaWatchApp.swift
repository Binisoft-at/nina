import SwiftUI
import SwiftData
import BinisoftKit

/// The watch app syncs on its own through the app's iCloud container (same store code as the phone).
@main
struct NinaWatchApp: App {
    let container: ModelContainer

    init() {
        AppLog.bootstrap(appName: AppInfo.name)
        container = Persistence.open().container
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
        }
        .modelContainer(container)
    }
}
