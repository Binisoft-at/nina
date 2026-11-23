import Foundation

// Automatic weekly backups (Import & Export → Automatic Backup). The app writes each one with the
// Back Up Everything code (a "Nina Backup 2030-01-07" folder, see Backup.swift) into Nina's own
// folder or a folder the person chose, at most once every 7 days, in the background after the
// app opens. This file decides when one is due, what the next folder is called, which old ones go
// (the last 4 stay) and what the status line says. The state lives on the device only
// (UserDefaults): every device has its own switch and its own backups, nothing of it syncs.

/// What this device knows about its automatic backups. Device-only, stored as JSON; a value that
/// can't be read starts fresh (nothing is removed then: only backups listed here are ever removed).
public struct BackupAutoState: Equatable, Sendable {
    /// Where `Made.place` says a backup is when it went to Nina's own folder.
    public static let appFolder = "app"

    /// A backup folder this device's automatic backup made.
    public struct Made: Codable, Equatable, Sendable {
        /// The folder's name ("Nina Backup 2030-01-07").
        public var name: String
        /// `BackupAutoState.appFolder`, or the chosen folder's `Folder.id`.
        public var place: String
        public var created: Date
        /// Records in it (the manifest's total), for the rule that keeps a much fuller backup.
        public var records: Int

        public init(name: String, place: String, created: Date, records: Int) {
            self.name = name
            self.place = place
            self.created = created
            self.records = records
        }
    }

    /// The folder the person chose with "Choose Folder…".
    public struct Folder: Codable, Equatable, Sendable {
        /// Its path when it was chosen: the same folder chosen again keeps its backups' list.
        public var id: String
        /// How it is shown ("iCloud Drive → Nina", see `BackupSchedule.placeTitle(path:)`).
        public var title: String
        /// The security-scoped bookmark that opens it again after a relaunch.
        public var bookmark: Data

        public init(id: String, title: String, bookmark: Data) {
            self.id = id
            self.title = title
            self.bookmark = bookmark
        }
    }

    /// Why the latest try didn't work.
    public enum Problem: String, Codable, Sendable {
        /// Neither the chosen folder nor Nina's own folder could be opened.
        case folder
        /// The device is full.
        case space
        /// Anything else while writing.
        case write

        /// The end of "The latest try didn't work – …".
        public var text: String {
            switch self {
            case .folder: "the folder couldn't be opened. Choose it again, or use Nina's own folder"
            case .space: "there isn't enough free space on this device"
            case .write: "the backup couldn't be written"
            }
        }
    }

    public var lastSuccess: Date?
    /// The latest try, whatever came of it (a failed one waits `BackupSchedule.retryHours`).
    public var lastAttempt: Date?
    /// Set by a failed try, cleared by the next backup.
    public var problem: Problem?
    /// The latest backup went to Nina's own folder because the chosen folder couldn't be opened.
    public var usedFallback: Bool
    public var folder: Folder?
    /// The automatic backups this device made that may still be there, oldest first.
    public var made: [Made]
    /// The one calm notice about failing backups was shown (once per run of failures).
    public var noticeShown: Bool

    public init(lastSuccess: Date? = nil, lastAttempt: Date? = nil, problem: Problem? = nil, usedFallback: Bool = false,
                folder: Folder? = nil, made: [Made] = [], noticeShown: Bool = false) {
        self.lastSuccess = lastSuccess
        self.lastAttempt = lastAttempt
        self.problem = problem
        self.usedFallback = usedFallback
        self.folder = folder
        self.made = made
        self.noticeShown = noticeShown
    }

    /// Where the next backup goes: the chosen folder's id, or `appFolder`.
    public var place: String { folder?.id ?? Self.appFolder }

    // MARK: Recording what happened

    /// A backup was written (`made.place` says where; `usedFallback` when the chosen folder
    /// couldn't be opened and it went to Nina's own folder instead).
    public mutating func succeeded(_ backup: Made, usedFallback: Bool) {
        lastSuccess = backup.created
        lastAttempt = backup.created
        problem = nil
        self.usedFallback = usedFallback
        noticeShown = false
        made.removeAll { $0.place == backup.place && $0.name == backup.name }
        made.append(backup)
        made.sort { $0.created < $1.created }
    }

    /// A try didn't work. True when the calm notice should be shown now: the first failure of a
    /// run of failures, once there has been no backup for `BackupSchedule.noticeDays` (or never).
    public mutating func failed(_ problem: Problem, at now: Date, calendar: Calendar = .current) -> Bool {
        lastAttempt = now
        self.problem = problem
        guard !noticeShown else { return false }
        if let lastSuccess, BackupSchedule.days(from: lastSuccess, to: now, calendar: calendar) < BackupSchedule.noticeDays {
            return false
        }
        noticeShown = true
        return true
    }

