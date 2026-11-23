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
/// The watch reads nothing from Apple Health itself, so the iPhone also sends what only it knows
/// from Health (`PhoneCoach`): today's morning weigh-in from Health, the status line worked out
/// over typed and Health weigh-ins, and today's active energy for the activity bonus. The watch
/// keeps it on the watch only (never in its SwiftData store) and shows the iPhone's numbers while
/// they are at least as fresh as its own (`coachView`). The snapshot itself carries the bonus, and
/// the watch adds the same bonus to its ring and to its own snapshots.
public enum WatchSnapshotRelay {
    /// What the iPhone sends.
    public struct Payload: Equatable, Sendable {
        public var snapshot: TodaySnapshot
        /// When the iPhone's data of the snapshot's day last changed (nil: nothing that day).
        public var freshness: Date?
        public var sentAt: Date
        /// What only the iPhone knows from Apple Health; nil from an older iPhone build, or from an
        /// iPhone that hasn't read Health since it was started in the background.
        public var coach: PhoneCoach?

        public init(snapshot: TodaySnapshot, freshness: Date?, sentAt: Date = Date(), coach: PhoneCoach? = nil) {
            self.snapshot = snapshot
            self.freshness = freshness
            self.sentAt = sentAt
            self.coach = coach
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
    /// The iPhone's coach part (`PhoneCoach` as JSON). Optional: a watch of an older build ignores
    /// it, so the format stays 1.
    static let coachKey = "nina.coach"
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
        if let coach = payload.coach?.encoded() { message[coachKey] = coach }
        return message
    }

