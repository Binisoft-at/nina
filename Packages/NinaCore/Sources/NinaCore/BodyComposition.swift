import Foundation

// Body composition (F7, F8) and girth trends (F6): the US Navy tape estimate, body-fat series per
// method and device, fat and lean mass from the weight around an assessment, FFMI, the long-term
// goal gap and goal rows, and what tape readings say over weeks. Everything is computed from the
// records and weights passed in; nothing here is stored.

// MARK: - Tape records

/// One tape session as Core sees it (a `BodyMeasurement` of kind tape): the day, the time, the
/// values in cm and the condition tags.
public struct BodyTapeRecord: Equatable, Sendable {
    public var day: DayKey
    public var time: Date?
    public var values: BodyValues
    /// Comma tags ("morning,fasted").
    public var conditions: String

    public init(day: DayKey, time: Date? = nil, values: BodyValues, conditions: String = "") {
        self.day = day
        self.time = time
        self.values = values
        self.conditions = conditions
    }

    /// Morning and fasted with no exception tag: the only readings in trends and goal maths by
    /// default.
    public var isStandard: Bool { BodyProtocol.isStandard(conditions) }

    /// Oldest first (by day, then time).
    static func sorted(_ records: [BodyTapeRecord]) -> [BodyTapeRecord] {
        records.enumerated().sorted { lhs, rhs in
            if lhs.element.day != rhs.element.day { return lhs.element.day < rhs.element.day }
            let l = lhs.element.time ?? .distantPast, r = rhs.element.time ?? .distantPast
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// One value of one site on one day.
public struct GirthReading: Equatable, Sendable, Codable {
    public var day: DayKey
    public var time: Date?
    /// cm
    public var value: Double
    public var isStandard: Bool

    public init(day: DayKey, value: Double, time: Date? = nil, isStandard: Bool = true) {
        self.day = day
        self.value = value
        self.time = time
        self.isStandard = isStandard
    }
}

// MARK: - US Navy tape estimate

/// The US Navy tape estimate of body fat (Hodgdon & Beckett), computed live from tape records,
/// height and sex. Never stored. Shown as "tape estimate ±3.5 points".
public enum NavyBodyFat {
    /// Which formula to use. People with sex "unspecified" are asked once; the answer is kept.
    public enum Formula: String, Codable, Sendable, CaseIterable, Identifiable {
        case male, female

        public var id: String { rawValue }

        /// nil for "unspecified" (ask which formula to use).
        public init?(sex: Sex) {
            switch sex {
            case .male: self = .male
            case .female: self = .female
            case .unspecified: return nil
            }
        }

        public var title: String { self == .male ? "Men's formula" : "Women's formula" }

        /// The waist site the formula uses: the navel waist for men, the narrow waist for women.
        public var waistSite: BodySite { self == .male ? .waist : .waistNarrow }

        /// Every site it needs: waist and neck (women: narrow waist, hip and neck).
        public var sites: [BodySite] { self == .male ? [.waist, .neck] : [.waistNarrow, .hip, .neck] }
    }

    /// The readings used for one estimate may be at most this many days apart (12 weeks).
    public static let maxApartDays = 84
    /// Body-fat points.
    public static let errorBand = 3.5
    public static let label = "tape estimate ±3.5 points"
    /// Shown when the height is missing.
    public static let heightNeeded = "needed for the tape estimate"
    /// Results outside this range (%) come from typos and are dropped.
    public static let plausibleRange: ClosedRange<Double> = 2...70

    /// Men: 495 / (1.0324 − 0.19077·log10(waist − neck) + 0.15456·log10(height)) − 450 (cm).
    public static func male(heightCm: Double, waistCm: Double, neckCm: Double) -> Double? {
        guard heightCm > 0, waistCm - neckCm > 0 else { return nil }
        return checked(495 / (1.0324 - 0.19077 * log10(waistCm - neckCm) + 0.15456 * log10(heightCm)) - 450)
    }

    /// Women: 495 / (1.29579 − 0.35004·log10(narrow waist + hip − neck) + 0.22100·log10(height)) − 450 (cm).
    public static func female(heightCm: Double, waistCm: Double, hipCm: Double, neckCm: Double) -> Double? {
        guard heightCm > 0, waistCm + hipCm - neckCm > 0 else { return nil }
        return checked(495 / (1.29579 - 0.35004 * log10(waistCm + hipCm - neckCm) + 0.22100 * log10(heightCm)) - 450)
    }

    /// Percent, unrounded; nil for impossible input or an implausible result.
    public static func bodyFat(_ formula: Formula, heightCm: Double, waistCm: Double, neckCm: Double, hipCm: Double = 0) -> Double? {
        switch formula {
        case .male: male(heightCm: heightCm, waistCm: waistCm, neckCm: neckCm)
        case .female: female(heightCm: heightCm, waistCm: waistCm, hipCm: hipCm, neckCm: neckCm)
        }
    }

    private static func checked(_ value: Double) -> Double? {
        value.isFinite && plausibleRange.contains(value) ? value : nil
    }

    /// One tape estimate and the readings behind it.
    public struct Estimate: Equatable, Sendable, Codable {
        /// The day of the waist reading.
        public var day: DayKey
        /// Percent, unrounded.
        public var bodyFat: Double
        public var formula: Formula
        public var heightCm: Double
        public var waistCm: Double
        public var neckCm: Double
        public var neckDay: DayKey
        /// Women only.
        public var hipCm: Double?
        public var hipDay: DayKey?

        public init(day: DayKey, bodyFat: Double, formula: Formula, heightCm: Double, waistCm: Double, neckCm: Double,
                    neckDay: DayKey, hipCm: Double? = nil, hipDay: DayKey? = nil) {
            self.day = day
            self.bodyFat = bodyFat
            self.formula = formula
            self.heightCm = heightCm
            self.waistCm = waistCm
            self.neckCm = neckCm
            self.neckDay = neckDay
            self.hipCm = hipCm
            self.hipDay = hipDay
        }
    }

    /// Whether the estimate can be shown, and what is missing otherwise (checked in this order).
    public enum Availability: Equatable, Sendable {
        case available(Estimate)
        /// Height is 0: "needed for the tape estimate".
        case needsHeight
        /// Sex is unspecified and no formula was chosen yet.
        case needsFormula
        /// These sites have no reading within 12 weeks of the others (in `Formula.sites` order).
        case needsSites([BodySite])
        /// The readings give no plausible value (a typo?).
        case implausible

        public var estimate: Estimate? {
            if case .available(let estimate) = self { return estimate }
            return nil
        }
    }

    /// The estimate from the latest waist reading on or before `day` (default: the latest one),
    /// with the neck (and hip) reading nearest to it: the latest one before it, else the first one
    /// after it; all within 12 weeks of each other. Standard readings only unless
    /// `includeNonStandard`.
    public static func estimate(formula: Formula?, heightCm: Double, records: [BodyTapeRecord], on day: DayKey? = nil,
                                includeNonStandard: Bool = false, calendar: Calendar = .current) -> Availability {
        guard heightCm > 0 else { return .needsHeight }
        guard let formula else { return .needsFormula }
        let usable = day.map { limit in records.filter { $0.day <= limit } } ?? records
        let waists = GirthTrend.readings(formula.waistSite, in: usable, includeNonStandard: includeNonStandard)
        guard let waist = waists.last else {
            let others = formula.sites.filter { $0 != formula.waistSite }
                .filter { GirthTrend.readings($0, in: usable, includeNonStandard: includeNonStandard).isEmpty }
            return .needsSites([formula.waistSite] + others)
        }
        return estimate(formula: formula, heightCm: heightCm, waist: waist, records: usable,
                        includeNonStandard: includeNonStandard, calendar: calendar)
    }

    /// One estimate per day with a waist reading (the tape-estimate series), oldest first.
    public static func series(formula: Formula?, heightCm: Double, records: [BodyTapeRecord], includeNonStandard: Bool = false,
                              calendar: Calendar = .current) -> [Estimate] {
        guard let formula, heightCm > 0 else { return [] }
        return GirthTrend.readings(formula.waistSite, in: records, includeNonStandard: includeNonStandard).compactMap {
            estimate(formula: formula, heightCm: heightCm, waist: $0, records: records, includeNonStandard: includeNonStandard,
                     calendar: calendar).estimate
        }
    }

    private static func estimate(formula: Formula, heightCm: Double, waist: GirthReading, records: [BodyTapeRecord],
                                 includeNonStandard: Bool, calendar: Calendar) -> Availability {
        func nearest(_ site: BodySite) -> GirthReading? {
            let readings = GirthTrend.readings(site, in: records, includeNonStandard: includeNonStandard)
            if let before = readings.last(where: { $0.day <= waist.day }),
               before.day.days(to: waist.day, calendar: calendar) <= maxApartDays {
                return before
            }
            return readings.first { $0.day > waist.day && waist.day.days(to: $0.day, calendar: calendar) <= maxApartDays }
        }
        let neck = nearest(.neck)
        let hip = formula == .female ? nearest(.hip) : nil
        var missing: [BodySite] = []
        if neck == nil { missing.append(.neck) }
        if formula == .female, hip == nil { missing.append(.hip) }
        guard missing.isEmpty, let neck else {
            return .needsSites(formula.sites.filter { missing.contains($0) })
        }
        let days = [waist.day, neck.day] + (hip.map { [$0.day] } ?? [])
        if let first = days.min(), let last = days.max(), first.days(to: last, calendar: calendar) > maxApartDays {
            return .needsSites(formula.sites.filter { $0 != formula.waistSite })
        }
        guard let value = bodyFat(formula, heightCm: heightCm, waistCm: waist.value, neckCm: neck.value, hipCm: hip?.value ?? 0)
        else { return .implausible }
        return .available(Estimate(day: waist.day, bodyFat: value, formula: formula, heightCm: heightCm, waistCm: waist.value,
                                   neckCm: neck.value, neckDay: neck.day, hipCm: hip?.value, hipDay: hip?.day))
    }
}

// MARK: - Body-fat readings and series

/// A body-fat value from any source: an assessment record, a weigh-in's body fat, or a tape
/// estimate.
public struct BodyFatReading: Equatable, Sendable, Codable {
    public var day: DayKey
    public var time: Date?
    /// Percent.
    public var bodyFat: Double
    public var method: BodyMethod
    /// "InBody 570": each device is its own series ("" = unnamed).
    public var device: String
    /// kg from the device (DEXA lean excludes bone).
    public var leanKg: Double?
    public var fatKg: Double?
    public var boneKg: Double?
    /// The weight that came with the value (a weigh-in's kg); used when no morning weights are around.
    public var weightKg: Double?
    /// From a weigh-in (`WeightEntry.bodyFat`): the "Weigh-in body fat" series.
    public var isWeighIn: Bool

    public init(day: DayKey, time: Date? = nil, bodyFat: Double, method: BodyMethod, device: String = "",
                leanKg: Double? = nil, fatKg: Double? = nil, boneKg: Double? = nil, weightKg: Double? = nil, isWeighIn: Bool = false) {
        self.day = day
        self.time = time
        self.bodyFat = bodyFat
        self.method = method
        self.device = device.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leanKg = leanKg.flatMap { $0 > 0 ? $0 : nil }
        self.fatKg = fatKg.flatMap { $0 > 0 ? $0 : nil }
        self.boneKg = boneKg.flatMap { $0 > 0 ? $0 : nil }
        self.weightKg = weightKg.flatMap { $0 > 0 ? $0 : nil }
        self.isWeighIn = isWeighIn
    }

    /// From an assessment record's values (`bodyFat`, `leanKg`, `fatKg`, `boneKg`). Without a
    /// body-fat value it is computed from fat ÷ (fat + lean + bone); nil when neither is there.
    public init?(assessmentOn day: DayKey, time: Date? = nil, method: BodyMethod, device: String = "", values: BodyValues) {
        var percent = values.bodyFat.flatMap { $0 > 0 ? $0 : nil }
        if percent == nil, let fat = values.fatKg, let lean = values.leanKg, fat > 0, lean > 0 {
            percent = fat / (fat + lean + max(0, values.boneKg ?? 0)) * 100
        }
        guard let percent else { return nil }
        self.init(day: day, time: time, bodyFat: percent, method: method, device: device, leanKg: values.leanKg,
                  fatKg: values.fatKg, boneKg: values.boneKg)
    }

    /// A weigh-in with body fat ("Weigh-in body fat": a smart scale, device unspecified); nil
    /// when no body fat was measured (0).
    public static func weighIn(day: DayKey, time: Date? = nil, kilograms: Double, bodyFat: Double) -> BodyFatReading? {
        guard bodyFat > 0 else { return nil }
        return BodyFatReading(day: day, time: time, bodyFat: bodyFat, method: .scale, weightKg: kilograms, isWeighIn: true)
    }

    /// A tape estimate as a reading of the tape-estimate series.
    public init(navy estimate: NavyBodyFat.Estimate) {
        self.init(day: estimate.day, bodyFat: estimate.bodyFat, method: .navy)
    }

    public var seriesKey: BodyFatSeriesKey { BodyFatSeriesKey(method: method, device: device, isWeighIn: isWeighIn) }
}

/// What makes a series: the method, the device (case-insensitive) and whether the values came
/// from weigh-ins. Values of different series are never averaged or compared.
public struct BodyFatSeriesKey: Hashable, Sendable, Codable, Identifiable {
    public var method: BodyMethod
    /// Lowercased.
    public var device: String
    public var isWeighIn: Bool

    public init(method: BodyMethod, device: String = "", isWeighIn: Bool = false) {
        self.method = method
        self.device = device.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.isWeighIn = isWeighIn
    }

    /// "dexa", "bia_pro:inbody 570", "scale:weigh-in".
    public var id: String {
        if isWeighIn { return "\(method.rawValue):weigh-in" }
        return device.isEmpty ? method.rawValue : "\(method.rawValue):\(device)"
    }
}

/// The values of one method (and device), oldest first.
public struct BodyFatSeries: Equatable, Sendable, Identifiable {
    public var key: BodyFatSeriesKey
    public var readings: [BodyFatReading]

    public init(key: BodyFatSeriesKey, readings: [BodyFatReading]) {
        self.key = key
        self.readings = BodyFatSeries.sorted(readings)
    }

    public var id: String { key.id }
    public var method: BodyMethod { key.method }
    public var count: Int { readings.count }
    public var first: BodyFatReading? { readings.first }
    public var latest: BodyFatReading? { readings.last }
    /// ± body-fat points (nil = unknown).
    public var errorBand: Double? { method.errorBand }

    /// "DEXA scan", "Professional BIA (InBody …) · InBody 570", "Weigh-in body fat".
    public var title: String {
        if key.isWeighIn { return "Weigh-in body fat" }
        let device = readings.last { !$0.device.isEmpty }?.device ?? ""
        return device.isEmpty ? method.title : "\(method.title) · \(device)"
    }

    /// Shown when the values switch to another series.
    public static let newSeriesNote = "new series – compare like with like"
    /// Shown once, when the first body-fat value is added.
    public static let firstUseTip = "Pick one method you can repeat every 8 weeks under the same conditions. The tape estimate is "
        + "free and works weekly. A DEXA is best repeated on the same machine, fasted, in the morning."

    /// The readings split into series: most accurate method first, assessments before weigh-ins,
    /// then the longer series, then by device name.
    public static func group(_ readings: [BodyFatReading]) -> [BodyFatSeries] {
        var order: [BodyFatSeriesKey] = []
        var byKey: [BodyFatSeriesKey: [BodyFatReading]] = [:]
        for reading in readings where reading.bodyFat.isFinite && reading.bodyFat > 0 {
            let key = reading.seriesKey
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(reading)
        }
        return order.map { BodyFatSeries(key: $0, readings: byKey[$0] ?? []) }.sorted { lhs, rhs in
            if lhs.method.accuracyRank != rhs.method.accuracyRank { return lhs.method.accuracyRank < rhs.method.accuracyRank }
            if lhs.key.isWeighIn != rhs.key.isWeighIn { return !lhs.key.isWeighIn }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.key.device < rhs.key.device
        }
    }

    /// The series that drives goal progress. With a tracking method (`routine.bodyFatMethod`): its
    /// longest series (nil when there is none yet). Without one: the most accurate series with at
    /// least 2 values (dexa > bodpod > bia_pro > skinfold > navy > scale > estimate); while no
    /// series has 2 values yet, the most accurate one with a value, so a baseline shows.
    public static func tracking(_ series: [BodyFatSeries], method: BodyMethod?) -> BodyFatSeries? {
        func best(_ list: [BodyFatSeries]) -> BodyFatSeries? {
            list.min { lhs, rhs in
                if lhs.method.accuracyRank != rhs.method.accuracyRank { return lhs.method.accuracyRank < rhs.method.accuracyRank }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                let l = lhs.latest?.day.rawValue ?? "", r = rhs.latest?.day.rawValue ?? ""
                if l != r { return l > r }
                return lhs.key.isWeighIn ? false : rhs.key.isWeighIn
            }
        }
        let filled = series.filter { $0.count > 0 }
        if let method { return best(filled.filter { $0.method == method }) }
        return best(filled.filter { $0.count >= 2 }) ?? best(filled)
    }

    static func sorted(_ readings: [BodyFatReading]) -> [BodyFatReading] {
        readings.enumerated().sorted { lhs, rhs in
            if lhs.element.day != rhs.element.day { return lhs.element.day < rhs.element.day }
            let l = lhs.element.time ?? .distantPast, r = rhs.element.time ?? .distantPast
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: - Fat and lean mass

/// Weight split into fat mass and fat-free ("lean") mass.
public struct BodyComposition: Equatable, Sendable, Codable {
    public var weightKg: Double
    /// Percent.
    public var bodyFat: Double
    /// Fat mass (FM).
    public var fatKg: Double
    /// Fat-free mass (FFM): everything that isn't fat, bone included.
    public var leanKg: Double
    /// Lean and fat kg came from the device (DEXA, InBody) rather than weight × body fat.
    public var isMeasured: Bool

    /// FM = W × BF ÷ 100; FFM = W − FM.
    public init(weightKg: Double, bodyFat: Double) {
        self.weightKg = weightKg
        self.bodyFat = bodyFat
        fatKg = weightKg * bodyFat / 100
        leanKg = weightKg - fatKg
        isMeasured = false
    }

    /// From the device's own kg: FFM = lean + bone (DEXA lean excludes bone). The body fat is the
    /// device's value when given, else fat ÷ (fat + FFM).
    public init(fatKg: Double, leanKg: Double, boneKg: Double? = nil, bodyFat: Double? = nil) {
        self.fatKg = fatKg
        self.leanKg = leanKg + max(0, boneKg ?? 0)
        weightKg = self.fatKg + self.leanKg
        self.bodyFat = bodyFat.flatMap { $0 > 0 ? $0 : nil } ?? (weightKg > 0 ? self.fatKg / weightKg * 100 : 0)
        isMeasured = true
    }

    /// A reading's composition: the device's lean and fat kg when it gave both, else the weight
    /// split by the body fat (nil without a weight).
    public init?(reading: BodyFatReading, weightKg: Double?) {
        if let fat = reading.fatKg, let lean = reading.leanKg {
            self.init(fatKg: fat, leanKg: lean, boneKg: reading.boneKg, bodyFat: reading.bodyFat)
            return
        }
        guard let weightKg, weightKg > 0, reading.bodyFat > 0 else { return nil }
        self.init(weightKg: weightKg, bodyFat: reading.bodyFat)
    }

    /// Fat-free mass index: FFM ÷ height (m)².
    public static func ffmi(leanKg: Double, heightCm: Double) -> Double? {
        guard leanKg > 0, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return leanKg / (meters * meters)
    }

    /// FFMI normalised to 1.8 m: FFMI + 6.1 × (1.8 − height in m).
    public static func normalisedFFMI(leanKg: Double, heightCm: Double) -> Double? {
        ffmi(leanKg: leanKg, heightCm: heightCm).map { $0 + 6.1 * (1.8 - heightCm / 100) }
    }

    public func ffmi(heightCm: Double) -> Double? { BodyComposition.ffmi(leanKg: leanKg, heightCm: heightCm) }
    public func normalisedFFMI(heightCm: Double) -> Double? { BodyComposition.normalisedFFMI(leanKg: leanKg, heightCm: heightCm) }

    /// Shown once during a gain phase.
    public static let glycogenNote = "Part of the measured lean gain is glycogen and water (about 3 g of water per gram of "
        + "carbohydrate). Compare after similar carb days."
}

/// The weight used to split a body-fat value into fat and lean mass.
public struct CompositionWeight: Equatable, Sendable, Codable {
    public enum Source: String, Codable, Sendable {
        /// The mean of the morning weights around the day.
        case morningAverage
        /// The EMA trend weight on the day.
        case trend
        /// A typed weight (the weigh-in that came with the value, or the latest one).
        case typed
    }

    public var kg: Double
    public var source: Source
    /// Morning weights in the mean (0 for the other sources).
    public var count: Int

    public init(kg: Double, source: Source, count: Int = 0) {
        self.kg = kg
        self.source = source
        self.count = count
    }
}

/// A body-fat reading with its weight and composition.
public struct BodyCompositionPoint: Equatable, Sendable, Codable {
    public var reading: BodyFatReading
    /// nil when the device gave lean and fat kg.
    public var weight: CompositionWeight?
    public var composition: BodyComposition

    public init(reading: BodyFatReading, weight: CompositionWeight?, composition: BodyComposition) {
        self.reading = reading
        self.weight = weight
        self.composition = composition
    }

    public var day: DayKey { reading.day }
}

extension BodyComposition {
    /// Days on each side of the day in the morning-weight mean.
    public static let weightWindowDays = 3
    /// Morning weights the mean needs.
    public static let minimumWeighIns = 3

    /// The weight for a body-fat value on `day`: the mean of the morning weights from 3 days before
    /// to 3 days after (while those later days haven't all happened yet: the 7 days ending on
    /// `day`), with at least 3; otherwise the EMA trend on that day (`trend`, or computed from the
    /// morning weights); otherwise `typed`.
    public static func weight(on day: DayKey, morningWeights: [DayKey: Double], today: DayKey, trend: Double? = nil,
                              typed: Double? = nil, calendar: Calendar = .current) -> CompositionWeight? {
        let window = weightWindowDays
        let end = day.adding(days: window, calendar: calendar)
        let first = end <= today ? day.adding(days: -window, calendar: calendar) : day.adding(days: -(2 * window), calendar: calendar)
        let last = end <= today ? end : day
        let values = morningWeights.filter { $0.key >= first && $0.key <= last && $0.value > 0 && $0.value.isFinite }.map(\.value)
        if values.count >= minimumWeighIns {
            return CompositionWeight(kg: values.reduce(0, +) / Double(values.count), source: .morningAverage, count: values.count)
        }
        if let trend = trend ?? trendWeight(on: day, morningWeights: morningWeights, calendar: calendar), trend > 0 {
            return CompositionWeight(kg: trend, source: .trend)
        }
        if let typed, typed > 0 { return CompositionWeight(kg: typed, source: .typed) }
        return nil
    }

    /// The EMA trend weight on a day (carried forward after the last weigh-in; nil before the first).
    static func trendWeight(on day: DayKey, morningWeights: [DayKey: Double], calendar: Calendar) -> Double? {
        let earlier = morningWeights.filter { $0.key <= day && $0.value > 0 && $0.value.isFinite }
        return Insights.weightTrend(earlier, through: day, calendar: calendar).last { $0.day == day }?.trend
    }

    /// Each reading with its composition (readings without a usable weight are left out). The
    /// typed fallback is the weight that came with the reading, else `typedWeight`.
    public static func points(_ readings: [BodyFatReading], morningWeights: [DayKey: Double], today: DayKey,
                              typedWeight: Double? = nil, calendar: Calendar = .current) -> [BodyCompositionPoint] {
        BodyFatSeries.sorted(readings).compactMap { reading in
            if reading.fatKg != nil, reading.leanKg != nil, let composition = BodyComposition(reading: reading, weightKg: nil) {
                return BodyCompositionPoint(reading: reading, weight: nil, composition: composition)
            }
            guard let weight = weight(on: reading.day, morningWeights: morningWeights, today: today,
                                      typed: reading.weightKg ?? typedWeight, calendar: calendar),
                  let composition = BodyComposition(reading: reading, weightKg: weight.kg) else { return nil }
            return BodyCompositionPoint(reading: reading, weight: weight, composition: composition)
        }
    }
}

// MARK: - Changes within a series

extension BodyMethod {
    /// kg: a lean (or fat) mass change smaller than this is "within measurement error" (DEXA about
    /// 0.5 kg, Bod Pod and professional BIA about 1 kg, the tape estimate, scales and the rest
    /// about 1.5 kg).
    public var leanNoiseKg: Double {
        switch self {
        case .dexa: 0.5
        case .bodpod, .biaPro: 1.0
        case .skinfold, .navy, .scale, .estimate: 1.5
        }
    }
}

/// How much of a weight gain was lean mass: 50 % or more is good; below 30 % the check-in suggests
/// the low end of the rate range.
public enum LeanShareRating: String, Codable, Sendable, CaseIterable {
    case good, fair, low

    public static let goodShare = 0.5
    public static let lowShare = 0.3

    /// `share` as a fraction (0.5 = 50 %).
    public init(share: Double) {
        if share >= LeanShareRating.goodShare { self = .good }
        else if share >= LeanShareRating.lowShare { self = .fair }
        else { self = .low }
    }

    public var suggestsLowEndOfRate: Bool { self == .low }
}

/// The change between two values of one series (Δ weight, Δ FM, Δ FFM).
public struct CompositionChange: Equatable, Sendable {
    public var from: BodyComposition
    public var to: BodyComposition
    public var method: BodyMethod

    /// The lean share needs at least this much weight gained (kg), else it's noise.
    public static let minimumGainForShare = 0.5
    public static let withinErrorText = "within measurement error"

    public init(from: BodyComposition, to: BodyComposition, method: BodyMethod) {
        self.from = from
        self.to = to
        self.method = method
    }

    /// nil when the points belong to different series ("new series – compare like with like").
    public init?(from: BodyCompositionPoint, to: BodyCompositionPoint) {
        guard from.reading.seriesKey == to.reading.seriesKey else { return nil }
        self.init(from: from.composition, to: to.composition, method: from.reading.method)
    }

    public var weight: Double { to.weightKg - from.weightKg }
    public var fat: Double { to.fatKg - from.fatKg }
    public var lean: Double { to.leanKg - from.leanKg }
    /// Body-fat points.
    public var bodyFat: Double { to.bodyFat - from.bodyFat }

    public var noiseKg: Double { method.leanNoiseKg }
    public var isLeanWithinError: Bool { abs(lean) < noiseKg - 1e-9 }
    public var isFatWithinError: Bool { abs(fat) < noiseKg - 1e-9 }

    /// ΔFFM ÷ Δweight (a fraction) for a gain of at least 0.5 kg; nil otherwise.
    public var leanShare: Double? {
        guard weight >= CompositionChange.minimumGainForShare - 1e-9 else { return nil }
        return lean / weight
    }

    public var leanShareRating: LeanShareRating? { leanShare.map(LeanShareRating.init(share:)) }
}

// MARK: - Long-term goal

/// How far the long-term goal is from today's composition.
public struct BodyGoalGap: Equatable, Sendable, Codable {
    /// kg (0 = none).
    public var goalWeight: Double
    /// Percent (0 = none).
    public var goalBodyFat: Double
    /// Goal weight × goal body fat (needs both).
    public var targetFatKg: Double?
    public var targetLeanKg: Double?
    /// Target FFM − FFM now: + = lean mass to gain.
    public var leanToGo: Double?
    /// Target FM − FM now: − = fat to lose.
    public var fatToGo: Double?
    /// Goal weight − weight now.
    public var weightToGo: Double?
    /// The weight at the goal body fat with today's lean mass: FFM ÷ (1 − BF goal).
    public var weightAtGoalBodyFat: Double?

    /// Lean gain below this isn't worth an "it depends on lean mass" line.
    public static let leanLineMinimum = 0.5

    /// nil when the goal has neither a weight nor a body fat.
    public init?(goal: CoachPlan.LongTerm, now: BodyComposition) {
        guard goal.weightKg > 0 || goal.bodyFat > 0 else { return nil }
        goalWeight = max(0, goal.weightKg)
        goalBodyFat = max(0, goal.bodyFat)
        if goalWeight > 0 { weightToGo = goalWeight - now.weightKg }
        if goalBodyFat > 0, goalBodyFat < 100 { weightAtGoalBodyFat = now.leanKg / (1 - goalBodyFat / 100) }
        if goalWeight > 0, goalBodyFat > 0 {
            let fat = goalWeight * goalBodyFat / 100
            targetFatKg = fat
            targetLeanKg = goalWeight - fat
            leanToGo = goalWeight - fat - now.leanKg
            fatToGo = fat - now.fatKg
        }
    }

    /// Reaching the goal needs lean mass gained (at least 0.5 kg).
    public var dependsOnLeanGain: Bool { (leanToGo ?? 0) >= BodyGoalGap.leanLineMinimum - 1e-9 }

    /// "Reaching 78 kg at 14 % depends on gaining about 3 kg of lean mass." (kg to the nearest 0.5).
    public var honestLine: String? {
        guard dependsOnLeanGain, let lean = leanToGo else { return nil }
        let rounded = max(0.5, (lean * 2).rounded() / 2)
        return "Reaching \(NumberText.plain(goalWeight, decimals: 1)) kg at \(NumberText.plain(goalBodyFat, decimals: 1)) % "
            + "depends on gaining about \(NumberText.plain(rounded, decimals: 1)) kg of lean mass."
    }
}

/// Whether the lean mass still to gain fits the time: trained people usually gain 0.25–0.5 kg of
/// lean mass per month. When the goal date needs more, "goal date likely later (~month)" — a hint,
/// never an error.
public struct LeanGainOutlook: Equatable, Sendable, Codable {
    public static let usualPerMonth: ClosedRange<Double> = 0.25...0.5
    public static let daysPerMonth = 30.44

    public var leanToGo: Double
    /// At the fast end (0.5 kg a month).
    public var monthsFast: Double
    /// At the slow end (0.25 kg a month).
    public var monthsSlow: Double
    /// At the middle of the usual range: the "~month" shown.
    public var likelyDay: DayKey
    public var earliestDay: DayKey
    public var latestDay: DayKey
    /// kg a month the goal date asks for (nil without a goal date in the future).
    public var neededPerMonth: Double?
    public var isGoalDateLikelyLater: Bool

    /// nil when no lean mass is left to gain.
    public init?(leanToGo: Double, today: DayKey, goalDate: DayKey? = nil, perMonth: ClosedRange<Double> = LeanGainOutlook.usualPerMonth,
                 calendar: Calendar = .current) {
        guard leanToGo > 0, perMonth.lowerBound > 0 else { return nil }
        self.leanToGo = leanToGo
        monthsFast = leanToGo / perMonth.upperBound
        monthsSlow = leanToGo / perMonth.lowerBound
        let middle = (perMonth.lowerBound + perMonth.upperBound) / 2
        func day(months: Double) -> DayKey { today.adding(days: Int((months * LeanGainOutlook.daysPerMonth).rounded()), calendar: calendar) }
        likelyDay = day(months: leanToGo / middle)
        earliestDay = day(months: monthsFast)
        latestDay = day(months: monthsSlow)
        if let goalDate {
            let days = today.days(to: goalDate, calendar: calendar)
            neededPerMonth = days > 0 ? leanToGo / (Double(days) / LeanGainOutlook.daysPerMonth) : nil
            isGoalDateLikelyLater = days <= 0 || (neededPerMonth ?? 0) > perMonth.upperBound + 1e-9
        } else {
            neededPerMonth = nil
            isGoalDateLikelyLater = false
        }
    }

    /// "goal date likely later (~Sep 2031)"; nil when the date fits or there is none.
    public var text: String? {
        isGoalDateLikelyLater ? "goal date likely later (~\(BodyCompositionText.month(likelyDay)))" : nil
    }
}

/// One row of the body goal card: start, now and target, with a bar.
public struct BodyGoalRow: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lean, fat, bodyFat

        public var title: String {
            switch self {
            case .lean: "Lean mass"
            case .fat: "Fat mass"
            case .bodyFat: "Body fat"
            }
        }

        public var unit: String { self == .bodyFat ? "%" : "kg" }
    }

    public var kind: Kind
    public var start: Double
    public var now: Double
    public var target: Double
    /// The body-fat row: the tracking method's ± band (nil = unknown).
    public var errorBand: Double?

    public init(kind: Kind, start: Double, now: Double, target: Double, errorBand: Double? = nil) {
        self.kind = kind
        self.start = start
        self.now = now
        self.target = target
        self.errorBand = errorBand
    }

    public var id: String { kind.rawValue }

    private static let slack = 0.05

    /// now − start.
    public var change: Double { now - start }
    /// target − start.
    public var needed: Double { target - start }

    /// Moved the other way than the target lies.
    public var isMovedAway: Bool {
        if abs(needed) < BodyGoalRow.slack { return abs(now - target) >= BodyGoalRow.slack }
        return change * needed < 0 && abs(change) >= BodyGoalRow.slack
    }

    /// Share of the way from start to target, clamped to 0…1 for the bar.
    public var progress: Double {
        if abs(needed) < BodyGoalRow.slack { return isMovedAway ? 0 : 1 }
        return min(1, max(0, change / needed))
    }

    /// "+1.2 of +3.1 kg", "−0.3 kg (moved away)", "at goal".
    public var text: String {
        let unit = kind.unit
        if isMovedAway { return "\(BodyCompositionText.signed(change)) \(unit) (moved away)" }
        if abs(needed) < BodyGoalRow.slack { return "at goal" }
        return "\(BodyCompositionText.signed(change)) of \(BodyCompositionText.signed(needed)) \(unit)"
    }
}

/// The 7-day average against the phase target and the long-term goal.
public struct BodyGoalWeightRow: Equatable, Sendable, Codable {
    public var now: Double
    /// 0 = none.
    public var phaseTarget: Double
    /// 0 = none.
    public var longTermTarget: Double

    public init(now: Double, phaseTarget: Double, longTermTarget: Double) {
        self.now = now
        self.phaseTarget = phaseTarget
        self.longTermTarget = longTermTarget
    }

    public var toPhaseTarget: Double? { phaseTarget > 0 ? phaseTarget - now : nil }
    public var toLongTerm: Double? { longTermTarget > 0 ? longTermTarget - now : nil }
}

/// The body goal card (Progress; compact in Insights): lean mass, fat mass and body fat rows from
/// the tracking series, the gap and a phase caption.
public struct BodyGoalCard: Equatable, Sendable {
    /// The first value of the tracking series on or after the goal was set (else the last one
    /// before it).
    public var start: BodyCompositionPoint?
    /// The latest value of the tracking series.
    public var now: BodyCompositionPoint?
    public var rows: [BodyGoalRow]
    public var gap: BodyGoalGap?
    public var caption: String?

    public static let emptyText = "Do your baseline check"

    /// `points`: the tracking series' compositions. `goalSetOn`: when the long-term goal was set
    /// (nil = from the first value). `phaseGoal`: the active phase's goal (for the caption).
    public init(goal: CoachPlan.LongTerm, points: [BodyCompositionPoint], goalSetOn: DayKey? = nil, phaseGoal: WeightGoal? = nil) {
        let sorted = points.sorted { $0.day < $1.day }
        let now = sorted.last
        let start = goalSetOn.flatMap { day in sorted.first { $0.day >= day } ?? sorted.last { $0.day < day } } ?? sorted.first
        self.start = start
        self.now = now
        caption = BodyGoalCard.caption(for: phaseGoal)
        guard let start, let now else {
            rows = []
            gap = nil
            return
        }
        gap = BodyGoalGap(goal: goal, now: now.composition)
        var rows: [BodyGoalRow] = []
        if goal.weightKg > 0, goal.bodyFat > 0 {
            let targetFat = goal.weightKg * goal.bodyFat / 100
            rows.append(BodyGoalRow(kind: .lean, start: start.composition.leanKg, now: now.composition.leanKg,
                                    target: goal.weightKg - targetFat))
            rows.append(BodyGoalRow(kind: .fat, start: start.composition.fatKg, now: now.composition.fatKg, target: targetFat))
        }
        if goal.bodyFat > 0 {
            rows.append(BodyGoalRow(kind: .bodyFat, start: start.composition.bodyFat, now: now.composition.bodyFat,
                                    target: goal.bodyFat, errorBand: now.reading.method.errorBand))
        }
        self.rows = rows
    }

    /// No value in the tracking series yet: "Do your baseline check".
    public var isEmpty: Bool { now == nil }

    /// Gain: "Watch lean mass – a little fat gain is expected"; loss: "Watch fat mass – keep lean
    /// mass"; otherwise none.
    public static func caption(for goal: WeightGoal?) -> String? {
        switch goal {
        case .gain: "Watch lean mass – a little fat gain is expected"
        case .lose: "Watch fat mass – keep lean mass"
        default: nil
        }
    }
}

/// What can be wrong with a long-term goal.
public enum BodyGoalIssue: String, Codable, Sendable, CaseIterable, Identifiable {
    case bodyFatOutOfRange, weightOutOfRange, waistOutOfRange
    /// A soft warning: below 8 % (men) or 15 % (women).
    case contestLevel

    public var id: String { rawValue }
    public var isWarning: Bool { self == .contestLevel }

    public var message: String {
        switch self {
        case .bodyFatOutOfRange: "Body-fat goal must be between 3 and 50 %"
        case .weightOutOfRange: "Goal weight must be between 30 and 300 kg"
        case .waistOutOfRange: "Waist goal must be between 50 and 200 cm"
        case .contestLevel: "contest-level target"
        }
    }

    public static let bodyFatRange: ClosedRange<Double> = 3...50
    public static let weightRange: ClosedRange<Double> = 30...300

    /// Below this body fat (%) a goal is "contest-level": 15 for women, 8 otherwise.
    public static func contestLevelBodyFat(for sex: Sex) -> Double { sex == .female ? 15 : 8 }

    /// What is wrong with a long-term goal: errors first, then the soft warning. 0 values (not set)
    /// are fine.
    public static func check(_ goal: CoachPlan.LongTerm, sex: Sex) -> [BodyGoalIssue] {
        var issues: [BodyGoalIssue] = []
        if goal.bodyFat != 0, !bodyFatRange.contains(goal.bodyFat) { issues.append(.bodyFatOutOfRange) }
        if goal.weightKg != 0, !weightRange.contains(goal.weightKg) { issues.append(.weightOutOfRange) }
        if goal.waistCm != 0, !BodySite.waist.isPlausible(goal.waistCm) { issues.append(.waistOutOfRange) }
        if goal.bodyFat > 0, goal.bodyFat < contestLevelBodyFat(for: sex), !issues.contains(.bodyFatOutOfRange) {
            issues.append(.contestLevel)
        }
        return issues
    }
}


// MARK: - Ratios and ceilings

extension BodyComposition {
    /// Waist ÷ height.
    public static func waistToHeight(waistCm: Double, heightCm: Double) -> Double? {
        guard waistCm > 0, heightCm > 0 else { return nil }
        return waistCm / heightCm
    }

    /// Waist ÷ hip.
    public static func waistToHip(waistCm: Double, hipCm: Double) -> Double? {
        guard waistCm > 0, hipCm > 0 else { return nil }
        return waistCm / hipCm
    }

    public static let waistToHeightGuideline = 0.5
    /// The neutral label next to the waist-to-height ratio.
    public static let waistToHeightNote = "under 0.5 is the usual health guideline"

    /// The waist ratios the Body page shows, from tape records in any order. The waist is the
    /// latest standard reading (morning, before eating; any reading only when there is no
    /// standard one), as the review ceiling reads it. Waist-to-hip pairs it with the latest hip
    /// reading (standard first) at most `NavyBodyFat.maxApartDays` away, so a weekly waist-only
    /// record doesn't hide the ratio until the next full set. `heightCm` 0 = unknown.
    public static func waistRatios(_ records: [BodyTapeRecord], sex: Sex, heightCm: Double,
                                   calendar: Calendar = .current) -> (waistToHeight: Double?, waistToHip: Double?) {
        let sorted = records.sorted { ($0.day, $0.time ?? .distantPast) < ($1.day, $1.time ?? .distantPast) }
        let withWaist = sorted.filter { BodyComposition.waist(in: $0.values, sex: sex) != nil }
        guard let record = withWaist.last(where: { $0.isStandard }) ?? withWaist.last,
              let waistCm = BodyComposition.waist(in: record.values, sex: sex) else { return (nil, nil) }
        let height = heightCm > 0 ? BodyComposition.waistToHeight(waistCm: waistCm, heightCm: heightCm) : nil
        let hips = sorted.filter { candidate in
            (candidate.values[.hip] ?? 0) > 0
                && abs(candidate.day.days(to: record.day, calendar: calendar)) <= NavyBodyFat.maxApartDays
        }
        let hipCm = (hips.last(where: { $0.isStandard }) ?? hips.last)?.values[.hip]
        let hip = hipCm.flatMap { BodyComposition.waistToHip(waistCm: waistCm, hipCm: $0) }
        return (height, hip)
    }

    /// The waist value for the ratios: the narrow waist first for women, else the navel waist
    /// (and the other one when that is missing).
    public static func waist(in values: BodyValues, sex: Sex) -> Double? {
        let order: [BodySite] = sex == .female ? [.waistNarrow, .waist] : [.waist, .waistNarrow]
        return order.lazy.compactMap { values[$0] }.first { $0 > 0 }
    }
}

/// A ceiling in a gain phase that opens the phase review (F5).
public enum BodyCeiling: String, Codable, Sendable, CaseIterable {
    /// Waist up by the phase's `maxWaistGainCm` since the phase start.
    case waistGain
    /// Waist-to-height ratio of 0.5 or more.
    case waistToHeight
    /// Body fat at or above the optional ceiling.
    case bodyFat

    public var message: String {
        switch self {
        case .waistGain: "Your waist is up by your limit for this phase – time to review"
        case .waistToHeight: "Waist-to-height ratio reached 0.5 – time to review"
        case .bodyFat: "Body fat reached your ceiling – time to review"
        }
    }

    /// The ceilings reached in a gain phase (none in other phases). `bodyFatCeiling` 0 = off.
    public static func reached(phase: CoachPlan.Phase, waistChangeSinceStart: Double?, waistToHeight: Double?,
                               bodyFat: Double? = nil, bodyFatCeiling: Double = 0) -> [BodyCeiling] {
        guard phase.goal == .gain else { return [] }
        var reached: [BodyCeiling] = []
        if phase.maxWaistGainCm > 0, let change = waistChangeSinceStart, change >= phase.maxWaistGainCm - 1e-9 {
            reached.append(.waistGain)
        }
        if let ratio = waistToHeight, ratio >= BodyComposition.waistToHeightGuideline - 1e-9 { reached.append(.waistToHeight) }
        if bodyFatCeiling > 0, let bodyFat, bodyFat >= bodyFatCeiling - 1e-9 { reached.append(.bodyFat) }
        return reached
    }

    /// The ceilings reached in a gain phase from its standard waist readings (any order;
    /// `waists`: day and cm). The base is the last reading on or before the phase start, else the
    /// first after it; the change since the start compares the latest reading with it. The
    /// waist-to-height ceiling (`heightCm` 0 = unknown) fires only once the ratio rose to 0.5 or
    /// more during the phase: not from the base reading alone when it was taken by the start (a
    /// person who starts at 0.5 or more isn't asked to review on day 1), and not when the base
    /// was already at 0.5 or more. A first reading after the start counts on its own.
    public static func reached(phase: CoachPlan.Phase, waists: [(day: DayKey, cm: Double)], heightCm: Double,
                               bodyFat: Double? = nil, bodyFatCeiling: Double = 0) -> [BodyCeiling] {
        guard phase.goal == .gain, let start = phase.start else { return [] }
        let sorted = waists.filter { $0.cm > 0 }.sorted { $0.day < $1.day }
        var change: Double?
        var ratio: Double?
        if let latest = sorted.last, let base = sorted.last(where: { $0.day <= start }) ?? sorted.first(where: { $0.day >= start }) {
            if latest.day > base.day { change = latest.cm - base.cm }
            if heightCm > 0, let now = BodyComposition.waistToHeight(waistCm: latest.cm, heightCm: heightCm) {
                if latest.day > base.day {
                    let before = BodyComposition.waistToHeight(waistCm: base.cm, heightCm: heightCm) ?? 0
                    if before < BodyComposition.waistToHeightGuideline - 1e-9 { ratio = now }
                } else if base.day > start {
                    ratio = now
                }
            }
        }
        return reached(phase: phase, waistChangeSinceStart: change, waistToHeight: ratio, bodyFat: bodyFat,
                       bodyFatCeiling: bodyFatCeiling)
    }
}

// MARK: - Girth trends

/// A change of one site between two readings, judged against the site's MDC.
public struct GirthChange: Equatable, Sendable, Codable {
    public var site: BodySite
    public var from: GirthReading
    public var to: GirthReading

    public init(site: BodySite, from: GirthReading, to: GirthReading) {
        self.site = site
        self.from = from
        self.to = to
    }

    /// cm
    public var change: Double { to.value - from.value }
    /// At least the minimal detectable change.
    public var isClear: Bool { GirthTrend.isClear(change, site: site) }

    /// "no clear change", or "up 1.2 cm (7 Jan – 4 Feb)".
    public var label: String {
        guard isClear else { return GirthTrend.noClearChange }
        return "\(GirthTrend.label(change, site: site)) (\(BodyCompositionText.range(from.day, to.day)))"
    }
}

/// What tape readings say over weeks. Changes smaller than a site's MDC are "no clear change".
public enum GirthTrend {
    public static let noClearChange = "no clear change"
    /// The 4-week change uses the last 4–6 readings…
    public static let minReadings = 4
    public static let maxReadings = 6
    /// …spanning at least two weeks (closer readings would be extrapolated noise).
    public static let minSpanDays = 14

    /// One reading per day (the latest of the day) of a site, oldest first; standard readings only
    /// unless `includeNonStandard`.
    public static func readings(_ site: BodySite, in records: [BodyTapeRecord], includeNonStandard: Bool = false) -> [GirthReading] {
        var byDay: [DayKey: GirthReading] = [:]
        for record in BodyTapeRecord.sorted(records) where includeNonStandard || record.isStandard {
            guard let value = record.values[site], value.isFinite, value > 0 else { continue }
            byDay[record.day] = GirthReading(day: record.day, value: value, time: record.time, isStandard: record.isStandard)
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// Least-squares slope in cm per day (x = days since the first reading); nil with fewer than 2
    /// days.
    public static func slopePerDay(_ readings: [GirthReading], calendar: Calendar = .current) -> Double? {
        guard let first = readings.first?.day, readings.count >= 2 else { return nil }
        let points = readings.map { (x: Double(first.days(to: $0.day, calendar: calendar)), y: $0.value) }
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
        let sxx = points.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = points.map { ($0.x - meanX) * ($0.y - meanY) }.reduce(0, +)
        return sxy / sxx
    }

    /// The 4-week change (cm): the least-squares slope over the last 4–6 readings × 28 days. nil
    /// with fewer than 4 readings or when they span less than 14 days.
    public static func fourWeekChange(_ readings: [GirthReading], calendar: Calendar = .current) -> Double? {
        let recent = Array(readings.sorted { $0.day < $1.day }.suffix(maxReadings))
        guard recent.count >= minReadings, let first = recent.first?.day, let last = recent.last?.day,
              first.days(to: last, calendar: calendar) >= minSpanDays,
              let slope = slopePerDay(recent, calendar: calendar) else { return nil }
        return slope * 28
    }

    public static func fourWeekChange(_ site: BodySite, in records: [BodyTapeRecord], includeNonStandard: Bool = false,
                                      calendar: Calendar = .current) -> Double? {
        fourWeekChange(readings(site, in: records, includeNonStandard: includeNonStandard), calendar: calendar)
    }

    /// |change| at least the site's MDC, judged at the 0.1 cm the screens show: means of two
    /// readings end in .x5, and "+1.0 cm" must never read "no clear change" (84.25 → 85.2).
    public static func isClear(_ change: Double, site: BodySite) -> Bool {
        abs((change * 10).rounded() / 10) >= site.mdc - 1e-9
    }

    /// "no clear change", "up 1.2 cm", "down 0.6 cm".
    public static func label(_ change: Double, site: BodySite) -> String {
        guard isClear(change, site: site) else { return noClearChange }
        return "\(change > 0 ? "up" : "down") \(String(format: "%.1f", abs(change))) cm"
    }

    /// The change of a site from its value at `since` (the latest reading on or up to 7 days before
    /// it, else the first one after it; nil = the first reading) to the latest reading.
    public static func change(_ site: BodySite, readings: [GirthReading], since: DayKey? = nil,
                              calendar: Calendar = .current) -> GirthChange? {
        let sorted = readings.sorted { $0.day < $1.day }
        guard let last = sorted.last else { return nil }
        var start = sorted.first
        if let since {
            let graceStart = since.adding(days: -7, calendar: calendar)
            start = sorted.last { $0.day <= since && $0.day >= graceStart } ?? sorted.first { $0.day > since }
        }
        guard let start, start.day <= last.day else { return nil }
        return GirthChange(site: site, from: start, to: last)
    }

    public static func change(_ site: BodySite, in records: [BodyTapeRecord], since: DayKey? = nil, includeNonStandard: Bool = false,
                              calendar: Calendar = .current) -> GirthChange? {
        change(site, readings: readings(site, in: records, includeNonStandard: includeNonStandard), since: since, calendar: calendar)
    }

    /// The baseline table (site | start | last | change | real change?), one row per site with
    /// readings, in the order given.
    public static func baseline(_ sites: [BodySite], in records: [BodyTapeRecord], since: DayKey? = nil,
                                includeNonStandard: Bool = false, calendar: Calendar = .current) -> [GirthChange] {
        sites.compactMap { change($0, in: records, since: since, includeNonStandard: includeNonStandard, calendar: calendar) }
    }

    /// The gain-phase line: "arm +0.8, chest +1.4, thigh +1.1 cm; waist +0.4 cm (no clear change)".
    /// nil without arm, chest, thigh and waist changes. Left-side sites (`arm_l`, `thigh_l`) count
    /// as arm and thigh when the right side isn't there.
    public static func gainLine(_ changes: [GirthChange]) -> String? {
        let bySite = Dictionary(changes.sorted { !$0.site.isLeft && $1.site.isLeft }.map { ($0.site.base, $0) },
                                uniquingKeysWith: { first, _ in first })
        let muscles = [BodySite.arm, .chest, .thigh].compactMap { site in
            bySite[site].map { "\(site.rawValue) \(BodyCompositionText.signed($0.change))" }
        }
        let waist = (bySite[.waist] ?? bySite[.waistNarrow]).map { change in
            "waist \(BodyCompositionText.signed(change.change)) cm" + (change.isClear ? "" : " (\(noClearChange))")
        }
        var parts: [String] = []
        if !muscles.isEmpty { parts.append(muscles.joined(separator: ", ") + " cm") }
        if let waist { parts.append(waist) }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    // MARK: Waist guard and waist note (F6)

    /// cm over 4 weeks.
    public static let waistGuardRise = 1.5
    public static let waistGuardMessage = "Waist is rising faster than other sites – consider the low end of your rate"

    /// Gain phase: the waist rose 1.5 cm or more over 4 weeks while arm, chest and thigh didn't
    /// clearly grow (each below its MDC; a site without a change counts as not grown). Only a
    /// hint in the check-in, never an automatic change.
    public static func waistGuard(waistFourWeekChange: Double?, otherChanges: [BodySite: Double]) -> Bool {
        guard let waist = waistFourWeekChange, waist >= waistGuardRise - 1e-9 else { return false }
        return [BodySite.arm, .chest, .thigh].allSatisfy { site in
            guard let change = otherChanges[site] else { return true }
            return change < site.mdc - 1e-9
        }
    }

    /// The waist guard from tape records: the waist's 4-week change against the arm, chest and
    /// thigh changes since `since` (the phase start). Gain phases only.
    public static func waistGuard(phase: CoachPlan.Phase, records: [BodyTapeRecord], waistSite: BodySite = .waist,
                                  includeNonStandard: Bool = false, calendar: Calendar = .current) -> Bool {
        guard phase.goal == .gain else { return false }
        let since = phase.start
        var others: [BodySite: Double] = [:]
        for site in [BodySite.arm, .chest, .thigh] {
            others[site] = change(site, in: records, since: since, includeNonStandard: includeNonStandard, calendar: calendar)?.change
        }
        let inPhase = since.map { start in records.filter { $0.day >= start } } ?? records
        return waistGuard(waistFourWeekChange: fourWeekChange(waistSite, in: inPhase, includeNonStandard: includeNonStandard,
                                                              calendar: calendar),
                          otherChanges: others)
    }

    /// Weight loss expected over the flat stretch (rate × weeks) before the waist note shows (kg).
    public static let waistNoteMinLoss = 1.0
    public static let waistNoteDays = 28
    public static let waistNoteMessage = "Your weight is falling but your waist hasn't changed for 4 weeks – check measuring consistency"

    /// Loss phase: the weight is falling (`ratePerWeek` × the weeks between the readings is at
    /// least 1 kg down) while the waist stayed flat (latest reading within the MDC of the last one
    /// at least 4 weeks earlier).
    public static func waistNote(waist readings: [GirthReading], ratePerWeek: Double?, site: BodySite = .waist,
                                 calendar: Calendar = .current) -> Bool {
        let sorted = readings.sorted { $0.day < $1.day }
        guard let rate = ratePerWeek, rate < 0, let last = sorted.last,
              let earlier = sorted.last(where: { $0.day.days(to: last.day, calendar: calendar) >= waistNoteDays }) else { return false }
        let weeks = Double(earlier.day.days(to: last.day, calendar: calendar)) / 7
        guard rate * weeks <= -waistNoteMinLoss + 1e-9 else { return false }
        return !isClear(last.value - earlier.value, site: site)
    }
}

// MARK: - Text

/// The few strings Core builds here (UI text is English; numbers with "." like the rest of Core).
private enum BodyCompositionText {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "+1.2", "−0.3" (a real minus sign), "0.0".
    static func signed(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        let zero = String(format: "%.\(decimals)f", 0.0)
        if text == zero { return zero }
        return (value < 0 ? "−" : "+") + text
    }

    /// "7 Jan".
    static func day(_ day: DayKey) -> String { "\(day.day) \(months[max(0, min(11, day.month - 1))])" }

    /// "Sep 2031".
    static func month(_ day: DayKey) -> String { "\(months[max(0, min(11, day.month - 1))]) \(day.year)" }

    /// "7 Jan – 4 Feb"; with the years when they differ: "17 Dec 2030 – 14 Jan 2031".
    static func range(_ from: DayKey, _ to: DayKey) -> String {
        from.year == to.year ? "\(day(from)) – \(day(to))" : "\(day(from)) \(from.year) – \(day(to)) \(to.year)"
    }
}