    /// Nothing to back up yet (a new, empty Nina): tried, nothing written, no problem.
    public mutating func skipped(at now: Date) {
        lastAttempt = now
    }

    /// Old backups that were removed (or were already gone).
    public mutating func forget(_ removed: [Made]) {
        made.removeAll { backup in removed.contains { $0.place == backup.place && $0.name == backup.name } }
    }

    /// The person chose a folder (nil: back to Nina's own folder). Backups listed for a folder that
    /// is neither this one nor Nina's own are forgotten – they stay where they are, never removed.
    public mutating func choose(_ folder: Folder?) {
        self.folder = folder
        usedFallback = false
        if problem == .folder { problem = nil }
        let keep: Set<String> = [Self.appFolder, folder?.id ?? Self.appFolder]
        made.removeAll { !keep.contains($0.place) }
    }
}

/// When the automatic backup runs, how its folders are named and which old ones go.
public enum BackupSchedule {
    /// At most one automatic backup in this many days.
    public static let intervalDays = 7
    /// Automatic backups kept per folder (older ones are removed after a new one is written).
    public static let keep = 4
    /// After a try that didn't work (or found nothing to back up), the next one waits this long.
    public static let retryHours: Double = 6
    /// A failure shows the one calm notice only when there has been no backup for this long.
    public static let noticeDays = 14

    /// On by default on iPhone; off on iPad and Mac (they usually have the same data).
    public static func isOnByDefault(isPhone: Bool) -> Bool { isPhone }

    /// Whole days between two moments, by the calendar (midnight to midnight).
    public static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// Due when there has never been a backup, or the latest one is 7 or more calendar days old,
    /// and no try in the last 6 hours. A latest backup more than a day in the future (the clock
    /// was set back) counts as old, and so does a try in the future.
    public static func isDue(_ state: BackupAutoState, now: Date, calendar: Calendar = .current) -> Bool {
        if let attempt = state.lastAttempt, attempt <= now, now.timeIntervalSince(attempt) < retryHours * 3600 { return false }
        guard let last = state.lastSuccess else { return true }
        if last > now.addingTimeInterval(86_400) { return true }
        return days(from: last, to: now, calendar: calendar) >= intervalDays
    }

    /// Days until the next backup is due (0: due now); nil before the first one.
    public static func daysUntilNext(_ state: BackupAutoState, now: Date, calendar: Calendar = .current) -> Int? {
        guard let last = state.lastSuccess else { return nil }
        if last > now.addingTimeInterval(86_400) { return 0 }
        return max(0, intervalDays - days(from: last, to: now, calendar: calendar))
    }

    /// Whether a backup has anything in it: some record besides the goals & plan. A new, empty
    /// Nina (or one still waiting for iCloud) writes nothing.
    public static func hasData(_ counts: [String: Int]) -> Bool {
        counts.contains { $0.key != BackupType.profile.rawValue && $0.value > 0 }
    }

    // MARK: Folder names

