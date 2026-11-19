import Foundation

/// Where the tape goes. Stable keys (stored in `BodyMeasurement.values` and the plan's routine).
/// `arm`, `thigh` and `calf` are the right side; the left side has its own keys (`arm_l`, …), so
/// the two sides never mix.
public enum BodySite: String, CaseIterable, Codable, Sendable, Identifiable {
    case waist
    case waistNarrow = "waist_narrow"
    case hip
    case chest
    case arm
    case thigh
    case neck
    case calf
    case armFlexed = "arm_flexed"
    case armLeft = "arm_l"
    case thighLeft = "thigh_l"
    case calfLeft = "calf_l"

    public var id: String { rawValue }

    /// The sites without the left-side variants, in the order of the measure sheet.
    public static let mainSites: [BodySite] = [.waist, .waistNarrow, .hip, .chest, .arm, .thigh, .neck, .calf, .armFlexed]

    public var title: String {
        switch self {
        case .waist: "Waist"
        case .waistNarrow: "Narrow waist"
        case .hip: "Hip"
        case .chest: "Chest"
        case .arm: "Arm"
        case .thigh: "Thigh"
        case .neck: "Neck"
        case .calf: "Calf"
        case .armFlexed: "Arm, flexed"
        case .armLeft: "Arm (left)"
        case .thighLeft: "Thigh (left)"
        case .calfLeft: "Calf (left)"
        }
    }

    /// Where exactly to measure (shown in the measure sheet).
    public var landmark: String {
        switch self {
        case .waist: "Horizontal at the navel, relaxed, at the end of a normal breath out"
        case .waistNarrow: "Narrowest point between the lowest rib and the hip bone"
        case .hip: "Widest point over the buttocks, feet together"
        case .chest: "At nipple height (women: the fullest point), arms down, after breathing out"
        case .arm, .armLeft: "Relaxed upper arm, halfway between shoulder tip and elbow, arm hanging"
        case .thigh, .thighLeft: "Halfway between hip crease and the top of the kneecap, weight on both legs"
        case .neck: "Just below the larynx, tape sloping slightly down at the front"
        case .calf, .calfLeft: "Maximum girth, standing"
        case .armFlexed: "Elbow at 90°, biceps tensed, at the peak"
        }
    }

    /// Values outside this range (cm) are typos.
    public var plausibleRange: ClosedRange<Double> {
        switch base {
        case .waist, .waistNarrow: 50...200
        case .hip: 60...200
        case .chest: 60...170
        case .arm, .armFlexed: 18...60
        case .thigh: 30...100
        case .neck: 25...60
        case .calf: 20...60
        default: 1...300
        }
    }

    /// Technical error of measurement (cm): the usual difference between two careful readings.
    public var tem: Double { isSmall ? 0.2 : 0.4 }

    /// Minimal detectable change (cm): smaller changes are "no clear change".
    public var mdc: Double { isSmall ? 0.5 : 1.0 }

    private var isSmall: Bool {
        switch base {
        case .arm, .armFlexed, .neck, .calf: true
        default: false
        }
    }

    public func isPlausible(_ centimeters: Double) -> Bool { plausibleRange.contains(centimeters) }

    /// The right-side (or only) site: `arm_l` → `arm`.
    public var base: BodySite {
        switch self {
        case .armLeft: .arm
        case .thighLeft: .thigh
        case .calfLeft: .calf
        default: self
        }
    }

    public var isLeft: Bool { self != base }

    /// Measured per side (arm, thigh, calf).
    public var hasSides: Bool { base.left != nil }

    /// The left-side variant of a sided site.
    public var left: BodySite? {
        switch self {
        case .arm: .armLeft
        case .thigh: .thighLeft
        case .calf: .calfLeft
        default: nil
        }
    }

