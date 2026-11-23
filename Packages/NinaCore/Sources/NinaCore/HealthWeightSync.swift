import Foundation

/// Which weigh-ins an iPhone or iPad writes to Apple Health on its sync, so a weigh-in saved on the
/// watch, another device or a Mac reaches Health once (each writes the ones typed on it right
/// away; this pass only records those). Pure planning: the app checks Health and writes.
///
/// - A live weigh-in of the sync window with no mark: make sure Health has it (write unless a
///   sample Nina wrote already sits at that time and weight), then remember it.
/// - A weigh-in whose weight or time changed since it was remembered: remove the old sample first.
/// - A deleted weigh-in that was remembered: remove its sample and forget it.
/// - A remembered weigh-in that is gone from the window (deleted for good on another device, or
///   moved more than 14 days back): remove its sample when it was inside the window, then forget it.
/// - Imported history is never written (it may already be in Health from the scale it came from).
///
/// Every sample Nina writes carries the sync identifier `HealthMapping.syncIdentifier(weight:)` and
/// a version, so two devices (iPhone and iPad) or two passes never leave the same weigh-in twice.
public enum HealthWeightSync {
    /// What this device remembers about a weigh-in it made sure Health has.
    public struct Mark: Codable, Equatable, Sendable {
        public var kilograms: Double
        public var time: Date
        public var version: Int

        public init(kilograms: Double, time: Date, version: Int) {
            self.kilograms = kilograms
            self.time = time
            self.version = version
        }
    }

    /// A weigh-in as stored in Nina.
    public struct Item: Equatable, Sendable {
        public var id: String
        public var kilograms: Double
        public var time: Date
        public var version: Int
        public var isDeleted: Bool
        public var isImported: Bool

        public init(id: String, kilograms: Double, time: Date, version: Int, isDeleted: Bool = false, isImported: Bool = false) {
            self.id = id
            self.kilograms = kilograms
            self.time = time
            self.version = version
            self.isDeleted = isDeleted
            self.isImported = isImported
        }
    }

    public enum Step: Equatable, Sendable {
        /// Remove the sample Nina wrote for this old weight and time.
        case remove(kilograms: Double, time: Date)
        /// Make sure Health has this weigh-in (write it unless Nina's sample is already there),
        /// then remember it with `mark`.
        case ensure(id: String, mark: Mark)
        /// Forget the weigh-in (nothing to do in Health).
        case forget(id: String)
    }

    /// Whether Nina may write this weigh-in to Apple Health: live, typed in Nina (not imported
    /// history) and 25–300 kg. Every write – the weigh-in sheet, the notification, Undo, Recently
    /// Deleted and the sync pass – asks this first.
    public static func writes(_ item: Item) -> Bool {
        !item.isDeleted && !item.isImported && plausible.contains(item.kilograms)
    }

    static let plausible: ClosedRange<Double> = 25...300

    /// The steps for one sync, in order (removals before writes). `items`: the weigh-ins of the
    /// sync window. A mark whose weigh-in isn't among them is forgotten; when its time is at or
    /// after `windowStart`, its sample is removed first (nil: only forget, e.g. when the store
    /// couldn't be read for real).
    public static func plan(_ items: [Item], marks: [String: Mark], windowStart: Date? = nil) -> [Step] {
        var removals: [Step] = []
        var ensures: [Step] = []
        let ids = Set(items.map(\.id))
        for (id, mark) in marks.sorted(by: { $0.key < $1.key }) where !ids.contains(id) {
            if let windowStart, mark.time >= windowStart {
                removals.append(.remove(kilograms: mark.kilograms, time: mark.time))
            }
            removals.append(.forget(id: id))
        }
        for item in items {
            let mark = marks[item.id]
            if !writes(item) {
                if let mark {
                    if !item.isImported { removals.append(.remove(kilograms: mark.kilograms, time: mark.time)) }
                    removals.append(.forget(id: item.id))
                }
                continue
            }
            if let mark, mark.version == item.version { continue }
            if let mark, !sameSample(mark, kilograms: item.kilograms, time: item.time) {
                removals.append(.remove(kilograms: mark.kilograms, time: mark.time))
            }
            ensures.append(.ensure(id: item.id, mark: Mark(kilograms: item.kilograms, time: item.time, version: item.version)))
        }
        return removals + ensures
    }

    /// How many remembered weigh-ins may vanish from the store in one pass before the store looks
    /// emptied rather than edited (`trustsStore`).
    public static let maxVanished = 3

    /// Whether the store's weigh-ins can say which ones are gone for good, so their samples may
    /// leave Apple Health. Not when the store looks emptied – after an iCloud sign-out, a switch to
    /// another Apple Account or a reset the store reads fine but has nothing (yet): remembered
    /// weigh-ins of the window exist but the window holds no weigh-in at all, or more than
    /// `maxVanished` of them vanished at once. Then plan with `windowStart` nil (forget only): the
    /// samples stay in Health, and a weigh-in that comes back is found there again.
    /// `items`: the window's weigh-ins, trashed ones included.
    public static func trustsStore(items: [Item], marks: [String: Mark], windowStart: Date) -> Bool {
        let inWindow = marks.filter { $0.value.time >= windowStart }
        guard !inWindow.isEmpty else { return true }
        guard !items.isEmpty else { return false }
        let ids = Set(items.map(\.id))
        let vanished = inWindow.keys.filter { !ids.contains($0) }.count
        return vanished <= maxVanished
    }