    /// "Nina Backup 2030-01-07", or "Nina Backup 2030-01-07 (2)" … when a folder of that name is
    /// already there (compared without case, like the file systems).
    public static func folderName(app: String, day: DayKey, existing: [String]) -> String {
        let taken = Set(existing.map { listedName($0).lowercased() })
        let base = NinaBackup.folderName(app: app, day: day)
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) (\(number))".lowercased()) { number += 1 }
        return "\(base) (\(number))"
    }

    /// A name as a folder listing gives it: iCloud Drive lists something it hasn't downloaded yet
    /// as ".Name.icloud".
    public static func listedName(_ name: String) -> String {
        let suffix = ".icloud"
        guard name.hasPrefix("."), name.hasSuffix(suffix), name.count > suffix.count + 1 else { return name }
        return String(name.dropFirst().dropLast(suffix.count))
    }

    // MARK: Keeping the last 4

    /// The automatic backups in `place` to remove after a new one was written: all but the newest
    /// `keep`. One exception keeps data safe when a lot went missing (a mass deletion, an emptied
    /// iCloud): a backup with more than twice the records of every kept one stays – the fullest
    /// of them – until newer backups are about as full again.
    public static func removals(_ made: [BackupAutoState.Made], in place: String, keep: Int = keep) -> [BackupAutoState.Made] {
        let here = made.filter { $0.place == place }.sorted { $0.created < $1.created }
        guard keep > 0, here.count > keep else { return [] }
        var remove = Array(here.dropLast(keep))
        let fullestKept = here.suffix(keep).map(\.records).max() ?? 0
        let fuller = remove.filter { $0.records > fullestKept * 2 }
        if let fullest = fuller.max(by: { ($0.records, $0.created) < ($1.records, $1.created) }) {
            remove.removeAll { $0 == fullest }
        }
        return remove
    }

    /// Whether the folder with an automatic backup's name still holds that backup, by its
    /// manifest.json: the same time of writing. One saved by hand (or by another device) under
    /// that name, or anything that isn't a Nina backup, is never removed. Without a manifest to
    /// read (gone, or not downloaded yet) the list of what this device made decides.
    public static func isSameBackup(_ backup: BackupAutoState.Made, manifestData: Data?) -> Bool {
        guard let manifestData else { return true }
        guard let manifest = try? NinaBackup.decodeManifest(manifestData) else { return false }
        return abs(manifest.created.timeIntervalSince(backup.created)) < 1
    }

    // MARK: Words

    /// How a chosen folder is shown: "iCloud Drive → Nina" for iCloud Drive, "Documents → Nina
    /// Backups" in a Mac's home folder, "USB → Nina" on a drive, otherwise the folder's name.
    public static func placeTitle(path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return path }
        if let cloud = parts.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + parts[(cloud + 1)...]).joined(separator: " → ")
        }
        if parts.first == "Users", parts.count > 2 {
            return parts.dropFirst(2).joined(separator: " → ")
        }
        if parts.first == "Volumes", parts.count > 1 {
            return parts.dropFirst().joined(separator: " → ")
        }
        return last
    }

    /// "today", "yesterday", "3 days ago".
    public static func ago(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let count = days(from: date, to: now, calendar: calendar)
        switch count {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(count) days ago"
        }
    }

    /// The status line under the switch: "Last backup: 3 days ago · next in 4 days.", what went
    /// wrong in plain words, or that there is none yet.
    public static func status(_ state: BackupAutoState, now: Date, calendar: Calendar = .current) -> String {
        var text: String
        if let last = state.lastSuccess {
            text = "Last backup: \(ago(last, now: now, calendar: calendar))"
            if state.problem == nil, let next = daysUntilNext(state, now: now, calendar: calendar) {
                switch next {
                case 0: text += " · the next one starts soon"
                case 1: text += " · next in 1 day"
                default: text += " · next in \(next) days"
                }
            }
            text += "."
        } else if state.problem == nil {
            text = "No automatic backup yet – the first one starts soon."
        } else {
            text = ""
        }
        if let problem = state.problem {
            let lead = state.lastSuccess == nil ? "The automatic backup didn't work" : " The latest try didn't work"
            text += "\(lead) – \(problem.text). Nina tries again later."
        } else if state.usedFallback, state.lastSuccess != nil {
            text += " Your chosen folder couldn't be opened, so it went to Nina's own folder."
        }
        return text
    }
}

// MARK: - JSON (lenient: a missing or broken field gets its default)

extension BackupAutoState: Codable {
    private enum CodingKeys: String, CodingKey {
        case lastSuccess, lastAttempt, problem, usedFallback, folder, made, noticeShown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSuccess = (try? container.decodeIfPresent(Date.self, forKey: .lastSuccess)) ?? nil
        lastAttempt = (try? container.decodeIfPresent(Date.self, forKey: .lastAttempt)) ?? nil
        problem = (try? container.decodeIfPresent(Problem.self, forKey: .problem)) ?? nil
        usedFallback = (try? container.decodeIfPresent(Bool.self, forKey: .usedFallback)) ?? false
        folder = (try? container.decodeIfPresent(Folder.self, forKey: .folder)) ?? nil
        made = (try? container.decodeIfPresent([Made].self, forKey: .made)) ?? []
        noticeShown = (try? container.decodeIfPresent(Bool.self, forKey: .noticeShown)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastSuccess, forKey: .lastSuccess)
        try container.encodeIfPresent(lastAttempt, forKey: .lastAttempt)
        try container.encodeIfPresent(problem, forKey: .problem)
        try container.encode(usedFallback, forKey: .usedFallback)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encode(made, forKey: .made)
        try container.encode(noticeShown, forKey: .noticeShown)
    }

    /// The stored JSON (dates as seconds since 1970); a fresh state when there is none or it
    /// can't be read.
    public static func decode(_ data: Data?) -> BackupAutoState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data, let state = try? decoder.decode(BackupAutoState.self, from: data) else { return BackupAutoState() }
        return state
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
