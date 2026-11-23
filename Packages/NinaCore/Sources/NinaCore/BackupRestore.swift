import Foundation

/// What restoring a backup would do. Records are matched by uuid within their type, live or in
/// Recently Deleted: one Nina already has is left as it is (nothing is overwritten); a missing one
/// is added with its uuid and dates, so links (a diary entry's food, a routine's meal, a photo's
/// measurement) and the plan's day marks stay intact. Records that were in the backup's trash for
/// longer than the trash keeps them are left out. The profile (goals & plan) is added when there
/// is none; when there is one that differs, it is only replaced if the person switches that on.
public struct BackupRestorePlan: Equatable, Sendable {
    /// One preview line per type in the backup.
    public struct Line: Equatable, Sendable, Identifiable {
        public var type: BackupType
        public var inFile: Int
        /// Missing here: added.
        public var new: Int
        /// The same record is here (live or in Recently Deleted): kept as it is.
        public var alreadyHere: Int
        /// Of those, how many were changed since (here or in the backup) – still kept as they are.
        public var differ: Int
        /// In the backup's Recently Deleted for longer than it keeps things: left out.
        public var expired: Int

        public var id: String { type.rawValue }

        /// "12 new · 340 already here (3 differ – yours are kept)".
        public var detail: String {
            var parts: [String] = []
            if new > 0 { parts.append("\(grouped(new)) new") }
            if alreadyHere > 0 {
                var here = "\(grouped(alreadyHere)) already here"
                if differ > 0 { here += " (\(grouped(differ)) changed since – yours are kept)" }
                parts.append(here)
            }
            if expired > 0 { parts.append("\(grouped(expired)) deleted long ago, left out") }
            return parts.isEmpty ? "none" : parts.joined(separator: " · ")
        }
    }

    public enum ProfileState: Equatable, Sendable {
        /// The backup has no goals & plan.
        case none
        /// Nina has none: the backup's are added.
        case new
        /// The same as Nina's.
        case same
        /// Different from Nina's: kept unless the person switches "Use the backup's goals & plan" on.
        case differs
    }

    public var lines: [Line]
    /// What a restore adds, in insert order (foods and recipes before the entries that use them).
    public var inserts: [BackupRecord]
    /// The backup's goals & plan.
    public var profile: BackupRecord?
    public var profileState: ProfileState
    /// Types this version doesn't know (from a newer Nina), left out.
    public var unknownTypes: [String]

    /// Records the restore adds (without the profile).
    public var newCount: Int { inserts.count }

    public var hasChanges: Bool { !inserts.isEmpty || profileState == .new }

    /// "1,204 to add · 3,410 already here" or "Everything in this backup is already in Nina".
    public var summary: String {
        let here = lines.map(\.alreadyHere).reduce(0, +)
        let added = newCount + (profileState == .new ? 1 : 0)
        guard added > 0 else { return "Everything in this backup is already in Nina" }
        var text = "\(grouped(added)) to add"
        if here > 0 { text += " · \(grouped(here)) already here" }
        return text
    }

    /// - Parameters:
    ///   - existing: per type, the uuids Nina has (live and in Recently Deleted) with their last
    ///     change (`modifiedAt`).
    ///   - currentProfile: Nina's goals & plan as a backup record (nil when there is none).
    ///   - keepTrashDays: how long Recently Deleted keeps things.
    public init(_ records: [BackupRecord], existing: [BackupType: [UUID: Date]], currentProfile: BackupRecord?,
                now: Date = Date(), keepTrashDays: Int = 30) {
        var lines: [BackupType: Line] = [:]
        var inserts: [BackupType: [BackupRecord]] = [:]
        var seen: [BackupType: Set<UUID>] = [:]
        var unknown: [String] = []
        var profile: BackupRecord?
        let oldest = now.addingTimeInterval(-Double(keepTrashDays) * 86_400)
        for record in records {
            guard let type = record.kind else {
                if !unknown.contains(record.type) { unknown.append(record.type) }
                continue
            }
            guard seen[type, default: []].insert(record.uuid).inserted else { continue }
            var line = lines[type] ?? Line(type: type, inFile: 0, new: 0, alreadyHere: 0, differ: 0, expired: 0)
            line.inFile += 1
            if type == .profile {
                profile = profile ?? record
            } else if let here = existing[type]?[record.uuid] {
                line.alreadyHere += 1
                if let modified = record.modifiedAt, abs(modified.timeIntervalSince(here)) > 0.001 { line.differ += 1 }
            } else if let deleted = record.deletedAt, deleted < oldest {
                line.expired += 1
            } else {
                line.new += 1
                inserts[type, default: []].append(record)
            }
            lines[type] = line
        }
        let state: ProfileState
        if let profile {
            if let currentProfile {
                state = BackupRestorePlan.sameProfile(profile, currentProfile) ? .same : .differs
            } else {
                state = .new
            }
            var line = lines[.profile] ?? Line(type: .profile, inFile: 1, new: 0, alreadyHere: 0, differ: 0, expired: 0)
            switch state {
            case .new: line.new = 1
            case .differs:
                line.alreadyHere = 1
                line.differ = 1
            default: line.alreadyHere = 1
            }
            lines[.profile] = line
        } else {
            state = .none
        }
        self.lines = BackupType.allCases.compactMap { lines[$0] }
        self.inserts = BackupType.allCases.flatMap { inserts[$0] ?? [] }
        self.profile = profile
        self.profileState = state
        self.unknownTypes = unknown
    }

    /// The same goals & plan: every field but the uuid and the dates.
    static func sameProfile(_ a: BackupRecord, _ b: BackupRecord) -> Bool {
        let ignored: Set<String> = ["createdAt", "modifiedAt"]
        return a.fields.filter { !ignored.contains($0.key) } == b.fields.filter { !ignored.contains($0.key) }
    }
}

/// "1,234".
private func grouped(_ count: Int) -> String {
    let digits = String(count)
    var result = ""
    for (index, character) in digits.reversed().enumerated() {
        if index > 0, index % 3 == 0 { result.append(",") }
        result.append(character)
    }
    return String(result.reversed())
}
