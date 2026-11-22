import Foundation

// Apple Health body data (spec F22). The app reads it live, keeps it in memory and never stores it
// (App Store guideline 5.1.3(ii)): not in a measurement, a day mark, the plan, a check-in or the
// profile. Here it becomes series of its own that sit next to Nina's records and are never merged
// into them: body fat (with lean mass) per source app, waist as one series, height as a hint.

/// One body value read live from Apple Health.
public struct HealthBodySample: Equatable, Sendable {
    public var date: Date
    /// Body fat in percent (Health's fraction × 100), lean mass in kg, waist and height in cm.
    public var value: Double
    /// The source app's bundle identifier: each source is its own body-fat series.
    public var sourceID: String
    /// The source app's name ("Withings").
    public var sourceName: String

    public init(date: Date, value: Double, sourceID: String, sourceName: String = "") {
        self.date = date
        self.value = value
        self.sourceID = sourceID
        self.sourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A source app that wrote body fat to Health, for the relabel list in Settings.
public struct HealthBodySource: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var count: Int
    public var latest: Date

    public init(id: String, name: String, count: Int, latest: Date) {
        self.id = id
        self.name = name
        self.count = count
        self.latest = latest
    }
}

/// The body fat (and lean mass) of one source app in Apple Health: its own series, never
/// averaged with or added to Nina's records.
public struct HealthBodyFatSeries: Equatable, Sendable, Identifiable {
    public var sourceID: String
    /// "Withings" ("Apple Health" when Health gave no name).
    public var sourceName: String
    /// `.scale` unless the person relabelled the source (device-only).
    public var method: BodyMethod
    /// One value per day (the first of the day), oldest first: the method, the source name as the
    /// device, and lean and fat kg when Health has lean mass from the same source at the same time.
    public var readings: [BodyFatReading]

    public init(sourceID: String, sourceName: String, method: BodyMethod, readings: [BodyFatReading]) {
        self.sourceID = sourceID
        self.sourceName = sourceName.isEmpty ? HealthBody.healthName : sourceName
        self.method = method
        self.readings = readings
    }

    /// "health:<bundle id>": never the id of one of Nina's own series.
    public var id: String { HealthBody.seriesID(sourceID) }
    public var count: Int { readings.count }
    public var first: BodyFatReading? { readings.first }
    public var latest: BodyFatReading? { readings.last }
    /// ± body-fat points of the method (nil = unknown).
    public var errorBand: Double? { method.errorBand }
    /// "Smart scale · Withings (Health)".
    public var title: String { "\(method.title) · \(sourceName) (Health)" }
}

/// Health body data for the body page, as read at the last refresh. Memory only.
public struct HealthBodySnapshot: Equatable, Sendable {
    /// One series per source app, most accurate method first.
    public var bodyFat: [HealthBodyFatSeries]
    /// Health's waist circumference, one reading per day (the latest of the day), oldest first.
    public var waist: [GirthReading]
    /// The newest height in Health (cm).
    public var heightCm: Double?

    public init(bodyFat: [HealthBodyFatSeries] = [], waist: [GirthReading] = [], heightCm: Double? = nil) {
        self.bodyFat = bodyFat
        self.waist = waist
        self.heightCm = heightCm
    }

    public static let empty = HealthBodySnapshot()

    public var isEmpty: Bool { bodyFat.isEmpty && waist.isEmpty && heightCm == nil }
    public var latestWaist: GirthReading? { waist.last }
}

public enum HealthBody {
    /// The method a Health source counts as until the person relabels it.
    public static let defaultMethod: BodyMethod = .scale
    /// What a source can be relabelled to: every method a device can measure (not the tape
    /// estimate, which Nina computes itself).
    public static var methods: [BodyMethod] { BodyMethod.allCases.filter { $0 != .navy } }
    /// The name used when Health gave a source none.
    public static let healthName = "Apple Health"
    /// Lean mass belongs to a body-fat value when the same source wrote it within 10 minutes.
    public static let leanPairingSeconds: TimeInterval = 600
    /// Values outside these ranges are dropped as typos or unit mix-ups.
    public static let bodyFatRange: ClosedRange<Double> = 2...75
    public static let leanRange: ClosedRange<Double> = 15...150
    public static let heightRange: ClosedRange<Double> = 100...250
    /// Shown with Health values on the body page.
    public static let liveNote = "Values marked Health are read live from Apple Health and never stored in Nina."

    public static func seriesID(_ sourceID: String) -> String { "health:" + sourceID }

    // MARK: Body fat and lean mass