    /// The payload of a message from `message(_:)`; nil for anything else.
    public static func payload(from message: [String: Any]) -> Payload? {
        guard let version = message[formatKey] as? Int, version <= format,
              let data = message[snapshotKey] as? Data,
              let sentAt = message[sentAtKey] as? Double,
              let snapshot = try? decoder.decode(TodaySnapshot.self, from: data) else { return nil }
        let freshness = (message[freshnessKey] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        // A coach part that doesn't read (from a newer iPhone build) is left out; the snapshot counts.
        let coach = (message[coachKey] as? Data).flatMap(PhoneCoach.init(encoded:))
        return Payload(snapshot: snapshot, freshness: freshness, sentAt: Date(timeIntervalSinceReferenceDate: sentAt), coach: coach)
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

    // MARK: What only the iPhone knows from Apple Health

    /// The iPhone's part for the coach on the watch: what it knows from Apple Health that the watch
    /// can't see. The watch keeps it on the watch only (UserDefaults), never in its SwiftData store,
    /// so nothing from Health reaches iCloud.
    public struct PhoneCoach: Codable, Equatable, Sendable {
        /// The iPhone's diary day the numbers are for.
        public var day: String
        /// When the weigh-ins (trashed ones included), the profile with the plan, and the saved
        /// check-ins last changed in the iPhone's store: what the status line rests on besides
        /// Health. nil: none of them.
        public var freshness: Date?
        /// Morning weigh-ins from Apple Health count in the iPhone's numbers (the last
        /// `healthDays` days): the watch's own numbers leave them out.
        public var healthWeighIns: Bool
        /// Today's morning weigh-in when it came from Apple Health (nil: none yet, or the morning
        /// weigh-in was typed in Nina – the watch has that one itself).
        public var healthMorning: Morning?
        /// The status line as the iPhone works it out, typed and Health weigh-ins together; nil
        /// without a plan or without anything to show.
        public var status: WatchCoach.Status?
        /// Active energy from Apple Health (kcal, before "Add to my budget"), as last read on the
        /// calendar day `activeEnergyDay`.
        public var activeEnergy: Double
        public var activeEnergyDay: String

        public init(day: String, freshness: Date?, healthWeighIns: Bool, healthMorning: Morning?, status: WatchCoach.Status?,
                    activeEnergy: Double, activeEnergyDay: String) {
            self.day = day
            self.freshness = freshness
            self.healthWeighIns = healthWeighIns
            self.healthMorning = healthMorning
            self.status = status
            self.activeEnergy = activeEnergy
            self.activeEnergyDay = activeEnergyDay
        }

        /// JSON with dates as plain seconds, so a freshness compares exactly after the trip.
        public func encoded() -> Data? { try? JSONEncoder().encode(self) }

        /// From `encoded()`; nil for anything else.
        public init?(encoded data: Data) {
            guard let value = try? JSONDecoder().decode(PhoneCoach.self, from: data) else { return nil }
            self = value
        }
    }

    /// A morning weigh-in read from Apple Health on the iPhone.
    public struct Morning: Codable, Equatable, Sendable {
        public var kilograms: Double
        public var time: Date

        public init(kilograms: Double, time: Date) {
            self.kilograms = kilograms
            self.time = time
        }
    }

    /// How far back morning weigh-ins from Health make the iPhone's numbers differ from the
    /// watch's (the longest rate window).
    public static let healthDays = 21
    /// Without word from the iPhone: fewer morning weigh-ins typed in Nina in the last 7 days than
    /// this, and the watch says Health weigh-ins count on the iPhone.
    public static let healthHintBelow = 4

    /// The iPhone's part on `today`: `signal` over the typed and the live Health weigh-ins,
    /// `freshness` from its store (`NinaStore.watchLinkCoachFreshness`), `activeEnergy` as last read
    /// from Health on the calendar day `activeEnergyDay`.
    public static func phoneCoach(signal: WeightSignal, plan: CoachPlan, checkIns: [CheckInSnapshot], today: DayKey,
                                  freshness: Date?, activeEnergy: Double, activeEnergyDay: DayKey,
                                  calendar: Calendar = .current) -> PhoneCoach {
        var status: WatchCoach.Status?
        if plan.isSetUp {
            status = WatchCoach.status(summary: signal.summary(on: today, plan: plan), plan: plan, checkIns: checkIns,
                                       calendar: calendar)
        }
        let morning = signal.morning(on: today).flatMap { reading -> Morning? in
            reading.source == .health ? Morning(kilograms: reading.kilograms, time: reading.time) : nil
        }
        let usesHealth = signal.usesHealth(from: today.adding(days: -(healthDays - 1), calendar: calendar), through: today)
        let energy = activeEnergy.isFinite ? max(0, activeEnergy) : 0
        return PhoneCoach(day: today.rawValue, freshness: freshness, healthWeighIns: usesHealth, healthMorning: morning,
                          status: status, activeEnergy: energy, activeEnergyDay: activeEnergyDay.rawValue)
    }

    /// The coach part the watch keeps after a newer message (`isNewer`): the message's own, else
    /// the one it had (an older iPhone build, or an iPhone that hasn't read Health yet since it was
    /// started in the background, sends none).
    public static func keptCoach(_ payload: Payload, previous: PhoneCoach?) -> PhoneCoach? {
        payload.coach ?? previous
    }

    /// The coach on the watch, its own numbers and the iPhone's put together.
    public struct CoachView: Equatable, Sendable {
        /// The status line: the iPhone's or the watch's own.
        public var status: WatchCoach.Status?
        /// The status line is the iPhone's (Health weigh-ins included).
        public var isFromPhone: Bool
        /// Today's morning weigh-in from Apple Health, as the iPhone reported it: the status line
        /// shows it and the "Weigh in" pill is hidden.
        public var healthMorning: Morning?
        /// The note that weigh-ins from Apple Health count on the iPhone, under the watch's own numbers.
        public var showsHealthHint: Bool

        public init(status: WatchCoach.Status?, isFromPhone: Bool, healthMorning: Morning?, showsHealthHint: Bool) {
            self.status = status
            self.isFromPhone = isFromPhone
            self.healthMorning = healthMorning
            self.showsHealthHint = showsHealthHint
        }

        /// Hide the "Weigh in" pill: the iPhone saw this morning's weigh-in in Apple Health.
        public var hidesWeighIn: Bool { healthMorning != nil }
    }

    /// May the watch show the iPhone's numbers? Only those of its own diary day, and only once the
    /// iPhone has seen every weigh-in, plan change and check-in the watch has (`watchFreshness`:
    /// the watch's `watchLinkCoachFreshness`) – a weigh-in just saved on the watch shows at once in
    /// its own numbers, and the iPhone's count again once they include it.
    public static func usesPhoneNumbers(_ phone: PhoneCoach, watchFreshness: Date?, watchToday: String) -> Bool {
        guard phone.day == watchToday else { return false }
        guard let watch = watchFreshness else { return true }
        guard let phoneFreshness = phone.freshness else { return false }
        return watch <= phoneFreshness
    }

    /// What the watch shows: the iPhone's status line when `usesPhoneNumbers`, else its own (`own`,
    /// from typed weigh-ins only); today's Health morning weigh-in from the iPhone whenever it is
    /// of the watch's day (a Health weigh-in can't be undone on the watch). The Health note goes
    /// under the watch's own numbers when the iPhone said Health weigh-ins count there, or – with
    /// no word from the iPhone yet – when fewer than 4 mornings were typed in Nina in 7 days
    /// (`typedMornings`).
    public static func coachView(own: WatchCoach.Status?, watchFreshness: Date?, typedMornings: Int,
                                 phone: PhoneCoach?, watchToday: String) -> CoachView {
        let current = phone.flatMap { $0.day == watchToday ? $0 : nil }
        let fromPhone = current.map { usesPhoneNumbers($0, watchFreshness: watchFreshness, watchToday: watchToday) } ?? false
        var hint = false
        if !fromPhone {
            hint = phone.map(\.healthWeighIns) ?? (typedMornings < healthHintBelow)
        }
        return CoachView(status: fromPhone ? current?.status : own, isFromPhone: fromPhone,
                         healthMorning: current?.healthMorning, showsHealthHint: hint)
    }

    /// The active energy (kcal) the watch counts on the calendar day `calendarDay` – times "Add to
    /// my budget", as on the iPhone: the iPhone's latest reading of that day, else 0 (yesterday's
    /// must never raise today's budget).
    public static func activeEnergy(_ phone: PhoneCoach?, on calendarDay: String) -> Double {
        guard let phone, phone.activeEnergyDay == calendarDay, phone.activeEnergy.isFinite else { return 0 }
        return max(0, phone.activeEnergy)
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
