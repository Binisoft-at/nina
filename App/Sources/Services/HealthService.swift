import Foundation
import SwiftData
import Observation
import BinisoftKit
import NinaCore
#if os(iOS)
import HealthKit
#endif

/// Apple Health, iPhone only. Writes what was eaten (one food correlation per entry, with a sync
/// identifier so edits replace instead of duplicating) and water; reads weight and active energy
/// live. Health values are never stored in Nina's iCloud data (App Store guideline 5.1.3).
/// What was written is remembered in a device-only file, so each entry is written once per change.
@MainActor
@Observable
final class HealthService {
    enum Option: String, CaseIterable {
        case writeDiary, writeWater, weight, activity

        var title: String {
            switch self {
            case .writeDiary: "Meals and nutrients"
            case .writeWater: "Water"
            case .weight: "Weight (read and write)"
            case .activity: "Active energy (read)"
            }
        }

        var key: String { "nina.health." + rawValue }
    }

    let enabled: Bool
    private(set) var options: Set<Option> = []
    private(set) var activeEnergyToday: Double = 0
    private(set) var weights: [DayKey: Double] = [:]
    /// Weigh-ins from other apps and scales, with their times (not the ones Nina wrote), newest
    /// first. Read live for the weight signal (`AppModel.healthWeightReadings`), never stored.
    private(set) var weightSamples: [HealthWeightSample] = []
    private(set) var latestWeight: Double?
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    /// Body fat, lean mass, waist, height and today's workouts, read live (HealthService+Body.swift).
    let bodyData: HealthBodyReader
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(enabled: Bool) {
        self.enabled = enabled
        bodyData = HealthBodyReader(enabled: enabled)
        for option in Option.allCases where UserDefaults.standard.bool(forKey: option.key) {
            options.insert(option)
        }
    }

