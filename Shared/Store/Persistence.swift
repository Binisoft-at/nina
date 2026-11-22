import Foundation
import SwiftData
import BinisoftKit

/// Opens Nina's store (rules in BinisoftKit `ModelStore`): synced through
/// `.private(APP_CLOUDKIT_CONTAINER)` with `groupContainer: .none`, local-only when iCloud isn't
/// available, sample data in memory for `-Demo`, and a separate practice store for the tour.
/// No Apple Health values are stored: they are read live on each device.
enum Persistence {
    /// The watch leaves out the progress photos: it never shows them, so its store doesn't keep
    /// them (a store skips CloudKit records of models it doesn't have, as older builds do).
    #if os(watchOS)
    static let models: [any PersistentModel.Type] = [
        LogEntry.self, Food.self, Recipe.self, RecipeItem.self, WaterLog.self, WeightEntry.self, PlanRule.self, NinaProfile.self,
        BodyMeasurement.self, DayMark.self,
    ]
    #else
    static let models: [any PersistentModel.Type] = [
        LogEntry.self, Food.self, Recipe.self, RecipeItem.self, WaterLog.self, WeightEntry.self, PlanRule.self, NinaProfile.self,
        BodyMeasurement.self, DayMark.self, ProgressPhoto.self,
    ]
    #endif

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// One store per process – the app, its App Intents and widgets-triggered actions share it,
    /// so CloudKit mirroring never runs twice.
    @MainActor
    static let shared: ModelStore.Opened = ModelStore.open(
        name: AppInfo.name,
        models: models,
        initializeCloudKitSchema: isDebugBuild,
        seedDemo: DemoData.seed
    )

    /// The tour's practice day: in memory, seeded, never synced, gone when the tour closes.
    @MainActor
    static func practiceStore() -> ModelContainer {
        ModelStore.inMemory(name: "\(AppInfo.name)Tour", models: models, seed: DemoData.seedPractice)
    }
}
