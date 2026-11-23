import Foundation

/// The morning weight signal (F4): one morning weight per diary day, the 7-day average, the weekly
/// change, the decision rate (a least-squares slope over a window of up to 21 days) and its status
/// against the active phase's range, unusual readings and `#tag`s, the phase corridor, the phase
/// start weight, the projected end weight, the review checkpoint and the personal noise band.
///
/// Typed weigh-ins (`WeightEntry`) and live Apple Health weights go in as plain `Reading`s and follow
/// the same rule; nothing here is stored. Single readings swing with water, salt and gut content,
/// so every number uses the morning weights only: the earliest weigh-in of a diary day before the
/// morning cutoff (11:00). Later weigh-ins are kept for the chart (faint dots, `others`) and left
/// out of every calculation.
public struct WeightSignal: Equatable, Sendable {
    // MARK: Rules

    /// Days in the rolling average, and the morning weights it needs to count.
    public static let averageDays = 7
    public static let averageMinimum = 4
    /// Untagged morning weigh-ins the decision rate needs in its window.
    public static let rateMinimumWeighIns = 10
    /// kg/week of slack around a phase's rate range (the plan's `adjust.tolerance` wins).
    public static let defaultTolerance = 0.03
    /// A reading further than this share of body weight from the trend is unusual (1.5 %, 1.2 kg at 80 kg).
    public static let unusualShare = 0.015
    /// EMA smoothing of the trend line (as on the weight chart).
    public static let trendSmoothing = 0.1
    /// kg accepted at all; anything else is a typo or a broken reading.
    public static let plausibleRange: ClosedRange<Double> = 25...300
    /// kg away from the 7-day average that asks "typo?".
    public static let typoJump = 3.0
    /// Days of the personal noise band, and the readings it needs.
    public static let noiseDays = 28
    public static let noiseMinimum = 10
    /// kg/week either side of zero for a maintain phase without a rate of its own.
    public static let maintainBand = 0.1
    /// A Health weight this close to a typed one is the same weigh-in (Nina writes typed weights to Health).
    static let duplicateSeconds: TimeInterval = 600
    static let duplicateKilograms = 0.05
    private static let slack = 1e-9

    // MARK: Readings

    /// One weigh-in, typed in Nina or read live from Apple Health.
    public struct Reading: Codable, Equatable, Hashable, Sendable {
        public enum Source: String, Codable, Sendable, CaseIterable {
            /// Typed in Nina (`WeightEntry`, synced).
            case nina
            /// Read live from Apple Health (never stored).
            case health
        }

        /// The diary day it counts for.
        public var day: DayKey
        public var time: Date
        public var kilograms: Double
        /// `WeightEntry.note`; reasons are `#tag` tokens in it ("#salty").
        public var note: String
        public var source: Source

        public init(day: DayKey, time: Date, kilograms: Double, note: String = "", source: Source = .nina) {
            self.day = day
            self.time = time
            self.kilograms = kilograms
            self.note = note
            self.source = source
        }

        /// A reading whose diary day comes from its time (Health samples).
        public init(time: Date, kilograms: Double, note: String = "", source: Source = .health, dayStartHour: Int = 0,
                    calendar: Calendar = .current) {
            self.init(day: DayKey(date: time, calendar: calendar, dayStartHour: dayStartHour), time: time, kilograms: kilograms,
                      note: note, source: source)
        }

        /// The reasons in the note.
        public var tags: [Tag] { Tag.parse(note) }

        /// Tagged readings stay on the chart but are left out of the decision rate.
        public var isTagged: Bool { !tags.isEmpty }

        /// Minutes after midnight on its diary day: a 01:30 weigh-in that still counts for the day
        /// before (`dayStartHour` 3) reads 1530. A reading filed under another day than its time
        /// (typed in later) uses its clock time.
        public func minutes(dayStartHour: Int = 0, calendar: Calendar = .current) -> Int {
            let clock = ClockTime.minutes(of: time, calendar: calendar)
            let calendarDay = DayKey(date: time, calendar: calendar)
            if calendarDay == day.adding(days: 1, calendar: calendar), clock < max(0, min(dayStartHour, 12)) * 60 {
                return clock + 1440
            }
            return clock
        }

        /// Weighed before the morning cutoff of its diary day.
        public func isMorning(cutoffMinutes: Int = 660, dayStartHour: Int = 0, calendar: Calendar = .current) -> Bool {
            minutes(dayStartHour: dayStartHour, calendar: calendar) < cutoffMinutes
        }
    }

