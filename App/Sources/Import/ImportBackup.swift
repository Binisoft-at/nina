import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

// "Back Up Everything" and "Restore from Backup" in Import & Export. The format and the restore
// planning are in NinaCore (NinaBackup, BackupRestorePlan), the models in NinaStore+Backup.

/// A backup folder read for restoring: its manifest and records (the photos are read when they
/// are restored).
struct ImportBackupFolder: Sendable {
    let url: URL
    let manifest: NinaBackup.Manifest
    let records: [BackupRecord]
    /// Lines of records.jsonl that couldn't be read.
    let unreadable: Int

    var name: String { url.lastPathComponent }

    /// Reads manifest.json and records.jsonl (a folder in iCloud Drive is downloaded first).
    init(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let manifestData = try? Self.read(url.appendingPathComponent(NinaBackup.manifestName)) else {
            throw NinaBackup.ReadError.notABackup
        }
        manifest = try NinaBackup.decodeManifest(manifestData)
        guard let data = try? Self.read(url.appendingPathComponent(NinaBackup.recordsName)) else {
            throw NinaBackup.ReadError.unreadable
        }
        let decoded = NinaBackup.decode(data)
        records = decoded.records
        unreadable = decoded.unreadable
        self.url = url
    }

    /// A photo's JPEGs, by its uuid (never a path from the file). Call within the folder's
    /// security scope.
    func photo(_ record: BackupRecord) -> (image: Data?, thumbnail: Data?) {
        let image = try? Self.read(url.appendingPathComponent(NinaBackup.photoPath(record.uuid)))
        let thumbnail = try? Self.read(url.appendingPathComponent(NinaBackup.photoPath(record.uuid, thumbnail: true)))
        return (image, thumbnail)
    }

