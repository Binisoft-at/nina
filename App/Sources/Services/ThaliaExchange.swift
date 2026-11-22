#if !os(watchOS)
import Foundation
import CoreData
import SwiftData
import Observation
import BinisoftKit
import NinaCore
#if os(macOS)
import Security
#endif

// Nina → Thalia (Binisoft exchange, format v1; docs/THALIA.md). On each iPhone, iPad and Mac, Nina
// writes the day's calories, protein, carbs, fat and water from its synced store into the shared App
// Group: `<group>/Nina/exchange/source.json` and `days/<YYYY-MM-DD>.json` (NinaCore: `ThaliaFeed`,
// `ThaliaExchangeWriter`). Thalia reads them when it opens on the same device. Never on the watch,
// never from the demo, the tour's practice store, previews, tests or an in-memory store; on the Mac
// only when the signed app really has the App Group. Never an error on screen – the app log only.

/// The App Group side of the exchange: Nina's folder, Thalia's catalog, the change notification.
enum ThaliaExchange {
    /// `<group>/Nina` – nil without the App Group (unsigned builds), and on the Mac when the signed
    /// app doesn't have it (macOS would ask for access to other apps' data instead). Checked once
    /// per launch; call it off the main thread, never during launch.
    static func appFolder() -> URL? {
        groupRoot()?.appendingPathComponent(ThaliaFeed.folderName, isDirectory: true)
    }

    /// The App Group's folder (checked once, then remembered).
    static func groupRoot() -> URL? {
        check.value {
            guard let group = AppIdentifiers.main.sharedAppGroup else {
                AppLog.notice("Thalia: this build has no App Group, nothing is written", category: "thalia")
                return nil
            }
            #if os(macOS)
            guard hasAppGroupEntitlement(group) else {
                AppLog.notice("Thalia: the signed app doesn't have \(group), nothing is written", category: "thalia")
                return nil
            }
            #endif
            guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                AppLog.notice("Thalia: no App Group folder on this device, nothing is written", category: "thalia")
                return nil
            }
            return root
        }
    }

    /// Thalia's catalog on this device (goals, categories, measures – structure only), read
    /// tolerantly. Nina doesn't use it (no category choice); nil when Thalia hasn't written one.
    static func catalog() -> ExchangeCatalog? {
        guard let root = groupRoot() else { return nil }
        return ThaliaFeed.catalog(try? Data(contentsOf: ThaliaFeed.catalogURL(groupRoot: root)))
    }

    /// Tells Thalia that files changed: the Darwin notification `at.binisoft.exchange.changed`.
    static func postChanged() {
        #if os(iOS) || os(macOS)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(BinisoftExchange.changedNotification as CFString), nil, nil, true)
        #endif
    }

    #if os(macOS)
    /// Whether the signed app has `group` among its App Groups. Call it off the main thread.
    static func hasAppGroupEntitlement(_ group: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        guard let groups = value as? [String] else { return false }
        return groups.contains(group)
    }
    #endif

    private static let check = GroupCheck()
}

/// The App Group check, made once per process (any thread).
private final class GroupCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var root: URL?

    func value(_ make: () -> URL?) -> URL? {
        lock.lock()
        if done {
            defer { lock.unlock() }
            return root
        }
        lock.unlock()
        let made = make()
        lock.lock()
        defer { lock.unlock() }
        if !done {
            root = made
            done = true
        }
        return root
    }
}

/// Runs Nina's passes for Thalia. Each pass reads the last 62 days from the store on the main actor
/// into plain values and does everything else off the main thread: the day values, the changed day
/// files, `source.json`, the Darwin notification. Triggers: every own save (`.ninaDataChanged`,
/// after 2 s of quiet), the end of the own CloudKit import, coming to the foreground
/// (`becameActive`), the day change, and the switch. The switch "Send to Thalia" and the time of the
/// last write are per device (UserDefaults). Off: one pass without values empties the day files of
/// the window, then nothing is written until it is on again.
@MainActor
@Observable
final class ThaliaDelivery {
    /// "Send to Thalia" on this device (default on).
    static let deliverKey = "nina.thalia.deliver"
    /// When a pass last wrote a file on this device.
    static let lastWrittenKey = "nina.thalia.lastWritten"
    /// Off and the day files emptied: nothing to do until it is on again.
    static let clearedKey = "nina.thalia.cleared"
    /// Quiet time after a trigger (saves come in bursts).
    nonisolated static let debounce: Duration = .seconds(2)
    /// The first pass waits longer, so it never slows the launch.
    nonisolated static let firstDelay: Duration = .seconds(5)

    /// SwiftUI previews and test runs never write.
    nonisolated static var isPreviewOrTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Whether this model may write at all: the real store, not the demo, the tour, a preview or a test.
    let canWrite: Bool
    /// "Send to Thalia" on this device.
    private(set) var isOn: Bool
    /// When a pass last wrote a day file or `source.json` on this device.
    private(set) var lastWritten: Date?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var hasRun = false

    /// `canWrite` false (demo, tour, previews): the switch works on screen only and nothing is
    /// read from or written to the device.
    init(container: ModelContainer, canWrite: Bool, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        self.canWrite = canWrite && !ThaliaDelivery.isPreviewOrTest
            && !container.configurations.contains { $0.isStoredInMemoryOnly }
        isOn = self.canWrite ? (defaults.object(forKey: ThaliaDelivery.deliverKey) as? Bool ?? true) : true
        lastWritten = self.canWrite ? defaults.object(forKey: ThaliaDelivery.lastWrittenKey) as? Date : nil
    }

