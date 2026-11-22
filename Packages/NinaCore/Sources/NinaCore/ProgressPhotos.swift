import Foundation

// Progress photos: the poses, the session order, the size maths for storing them, and what the
// compare view shows (the pair of days, the days between, the 7-day average weight and the waist
// at each day). The images themselves are app code (ImageIO); this is the logic around them.

/// The pose of a progress photo, stored as its raw value (`ProgressPhoto.pose`).
public enum PhotoPose: String, CaseIterable, Codable, Sendable, Identifiable {
    case front, side, back, other

    public var id: String { rawValue }

    /// The poses a photo session asks for, in this order.
    public static let session: [PhotoPose] = [.front, .side, .back]

    /// A stored value; anything unknown counts as "other".
    public init(stored: String) {
        self = PhotoPose(rawValue: stored.trimmingCharacters(in: .whitespaces).lowercased()) ?? .other
    }

    public var title: String {
        switch self {
        case .front: "Front"
        case .side: "Side"
        case .back: "Back"
        case .other: "Other"
        }
    }

    /// How to stand, one short line.
    public var hint: String {
        switch self {
        case .front: "Face the camera, feet hip-width apart, arms a little away from your body."
        case .side: "Turn to your right side, arms relaxed, look straight ahead."
        case .back: "Turn your back to the camera, arms a little away from your body."
        case .other: "Any pose you want to follow – keep it the same each time."
        }
    }

    /// Front, side, back, other.
    public var order: Int {
        switch self {
        case .front: 0
        case .side: 1
        case .back: 2
        case .other: 3
        }
    }
}

/// What the logic needs to know about a stored photo (no image data).
public struct PhotoRecord: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var day: DayKey
    public var time: Date
    public var pose: PhotoPose

    public init(id: UUID, day: DayKey, time: Date, pose: PhotoPose) {
        self.id = id
        self.day = day
        self.time = time
        self.pose = pose
    }
}

public enum ProgressPhotos {
    /// The stored photo's long side, in pixels.
    public static let fullPixels = 2048
    /// The thumbnail's long side (lists and the Body card), in pixels.
    public static let thumbnailPixels = 360
    /// JPEG quality of the stored photo and of the thumbnail.
    public static let fullQuality = 0.8
    public static let thumbnailQuality = 0.7
    /// The last photo of the pose shown over the camera picture.
    public static let ghostOpacity = 0.3
    /// A weigh-in average or tape value counts for a photo day this many days either side.
    public static let nearbyDays = 7

    /// The consistency guide of the session's first page.
    public static let guide: [String] = [
        "Same light and the same spot each time – a plain wall works best.",
        "Same distance, phone at chest height, the whole body in the frame.",
        "Same time of day: ideally the morning of a full measurement, before eating.",
        "Same clothing (or as little as you like) – it's private to your iCloud.",
    ]

    // MARK: Size

    /// The pixel size with the long side at most `maxPixels`, the aspect ratio kept and never
    /// larger than the original (at least 1 × 1).
    public static func fittedSize(width: Int, height: Int, maxPixels: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxPixels > 0 else { return (max(width, 1), max(height, 1)) }
        let long = max(width, height)
        guard long > maxPixels else { return (width, height) }
        let scale = Double(maxPixels) / Double(long)
        let fittedWidth = width >= height ? maxPixels : max(1, Int((Double(width) * scale).rounded()))
        let fittedHeight = height > width ? maxPixels : max(1, Int((Double(height) * scale).rounded()))
        return (fittedWidth, fittedHeight)
    }

    // MARK: Picking photos