    /// A coordinated read, so a file that is only in iCloud Drive is downloaded first.
    static func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in
            result = Result { try Data(contentsOf: actual) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

/// A backup chosen for restoring, with what restoring it would do.
struct ImportRestore {
    let folder: ImportBackupFolder
    let plan: BackupRestorePlan
}

/// Writing a backup and remembering when this device last made one.
enum ImportBackupFiles {
    /// Device-only: when this device last saved a backup (seconds since 1970).
    static let lastKey = "nina.backup.last"
    static let photosKey = "nina.backup.includePhotos"

    /// Writes a backup into a new temporary folder named "Nina Backup 2030-01-07" and returns it
    /// (the file mover then moves it where the person wants it). Read and written off the main
    /// thread, on a context of its own, so the app stays responsive with many photos.
    @MainActor
    static func write(app: AppModel, includePhotos: Bool) async throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("NinaBackup-" + UUID().uuidString, isDirectory: true)
        let folder = parent.appendingPathComponent(NinaBackup.folderName(app: AppInfo.name, day: app.today), isDirectory: true)
        // What was just changed counts too: the backup reads the saved store.
        let context = app.store.context
        if context.hasChanges { try? context.save() }
        let container = app.container
        let version = appVersion
        let deviceName = device
        _ = try await Task.detached(priority: .userInitiated) {
            try NinaBackupWriter(context: ModelContext(container)).write(to: folder, includePhotos: includePhotos, appVersion: version,
                                                                         device: deviceName)
        }.value
        return folder
    }

    /// Removes what is left of a temporary backup folder (after it was moved, or not).
    static func cleanUp(_ folder: URL?) {
        guard let parent = folder?.deletingLastPathComponent(), parent.lastPathComponent.hasPrefix("NinaBackup-") else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    @MainActor
    static var device: String {
        PlatformInfo.isMac ? "Mac" : (PlatformInfo.isPhone ? "iPhone" : "iPad")
    }

    /// "Last backup from this device: 12 days ago."
    static func lastBackupText(_ seconds: Double, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard seconds > 0 else { return "No backup from this device yet." }
        let then = calendar.startOfDay(for: Date(timeIntervalSince1970: seconds))
        let days = calendar.dateComponents([.day], from: then, to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Last backup from this device: today."
        case 1: return "Last backup from this device: yesterday."
        default: return "Last backup from this device: \(days) days ago."
        }
    }
}

/// Back Up Everything, the photos switch and Restore from Backup.
struct ImportBackupSection: View {
    @Binding var includePhotos: Bool
    let lastBackup: Double
    let isWorking: Bool
    let problem: String?
    let onBackUp: () -> Void
    let onRestore: () -> Void

    var body: some View {
        Section {
            Button(action: onBackUp) {
                Label("Back Up Everything…", systemImage: "externaldrive")
            }
            .disabled(isWorking)
            Toggle("Include Progress Photos", isOn: $includePhotos)
            Button(action: onRestore) {
                Label("Restore from Backup…", systemImage: "clock.arrow.circlepath")
            }
            .disabled(isWorking)
            if isWorking {
                HStack {
                    ProgressView()
                    Text("Working…").foregroundStyle(.secondary)
                }
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
        } header: {
            Text("Back Up & Restore")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        "One folder with everything Nina keeps in iCloud – diary, foods, meals & recipes, water, weigh-ins, measurements, "
            + "day types, checks and check-ins, routines, goals & plan, progress photos and Recently Deleted – to keep in Files, "
            + "iCloud Drive or on a Mac. iCloud sync isn't a backup: a deletion reaches every device. Apple Health data isn't "
            + "in it. Restoring adds only what is missing. " + ImportBackupFiles.lastBackupText(lastBackup)
    }
}

/// What restoring a chosen backup would do, with the switch for the goals & plan and Restore.
struct ImportRestoreSection: View {
    let restore: ImportRestore
    @Binding var useBackupProfile: Bool
    let onRestore: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Section {
            Text(restore.plan.summary).font(.headline)
            Text(madeText).font(.caption).foregroundStyle(.secondary)
            ForEach(restore.plan.lines) { line in
                ImportRestoreLine(line: line)
            }
            if restore.plan.profileState == .differs {
                Toggle(isOn: $useBackupProfile) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use the Backup's Goals & Plan")
                        Text("Yours differ from the backup's. Off: yours stay as they are.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.orange)
            }
            Button("Restore", action: onRestore)
                .primaryActionStyle()
                .disabled(!canRestore)
            Button("Cancel", role: .cancel, action: onCancel)
        } header: {
            Text("Restore · \(restore.folder.name)")
        } footer: {
            Text("Nothing Nina has is changed or deleted: only what is missing is added, with its original dates. One Undo takes it back.")
        }
    }

    private var canRestore: Bool {
        restore.plan.hasChanges || (restore.plan.profileState == .differs && useBackupProfile)
    }

    /// "Made 7 Jan 2030 at 08:00 on iPhone · Nina 1.2.0".
    private var madeText: String {
        let manifest = restore.folder.manifest
        var text = "Made \(manifest.created.formatted(date: .abbreviated, time: .shortened)) on \(manifest.device)"
        if !manifest.appVersion.isEmpty { text += " · \(manifest.app) \(manifest.appVersion)" }
        return text
    }

    private var notes: [String] {
        var notes: [String] = []
        if !restore.plan.unknownTypes.isEmpty {
            notes.append("Some records come from a newer version of Nina and are left out. Update Nina to restore them too.")
        }
        let unreadable = restore.folder.unreadable
        if unreadable > 0 {
            notes.append(unreadable == 1 ? "1 line of the backup couldn't be read and is left out."
                                         : "\(unreadable) lines of the backup couldn't be read and are left out.")
        }
        if restore.folder.manifest.counts[BackupType.photo.rawValue] == nil {
            notes.append("This backup has no progress photos.")
        }
        return notes
    }
}

private struct ImportRestoreLine: View {
    let line: BackupRestorePlan.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(line.type.title)
            Text(line.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
