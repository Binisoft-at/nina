import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// The automatic weekly backup (Import & Export → Automatic Backup). A device-only switch – on by
// default on iPhone, off on iPad and Mac – saves a Back Up Everything folder at most once every
// 7 days, in the background shortly after Nina opens: AppModel calls `runIfDue` after the
// launch's first iCloud sync (or a while without one) and whenever the app comes back. It goes to
// Nina's own folder (iPhone/iPad: Files → On My iPhone → Nina; Mac: Nina's container) or to a
// folder the person chose (kept with a security-scoped bookmark; when it can't be opened the
// backup goes to Nina's own folder and the status says so). The last 4 automatic backups in a
// folder stay, older ones are removed – only folders this device's automatic backup made.
// When it is due, names and what to remove: BackupSchedule in NinaCore. Never in the demo, the
// tour's practice page or a store that isn't saved.

/// The switch, the device-only state and the runs. One per app (`shared`).
@MainActor
@Observable
final class ImportAutoBackup {
    static let shared = ImportAutoBackup()

    /// Device-only: the switch. Missing: on for iPhone, off for iPad and Mac.
    static let enabledKey = "nina.backup.auto"
    /// Device-only: `BackupAutoState` as JSON (the chosen folder's bookmark, what was made).
    static let stateKey = "nina.backup.autoState"

    private(set) var isOn: Bool
    private(set) var state: BackupAutoState
    /// A backup is being written (the section shows "Backing up…").
    private(set) var isRunning = false
    /// A due backup waiting for the app to settle after it opened.
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// A folder was chosen while a backup was being written: one more there right after.
    @ObservationIgnored private var runAgain = false

    private init() {
        let defaults = UserDefaults.standard
        isOn = defaults.object(forKey: Self.enabledKey) as? Bool ?? BackupSchedule.isOnByDefault(isPhone: PlatformInfo.isPhone)
        state = BackupAutoState.decode(defaults.data(forKey: Self.stateKey))
    }

    // MARK: Running

