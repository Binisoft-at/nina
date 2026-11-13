import Foundation
import BinisoftKitCore
import NinaCore
#if os(iOS)
import WidgetKit
#endif

/// The widget snapshot in the shared App Group: `<group>/Nina/snapshot.json`.
/// Only this small summary goes there – never the app's data.
enum WidgetBridge {
    nonisolated(unsafe) private static var lastPublished: ItemSummary?

    static var folder: URL? {
        guard let group = AppIdentifiers.main.sharedAppGroup,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Writes the summary and reloads the widgets when something changed.
    static func publish(_ summary: ItemSummary) {
        guard !summary.hasSameContent(as: lastPublished), let folder else { return }
        do {
            try SnapshotFile<ItemSummary>(folder: folder, name: ItemSummary.fileName).write(summary)
            lastPublished = summary
            #if os(iOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            AppLog.warning("Widget snapshot not written: \(error.localizedDescription)", category: "widgets")
        }
    }

    static func read() -> ItemSummary? {
        guard let folder else { return nil }
        return SnapshotFile<ItemSummary>(folder: folder, name: ItemSummary.fileName).read()
    }
}