    /// The line under the switch.
    var statusText: String {
        guard isOn else { return "Off on this device" }
        guard let lastWritten else { return "Not written yet" }
        return "Last written: \(lastWritten.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Starts listening (own saves, the CloudKit import, the day change); the first pass follows a
    /// few seconds after launch.
    func start() {
        guard canWrite, !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .ninaDataChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.passSoon() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.passSoon() }
        })
        // Changes from the other devices: right after the own CloudKit import ends.
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event, event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated { self?.passSoon() }
        })
        passSoon(after: ThaliaDelivery.firstDelay)
    }

    /// The app came to the foreground.
    func becameActive() {
        passSoon()
    }

    /// The switch: on writes everything at once, off empties the day files once.
    func setDeliver(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        guard canWrite else { return }
        defaults.set(on, forKey: ThaliaDelivery.deliverKey)
        defaults.set(false, forKey: ThaliaDelivery.clearedKey)
        AppLog.info(on ? "Thalia: sending on" : "Thalia: sending off, emptying the day files", category: "thalia")
        pending?.cancel()
        runPass()
    }

    /// A pass after `after` of quiet (a newer trigger starts the wait again).
    func passSoon(after delay: Duration = ThaliaDelivery.debounce) {
        guard canWrite, hasWork else { return }
        let wait = hasRun ? delay : max(delay, ThaliaDelivery.firstDelay)
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.runPass()
        }
    }

    /// On, or off with the day files not emptied yet.
    private var hasWork: Bool {
        isOn || !defaults.bool(forKey: ThaliaDelivery.clearedKey)
    }

    /// Reads the window from the store now, then writes off the main thread. A trigger meanwhile
    /// runs another pass afterwards.
    private func runPass() {
        guard canWrite, hasWork else { return }
        guard !running else {
            again = true
            return
        }
        running = true
        hasRun = true
        let deliver = isOn
        let now = Date()
        let timeZone = TimeZone.current
        let today = ExchangeDate.day(now, timeZone: timeZone)
        let records = deliver ? self.records(today: today) : ([], [])
        let appVersion = AppVersion.main.marketing
        Task.detached(priority: .utility) { [weak self] in
            let result = ThaliaDelivery.write(food: records.0, water: records.1, deliver: deliver, appVersion: appVersion,
                                              today: today, now: now, timeZone: timeZone)
            await self?.finish(result, deliver: deliver, now: now)
        }
    }

    private func finish(_ result: WriteResult, deliver: Bool, now: Date) {
        running = false
        if result == .written {
            lastWritten = now
            defaults.set(now, forKey: ThaliaDelivery.lastWrittenKey)
        }
        // Off, and the day files are empty now: nothing more until it is on again.
        if !deliver, !isOn, result == .written || result == .unchanged {
            defaults.set(true, forKey: ThaliaDelivery.clearedKey)
        }
        if again {
            again = false
            passSoon()
        }
    }

    /// The last 62 days of diary entries and water logs as plain values (Nina's synced store).
    private func records(today: String) -> ([ThaliaFeed.FoodRecord], [ThaliaFeed.WaterRecord]) {
        guard let last = DayKey(today), let start = BinisoftExchange.day(today, adding: -BinisoftExchange.keepDays),
              let first = DayKey(start) else { return ([], []) }
        let store = NinaStore(context: container.mainContext)
        let food = store.entries(from: first, through: last).map { entry in
            let values = entry.values
            return ThaliaFeed.FoodRecord(id: entry.uuid.uuidString, day: entry.dayKey.rawValue, time: entry.time,
                                         energy: values.energy, protein: values.protein, carbs: values.carbs, fat: values.fat,
                                         isEaten: entry.entryStatus == .eaten, isDeleted: entry.deletedAt != nil,
                                         isFromHealth: ThaliaFeed.isHealthSource(entry.source))
        }
        // Today's water card: the sum of the day's water logs.
        let water = store.water(from: first, through: last).map { log in
            ThaliaFeed.WaterRecord(id: log.uuid.uuidString, day: log.dayKey.rawValue, time: log.time, milliliters: log.amount,
                                   isDeleted: log.deletedAt != nil)
        }
        return (food, water)
    }

    enum WriteResult: Equatable, Sendable {
        case written, unchanged, noFolder, failed
    }

    /// One pass's file work (off the main thread): the day files (empty ones when `deliver` is off),
    /// `source.json` while it is on, then the Darwin notification once if anything was written.
    nonisolated static func write(food: [ThaliaFeed.FoodRecord], water: [ThaliaFeed.WaterRecord], deliver: Bool,
                                  appVersion: String, today: String, now: Date, timeZone: TimeZone) -> WriteResult {
        guard let folder = ThaliaExchange.appFolder() else { return .noFolder }
        let facts = deliver ? ThaliaFeed.facts(food: food, water: water, today: today, timeZone: timeZone) : [:]
        var changed = false
        var failed = false
        do {
            changed = try ThaliaExchangeWriter.sync(facts, source: ThaliaFeed.source, appFolder: folder, today: today, now: now,
                                                    timeZone: timeZone)
        } catch {
            failed = true
            AppLog.warning("Thalia: day files not written: \(error.localizedDescription)", category: "thalia")
        }
        if deliver {
            do {
                let info = ThaliaFeed.sourceInfo(appVersion: appVersion, now: now, timeZone: timeZone)
                if try ThaliaExchangeWriter.syncSource(info, appFolder: folder, today: today, timeZone: timeZone) { changed = true }
            } catch {
                failed = true
                AppLog.warning("Thalia: source.json not written: \(error.localizedDescription)", category: "thalia")
            }
        }
        guard changed else { return failed ? .failed : .unchanged }
        ThaliaExchange.postChanged()
        AppLog.debug(deliver ? "Thalia: day values updated" : "Thalia: day values emptied", category: "thalia")
        return .written
    }
}
#endif