    /// Oldest first (by day, then time).
    public static func sorted(_ photos: [PhotoRecord]) -> [PhotoRecord] {
        photos.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            return lhs.time < rhs.time
        }
    }

    /// The newest photo of each pose.
    public static func latest(_ photos: [PhotoRecord]) -> [PhotoPose: PhotoRecord] {
        var result: [PhotoPose: PhotoRecord] = [:]
        for photo in sorted(photos) { result[photo.pose] = photo }
        return result
    }

    /// The days with a photo of `pose`, oldest first.
    public static func days(of pose: PhotoPose, in photos: [PhotoRecord]) -> [DayKey] {
        Array(Set(photos.filter { $0.pose == pose }.map(\.day))).sorted()
    }

    /// The newest photo of `pose` on `day`.
    public static func photo(of pose: PhotoPose, on day: DayKey, in photos: [PhotoRecord]) -> PhotoRecord? {
        sorted(photos).last { $0.pose == pose && $0.day == day }
    }

    /// The photos of `pose`, oldest first (the viewer steps through them).
    public static func timeline(of pose: PhotoPose, in photos: [PhotoRecord]) -> [PhotoRecord] {
        sorted(photos).filter { $0.pose == pose }
    }

    /// The poses with photos on at least two days, in pose order (what Compare offers).
    public static func comparablePoses(_ photos: [PhotoRecord]) -> [PhotoPose] {
        PhotoPose.allCases.filter { days(of: $0, in: photos).count >= 2 }
    }

    /// The poses with any photo, in pose order.
    public static func poses(_ photos: [PhotoRecord]) -> [PhotoPose] {
        let present = Set(photos.map(\.pose))
        return PhotoPose.allCases.filter { present.contains($0) }
    }

    /// The pose Compare opens with: `preferred` when it can be compared, else the first that can.
    public static func comparePose(_ photos: [PhotoRecord], preferred: PhotoPose? = nil) -> PhotoPose? {
        let poses = comparablePoses(photos)
        if let preferred, poses.contains(preferred) { return preferred }
        return poses.first
    }

    /// The ghost over the camera picture: the newest photo of that pose.
    public static func ghost(for pose: PhotoPose, in photos: [PhotoRecord]) -> PhotoRecord? {
        latest(photos)[pose]
    }

    // MARK: Comparing

    /// Two days of one pose, the earlier first.
    public struct Pair: Equatable, Hashable, Sendable {
        public var before: DayKey
        public var after: DayKey

        /// Ordered: `before` is never later than `after`.
        public init(_ first: DayKey, _ second: DayKey) {
            before = min(first, second)
            after = max(first, second)
        }

        /// Days from `before` to `after`.
        public func days(calendar: Calendar = .current) -> Int {
            before.days(to: after, calendar: calendar)
        }
    }

    /// The pair Compare opens with for a pose: the first day and the latest day; nil with fewer
    /// than two days.
    public static func defaultPair(for pose: PhotoPose, in photos: [PhotoRecord]) -> Pair? {
        let days = days(of: pose, in: photos)
        guard let first = days.first, let last = days.last, first != last else { return nil }
        return Pair(first, last)
    }

    /// The pair after a day was picked for one side. The earlier day is always "before"; a day
    /// without a photo, or the other side's day, changes nothing.
    public static func pair(_ pair: Pair, picking day: DayKey, asBefore: Bool, days: [DayKey]) -> Pair {
        guard days.contains(day) else { return pair }
        if asBefore {
            if day == pair.after { return Pair(pair.before, pair.after) }
            return Pair(day, pair.after)
        }
        if day == pair.before { return Pair(pair.before, pair.after) }
        return Pair(pair.before, day)
    }

    /// "Same day", "1 day", "12 days", "5 weeks", "5 weeks 2 days".
    public static func spanText(days: Int) -> String {
        let days = abs(days)
        switch days {
        case 0: return "Same day"
        case 1: return "1 day"
        case 2..<14: return "\(days) days"
        default:
            let weeks = days / 7, rest = days % 7
            let weekText = "\(weeks) weeks"
            guard rest > 0 else { return weekText }
            return weekText + " " + (rest == 1 ? "1 day" : "\(rest) days")
        }
    }

    /// The value nearest `day` within `window` days: the same day first, then the closest
    /// (the earlier one on a tie).
    public static func nearest(_ values: [(day: DayKey, value: Double)], to day: DayKey, within window: Int = nearbyDays,
                               calendar: Calendar = .current) -> (day: DayKey, value: Double)? {
        var best: (day: DayKey, value: Double, distance: Int)?
        for item in values {
            let distance = abs(day.days(to: item.day, calendar: calendar))
            guard distance <= window else { continue }
            if let current = best {
                if distance > current.distance { continue }
                if distance == current.distance, item.day > current.day { continue }
            }
            best = (item.day, item.value, distance)
        }
        return best.map { (day: $0.day, value: $0.value) }
    }

    // MARK: Photo dates

    /// The capture time in a photo's EXIF ("2030:01:07 07:12:30", local time); nil when unreadable.
    public static func exifDate(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "-" || $0 == "T" }).compactMap { Int($0) }
        guard parts.count >= 5, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              (0...23).contains(parts[3]), (0...59).contains(parts[4]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4],
                                        second: parts.count > 5 ? min(parts[5], 59) : 0)
        return calendar.date(from: components)
    }
}