    /// The keys to measure for this site with the chosen side: `arm` with `.both` → arm, arm_l.
    public func sites(for side: BodySide) -> [BodySite] {
        guard let left = base.left else { return [self] }
        switch side {
        case .right: return [base]
        case .left: return [left]
        case .both: return [base, left]
        }
    }

    /// The keys to measure when this one site is measured on its own (from its detail screen):
    /// the site itself, plus the other side when both sides are measured (`arm` or `arm_l` with
    /// `.both` → arm, arm_l). A key of the other side than `side` stays as it is, so its own
    /// series goes on.
    public func measuredSites(side: BodySide) -> [BodySite] {
        guard side == .both, hasSides else { return [self] }
        return base.sites(for: .both)
    }

    /// On in a new routine: waist (women: the narrow waist instead), hip, chest, arm and thigh;
    /// neck when the tracking method is the tape estimate (Navy); calf and flexed arm off.
    public func isOnByDefault(sex: Sex, trackingMethod: BodyMethod? = nil) -> Bool {
        switch base {
        case .waist: sex != .female
        case .waistNarrow: sex == .female
        case .hip, .chest, .arm, .thigh: true
        case .neck: trackingMethod == .navy
        default: false
        }
    }

    /// The default sites with their side keys.
    public static func defaultSites(sex: Sex, trackingMethod: BodyMethod? = nil, side: BodySide = .right) -> [BodySite] {
        mainSites.filter { $0.isOnByDefault(sex: sex, trackingMethod: trackingMethod) }.flatMap { $0.sites(for: side) }
    }
}

/// Which side the tape goes on (chosen once).
public enum BodySide: String, CaseIterable, Codable, Sendable, Identifiable {
    case right, left, both

    public var id: String { rawValue }
}

/// Body numbers in one text field: tape values in cm ("waist=84.0;chest=101.5"), assessments in
/// kg and % ("bodyFat=20;leanKg=64;fatKg=16"), skinfolds in mm ("sf_chest=12"). Locale independent,
/// keys sorted, unknown keys kept (new sites never need a schema change).
public struct BodyValues: Equatable, Hashable, Sendable {
    public static let bodyFatKey = "bodyFat"
    public static let leanKey = "leanKg"
    public static let fatKey = "fatKg"
    public static let boneKey = "boneKg"

    public private(set) var storage: [String: Double]

    public init(_ values: [String: Double] = [:]) {
        storage = [:]
        for (key, value) in values { self[key] = value }
    }

    public init(_ sites: [BodySite: Double]) {
        self.init(Dictionary(uniqueKeysWithValues: sites.map { ($0.key.rawValue, $0.value) }))
    }

    public init(encoded: String) {
        let text = KeyValueText(encoded: encoded)
        storage = [:]
        for key in text.keys { self[key] = text.number(key) }
    }