    /// Starts a backup in the background when one is due – after a short wait, so the app's
    /// launch and its first sync go first. Cheap when nothing is due.
    func runIfDue(app: AppModel) {
        guard isOn, !isRunning, waiting == nil, Self.canRun(app), BackupSchedule.isDue(state, now: Date()) else { return }
        waiting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.waiting = nil
            // Still wanted after the wait (switched off, or made meanwhile)?
            guard self.isOn, !self.isRunning, BackupSchedule.isDue(self.state, now: Date()) else { return }
            self.isRunning = true
            await self.run(app: app, announce: false)
            self.finishRun(app: app)
        }
    }

    /// "Back Up Now" (and right after a folder was chosen): now, with a toast when it is done.
    /// While one is being written, the next follows right after it (a folder chosen meanwhile).
    func runNow(app: AppModel) {
        guard Self.canRun(app) else { return }
        guard !isRunning else {
            runAgain = true
            return
        }
        waiting?.cancel()
        waiting = nil
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(app: app, announce: true)
            self.finishRun(app: app)
        }
    }

    private func finishRun(app: AppModel) {
        isRunning = false
        guard runAgain else { return }
        runAgain = false
        runNow(app: app)
    }

    private func run(app: AppModel, announce: Bool) async {
        // What was just changed counts too: the backup reads the saved store on a context of its own.
        let context = app.store.context
        if context.hasChanges { try? context.save() }
        let now = Date()
        let job = ImportAutoBackupJob(container: app.container, folder: state.folder, made: state.made, day: app.today,
                                      includePhotos: Self.includesPhotos, appVersion: ImportBackupFiles.appVersion,
                                      device: ImportBackupFiles.device, now: now)
        let time = ImportBackgroundTime()
        time.begin()
        let outcome = await Task.detached(priority: announce ? .userInitiated : .utility) { job.run() }.value
        time.end()
        record(outcome, now: now, app: app, announce: announce)
    }

    private func record(_ outcome: ImportAutoBackupJob.Outcome, now: Date, app: AppModel, announce: Bool) {
        switch outcome {
        case .nothingToBackUp:
            state.skipped(at: now)
            AppLog.info("Automatic backup: nothing to back up yet", category: "backup")
            if announce { app.toasts.show("Nothing to back up yet", symbol: "externaldrive") }
        case .written(let backup, let usedFallback, let removed, let bookmark):
            state.succeeded(backup, usedFallback: usedFallback)
            state.forget(removed)
            if let bookmark, var folder = state.folder, folder.id == backup.place {
                folder.bookmark = bookmark
                state.folder = folder
            }
            AppLog.info("Automatic backup saved: \(backup.records) records\(usedFallback ? " (in Nina's own folder)" : ""), "
                        + "\(removed.count) old removed", category: "backup")
            if announce { app.toasts.show("Backup saved: \(backup.name)", symbol: "externaldrive.fill") }
        case .failed(let problem, let detail):
            AppLog.warning("Automatic backup failed: \(detail)", category: "backup")
            let notice = state.failed(problem, at: now)
            if announce {
                app.toasts.show("The backup didn't work – \(problem.text)", symbol: "exclamationmark.triangle.fill")
            } else if notice {
                app.toasts.show("The weekly backup didn't work – Settings → Import & Export says why",
                                symbol: "exclamationmark.triangle.fill")
            }
        }
        save()
    }

    // MARK: Settings

    func setOn(_ on: Bool, app: AppModel) {
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        AppLog.info("Automatic backup \(on ? "on" : "off")", category: "backup")
        if on { runIfDue(app: app) }
    }

    /// "Choose Folder…": keeps a bookmark to the folder and makes a backup there right away, so
    /// the person sees that it works. Returns what went wrong, in plain words.
    func choose(_ url: URL, app: AppModel) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard ImportAutoBackupJob.isFolder(url) else { return "Choose a folder for the backups." }
        do {
            let bookmark = try ImportAutoBackupJob.bookmark(for: url)
            let path = url.standardizedFileURL.path(percentEncoded: false)
            state.choose(BackupAutoState.Folder(id: path, title: BackupSchedule.placeTitle(path: path), bookmark: bookmark))
            save()
            AppLog.info("Automatic backup folder chosen", category: "backup")
            if isOn { runNow(app: app) }
            return nil
        } catch {
            AppLog.warning("Automatic backup folder not usable: \(ImportAutoBackupJob.describe(error))", category: "backup")
            return "Nina can't keep access to this folder. Choose another one, or use Nina's own folder."
        }
    }

    /// Back to Nina's own folder (the backups in the chosen folder stay there).
    func useOwnFolder() {
        state.choose(nil)
        save()
    }

    /// Where the backups go: the chosen folder, or Nina's own.
    var placeTitle: String { state.folder?.title ?? Self.ownFolderTitle }

    /// Nina's own folder, as the person finds it.
    static var ownFolderTitle: String {
        #if os(macOS)
        "\(AppInfo.name)'s own folder on this Mac"
        #else
        PlatformInfo.isPhone ? "On My iPhone → \(AppInfo.name)" : "On My iPad → \(AppInfo.name)"
        #endif
    }

    #if os(macOS)
    /// Shows the newest automatic backup (or the folder) in the Finder.
    func revealInFinder() {
        let newest = state.made.last { $0.place == state.place }
        if let folder = state.folder, let opened = ImportAutoBackupJob.open(folder) {
            defer { if opened.started { opened.url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.activateFileViewerSelecting([Self.item(newest, in: opened.url)])
        } else if let own = ImportAutoBackupJob.ownFolder() {
            NSWorkspace.shared.activateFileViewerSelecting([Self.item(state.folder == nil ? newest : nil, in: own)])
        }
    }

    private static func item(_ backup: BackupAutoState.Made?, in folder: URL) -> URL {
        guard let backup else { return folder }
        let url = folder.appendingPathComponent(backup.name, isDirectory: true)
        return ImportAutoBackupJob.isFolder(url) ? url : folder
    }
    #endif

    // MARK: Helpers

    /// The photos follow Back Up Everything's switch (on unless switched off), but stay out while
    /// Lock Photos is on: the folder in Files or the Finder would show them without Face ID.
    private static var includesPhotos: Bool {
        let defaults = UserDefaults.standard
        let wanted = defaults.object(forKey: ImportBackupFiles.photosKey) as? Bool ?? true
        return wanted && !defaults.bool(forKey: BodyPhotoLock.key)
    }

    /// Only for the real, saved store: never the demo, the practice page or an in-memory store.
    private static func canRun(_ app: AppModel) -> Bool {
        guard !app.isSandbox, !app.launch.isDemo else { return false }
        switch app.mode {
        case .iCloud, .local: return true
        case .memory, .demo: return false
        }
    }

    private func save() {
        UserDefaults.standard.set(state.encoded(), forKey: Self.stateKey)
    }
}

/// One automatic backup, off the main thread: finds the folder, writes the backup into a
/// temporary folder with Back Up Everything's writer, moves it in, then removes old ones.
struct ImportAutoBackupJob {
    let container: ModelContainer
    let folder: BackupAutoState.Folder?
    let made: [BackupAutoState.Made]
    let day: DayKey
    let includePhotos: Bool
    let appVersion: String
    let device: String
    let now: Date

    enum Outcome: Sendable {
        /// A new, empty Nina (or one still waiting for iCloud): nothing written.
        case nothingToBackUp
        /// `removed`: old automatic backups that are gone now (or are no longer this device's to
        /// remove). `bookmark`: a fresh one for the chosen folder, when the stored one was stale.
        case written(BackupAutoState.Made, usedFallback: Bool, removed: [BackupAutoState.Made], bookmark: Data?)
        /// What went wrong, and the error for the app log (no paths).
        case failed(BackupAutoState.Problem, String)
    }

    func run() -> Outcome {
        let destination: URL
        var place = BackupAutoState.appFolder
        var usedFallback = false
        var bookmark: Data?
        var access: URL?
        if let folder, let opened = Self.open(folder) {
            destination = opened.url
            place = folder.id
            bookmark = opened.bookmark
            if opened.started { access = opened.url }
        } else if let own = Self.ownFolder() {
            destination = own
            usedFallback = folder != nil
        } else {
            return .failed(.folder, "no folder to write to")
        }
        defer { access?.stopAccessingSecurityScopedResource() }

        let writer = NinaBackupWriter(context: ModelContext(container))
        let records = writer.records()
        guard BackupSchedule.hasData(NinaBackup.counts(records)) else { return .nothingToBackUp }

        let files = FileManager.default
        let existing = (try? files.contentsOfDirectory(atPath: destination.path(percentEncoded: false))) ?? []
        let name = BackupSchedule.folderName(app: AppInfo.name, day: day, existing: existing)
        let temporary = files.temporaryDirectory.appendingPathComponent("NinaBackup-" + UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: temporary) }
        let manifest: NinaBackup.Manifest
        do {
            let written = temporary.appendingPathComponent(name, isDirectory: true)
            manifest = try writer.write(to: written, records: records, includePhotos: includePhotos, appVersion: appVersion,
                                        device: device, now: now)
            try Self.move(written, to: destination.appendingPathComponent(name, isDirectory: true))
        } catch {
            return .failed(Self.problem(error), Self.describe(error))
        }

        let backup = BackupAutoState.Made(name: name, place: place, created: now, records: manifest.total)
        var removed: [BackupAutoState.Made] = []
        for old in BackupSchedule.removals(made + [backup], in: place) where old.name != name {
            let url = destination.appendingPathComponent(old.name, isDirectory: true)
            // A folder of that name that isn't the automatic backup any more stays; the list forgets it.
            if !BackupSchedule.isSameBackup(old, manifestData: Self.manifestData(in: url)) || Self.remove(url) {
                removed.append(old)
            }
        }
        return .written(backup, usedFallback: usedFallback, removed: removed, bookmark: bookmark)
    }

    // MARK: Folders

    /// Nina's own folder: Documents (iPhone/iPad: Files → On My iPhone → Nina; Mac: the container).
    static func ownFolder() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    /// iPhone/iPad: the Files app at Nina's own folder.
    static func filesAppLink() -> URL? {
        guard let folder = ownFolder() else { return nil }
        return URL(string: "shareddocuments://" + folder.path(percentEncoded: true))
    }

    /// The chosen folder with its access started when `started` (the caller stops it), and a
    /// fresh bookmark when the stored one is stale. nil when it can't be opened (deleted, on a
    /// drive that isn't connected, access gone).
    static func open(_ folder: BackupAutoState.Folder) -> (url: URL, started: Bool, bookmark: Data?)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: resolutionOptions, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        guard isFolder(url) else {
            if started { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        let fresh: Data? = stale ? (try? bookmark(for: url)) : nil
        return (url, started, fresh)
    }

    /// A bookmark that opens the folder again after a relaunch (call with its access started).
    static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope, .withoutUI]
        #else
        [.withoutUI]
        #endif
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Moves the finished backup in, coordinated (a folder in iCloud Drive or another provider).
    static func move(_ source: URL, to target: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { actual in
            do {
                try FileManager.default.moveItem(at: source, to: actual)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    /// A backup folder's manifest.json, when it is there to read.
    static func manifestData(in folder: URL) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(NinaBackup.manifestName))
    }

    /// Removes an old automatic backup; true when it is gone (also when it already was).
    static func remove(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return true }
        var removed = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { actual in
            removed = (try? FileManager.default.removeItem(at: actual)) != nil
        }
        return removed
    }

    // MARK: Errors

    /// A full device, or anything else.
    static func problem(_ error: Error) -> BackupAutoState.Problem {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSCocoaErrorDomain, error.code == CocoaError.Code.fileWriteOutOfSpace.rawValue { return .space }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return .space }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return .write
    }

    /// "NSCocoaErrorDomain 640" – for the app log, without file paths.
    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