    /// The body-fat series per source app. `bodyFat` in percent, `leanMass` in kg (any order);
    /// `labels`: source id → the method the person picked for it (missing = scale). Per source and
    /// day the first value counts (the morning one, like a weigh-in); its lean mass is the same
    /// source's value closest in time within `leanPairingSeconds`, and fat kg follows from lean
    /// and body fat, so the device's own split is used. Lean mass without a body-fat value is
    /// left out. Sorted most accurate method first, then the longer series, then by name.
    public static func bodyFatSeries(bodyFat: [HealthBodySample], leanMass: [HealthBodySample] = [],
                                     labels: [String: BodyMethod] = [:], dayStartHour: Int = 0,
                                     calendar: Calendar = .current) -> [HealthBodyFatSeries] {
        let valid = bodyFat.filter { $0.value.isFinite && bodyFatRange.contains($0.value) && !$0.sourceID.isEmpty }
        let lean = Dictionary(grouping: leanMass.filter { $0.value.isFinite && leanRange.contains($0.value) }, by: \.sourceID)
        var order: [String] = []
        var bySource: [String: [HealthBodySample]] = [:]
        for sample in valid {
            if bySource[sample.sourceID] == nil { order.append(sample.sourceID) }
            bySource[sample.sourceID, default: []].append(sample)
        }
        let series: [HealthBodyFatSeries] = order.map { source in
            let samples = (bySource[source] ?? []).sorted { $0.date < $1.date }
            let method = labels[source] ?? defaultMethod
            let name = samples.last { !$0.sourceName.isEmpty }?.sourceName ?? ""
            var seen = Set<DayKey>()
            var readings: [BodyFatReading] = []
            for sample in samples {
                let day = DayKey(date: sample.date, calendar: calendar, dayStartHour: dayStartHour)
                guard seen.insert(day).inserted else { continue }
                let leanKg = closest(to: sample.date, in: lean[source] ?? [])?.value
                var fatKg: Double?
                if let leanKg { fatKg = leanKg * sample.value / (100 - sample.value) }
                readings.append(BodyFatReading(day: day, time: sample.date, bodyFat: sample.value, method: method,
                                               device: name.isEmpty ? healthName : name, leanKg: leanKg, fatKg: fatKg))
            }
            return HealthBodyFatSeries(sourceID: source, sourceName: name, method: method, readings: readings)
        }
        return series.sorted { lhs, rhs in
            if lhs.method.accuracyRank != rhs.method.accuracyRank { return lhs.method.accuracyRank < rhs.method.accuracyRank }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.sourceName != rhs.sourceName { return lhs.sourceName < rhs.sourceName }
            return lhs.sourceID < rhs.sourceID
        }
    }

    /// The apps that wrote body fat, newest first, for relabelling.
    public static func sources(_ bodyFat: [HealthBodySample]) -> [HealthBodySource] {
        var result: [String: HealthBodySource] = [:]
        for sample in bodyFat.sorted(by: { $0.date < $1.date }) where !sample.sourceID.isEmpty {
            var source = result[sample.sourceID] ?? HealthBodySource(id: sample.sourceID, name: "", count: 0, latest: sample.date)
            source.count += 1
            source.latest = sample.date
            if !sample.sourceName.isEmpty { source.name = sample.sourceName }
            result[sample.sourceID] = source
        }
        return result.values.map { source in
            var named = source
            if named.name.isEmpty { named.name = healthName }
            return named
        }.sorted { lhs, rhs in lhs.latest != rhs.latest ? lhs.latest > rhs.latest : lhs.id < rhs.id }
    }

    private static func closest(to date: Date, in samples: [HealthBodySample]) -> HealthBodySample? {
        samples.filter { abs($0.date.timeIntervalSince(date)) <= leanPairingSeconds }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: Waist

    /// Health's waist circumference (cm, every source together) as its own series: one reading per
    /// day, the latest of the day (as tape readings), oldest first, plausible values only. Never
    /// mixed into the tape readings; changes are only computed within it.
    public static func waist(_ samples: [HealthBodySample], dayStartHour: Int = 0, calendar: Calendar = .current) -> [GirthReading] {
        var byDay: [DayKey: GirthReading] = [:]
        for sample in samples.sorted(by: { $0.date < $1.date }) where sample.value.isFinite && BodySite.waist.isPlausible(sample.value) {
            let day = DayKey(date: sample.date, calendar: calendar, dayStartHour: dayStartHour)
            byDay[day] = GirthReading(day: day, value: sample.value, time: sample.date, isStandard: true)
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// The change of the Health waist series since `since` (the phase start; nil = its first
    /// reading), judged against the waist's MDC like the tape.
    public static func waistChange(_ readings: [GirthReading], since: DayKey? = nil, calendar: Calendar = .current) -> GirthChange? {
        GirthTrend.change(.waist, readings: readings, since: since, calendar: calendar)
    }

    // MARK: Height

    /// The newest plausible height in Health (cm).
    public static func latestHeight(_ samples: [HealthBodySample]) -> Double? {
        samples.filter { $0.value.isFinite && heightRange.contains($0.value) }.max { $0.date < $1.date }?.value
    }

    /// The height to offer next to the profile's height field ("Health: 176 cm"): Health's
    /// height in whole cm, inside the field's range, when it differs from what the field shows
    /// (`profileCm` 0 = not set). nil = nothing to offer.
    public static func heightHint(health: Double?, profileCm: Double, range: ClosedRange<Double> = 120...230) -> Double? {
        guard let health, health.isFinite else { return nil }
        let rounded = health.rounded()
        guard range.contains(rounded) else { return nil }
        if profileCm > 0, profileCm.rounded() == rounded { return nil }
        return rounded
    }

    /// "Health: 176 cm".
    public static func heightHintText(_ centimeters: Double) -> String {
        "Health: \(NumberText.plain(centimeters, decimals: 0)) cm"
    }
}