    public var encoded: String {
        var text = KeyValueText()
        for (key, value) in storage { text.setNumber(value, for: key) }
        return text.encoded
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var keys: [String] { storage.keys.sorted() }

    public subscript(_ key: String) -> Double? {
        get { storage[KeyValueText.clean(key: key)] }
        set {
            let key = KeyValueText.clean(key: key)
            guard !key.isEmpty else { return }
            storage[key] = newValue.flatMap { $0.isFinite ? $0 : nil }
        }
    }

    public subscript(_ site: BodySite) -> Double? {
        get { self[site.rawValue] }
        set { self[site.rawValue] = newValue }
    }

    /// The tape values of known sites.
    public var sites: [BodySite: Double] {
        storage.reduce(into: [:]) { result, item in
            if let site = BodySite(rawValue: item.key) { result[site] = item.value }
        }
    }

    /// Percent.
    public var bodyFat: Double? {
        get { self[BodyValues.bodyFatKey] }
        set { self[BodyValues.bodyFatKey] = newValue }
    }

    public var leanKg: Double? {
        get { self[BodyValues.leanKey] }
        set { self[BodyValues.leanKey] = newValue }
    }

    public var fatKg: Double? {
        get { self[BodyValues.fatKey] }
        set { self[BodyValues.fatKey] = newValue }
    }

    public var boneKg: Double? {
        get { self[BodyValues.boneKey] }
        set { self[BodyValues.boneKey] = newValue }
    }
}

/// `BodyMeasurement.kind`.
public enum BodyRecordKind: String, CaseIterable, Codable, Sendable {
    /// Tape values in cm.
    case tape
    /// A body-fat assessment (method, %, optional lean, fat and bone kg).
    case assessment
}

/// How a body-fat value was measured. Each method (and each BIA device) is its own series; values
/// of different methods are never averaged or compared.
public enum BodyMethod: String, CaseIterable, Codable, Sendable, Identifiable {
    case dexa
    case bodpod
    case biaPro = "bia_pro"
    case scale
    case skinfold
    /// The US Navy tape estimate: computed live from tape values, never stored.
    case navy
    case estimate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dexa: "DEXA scan"
        case .bodpod: "Bod Pod"
        case .biaPro: "Professional BIA (InBody …)"
        case .scale: "Smart scale"
        case .skinfold: "Skinfold calipers"
        case .navy: "Tape estimate"
        case .estimate: "Estimate"
        }
    }

    /// Typical error in body-fat points (± band drawn around values); nil = unknown (estimate).
    /// DEXA repeats on the same machine are closer (±0.5–1).
    public var errorBand: Double? {
        switch self {
        case .dexa: 1.5
        case .bodpod: 2.5
        case .biaPro: 3
        case .skinfold: 3.5
        case .navy: 3.5
        case .scale: 4.5
        case .estimate: nil
        }
    }

    /// "±1.5", "±4–5", "unknown".
    public var errorText: String {
        switch self {
        case .scale: "±4–5"
        case .estimate: "unknown"
        default: "±" + NumberText.plain(errorBand ?? 0, decimals: 1)
        }
    }

    /// Most accurate first: dexa > bodpod > bia_pro > skinfold > navy > scale > estimate.
    public static let accuracyOrder: [BodyMethod] = [.dexa, .bodpod, .biaPro, .skinfold, .navy, .scale, .estimate]

    /// Position in `accuracyOrder` (0 = most accurate).
    public var accuracyRank: Int { BodyMethod.accuracyOrder.firstIndex(of: self) ?? BodyMethod.accuracyOrder.count }

    /// The default tracking method: the most accurate one with at least 2 values.
    public static func trackingDefault(counts: [BodyMethod: Int]) -> BodyMethod? {
        accuracyOrder.first { (counts[$0] ?? 0) >= 2 }
    }
}

/// The conditions of a reading (`BodyMeasurement.conditions`, comma tags). `morning,fasted` or
/// `later` are set automatically; the rest are exceptions the person can add.
public enum BodyCondition: String, CaseIterable, Codable, Sendable, Identifiable {
    case morning
    case fasted
    case later
    case afterTraining = "after_training"
    case lateHeavyMeal = "late_heavy_meal"
    case highSalt = "high_salt"
    case alcoholYesterday = "alcohol_yesterday"
    case sick
    /// Not offered to men.
    case menstrualPhase = "menstrual_phase"
    case notFasted = "not_fasted"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .morning: "Morning"
        case .fasted: "Before eating"
        case .later: "Later in the day"
        case .afterTraining: "After training"
        case .lateHeavyMeal: "Late heavy meal"
        case .highSalt: "Salty food"
        case .alcoholYesterday: "Alcohol yesterday"
        case .sick: "Ill"
        case .menstrualPhase: "Period"
        case .notFasted: "Not fasted"
        }
    }

    /// An exception tag (the person adds it; the reading isn't standard).
    public var isException: Bool {
        switch self {
        case .morning, .fasted, .later: false
        default: true
        }
    }

    /// The exception tags to offer.
    public static func exceptions(for sex: Sex) -> [BodyCondition] {
        allCases.filter { $0.isException && ($0 != .menstrualPhase || sex != .male) }
    }
}

