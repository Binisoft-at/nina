import Foundation
import SwiftData
import BinisoftKit

/// Opens Nina's store (rules in BinisoftKit `ModelStore`): synced through
/// `.private(APP_CLOUDKIT_CONTAINER)` with `groupContainer: .none`, local-only when iCloud isn't
/// available, sample data in memory for `-Demo`, and a separate practice store for the tour.
enum Persistence {
    static let models: [any PersistentModel.Type] = [Item.self, Folder.self]

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    @MainActor
    static func open() -> ModelStore.Opened {
        ModelStore.open(
            name: AppInfo.name,
            models: models,
            initializeCloudKitSchema: isDebugBuild,
            seedDemo: DemoData.seed
        )
    }

    /// The tour's practice page: in memory, seeded, never synced, gone when the tour closes.
    @MainActor
    static func practiceStore() -> ModelContainer {
        ModelStore.inMemory(name: "\(AppInfo.name)Tour", models: models, seed: DemoData.seedPractice)
    }
}
