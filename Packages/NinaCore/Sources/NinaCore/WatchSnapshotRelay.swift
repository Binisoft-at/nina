import Foundation

/// The iPhone hands today's numbers to the Apple Watch, device to device (WatchConnectivity, never
/// iCloud), so the watch face follows what is logged on the iPhone or the Mac even while the watch
/// app isn't running. Pure rules: the apps send, receive and write the snapshot file.
///
/// Each device's numbers carry a *freshness*: when the day's data last changed in its store (the
/// newest change of the day's entries, water and day marks – trashed ones included – and of the
/// settings) or by a save on the device itself that day. The watch keeps whichever snapshot is
/// fresher:
/// - The iPhone's snapshot is taken unless the watch has newer changes the iPhone hasn't seen yet,
///   or it is older than one already taken, or its day is over on the watch.
/// - The watch's own snapshot from a refresh replaces the iPhone's only once the watch's store is
///   at least as fresh (its CloudKit import has caught up). A save on the watch itself always
///   writes its snapshot (that change is the newest).
///
/// The iPhone sends its snapshot without the Apple Health activity bonus: the watch reads nothing
/// from Health, so its ring and its face both leave the bonus out.
public enum WatchSnapshotRelay {
    /// What the iPhone sends.
    public struct Payload: Equatable, Sendable {
        public var snapshot: TodaySnapshot
        /// When the iPhone's data of the snapshot's day last changed (nil: nothing that day).
        public var freshness: Date?
        public var sentAt: Date

        public init(snapshot: TodaySnapshot, freshness: Date?, sentAt: Date = Date()) {
            self.snapshot = snapshot
            self.freshness = freshness
            self.sentAt = sentAt
        }

        /// What the watch remembers of it.
        public var mark: PhoneMark { PhoneMark(day: snapshot.day, freshness: freshness, sentAt: sentAt) }
    }

    /// What the watch remembers of the last snapshot from the iPhone (device-only).
    public struct PhoneMark: Codable, Equatable, Sendable {
        public var day: String
        public var freshness: Date?
        public var sentAt: Date

        public init(day: String, freshness: Date?, sentAt: Date) {
            self.day = day
            self.freshness = freshness
            self.sentAt = sentAt
        }
    }

    static let formatKey = "nina.relay"
    static let snapshotKey = "nina.snapshot"
    static let freshnessKey = "nina.freshness"
    static let sentAtKey = "nina.sentAt"
    /// The message format; a watch ignores messages of a newer format it doesn't know.
    static let format = 1

    /// The message for WatchConnectivity (property-list values only); nil when the snapshot can't
    /// be encoded.
    public static func message(_ payload: Payload) -> [String: Any]? {
        guard let data = try? encoder.encode(payload.snapshot) else { return nil }
        var message: [String: Any] = [
            formatKey: format,
            snapshotKey: data,
            sentAtKey: payload.sentAt.timeIntervalSinceReferenceDate,
        ]
        if let freshness = payload.freshness { message[freshnessKey] = freshness.timeIntervalSinceReferenceDate }
        return message
    }

    /// The payload of a message from `message(_:)`; nil for anything else.
    public static func payload(from message: [String: Any]) -> Payload? {
        guard let version = message[formatKey] as? Int, version <= format,
              let data = message[snapshotKey] as? Data,
              let sentAt = message[sentAtKey] as? Double,
              let snapshot = try? decoder.decode(TodaySnapshot.self, from: data) else { return nil }
        let freshness = (message[freshnessKey] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        return Payload(snapshot: snapshot, freshness: freshness, sentAt: Date(timeIntervalSinceReferenceDate: sentAt))
    }

    /// The freshness of a day: the newest of its changes (`localChange`: this device's own last
    /// save that day, if any).
    public static func freshness(_ changes: [Date], localChange: Date? = nil) -> Date? {
        (changes + [localChange].compactMap { $0 }).max()
    }

    /// A message newer than the last one taken from the iPhone (messages can arrive twice or out of
    /// order: the face's transfers and the app context travel separately).
    public static func isNewer(_ payload: Payload, than previous: PhoneMark?) -> Bool {
        guard let previous else { return true }
        return payload.sentAt > previous.sentAt
    }

    /// The watch: take the iPhone's snapshot (after `isNewer`)? `watchFreshness`: the watch's own
    /// freshness of `watchToday`.
    public static func acceptsPhone(_ payload: Payload, watchFreshness: Date?, watchToday: String) -> Bool {
        let day = payload.snapshot.day
        if day < watchToday { return false }
        if day > watchToday { return true }
        guard let watch = watchFreshness else { return true }
        guard let phone = payload.freshness else { return false }
        return watch <= phone
    }

    /// The watch: may the snapshot of its own refresh for `day` (with the watch's `freshness`)
    /// replace the one from the iPhone?
    public static func acceptsOwn(day: String, freshness: Date?, phone: PhoneMark?) -> Bool {
        guard let phone else { return true }
        if day != phone.day { return day > phone.day }
        guard let phoneFreshness = phone.freshness else { return true }
        guard let freshness else { return false }
        return freshness >= phoneFreshness
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