/// What Compare shows under the two photos: the days between, the 7-day average weight and the
/// waist at each day (the nearest within a week), and the changes.
public struct PhotoComparison: Equatable, Sendable {
    public struct Side: Equatable, Sendable {
        public var day: DayKey
        /// The valid 7-day average on the day (nil without one).
        public var weight: Double?
        /// The tape value of `waistSite` nearest the day (within a week).
        public var waist: Double?
        /// The day that waist was measured.
        public var waistDay: DayKey?

        public init(day: DayKey, weight: Double?, waist: Double?, waistDay: DayKey?) {
            self.day = day
            self.weight = weight
            self.waist = waist
            self.waistDay = waistDay
        }
    }

    public var before: Side
    public var after: Side
    public var days: Int
    /// The waist site shown: the waist when known on either day, else the narrow waist.
    public var waistSite: BodySite

    public init(pair: ProgressPhotos.Pair, signal: WeightSignal, tape: [BodyTapeRecord], calendar: Calendar = .current) {
        let sites: [BodySite] = [.waist, .waistNarrow]
        func values(_ site: BodySite) -> [(day: DayKey, value: Double)] {
            tape.compactMap { record in record.values[site].map { (day: record.day, value: $0) } }
        }
        func near(_ site: BodySite, _ day: DayKey) -> (day: DayKey, value: Double)? {
            ProgressPhotos.nearest(values(site), to: day, calendar: calendar)
        }
        // The site both days have, else the first either day has.
        let both = sites.first { near($0, pair.before) != nil && near($0, pair.after) != nil }
        let either = sites.first { near($0, pair.before) != nil || near($0, pair.after) != nil }
        let site = both ?? either ?? .waist
        func side(_ day: DayKey) -> Side {
            let waist = near(site, day)
            return Side(day: day, weight: signal.average(on: day).value, waist: waist?.value, waistDay: waist?.day)
        }
        before = side(pair.before)
        after = side(pair.after)
        days = pair.days(calendar: calendar)
        waistSite = site
    }

    /// After minus before, kg (both averages known).
    public var weightChange: Double? {
        guard let first = before.weight, let second = after.weight else { return nil }
        return second - first
    }

    /// After minus before, cm (both known, and not the same measurement).
    public var waistChange: Double? {
        guard let first = before.waist, let second = after.waist, before.waistDay != after.waistDay else { return nil }
        return second - first
    }
}

/// The steps of a photo session: an optional first page with the guide, each pose (taken,
/// picked or skipped), then the review that saves.
public struct PhotoSession: Equatable, Sendable {
    public enum Step: Hashable, Sendable {
        case intro
        case pose(PhotoPose)
        case review
    }

    public var poses: [PhotoPose]
    public var showsIntro: Bool

    public init(poses: [PhotoPose] = PhotoPose.session, showsIntro: Bool = true) {
        self.poses = poses.isEmpty ? PhotoPose.session : poses
        self.showsIntro = showsIntro
    }

    public var steps: [Step] {
        (showsIntro ? [.intro] : []) + poses.map { Step.pose($0) } + [.review]
    }

    public var first: Step { steps[0] }

    public func next(after step: Step) -> Step? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    public func previous(before step: Step) -> Step? {
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// "Next: Side", "Review" (after the last pose), "Start" (on the guide page).
    public func nextTitle(after step: Step) -> String {
        switch next(after: step) {
        case .pose(let pose)?: return step == .intro ? "Start" : "Next: \(pose.title)"
        case .review?: return "Review"
        case .intro?, nil: return "Done"
        }
    }

    /// "Front · 1 of 3"
    public func position(of pose: PhotoPose) -> String? {
        guard let index = poses.firstIndex(of: pose) else { return nil }
        return "\(pose.title) · \(index + 1) of \(poses.count)"
    }
}