    /// Why a reading is off ("Unusual reading – anything special?"), stored as a token in
    /// `WeightEntry.note`: `#salty`, `#late_meal`, …
    public enum Tag: String, Codable, Sendable, CaseIterable, Identifiable {
        case salty
        case lateMeal = "late_meal"
        case alcohol, travel, ill, period, refeed
        case poorSleep = "poor_sleep"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .salty: "Salty"
            case .lateMeal: "Late meal"
            case .alcohol: "Alcohol"
            case .travel: "Travel"
            case .ill: "Ill"
            case .period: "Period"
            case .refeed: "Refeed"
            case .poorSleep: "Poor sleep"
            }
        }

        /// "#salty"
        public var token: String { "#" + rawValue }

        /// The chips to offer (no period for men).
        public static func options(for sex: Sex) -> [Tag] {
            allCases.filter { $0 != .period || sex != .male }
        }

        /// Token spellings after folding (case, accents, "_" and "-" ignored), English and German.
        private static let aliases: [String: Tag] = [
            "salty": .salty, "salt": .salty, "salzig": .salty,
            "latemeal": .lateMeal, "late": .lateMeal, "latedinner": .lateMeal, "spat": .lateMeal, "spaet": .lateMeal,
            "spatessen": .lateMeal, "spaetessen": .lateMeal,
            "alcohol": .alcohol, "alkohol": .alcohol, "drinks": .alcohol,
            "travel": .travel, "travelling": .travel, "traveling": .travel, "reise": .travel,
            "ill": .ill, "sick": .ill, "krank": .ill,
            "period": .period, "periode": .period, "menstruation": .period, "regel": .period,
            "refeed": .refeed, "cheatday": .refeed,
            "poorsleep": .poorSleep, "badsleep": .poorSleep, "sleep": .poorSleep, "schlaf": .poorSleep,
            "schlechtgeschlafen": .poorSleep,
        ]

        /// The tag a token means ("#Late-Meal" → .lateMeal); nil for other hashtags.
        public init?(token: String) {
            let body = token.hasPrefix("#") ? String(token.dropFirst()) : token
            let key = SearchText.normalize(body).replacingOccurrences(of: " ", with: "")
            guard let tag = Tag(rawValue: key) ?? Tag.aliases[key] else { return nil }
            self = tag
        }

        /// The known tags in a note, each once, in order of appearance. Other hashtags are ignored.
        public static func parse(_ note: String) -> [Tag] {
            var tags: [Tag] = []
            for token in tokens(in: note) {
                if let tag = Tag(token: token), !tags.contains(tag) { tags.append(tag) }
            }
            return tags
        }

        /// The note with exactly these tags: known tag tokens are removed, other text and hashtags
        /// stay, and the tokens are appended ("Hotel scale #travel #salty").
        public static func note(_ note: String, setting tags: [Tag]) -> String {
            var words: [String] = []
            for word in note.split(whereSeparator: \.isWhitespace) {
                let text = String(word)
                let wordTokens = tokens(in: text)
                if text.hasPrefix("#"), !wordTokens.isEmpty, wordTokens.allSatisfy({ Tag(token: $0) != nil }) { continue }
                words.append(text)
            }
            var seen: [Tag] = []
            for tag in tags where !seen.contains(tag) { seen.append(tag) }
            return (words + seen.map(\.token)).joined(separator: " ")
        }

        /// "#word" tokens (letters, digits, "_" and "-").
        static func tokens(in note: String) -> [String] {
            var tokens: [String] = []
            var current: String?
            var previousIsWord = false
            for character in note {
                let isWord = character.isLetter || character.isNumber || character == "_" || character == "-"
                if character == "#", current != nil || !previousIsWord {
                    // "#salty#travel" is two tokens, "x#salty" none.
                    if let token = current, token.count > 1 { tokens.append(token) }
                    current = "#"
                } else if current != nil, isWord {
                    current?.append(character)
                } else {
                    if let token = current, token.count > 1 { tokens.append(token) }
                    current = nil
                }
                previousIsWord = isWord
            }
            if let token = current, token.count > 1 { tokens.append(token) }
            return tokens
        }
    }

    /// A value on a day (chart points, the 7-day average history).
    public struct Point: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var day: DayKey
        public var kilograms: Double

        public init(day: DayKey, kilograms: Double) {
            self.day = day
            self.kilograms = kilograms
        }

        public var id: DayKey { day }
    }

    // MARK: State

    public let calendar: Calendar
    /// Minutes after midnight before which a weigh-in counts as the morning weight (11:00).
    public let cutoffMinutes: Int
    public let dayStartHour: Int
    /// The morning weight of each diary day that has one.
    public let mornings: [DayKey: Reading]
    /// The days with a morning weight, oldest first.
    public let days: [DayKey]
    /// Readings left out of every calculation (later in the day, or not the first in the morning),
    /// oldest first: faint dots on the chart.
    public let others: [Reading]
    /// The EMA trend on each day with a morning weight.
    private let trendByDay: [DayKey: Double]

    /// - Parameters:
    ///   - readings: typed and Health weigh-ins in any order. Readings outside 25–300 kg are
    ///     dropped, and a Health reading that repeats a typed one (same kg within 0.05, within
    ///     10 minutes) counts once, as the typed one.
    ///   - cutoffMinutes: `routine.morningCutoffMinutes` (660 = 11:00).
    ///   - dayStartHour: the profile's day start, so a weigh-in after midnight still belongs to the evening before.
    public init(_ readings: [Reading], cutoffMinutes: Int = 660, dayStartHour: Int = 0, calendar: Calendar = .current) {
        self.calendar = calendar
        self.cutoffMinutes = cutoffMinutes
        self.dayStartHour = dayStartHour
        let valid = readings.filter { $0.kilograms.isFinite && WeightSignal.plausibleRange.contains($0.kilograms) }
        let typedByDay = Dictionary(grouping: valid.filter { $0.source == .nina }, by: \.day)
        let kept = valid.filter { reading in
            guard reading.source == .health else { return true }
            return !(typedByDay[reading.day] ?? []).contains {
                abs($0.kilograms - reading.kilograms) <= WeightSignal.duplicateKilograms + WeightSignal.slack
                    && abs($0.time.timeIntervalSince(reading.time)) <= WeightSignal.duplicateSeconds
            }
        }
        var mornings: [DayKey: Reading] = [:]
        var others: [Reading] = []
        for (day, list) in Dictionary(grouping: kept, by: \.day) {
            var sorted = list.sorted { lhs, rhs in
                if lhs.time != rhs.time { return lhs.time < rhs.time }
                return lhs.source == .nina && rhs.source == .health
            }
            if let index = sorted.firstIndex(where: { $0.isMorning(cutoffMinutes: cutoffMinutes, dayStartHour: dayStartHour, calendar: calendar) }) {
                mornings[day] = sorted.remove(at: index)
            }
            others += sorted
        }
        self.mornings = mornings
        self.days = mornings.keys.sorted()
        self.others = others.sorted { $0.time != $1.time ? $0.time < $1.time : $0.day < $1.day }
        var trend: [DayKey: Double] = [:]
        if let last = days.last {
            for point in Insights.weightTrend(mornings.mapValues(\.kilograms), through: last, smoothing: WeightSignal.trendSmoothing,
                                              calendar: calendar) where !point.weight.isNaN {
                trend[point.day] = point.trend
            }
        }
        trendByDay = trend
    }

    /// The morning weight of a day.
    public func morning(on day: DayKey) -> Reading? { mornings[day] }

    /// The morning weights from `start` through `end`, oldest first.
    public func mornings(from start: DayKey, through end: DayKey) -> [Reading] {
        guard start <= end else { return [] }
        var index = firstIndex(onOrAfter: start)
        var result: [Reading] = []
        while index < days.count, days[index] <= end {
            if let reading = mornings[days[index]] { result.append(reading) }
            index += 1
        }
        return result
    }

    /// Days weighed in the morning from `start` through `end` ("Mornings weighed 6 of 7").
    public func morningCount(from start: DayKey, through end: DayKey) -> Int { mornings(from: start, through: end).count }

    /// A Health weight is among the morning weights of the span. Check-in snapshots then leave
    /// their weight numbers out (they are recomputed live).
    public func usesHealth(from start: DayKey, through end: DayKey) -> Bool {
        mornings(from: start, through: end).contains { $0.source == .health }
    }

    // MARK: Trend and average

    /// The EMA trend (carried forward over days without a weigh-in); nil before the first morning weight.
    public func trend(on day: DayKey) -> Double? {
        guard let index = lastIndex(onOrBefore: day) else { return nil }
        return trendByDay[days[index]]
    }

    /// The 7-day average and how many morning weights it has.
    public struct Average: Codable, Equatable, Sendable {
        /// The last day of the 7 days.
        public var day: DayKey
        /// Mean of the morning weights in the 7 days (nil without any).
        public var mean: Double?
        public var count: Int

        public init(day: DayKey, mean: Double?, count: Int) {
            self.day = day
            self.mean = mean
            self.count = count
        }

        /// Valid with at least 4 morning weights.
        public var isValid: Bool { mean != nil && count >= WeightSignal.averageMinimum }
        /// The average when valid.
        public var value: Double? { isValid ? mean : nil }
        public var missingMornings: Int { max(0, WeightSignal.averageMinimum - count) }
        /// "Weigh in 2 more mornings to see your average" (nil when valid).
        public var prompt: String? {
            guard !isValid else { return nil }
            let missing = max(1, missingMornings)
            return "Weigh in \(missing) more morning\(missing == 1 ? "" : "s") to see your average"
        }
    }

    /// The mean of the morning weights in the 7 days ending on `day`.
    public func average(on day: DayKey) -> Average {
        let values = mornings(from: day.adding(days: -(WeightSignal.averageDays - 1), calendar: calendar), through: day).map(\.kilograms)
        return Average(day: day, mean: WeightSignal.mean(values), count: values.count)
    }

    /// The valid 7-day averages of every day from `start` through `end` (the bold chart line).
    public func averages(from start: DayKey, through end: DayKey) -> [Point] {
        DayKey.range(start, through: end, calendar: calendar).compactMap { day in
            average(on: day).value.map { Point(day: day, kilograms: $0) }
        }
    }

    /// The weight that body math uses on a day.
    public struct Estimate: Codable, Equatable, Sendable {
        public enum Basis: String, Codable, Sendable {
            /// The valid 7-day average.
            case average
            /// The EMA trend ("estimate").
            case trend
            /// The latest weigh-in, when there is no morning weight at all.
            case latest
        }

        public var kilograms: Double
        public var basis: Basis

        public init(kilograms: Double, basis: Basis) {
            self.kilograms = kilograms
            self.basis = basis
        }

        /// Shown as "estimate".
        public var isEstimate: Bool { basis != .average }
    }

    /// The real weight on a day for body math (never a hard-coded one): the 7-day average if
    /// valid, else the trend, else the latest weigh-in; nil without any weigh-in up to that day.
    public func bodyWeight(on day: DayKey) -> Estimate? {
        if let value = average(on: day).value { return Estimate(kilograms: value, basis: .average) }
        if let trend = self.trend(on: day) { return Estimate(kilograms: trend, basis: .trend) }
        if let latest = others.last(where: { $0.day <= day }) { return Estimate(kilograms: latest.kilograms, basis: .latest) }
        return nil
    }

    /// A change between two weights: kg and % of body weight (kg ÷ the newer weight × 100).
    public struct Change: Codable, Equatable, Sendable {
        public var kilograms: Double
        public var percent: Double
        public var current: Double
        public var previous: Double

        public init(from previous: Double, to current: Double) {
            self.previous = previous
            self.current = current
            kilograms = current - previous
            percent = current > 0 ? kilograms / current * 100 : 0
        }
    }

    /// This 7-day average minus the one a week before, both valid.
    public func weeklyChange(on day: DayKey) -> Change? {
        guard let current = average(on: day).value,
              let previous = average(on: day.adding(days: -7, calendar: calendar)).value else { return nil }
        return Change(from: previous, to: current)
    }

    /// Display-only cross-check of the decision rate (kg/week): (7-day average now − 7-day average
    /// 14 days ago) ÷ 2, both valid.
    public func crossCheckRate(on day: DayKey) -> Double? {
        guard let current = average(on: day).value,
              let previous = average(on: day.adding(days: -14, calendar: calendar)).value else { return nil }
        return (current - previous) / 2
    }

    // MARK: Decision rate

    /// The days the decision rate looks at.
    public struct Window: Codable, Equatable, Sendable {
        public var start: DayKey
        public var end: DayKey

        public init(start: DayKey, end: DayKey) {
            self.start = start
            self.end = end
        }

        /// Days from start through end (0 when the start is later).
        public func days(calendar: Calendar = .current) -> Int {
            start <= end ? start.days(to: end, calendar: calendar) + 1 : 0
        }

        public func contains(_ day: DayKey) -> Bool { day >= start && day <= end }
    }

    /// The last `maxDays` days ending on `day`, never starting before any of `limits` (phase start,
    /// last applied adjustment, the day after a pause).
    public static func rateWindow(on day: DayKey, maxDays: Int = 21, notBefore limits: [DayKey?] = [],
                                  calendar: Calendar = .current) -> Window {
        var start = day.adding(days: -(max(1, maxDays) - 1), calendar: calendar)
        for case let limit? in limits where limit > start { start = limit }
        return Window(start: start, end: day)
    }

    /// The rate window from the plan: the last `adjust.windowMaxDays` days, not before the active
    /// phase's start, its last calorie change in force (`CoachPlan.lastCalorieChange`: Apply in a
    /// check-in, or an edit, calculation or import that moved the calories) or the day after the
    /// latest finished pause.
    public static func rateWindow(on day: DayKey, plan: CoachPlan, calendar: Calendar = .current) -> Window {
        var limits: [DayKey?] = []
        if let phase = plan.activePhase(on: day) {
            limits.append(phase.start)
            limits.append(plan.lastCalorieChange(on: day, inForce: true)?.from)
        }
        limits.append(plan.pauses.compactMap { pause in
            pause.end.flatMap { $0 < day ? $0.adding(days: 1, calendar: calendar) : nil }
        }.max())
        return rateWindow(on: day, maxDays: plan.adjust.windowMaxDays, notBefore: limits, calendar: calendar)
    }

    /// The first day a rate from a window starting on `start` can be valid (two weeks of daily
    /// weigh-ins, the first and the last day included): window start + 13 days. The first
    /// adjustment check is the first check-in day from then on.
    public static func firstRateDay(from start: DayKey, minimumDays: Int = 14, calendar: Calendar = .current) -> DayKey {
        start.adding(days: max(1, minimumDays) - 1, calendar: calendar)
    }

    /// kg as % of body weight (kg ÷ weight × 100), e.g. a rate in %/week; nil without a weight.
    public static func percent(_ kilograms: Double, of weight: Double) -> Double? {
        weight > 0 ? kilograms / weight * 100 : nil
    }

    /// The first day of the newest calorie change of a phase in force on `day`, judged without
    /// day types (`CoachPlan.calorieChanges`; with a plan use `CoachPlan.lastCalorieChange`).
    public static func lastAdjustment(in phase: CoachPlan.Phase, on day: DayKey) -> DayKey? {
        CoachPlan().calorieChanges(of: phase).last { $0.from <= day }?.from
    }

    /// The decision rate: least-squares slope of the untagged morning weights × 7.
    public struct Rate: Codable, Equatable, Sendable {
        public var window: Window
        /// kg/week (nil with fewer than two morning weights on different days).
        public var kilogramsPerWeek: Double?
        /// Untagged morning weigh-ins used.
        public var weighIns: Int
        /// Tagged morning weigh-ins left out.
        public var tagged: Int
        /// Days from the first through the last weigh-in used (inclusive).
        public var spanDays: Int
        public var minimumDays: Int
        public var minimumWeighIns: Int
        /// A Health weight was used (check-in snapshots then leave the weight numbers out).
        public var usesHealth: Bool

        public init(window: Window, kilogramsPerWeek: Double?, weighIns: Int, tagged: Int, spanDays: Int, minimumDays: Int = 14,
                    minimumWeighIns: Int = WeightSignal.rateMinimumWeighIns, usesHealth: Bool = false) {
            self.window = window
            self.kilogramsPerWeek = kilogramsPerWeek
            self.weighIns = weighIns
            self.tagged = tagged
            self.spanDays = spanDays
            self.minimumDays = minimumDays
            self.minimumWeighIns = minimumWeighIns
            self.usesHealth = usesHealth
        }

        /// Spans at least 14 days with at least 10 untagged morning weigh-ins.
        public var isValid: Bool { kilogramsPerWeek != nil && spanDays >= minimumDays && weighIns >= minimumWeighIns }
        /// The rate when valid.
        public var value: Double? { isValid ? kilogramsPerWeek : nil }
    }

    /// The decision rate over a window. Tagged readings and `excluding` days (paused) are left out.
    public func rate(in window: Window, minimumDays: Int = 14, minimumWeighIns: Int = WeightSignal.rateMinimumWeighIns,
                     excluding: (DayKey) -> Bool = { _ in false }) -> Rate {
        let inWindow = mornings(from: window.start, through: window.end).filter { !excluding($0.day) }
        let used = inWindow.filter { !$0.isTagged }
        let points = used.map { (x: Double(window.start.days(to: $0.day, calendar: calendar)), y: $0.kilograms) }
        let span = used.first.flatMap { first in used.last.map { first.day.days(to: $0.day, calendar: calendar) + 1 } } ?? 0
        return Rate(window: window, kilogramsPerWeek: WeightSignal.slope(points).map { $0 * 7 }, weighIns: used.count,
                    tagged: inWindow.count - used.count, spanDays: span, minimumDays: minimumDays, minimumWeighIns: minimumWeighIns,
                    usesHealth: used.contains { $0.source == .health })
    }

    /// The decision rate on a day with the plan's window rules; paused days are left out.
    public func rate(on day: DayKey, plan: CoachPlan) -> Rate {
        let window = WeightSignal.rateWindow(on: day, plan: plan, calendar: calendar)
        return rate(in: window, minimumDays: plan.adjust.windowMinDays, excluding: { plan.isPaused(on: $0) })
    }

    /// Least-squares slope (y per x); nil with fewer than two different x.
    public static func slope(_ points: [(x: Double, y: Double)]) -> Double? {
        guard points.count >= 2 else { return nil }
        let count = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / count
        let meanY = points.map(\.y).reduce(0, +) / count
        var products = 0.0, squares = 0.0
        for point in points {
            products += (point.x - meanX) * (point.y - meanY)
            squares += (point.x - meanX) * (point.x - meanX)
        }
        guard squares > 0 else { return nil }
        return products / squares
    }

    // MARK: Status

    /// The rate against the active phase's range. The same words and colours everywhere.
    public enum Status: String, Codable, Sendable, CaseIterable, Identifiable {
        case inRange, slower, faster, gathering

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .inRange: "In range"
            case .slower: "Slower than planned"
            case .faster: "Faster than planned"
            case .gathering: "Gathering data"
            }
        }

        /// Outside the range (slower or faster).
        public var isOutside: Bool { self == .slower || self == .faster }

        /// The word for a rate outside the range, in the phase's direction: gaining above the
        /// range or losing below it is faster, the other side slower; while maintaining, moving
        /// either way is faster than planned. The check-in uses the same words.
        public static func outside(above: Bool, goal: WeightGoal) -> Status {
            switch goal {
            case .gain: above ? .faster : .slower
            case .lose: above ? .slower : .faster
            case .maintain: .faster
            }
        }

        /// "Off track" (red) only after `count` check-ins in a row outside the range on the same
        /// side (`recent` oldest first, the latest last), as the check-in counts them: slower then
        /// faster is not off track. In a maintain phase both sides read "faster", so there the
        /// sides come from the check-ins' saved deviations (`isOffTrack(deviations:inARow:)`).
        public static func isOffTrack(_ recent: [Status], inARow count: Int = 2) -> Bool {
            guard count > 0, recent.count >= count, let latest = recent.last, latest.isOutside else { return false }
            return recent.suffix(count).allSatisfy { $0 == latest }
        }

        /// "Off track" from the sides of the latest check-ins (`CheckInSnapshot.deviation`, oldest
        /// first; nil = in range or no rate): the last `count` all outside on the same side.
        public static func isOffTrack(deviations recent: [CheckInEngine.Deviation?], inARow count: Int = 2) -> Bool {
            guard count > 0, recent.count >= count, let latest = recent.last ?? nil else { return false }
            return recent.suffix(count).allSatisfy { $0 == latest }
        }
    }

    /// The phase's range with its direction (kg/week): gain +min…+max, loss −max…−min, maintain
    /// ±max (at least ±0.1). nil for a gain or loss phase without a rate.
    public static func range(for phase: CoachPlan.Phase) -> ClosedRange<Double>? {
        switch phase.goal {
        case .maintain:
            let band = max(phase.rateRange.upperBound, maintainBand)
            return -band...band
        case .gain, .lose:
            guard phase.rateRange.upperBound > 0 else { return nil }
            return phase.signedRateRange
        }
    }

    /// kg/week outside the range plus tolerance: positive above (heavier than planned), negative
    /// below, 0 inside. nil without a range.
    public static func deviation(_ rate: Double, phase: CoachPlan.Phase, tolerance: Double = defaultTolerance) -> Double? {
        guard let range = WeightSignal.range(for: phase) else { return nil }
        let high = range.upperBound + tolerance, low = range.lowerBound - tolerance
        if rate > high + slack { return rate - high }
        if rate < low - slack { return rate - low }
        return 0
    }

    /// In range (with the tolerance), slower or faster than planned (in the phase's direction;
    /// a maintain phase moving either way is faster, see `Status.outside`), or gathering data
    /// without a valid rate. nil without a range to compare with.
    public static func status(rate: Double?, phase: CoachPlan.Phase, tolerance: Double = defaultTolerance) -> Status? {
        guard range(for: phase) != nil else { return nil }
        guard let rate, let offset = WeightSignal.deviation(rate, phase: phase, tolerance: tolerance) else { return .gathering }
        if offset == 0 { return .inRange }
        return .outside(above: offset > 0, goal: phase.goal)
    }

    // MARK: Unusual readings and sanity

    /// More than 1.5 % of body weight from the trend.
    public static func isUnusual(_ kilograms: Double, trend: Double?) -> Bool {
        guard let trend, trend > 0 else { return false }
        return abs(kilograms - trend) > trend * unusualShare + slack
    }

    /// A reading on `day` against the trend up to the day before: "Unusual reading – anything special?".
    public func isUnusual(_ kilograms: Double, on day: DayKey) -> Bool {
        WeightSignal.isUnusual(kilograms, trend: trend(on: day.adding(days: -1, calendar: calendar)))
    }

    /// Days whose morning weight was unusual.
    public func unusualDays(from start: DayKey, through end: DayKey) -> [DayKey] {
        mornings(from: start, through: end).filter { isUnusual($0.kilograms, on: $0.day) }.map(\.day)
    }

    /// What to do with a typed weight before saving it.
    public enum Sanity: Equatable, Sendable {
        case ok
        /// Outside 25–300 kg: not accepted.
        case outOfRange
        /// More than 3 kg from the average: ask "80.4 kg – typo?" inline.
        case typo(reference: Double)
    }

    public static func sanity(_ kilograms: Double, reference: Double?) -> Sanity {
        guard kilograms.isFinite, plausibleRange.contains(kilograms) else { return .outOfRange }
        if let reference, abs(kilograms - reference) > typoJump + slack { return .typo(reference: reference) }
        return .ok
    }

    /// Checks a new weight for `day` against the 7-day average (the trend while there is none).
    public func sanity(_ kilograms: Double, on day: DayKey) -> Sanity {
        WeightSignal.sanity(kilograms, reference: average(on: day).value ?? trend(on: day))
    }

    /// "Did you mean …?" for a typed weight that fails the sanity check: a misplaced decimal
    /// point, one wrong digit or two swapped digits that bring it within 3 kg of `reference` (the
    /// 7-day average; the closest wins), to 0.1 kg. Without a reference only a decimal point in
    /// the wrong place (742 or 7.42 for 74.2) into 35–200 kg. nil when the weight passes the check
    /// or nothing fits.
    public static func typoSuggestion(for kilograms: Double, reference: Double?) -> Double? {
        guard kilograms.isFinite, kilograms > 0, kilograms < 100_000,
              sanity(kilograms, reference: reference) != .ok else { return nil }
        let shifts = [kilograms / 10, kilograms * 10, kilograms / 100, kilograms * 100]
        func usable(_ values: [Double]) -> [Double] {
            values.map { ($0 * 10).rounded() / 10 }
                .filter { plausibleRange.contains($0) && abs($0 - kilograms) >= 0.05 }
        }
        guard let reference else {
            guard kilograms > plausibleRange.upperBound || kilograms < 10 else { return nil }
            return usable(shifts).first { (35...200).contains($0) }
        }
        var candidates = shifts
        let digits = Array(String(Int((kilograms * 10).rounded())))
        for index in digits.indices {
            for digit in "0123456789" where digit != digits[index] {
                var changed = digits
                changed[index] = digit
                if let value = Double(String(changed)) { candidates.append(value / 10) }
            }
            if index + 1 < digits.count, digits[index] != digits[index + 1] {
                var swapped = digits
                swapped.swapAt(index, index + 1)
                if let value = Double(String(swapped)) { candidates.append(value / 10) }
            }
        }
        return usable(candidates).filter { abs($0 - reference) <= typoJump + slack }
            .min { abs($0 - reference) < abs($1 - reference) }
    }

    // MARK: Phase

    /// The phase start weight: a stored `startWeight` wins (leave it 0 to follow the weigh-ins);
    /// else the 7-day average on the start day if valid; else the first valid one in the first 7
    /// days; else `fallback` (the imported or typed weight).
    public func startWeight(of phase: CoachPlan.Phase, fallback: Double? = nil) -> Double? {
        if phase.startWeight > 0 { return phase.startWeight }
        if let start = phase.start {
            for offset in 0..<WeightSignal.averageDays {
                if let value = average(on: start.adding(days: offset, calendar: calendar)).value { return value }
            }
        }
        return fallback.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The shaded corridor on a day: start + rateMin × weeks … start + rateMax × weeks (signed by
    /// the goal; ±max for maintain). nil before the start or without a range.
    public static func corridor(startWeight: Double, phase: CoachPlan.Phase, on day: DayKey, calendar: Calendar = .current) -> ClosedRange<Double>? {
        guard startWeight > 0, let start = phase.start, day >= start, let range = WeightSignal.range(for: phase) else { return nil }
        let weeks = Double(start.days(to: day, calendar: calendar)) / 7
        return (startWeight + range.lowerBound * weeks)...(startWeight + range.upperBound * weeks)
    }

    /// average + rate × weeks from `day` to `end`.
    public static func projectedWeight(average: Double, rate: Double, from day: DayKey, to end: DayKey,
                                       calendar: Calendar = .current) -> Double {
        average + rate * Double(day.days(to: end, calendar: calendar)) / 7
    }

    /// The weight at the phase end if the rate holds: 7-day average + rate × weeks left. nil
    /// without an end (or after it), a valid average or a rate.
    public func projectedEndWeight(of phase: CoachPlan.Phase, on day: DayKey, rate: Double?) -> Double? {
        guard let end = phase.end, end >= day, let rate, let average = self.average(on: day).value else { return nil }
        return WeightSignal.projectedWeight(average: average, rate: rate, from: day, to: end, calendar: calendar)
    }

    // MARK: Review checkpoint

    /// The weight that opens the review: the lower review bound (`reviewMin`, else `reviewMax`).
    /// nil for maintain phases and without a review range.
    public static func checkpoint(of phase: CoachPlan.Phase) -> Double? {
        guard phase.goal != .maintain else { return nil }
        return [phase.reviewMin, phase.reviewMax].filter { $0 > 0 }.min()
    }

    /// The checkpoint is reached: at or above it while gaining, at or below it while losing.
    public static func hasReached(_ average: Double, checkpoint: Double, goal: WeightGoal) -> Bool {
        switch goal {
        case .gain: average >= checkpoint - slack
        case .lose: average <= checkpoint + slack
        case .maintain: false
        }
    }

    /// Weeks until the 7-day average reaches the checkpoint: (checkpoint − average) ÷ rate. 0 when
    /// reached; nil without a checkpoint or when the rate doesn't move towards it.
    public static func weeksToCheckpoint(average: Double, rate: Double, phase: CoachPlan.Phase) -> Double? {
        guard let checkpoint = WeightSignal.checkpoint(of: phase) else { return nil }
        if hasReached(average, checkpoint: checkpoint, goal: phase.goal) { return 0 }
        guard rate.isFinite, abs(rate) > slack else { return nil }
        let weeks = (checkpoint - average) / rate
        return weeks > 0 ? weeks : nil
    }

    /// The day the checkpoint is reached at `rate` (kg/week, signed).
    public static func checkpointDate(average: Double, rate: Double, on day: DayKey, phase: CoachPlan.Phase,
                                      calendar: Calendar = .current) -> DayKey? {
        guard let weeks = weeksToCheckpoint(average: average, rate: rate, phase: phase) else { return nil }
        return day.adding(days: Int((weeks * 7).rounded()), calendar: calendar)
    }

    /// When the checkpoint comes at the ends of the phase's rate range: the earliest day at the
    /// fast end, the latest at the slow end. nil unless both ends move towards it.
    public static func checkpointDates(average: Double, on day: DayKey, phase: CoachPlan.Phase,
                                       calendar: Calendar = .current) -> ClosedRange<DayKey>? {
        let range = phase.signedRateRange
        guard phase.goal != .maintain, range.lowerBound != 0, range.upperBound != 0,
              let first = checkpointDate(average: average, rate: range.lowerBound, on: day, phase: phase, calendar: calendar),
              let second = checkpointDate(average: average, rate: range.upperBound, on: day, phase: phase, calendar: calendar)
        else { return nil }
        return min(first, second)...max(first, second)
    }

    /// The first day whose 7-day average reached the checkpoint (never a single weigh-in), on or
    /// after the phase start. `averages`: the valid 7-day averages, in any order.
    public static func checkpointCrossing(_ averages: [Point], phase: CoachPlan.Phase) -> DayKey? {
        guard let checkpoint = WeightSignal.checkpoint(of: phase) else { return nil }
        return averages.sorted { $0.day < $1.day }.first { point in
            (phase.start.map { point.day >= $0 } ?? true) && hasReached(point.kilograms, checkpoint: checkpoint, goal: phase.goal)
        }?.day
    }

    /// The first day from the phase start through `day` whose valid 7-day average reached the checkpoint.
    public func checkpointCrossing(of phase: CoachPlan.Phase, through day: DayKey) -> DayKey? {
        guard let start = phase.start, start <= day, WeightSignal.checkpoint(of: phase) != nil else { return nil }
        return WeightSignal.checkpointCrossing(averages(from: start, through: day), phase: phase)
    }

    // MARK: Noise band

    /// The personal day-to-day swing: standard deviation of (morning weight − centred 7-day
    /// average) over the 28 days ending on `day` ("your normal day-to-day swing ±0.6 kg"). A
    /// centred average needs 4 morning weights (days after `day` aren't looked at); nil with
    /// fewer than 10 such days.
    public func noiseBand(on day: DayKey, days count: Int = WeightSignal.noiseDays) -> Double? {
        let start = day.adding(days: -(max(1, count) - 1), calendar: calendar)
        var residuals: [Double] = []
        for reading in mornings(from: start, through: day) {
            let from = reading.day.adding(days: -3, calendar: calendar)
            let to = min(reading.day.adding(days: 3, calendar: calendar), day)
            let values = mornings(from: from, through: to).map(\.kilograms)
            guard values.count >= WeightSignal.averageMinimum, let centred = WeightSignal.mean(values) else { continue }
            residuals.append(reading.kilograms - centred)
        }
        guard residuals.count >= WeightSignal.noiseMinimum, let mean = WeightSignal.mean(residuals) else { return nil }
        let variance = residuals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(residuals.count - 1)
        return variance.squareRoot()
    }

    // MARK: Summary

    /// Everything the weight card, phase card, check-in, widget and watch show for a day.
    public struct Summary: Codable, Equatable, Sendable {
        public var day: DayKey
        public var average: Average
        /// The weight for body math (average, else trend, else latest).
        public var bodyWeight: Estimate?
        public var weeklyChange: Change?
        public var rate: Rate
        /// Display only.
        public var crossCheck: Double?
        /// The active phase.
        public var phaseID: String?
        /// nil without an active phase with a range.
        public var status: Status?
        public var startWeight: Double?
        /// The 7-day average against the phase start weight.
        public var sinceStart: Change?
        public var corridor: ClosedRange<Double>?
        public var projectedEnd: Double?
        public var checkpoint: Double?
        public var weeksToCheckpoint: Double?
        /// The first day the 7-day average reached the checkpoint.
        public var checkpointReached: DayKey?
        public var noise: Double?
        /// A Health weight is among the morning weights of the average or the rate.
        public var usesHealth: Bool
    }

    /// The summary on a day with the plan's rules. `fallbackWeight`: the imported or typed weight
    /// for the phase start weight when the weigh-ins don't give one.
    public func summary(on day: DayKey, plan: CoachPlan, fallbackWeight: Double? = nil) -> Summary {
        let average = self.average(on: day)
        let rate = self.rate(on: day, plan: plan)
        let phase = plan.activePhase(on: day)
        let start = phase.flatMap { startWeight(of: $0, fallback: fallbackWeight) }
        let checkpoint = phase.flatMap { WeightSignal.checkpoint(of: $0) }
        var weeks: Double?
        if let phase, let value = average.value {
            if let checkpoint, WeightSignal.hasReached(value, checkpoint: checkpoint, goal: phase.goal) {
                weeks = 0
            } else if let rate = rate.value {
                weeks = WeightSignal.weeksToCheckpoint(average: value, rate: rate, phase: phase)
            }
        }
        let averageStart = day.adding(days: -(WeightSignal.averageDays - 1), calendar: calendar)
        return Summary(
            day: day,
            average: average,
            bodyWeight: bodyWeight(on: day),
            weeklyChange: weeklyChange(on: day),
            rate: rate,
            crossCheck: crossCheckRate(on: day),
            phaseID: phase?.id,
            status: phase.flatMap { WeightSignal.status(rate: rate.value, phase: $0, tolerance: plan.adjust.tolerance) },
            startWeight: start,
            sinceStart: start.flatMap { start in average.value.map { Change(from: start, to: $0) } },
            corridor: phase.flatMap { phase in start.flatMap { WeightSignal.corridor(startWeight: $0, phase: phase, on: day, calendar: calendar) } },
            projectedEnd: phase.flatMap { projectedEndWeight(of: $0, on: day, rate: rate.value) },
            checkpoint: checkpoint,
            weeksToCheckpoint: weeks,
            checkpointReached: phase.flatMap { checkpointCrossing(of: $0, through: day) },
            noise: noiseBand(on: day),
            usesHealth: rate.usesHealth || usesHealth(from: averageStart, through: day)
        )
    }

    // MARK: Helpers

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func firstIndex(onOrAfter day: DayKey) -> Int {
        var low = 0, high = days.count
        while low < high {
            let middle = (low + high) / 2
            if days[middle] < day { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private func lastIndex(onOrBefore day: DayKey) -> Int? {
        var low = 0, high = days.count
        while low < high {
            let middle = (low + high) / 2
            if days[middle] <= day { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}

// MARK: - Status line

extension WeightSignal {
    /// What the Today phase line, the Body page and the watch say about the active phase, in the
    /// check-in's words and by its rules: the weight signal's status; "Off track" only once the
    /// check-ins since the last calorie change were outside on the same side as often as the
    /// check-in asks (`adjust.confirmChecks`, at least 1) and the live rate is still on that side;
    /// "New targets since Tue · first look Mon 21 Jan" while the rate restarts after a calorie
    /// change; "Paused · until 12 Feb" while coaching is paused.
    public struct StatusLine: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            /// The weight signal's status (in range, slower, faster, gathering data).
            case status(Status)
            case offTrack
            /// The rate restarted at a calorie change on `since` and can be judged at the
            /// check-in on `firstLook`.
            case newTargets(since: DayKey, firstLook: DayKey)
            /// Coaching paused since `since`, until `until` (nil = until resumed).
            case paused(since: DayKey, until: DayKey?)
        }

        public enum Tone: String, Sendable {
            case good, watch, alert, neutral
        }

        public var state: State
        /// The day it was worked out for.
        public var day: DayKey

        public init(state: State, day: DayKey) {
            self.state = state
            self.day = day
        }

        public var tone: Tone {
            switch state {
            case .status(.inRange): .good
            case .status(.slower), .status(.faster): .watch
            case .offTrack: .alert
            case .status(.gathering), .newTargets, .paused: .neutral
            }
        }

        public var isPaused: Bool {
            if case .paused = state { return true }
            return false
        }

        /// "In range", "Off track", "New targets since Tue · first look Mon 21 Jan", "Paused ·
        /// until 12 Feb". `date` writes a day without its weekday ("21 Jan"; the app passes its
        /// locale's format).
        public func text(date: (DayKey) -> String = StatusLine.shortDate, calendar: Calendar = .current) -> String {
            switch state {
            case .status(let status):
                return status.title
            case .offTrack:
                return CheckInVerdict.offTarget.title
            case .newTargets(let since, let firstLook):
                let ago = since.days(to: day, calendar: calendar)
                var sinceText = StatusLine.weekday(since, calendar: calendar)
                if ago < 0 || ago >= 7 { sinceText += " " + date(since) }
                return "New targets since \(sinceText) · first look \(StatusLine.weekday(firstLook, calendar: calendar)) \(date(firstLook))"
            case .paused(let since, let until):
                if let until { return "Paused · until \(date(until))" }
                return "Paused · since \(date(since))"
            }
        }

        /// "21 Jan".
        public static func shortDate(_ day: DayKey) -> String {
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return "\(day.day) \(months[max(1, min(12, day.month)) - 1])"
        }

        /// "Mon".
        static func weekday(_ day: DayKey, calendar: Calendar) -> String {
            Weekdays.shortNames[max(1, min(7, day.weekday(calendar: calendar))) - 1]
        }
    }

    /// The status line of the phase active on `day`; nil without an active phase, or when it has
    /// no rate range and coaching isn't paused (the app says "No rate set").
    /// - Parameters:
    ///   - rate: the decision rate on `day` (`rate(on:plan:)`, or `Summary.rate`).
    ///   - checkIns: the saved check-ins (any order; other phases are left out).
    public static func statusLine(on day: DayKey, plan: CoachPlan, rate: Rate, checkIns: [CheckInSnapshot],
                                  calendar: Calendar = .current) -> StatusLine? {
        guard let phase = plan.activePhase(on: day) else { return nil }
        if let pause = plan.pause(on: day) {
            return StatusLine(state: .paused(since: pause.start, until: pause.end), day: day)
        }
        guard let status = WeightSignal.status(rate: rate.value, phase: phase, tolerance: plan.adjust.tolerance) else { return nil }
        let change = plan.lastCalorieChange(on: day, inForce: true)
        guard let value = rate.value, status != .gathering else {
            // The window starts at a calorie change: say so instead of "Gathering data".
            if let change, change.from == rate.window.start {
                let first = CheckInEngine.firstAdjustmentCheck(plan: plan, on: day, windowStart: rate.window.start, calendar: calendar)
                return StatusLine(state: .newTargets(since: change.from, firstLook: first), day: day)
            }
            return StatusLine(state: .status(status), day: day)
        }
        guard status.isOutside, let side = CheckInEngine.deviation(rate: value, phase: phase, tolerance: plan.adjust.tolerance) else {
            return StatusLine(state: .status(status), day: day)
        }
        // The saved check-ins that judged the targets in force, newest first, on the live side.
        let counted = checkIns
            .filter { snapshot in
                snapshot.phaseID == phase.id && snapshot.day <= day && (change.map { $0.covers(checkInOn: snapshot.day) } ?? true)
            }
            .sorted { $0.day > $1.day }
        var inARow = 0
        for snapshot in counted {
            guard snapshot.deviation == side else { break }
            inARow += 1
        }
        let confirm = max(1, plan.adjust.confirmChecks)
        return StatusLine(state: inARow >= confirm ? .offTrack : .status(status), day: day)
    }
}