/// iPhone/iPad: a little time to finish when Nina goes to the background during a backup.
@MainActor
private final class ImportBackgroundTime {
    #if os(iOS)
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    func begin() {
        #if os(iOS)
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Nina Backup") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        #endif
    }

    func end() {
        #if os(iOS)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}

/// Import & Export → Automatic Backup: the weekly switch, where the backups go, the status and
/// Back Up Now.
struct ImportAutoBackupSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    /// Opens the folder picker (ImportView's file importer).
    let onChooseFolder: () -> Void
    /// What went wrong choosing a folder.
    let problem: String?

    private var auto: ImportAutoBackup { ImportAutoBackup.shared }

    var body: some View {
        Section {
            Toggle("Back Up Automatically Every Week", isOn: isOn)
            if auto.isOn { details }
        } header: {
            Text("Automatic Backup").info(ImportInfo.autoBackupTitle, ImportInfo.autoBackup)
        } footer: {
            Text(footer)
        }
    }

    private var isOn: Binding<Bool> {
        Binding(get: { auto.isOn }, set: { auto.setOn($0, app: app) })
    }

    @ViewBuilder
    private var details: some View {
        LabeledContent("Saves To", value: auto.placeTitle)
        Button("Choose Folder…", systemImage: "folder.badge.plus", action: onChooseFolder)
            .disabled(auto.isRunning)
        if auto.state.folder != nil {
            Button("Use \(AppInfo.name)'s Own Folder", systemImage: "folder") { auto.useOwnFolder() }
                .disabled(auto.isRunning)
        }
        if let title = showTitle {
            Button(title, systemImage: "magnifyingglass") { show() }
        }
        if let problem {
            Text(problem).font(.callout).foregroundStyle(.orange)
        }
        Text(BackupSchedule.status(auto.state, now: Date()))
            .font(.callout)
            .foregroundStyle(auto.state.problem == nil ? Color.secondary : Color.orange)
        backUpNow
    }

    @ViewBuilder
    private var backUpNow: some View {
        if auto.isRunning {
            HStack {
                ProgressView()
                Text("Backing up…").foregroundStyle(.secondary)
            }
        } else {
            Button("Back Up Now", systemImage: "arrow.clockwise") { auto.runNow(app: app) }
        }
    }

    /// Mac: the Finder, for either folder. iPhone/iPad: the Files app, for Nina's own folder.
    private var showTitle: String? {
        #if os(macOS)
        return "Show in Finder"
        #else
        return auto.state.folder == nil ? "Show in Files" : nil
        #endif
    }

    private func show() {
        #if os(macOS)
        auto.revealInFinder()
        #else
        guard let url = ImportAutoBackupJob.filesAppLink() else { return }
        let model = app
        openURL(url) { accepted in
            Task { @MainActor in
                if !accepted { model.toasts.show("Open the Files app → \(ImportAutoBackup.ownFolderTitle)", symbol: "folder") }
            }
        }
        #endif
    }

    private var footer: String {
        #if os(macOS)
        return "Once a week, shortly after you open \(AppInfo.name), everything is saved like Back Up Everything (photos as set above). "
            + "The last 4 stay; older ones are removed. Locked photos are left out. "
            + "To bring one back, use Restore from Backup… and choose its folder. This switch is for this Mac only."
        #else
        let device = PlatformInfo.isPhone ? "iPhone" : "iPad"
        return "Once a week, shortly after you open \(AppInfo.name), everything is saved like Back Up Everything (photos as set above). "
            + "The last 4 stay; older ones are removed. Locked photos are left out. "
            + "Choose a folder in iCloud Drive to keep them safe even without this \(device). "
            + "To bring one back, use Restore from Backup… and choose its folder. This switch is for this \(device) only."
        #endif
    }
}