    /// Marks to keep after a sync: the ones whose weigh-ins are still in the window (`plan`
    /// already forgets the others; this is the safety net).
    public static func pruned(_ marks: [String: Mark], keeping ids: Set<String>) -> [String: Mark] {
        marks.filter { ids.contains($0.key) }
    }

    /// The tag an imported weigh-in carries in its note, so every device knows it is history.
    public static let importTag = "#import"

    /// The note of an imported weigh-in: the file's note plus the import tag.
    public static func importedNote(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        if isImported(note: trimmed) { return trimmed }
        return trimmed.isEmpty ? importTag : trimmed + " " + importTag
    }

    /// The note without the import tag (what an export writes back out).
    public static func noteWithoutImportTag(_ note: String) -> String {
        note.split(separator: " ", omittingEmptySubsequences: true)
            .filter { $0.lowercased() != importTag }
            .joined(separator: " ")
    }

    /// The note as the weigh-in sheet shows it: without the import tag (and empty for the settings
    /// file's "import"), so the field never shows Nina's marker. `savedNote` puts it back.
    public static func editableNote(_ note: String) -> String {
        if note.lowercased().trimmingCharacters(in: .whitespaces) == "import" { return "" }
        return hasImportTag(note) ? noteWithoutImportTag(note) : note
    }

    /// The note the weigh-in sheet saves: an imported weigh-in keeps the import tag whatever was
    /// typed (so it stays history and never reaches Apple Health); a typed one never gets it.
    public static func savedNote(_ typed: String, imported: Bool) -> String {
        let clean = hasImportTag(typed) ? noteWithoutImportTag(typed) : typed
        return imported ? importedNote(clean) : clean
    }

    static func hasImportTag(_ note: String) -> Bool {
        note.lowercased().split(separator: " ").contains { $0 == importTag }
    }

    /// Whether a weigh-in came from an import: the history file's tag, or the settings file's
    /// weight (note "import").
    public static func isImported(note: String) -> Bool {
        let lower = note.lowercased().trimmingCharacters(in: .whitespaces)
        return lower == "import" || lower.split(separator: " ").contains { $0 == importTag }
    }

    static func sameSample(_ mark: Mark, kilograms: Double, time: Date) -> Bool {
        abs(mark.kilograms - kilograms) < 0.05 && abs(mark.time.timeIntervalSince(time)) < 1
    }
}

/// The diary and water a device wrote to Apple Health (its ledger) against what the store still
/// has. A ledger id missing from the sync window's records is looked up across all days: one that
/// is found was only moved out of the window and is forgotten (its samples stay); one with no
/// record anywhere was deleted for good – an Undo right after logging, ⌘Z, or a purge on another
/// device – so its samples leave Health before it is forgotten.
///
/// Nothing is removed when the store looks emptied (after an iCloud sign-out or an account switch
/// the store reads fine but is empty): no records of that kind at all, or more than `maxGone` gone
/// in one pass. Those ids are only forgotten, as before.
public struct HealthLedgerSweep: Equatable, Sendable {
    /// Deleted for good: remove their samples from Health, then forget them.
    public var remove: [String]
    /// Forget only: moved out of the window, or the store can't be trusted right now.
    public var forget: [String]
    /// Ids were gone but the store looked emptied, so nothing was removed.
    public var distrusted: Bool

    public static let maxGone = 20

    public init(remove: [String] = [], forget: [String] = [], distrusted: Bool = false) {
        self.remove = remove
        self.forget = forget
        self.distrusted = distrusted
    }

    /// The ledger ids that aren't among the window's records (`windowIDs`, trashed ones included),
    /// sorted: look these up across all days, then `plan`.
    public static func missing(ledgerIDs: [String], windowIDs: Set<String>) -> [String] {
        ledgerIDs.filter { !windowIDs.contains($0) }.sorted()
    }

    /// `missing`: from `missing(ledgerIDs:windowIDs:)`; `found`: those of them that still have a
    /// record on some day; `storeIsEmpty`: the store holds no record of this kind at all.
    public static func plan(missing: [String], found: Set<String>, storeIsEmpty: Bool, limit: Int = maxGone) -> HealthLedgerSweep {
        let moved = missing.filter { found.contains($0) }
        let gone = missing.filter { !found.contains($0) }
        guard !gone.isEmpty else { return HealthLedgerSweep(forget: moved) }
        if storeIsEmpty || gone.count > limit {
            return HealthLedgerSweep(forget: moved + gone, distrusted: true)
        }
        return HealthLedgerSweep(remove: gone, forget: moved)
    }
}