/// The measuring protocol: what makes a reading comparable.
public enum BodyProtocol {
    /// Shown at the top of the measure sheet (fully the first time, collapsed after that).
    public static let checklist: [String] = [
        "Morning, after the toilet, before eating or drinking",
        "Before training (a pump adds 0.5–1 cm to arm, chest and thigh)",
        "Bare skin, relaxed",
        "Tape level (use a mirror), snug without pressing in",
        "Same spot, side and tape each time",
    ]

    /// The tags in a conditions text ("morning,fasted"), lowercased, in order, without repeats.
    public static func tags(_ conditions: String) -> [String] {
        var seen = Set<String>()
        return conditions.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func encode(_ conditions: [BodyCondition]) -> String {
        var seen = Set<BodyCondition>()
        return conditions.filter { seen.insert($0).inserted }.map(\.rawValue).joined(separator: ",")
    }

    /// The automatic tags: morning and fasted when measured before the morning cutoff with nothing
    /// eaten logged yet that day, otherwise later.
    public static func automatic(at time: Date, cutoffMinutes: Int, hasEaten: Bool, calendar: Calendar = .current) -> [BodyCondition] {
        ClockTime.minutes(of: time, calendar: calendar) < cutoffMinutes && !hasEaten ? [.morning, .fasted] : [.later]
    }

    /// A standard reading: morning and fasted with no other tag (an unknown tag counts as an
    /// exception). Only standard readings go into trends and goal maths by default.
    public static func isStandard(_ conditions: String) -> Bool {
        let tags = Set(tags(conditions))
        return tags == [BodyCondition.morning.rawValue, BodyCondition.fasted.rawValue]
    }

    public static func isStandard(_ conditions: [BodyCondition]) -> Bool { isStandard(encode(conditions)) }
}

/// Taking tape readings: two per site in a full set, a third when they differ by more than
/// 0.5 cm; the stored value is the mean of two or the median of three. Weekly sites get one
/// reading, and a second when it moved more than 1.0 cm since last time.
public enum BodyReadings {
    /// cm: two readings further apart than this ask for a third.
    public static let maxDifference = 0.5
    /// cm: a single reading that moved more than this since last time asks for a second.
    public static let recheckChange = 1.0
    /// cm within `jumpDays`: "Same spot as last time?".
    public static let jumpLimit = 3.0
    public static let jumpDays = 7

    private static let slack = 1e-9

    /// Whether to ask for another reading. `twoReadings`: the full-set rule (two, a third when
    /// they differ); otherwise one, and a second when it moved more than 1.0 cm from `previous`.
    public static func needsAnother(_ readings: [Double], twoReadings: Bool = true, previous: Double? = nil) -> Bool {
        switch readings.count {
        case 0:
            return true
        case 1:
            if twoReadings { return true }
            guard let previous else { return false }
            return abs(readings[0] - previous) > recheckChange + slack
        case 2:
            return abs(readings[0] - readings[1]) > maxDifference + slack
        default:
            return false
        }
    }

    /// The value to store: one reading as it is, the mean of two, the median of three or more
    /// (to 0.01 cm). nil without readings.
    public static func merged(_ readings: [Double]) -> Double? {
        let values = readings.filter(\.isFinite)
        guard !values.isEmpty else { return nil }
        let value: Double
        if values.count <= 2 {
            value = values.reduce(0, +) / Double(values.count)
        } else {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            value = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        return (value * 100).rounded() / 100
    }

    /// A change of more than 3 cm within 7 days: ask (without blocking) whether it was the same spot.
    public static func isSuspiciousJump(_ value: Double, previous: Double?, daysApart: Int) -> Bool {
        guard let previous, daysApart <= jumpDays else { return false }
        return abs(value - previous) > jumpLimit + slack
    }
}
