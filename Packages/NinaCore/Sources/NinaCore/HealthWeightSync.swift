import Foundation

/// Which weigh-ins the iPhone writes to Apple Health on its sync, so a weigh-in saved on the
/// watch, an iPad or a Mac reaches Health once (the iPhone already writes the ones typed on it
/// right away; this pass only records those). Pure planning: the app checks Health and writes.
///
/// - A live weigh-in of the sync window with no mark: make sure Health has it (write unless a
///   sample Nina wrote already sits at that time and weight), then remember it.
/// - A weigh-in whose weight or time changed since it was remembered: remove the old sample first.
/// - A deleted weigh-in that was remembered: remove its sample and forget it.
/// - Imported history is never written (it may already be in Health from the scale it came from).
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

    /// The steps for one sync, in order (removals before writes).
    public static func plan(_ items: [Item], marks: [String: Mark]) -> [Step] {
        var removals: [Step] = []
        var writes: [Step] = []
        for item in items {
            let mark = marks[item.id]
            if item.isDeleted || item.isImported || !(25...300).contains(item.kilograms) {
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
            writes.append(.ensure(id: item.id, mark: Mark(kilograms: item.kilograms, time: item.time, version: item.version)))
        }
        return removals + writes
    }

    /// Marks to keep after a sync: the ones whose weigh-ins are still in the window.
    public static func pruned(_ marks: [String: Mark], keeping ids: Set<String>) -> [String: Mark] {
        marks.filter { ids.contains($0.key) }
    }

    static func sameSample(_ mark: Mark, kilograms: Double, time: Date) -> Bool {
        abs(mark.kilograms - kilograms) < 0.05 && abs(mark.time.timeIntervalSince(time)) < 1
    }
}