    var isAvailable: Bool {
        #if os(iOS)
        enabled && HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    var isConnected: Bool { isAvailable && !options.isEmpty }
    var readsWeight: Bool { isConnected && options.contains(.weight) }

    func isOn(_ option: Option) -> Bool { options.contains(option) }

    /// Turns an option on or off; asks for permission when something new is turned on.
    func set(_ option: Option, _ on: Bool, container: ModelContainer) async {
        if on { options.insert(option) } else { options.remove(option) }
        UserDefaults.standard.set(on, forKey: option.key)
        if on {
            await requestAuthorization()
            await refreshReadings()
            await syncNow(container: container)
        }
    }

    #if os(iOS)
    @ObservationIgnored private let store = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if options.contains(.writeDiary) {
            for item in HealthMapping.items {
                if let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: item.identifier)) {
                    types.insert(type)
                }
            }
        }
        if options.contains(.writeWater) { types.insert(HKQuantityType(.dietaryWater)) }
        if options.contains(.weight) { types.insert(HKQuantityType(.bodyMass)) }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if options.contains(.weight) { types.insert(HKQuantityType(.bodyMass)) }
        if options.contains(.activity) { types.insert(HKQuantityType(.activeEnergyBurned)) }
        return types
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            AppLog.info("Health permission asked (\(options.count) options)", category: "health")
        } catch {
            lastError = error.localizedDescription
            AppLog.warning("Health permission failed: \(error.localizedDescription)", category: "health")
        }
    }

    func refreshReadings() async {
        guard isAvailable else { return }
        if options.contains(.activity) {
            let start = Calendar.current.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned), predicate: predicate),
                                                         options: .cumulativeSum)
            if let statistics = try? await descriptor.result(for: store) {
                activeEnergyToday = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
        } else {
            activeEnergyToday = 0
        }
        WidgetBridge.activityBonus = activeEnergyToday

        if options.contains(.weight) {
            let start = Calendar.current.date(byAdding: .day, value: -400, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
                                                     sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 2000)
            if let samples = try? await descriptor.result(for: store) {
                var byDay: [DayKey: Double] = [:]
                for sample in samples {
                    let day = DayKey(date: sample.endDate)
                    if byDay[day] == nil { byDay[day] = sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
                }
                weights = byDay
                latestWeight = samples.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                let own = HKSource.default()
                weightSamples = samples.compactMap { sample -> HealthWeightSample? in
                    guard sample.metadata?["NinaWeight"] == nil, sample.sourceRevision.source != own else { return nil }
                    return HealthWeightSample(date: sample.endDate, kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
            }
        } else {
            weights = [:]
            weightSamples = []
            latestWeight = nil
        }
        await bodyData.refresh()
    }

    /// Debounced: many saves in a row cause one Health sync.
    func scheduleSync(container: ModelContainer) {
        guard isConnected else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncNow(container: container)
        }
    }

    /// Writes new and changed entries of the last 14 days, removes deleted, planned and skipped ones.
    func syncNow(container: ModelContainer) async {
        guard isAvailable, options.contains(.writeDiary) || options.contains(.writeWater) || options.contains(.weight) else { return }
        let context = container.mainContext
        let first = DayKey.today().adding(days: -14).rawValue
        var ledger = HealthLedger.load()
        var removeIDs: [String] = []
        var write: [(id: String, version: Int, entry: LogEntry)] = []

        let entries = (try? context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.day >= first }))) ?? []
        for entry in entries {
            let id = entry.uuid.uuidString
            let version = HealthMapping.syncVersion(modifiedAt: entry.modifiedAt)
            let wanted = options.contains(.writeDiary) && entry.deletedAt == nil && entry.isEaten && entry.energy > 0
            if wanted {
                if ledger.versions[id] != version {
                    if ledger.versions[id] != nil { removeIDs.append(id) }
                    write.append((id, version, entry))
                }
            } else if ledger.versions[id] != nil {
                removeIDs.append(id)
                ledger.versions[id] = nil
            }
        }

        var waterWrite: [WaterLog] = []
        var waterRemove: [String] = []
        let waters = (try? context.fetch(FetchDescriptor<WaterLog>(predicate: #Predicate<WaterLog> { $0.day >= first }))) ?? []
        for log in waters {
            let id = "w:" + log.uuid.uuidString
            let wanted = options.contains(.writeWater) && log.deletedAt == nil && log.amount > 0
            if wanted, ledger.versions[id] == nil {
                waterWrite.append(log)
            } else if !wanted, ledger.versions[id] != nil {
                waterRemove.append(log.uuid.uuidString)
                ledger.versions[id] = nil
            }
        }

        if !removeIDs.isEmpty { await delete(metadataValues: removeIDs, key: "NinaEntry") }
        if !waterRemove.isEmpty { await delete(metadataValues: waterRemove, key: "NinaWater", types: [HKQuantityType(.dietaryWater)]) }

        var written = 0
        for item in write {
            if await save(item.entry, version: item.version) {
                ledger.versions[item.id] = item.version
                written += 1
            }
        }
        for log in waterWrite {
            let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: log.amount),
                                          start: log.time, end: log.time,
                                          metadata: ["NinaWater": log.uuid.uuidString, HKMetadataKeySyncIdentifier: HealthMapping.syncIdentifier(water: log.uuid),
                                                     HKMetadataKeySyncVersion: NSNumber(value: 1)])
            do {
                try await store.save(sample)
                ledger.versions["w:" + log.uuid.uuidString] = 1
                written += 1
            } catch {
                lastError = error.localizedDescription
            }
        }
        ledger.prune(keeping: Set(entries.map(\.uuid.uuidString) + waters.map { "w:" + $0.uuid.uuidString }))
        written += await syncWeights(context: context, from: first, ledger: &ledger)
        ledger.save()
        lastSync = Date()
        if written > 0 || !removeIDs.isEmpty {
            AppLog.info("Health: wrote \(written), removed \(removeIDs.count + waterRemove.count)", category: "health")
        }
    }

    /// Weigh-ins of the sync window that Health doesn't have yet – saved on the watch, an iPad or a
    /// Mac – are written here once (HealthWeightSync plans it). The ones typed on this iPhone were
    /// written right away; they are found in Health and only remembered. Imported history stays out.
    private func syncWeights(context: ModelContext, from first: String, ledger: inout HealthLedger) async -> Int {
        guard canWriteWeight else { return 0 }
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate<WeightEntry> { $0.day >= first }))) ?? []
        let items: [HealthWeightSync.Item] = weights.map { (weight: WeightEntry) in
            HealthWeightSync.Item(id: weight.uuid.uuidString, kilograms: weight.kilograms, time: weight.time,
                                  version: HealthMapping.syncVersion(modifiedAt: weight.modifiedAt),
                                  isDeleted: weight.deletedAt != nil, isImported: Self.isImported(weight))
        }
        var marks = ledger.weights ?? [:]
        var written = 0
        for step in HealthWeightSync.plan(items, marks: marks) {
            switch step {
            case .remove(let kilograms, let time):
                await deleteWeightSamples(kilograms: kilograms, date: time)
            case .forget(let id):
                marks[id] = nil
            case .ensure(let id, let mark):
                if await hasWeightSample(kilograms: mark.kilograms, date: mark.time) {
                    marks[id] = mark
                } else if await saveWeightSample(mark.kilograms, date: mark.time) {
                    marks[id] = mark
                    written += 1
                }
            }
        }
        ledger.weights = HealthWeightSync.pruned(marks, keeping: Set(items.map(\.id)))
        return written
    }

    /// Weigh-ins that came from an import (the settings file's weight or the history file) are
    /// history, maybe already in Health from the scale they came from.
    private static func isImported(_ weight: WeightEntry) -> Bool {
        let note = weight.note.lowercased()
        return note == "import" || note.hasPrefix("import") || note.contains("#import")
    }

    private func save(_ entry: LogEntry, version: Int) async -> Bool {
        let values = entry.values
        let metadata: [String: Any] = ["NinaEntry": entry.uuid.uuidString, HKMetadataKeyFoodType: entry.displayName]
        var samples = Set<HKSample>()
        for item in HealthMapping.items {
            guard let value = values[item.nutrient], value > 0,
                  let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: item.identifier)),
                  store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            samples.insert(HKQuantitySample(type: type, quantity: HKQuantity(unit: Self.unit(item.unit), doubleValue: value),
                                            start: entry.time, end: entry.time, metadata: metadata))
        }
        guard !samples.isEmpty else { return true }
        var correlationMetadata = metadata
        correlationMetadata[HKMetadataKeySyncIdentifier] = HealthMapping.syncIdentifier(entry: entry.uuid)
        correlationMetadata[HKMetadataKeySyncVersion] = NSNumber(value: version)
        let correlation = HKCorrelation(type: HKCorrelationType(.food), start: entry.time, end: entry.time, objects: samples,
                                        metadata: correlationMetadata)
        do {
            try await store.save(correlation)
            return true
        } catch {
            lastError = error.localizedDescription
            AppLog.warning("Health write failed: \(error.localizedDescription)", category: "health")
            return false
        }
    }

    private func delete(metadataValues: [String], key: String, types: [HKObjectType]? = nil) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: key, allowedValues: metadataValues)
        var targets: [HKObjectType] = types ?? HealthMapping.items.compactMap {
            HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: $0.identifier))
        }
        if types == nil { targets.append(HKCorrelationType(.food)) }
        for type in targets {
            if let sample = type as? HKQuantityType, store.authorizationStatus(for: sample) != .sharingAuthorized { continue }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.deleteObjects(of: type, predicate: predicate) { _, _, _ in continuation.resume() }
            }
        }
    }

    /// A new weigh-in typed in Nina goes to Apple Health (marked `NinaWeight`, so Nina never reads
    /// it back as a Health weigh-in).
    func writeWeight(_ kilograms: Double, date: Date) async {
        guard canWriteWeight else { return }
        await saveWeightSample(kilograms, date: date)
        await refreshReadings()
    }

    /// An edited weigh-in: the sample Nina wrote for the old weight and time leaves Apple Health
    /// and the new one is written, so Health doesn't keep both.
    func replaceWeight(old: (kilograms: Double, date: Date), new: (kilograms: Double, date: Date)) async {
        guard canWriteWeight else { return }
        await deleteWeightSamples(kilograms: old.kilograms, date: old.date)
        await saveWeightSample(new.kilograms, date: new.date)
        await refreshReadings()
    }

    /// A deleted or undone weigh-in: the sample Nina wrote for it leaves Apple Health. Returns
    /// whether there was one (only then does an Undo write it back).
    @discardableResult
    func deleteWeight(_ kilograms: Double, date: Date) async -> Bool {
        guard canWriteWeight else { return false }
        let removed = await deleteWeightSamples(kilograms: kilograms, date: date)
        await refreshReadings()
        return removed > 0
    }

    private var canWriteWeight: Bool {
        isAvailable && options.contains(.weight)
            && store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized
    }

    @discardableResult
    private func saveWeightSample(_ kilograms: Double, date: Date) async -> Bool {
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
                                      start: date, end: date, metadata: ["NinaWeight": "1"])
        do {
            try await store.save(sample)
            return true
        } catch {
            lastError = error.localizedDescription
            AppLog.warning("Health weight write failed: \(error.localizedDescription)", category: "health")
            return false
        }
    }

    /// The samples Nina wrote at `date` (within a second) with that weight (within 0.05 kg).
    private func weightPredicate(kilograms: Double, date: Date) -> NSPredicate {
        let kilo = HKUnit.gramUnit(with: .kilo)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1), end: date.addingTimeInterval(1), options: []),
            HKQuery.predicateForObjects(withMetadataKey: "NinaWeight"),
            HKQuery.predicateForQuantitySamples(with: .greaterThanOrEqualTo, quantity: HKQuantity(unit: kilo, doubleValue: kilograms - 0.05)),
            HKQuery.predicateForQuantitySamples(with: .lessThanOrEqualTo, quantity: HKQuantity(unit: kilo, doubleValue: kilograms + 0.05)),
        ])
    }

    /// Whether Health already has the sample Nina wrote for this weigh-in.
    private func hasWeightSample(kilograms: Double, date: Date) async -> Bool {
        let predicate = weightPredicate(kilograms: kilograms, date: date)
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    /// Deletes the body-mass samples Nina wrote at `date` (within a second) with that weight
    /// (within 0.05 kg); returns how many. Health only lets an app delete its own samples:
    /// weigh-ins from scales and other apps always stay.
    @discardableResult
    private func deleteWeightSamples(kilograms: Double, date: Date) async -> Int {
        let predicate = weightPredicate(kilograms: kilograms, date: date)
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            store.deleteObjects(of: type, predicate: predicate) { _, count, _ in continuation.resume(returning: count) }
        }
    }

    private static func unit(_ text: String) -> HKUnit {
        switch text {
        case "kcal": .kilocalorie()
        case "mg": .gramUnit(with: .milli)
        case "mcg": .gramUnit(with: .micro)
        default: .gram()
        }
    }
    #else
    func requestAuthorization() async {}
    func refreshReadings() async {}
    func scheduleSync(container: ModelContainer) {}
    func syncNow(container: ModelContainer) async {}
    func writeWeight(_ kilograms: Double, date: Date) async {}
    func replaceWeight(old: (kilograms: Double, date: Date), new: (kilograms: Double, date: Date)) async {}
    @discardableResult
    func deleteWeight(_ kilograms: Double, date: Date) async -> Bool { false }
    #endif
}

/// One weigh-in read from Apple Health (shown and used live, never stored).
struct HealthWeightSample: Equatable, Sendable {
    let date: Date
    let kilograms: Double
}

/// What this device already wrote to Health: entry id → version. Device-only file in Application
/// Support (never synced, never in iCloud).
struct HealthLedger: Codable {
    var versions: [String: Int] = [:]
    /// Weigh-ins this device made sure Health has (optional, so older ledger files still load).
    var weights: [String: HealthWeightSync.Mark]?

    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppInfo.name, isDirectory: true)
            .appendingPathComponent("health-ledger.json")
    }

    static func load() -> HealthLedger {
        guard let url, let data = try? Data(contentsOf: url), let ledger = try? JSONDecoder().decode(HealthLedger.self, from: data) else {
            return HealthLedger()
        }
        return ledger
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Forgets entries older than the sync window (they stay in Health).
    mutating func prune(keeping ids: Set<String>) {
        versions = versions.filter { ids.contains($0.key) }
    }
}
