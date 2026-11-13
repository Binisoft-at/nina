import Foundation
import BinisoftKitCore
import NinaCore
#if os(iOS) || os(watchOS)
import WidgetKit
#endif

/// The widget snapshot in the shared App Group: `<group>/Nina/today.json` – today's numbers only,
/// never the diary. On the watch the same file feeds the complications.
enum WidgetBridge {
    nonisolated(unsafe) private static var lastPublished: TodaySnapshot?
    /// Active energy (kcal) from Apple Health today, set by the Health service.
    nonisolated(unsafe) static var activityBonus: Double = 0

    static var folder: URL? {
        guard let group = AppIdentifiers.main.sharedAppGroup,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Writes the snapshot and reloads the widgets when something changed.
    static func publish(_ snapshot: TodaySnapshot) {
        guard !snapshot.hasSameContent(as: lastPublished), let folder else { return }
        do {
            try SnapshotFile<TodaySnapshot>(folder: folder, name: TodaySnapshot.fileName).write(snapshot)
            lastPublished = snapshot
            #if os(iOS) || os(watchOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            AppLog.warning("Widget snapshot not written: \(error.localizedDescription)", category: "widgets")
        }
    }

    static func read() -> TodaySnapshot? {
        guard let folder else { return nil }
        return SnapshotFile<TodaySnapshot>(folder: folder, name: TodaySnapshot.fileName).read()
    }
}
