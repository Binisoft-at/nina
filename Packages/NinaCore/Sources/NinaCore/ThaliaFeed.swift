import Foundation

// What Nina hands Thalia through the Binisoft exchange (format v1, ExchangeFormat.swift): one `value`
// fact per metric and day – the day's eaten kcal, protein, carbs and fat, its water and its morning
// weight – built from plain records, and `source.json` with the six metrics as refs.
// `ThaliaExchangeWriter` writes them; the app (App/Sources/Services/ThaliaExchange.swift) fetches the
// records from the synced store and runs the passes. Never values from Apple Health, never on the
// watch. Owner doc: docs/THALIA.md.

/// Nina's side of the exchange with Thalia.
public enum ThaliaFeed {
    /// Nina's folder in the App Group (the app's display name): `<group>/Nina/exchange/…`.
    public static let folderName = "Nina"
    /// The `source` of every file Nina writes ("nina").
    public static let source = BinisoftExchange.sourceID(folderName)
    /// Thalia's folder (its `catalog.json`, which Nina may read but doesn't need).
    public static let thaliaFolderName = "Thalia"

    /// The metrics Nina delivers, in this order: the day's sums, then the morning weight (agg last).
    public static let metricIDs = ["kcal", "protein_g", "carbs_g", "fat_g", "water_ml", "body_weight_kg"]
    public static let metrics: [ExchangeMetric] = metricIDs.compactMap(ExchangeMetric.named)

    /// `source.json` → `refs`: the six metrics, kind "metric", with their German titles.
    public static let refs: [ExchangeRef] = metrics.map { ExchangeRef(id: $0.id, title: $0.title, kind: "metric") }

    /// A diary entry as plain values (`LogEntry`).
    public struct FoodRecord: Equatable, Sendable {
        /// The synced id (the entry's uuid).
        public var id: String
        /// Nina's diary day ("2026-11-22", `LogEntry.day` – it already follows the day-start hour).
        /// Empty or broken: the day of `time` in the pass's time zone.
        public var day: String
        /// When it was eaten.
        public var time: Date
        /// kcal (Nina stores and shows kcal); nil when the entry has no energy value.
        public var energy: Double?
        /// Grams; nil when the entry has no value for it (`NutrientValues` leaves the key out) –
        /// different from a 0 that was entered.
        public var protein: Double?
        public var carbs: Double?
        public var fat: Double?
        /// Eaten (not planned, not skipped).
        public var isEaten: Bool
        public var isDeleted: Bool
        /// Came from Apple Health – never counts. Nina records none today.
        public var isFromHealth: Bool

        public init(id: String, day: String, time: Date, energy: Double?, protein: Double?, carbs: Double?, fat: Double?,
                    isEaten: Bool = true, isDeleted: Bool = false, isFromHealth: Bool = false) {
            self.id = id
            self.day = day
            self.time = time
            self.energy = energy
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.isEaten = isEaten
            self.isDeleted = isDeleted
            self.isFromHealth = isFromHealth
        }
    }

    /// A water log as plain values (`WaterLog`).
    public struct WaterRecord: Equatable, Sendable {
        public var id: String
        /// Nina's diary day (`WaterLog.day`); empty or broken: the day of `time`.
        public var day: String
        public var time: Date
        public var milliliters: Double
        public var isDeleted: Bool
        /// Came from Apple Health – never counts. Nina records none today.
        public var isFromHealth: Bool

        public init(id: String, day: String, time: Date, milliliters: Double, isDeleted: Bool = false, isFromHealth: Bool = false) {
            self.id = id
            self.day = day
            self.time = time
            self.milliliters = milliliters
            self.isDeleted = isDeleted
            self.isFromHealth = isFromHealth
        }
    }

    /// A weigh-in as plain values (`WeightEntry`: typed on any device, from the watch, a
    /// notification or Siri, or imported history). Weights read from Apple Health are never
    /// stored in Nina, so they never become a record; should one ever be marked as from Health,
    /// it never counts.
    public struct WeightRecord: Equatable, Sendable {
        /// The synced id (the weigh-in's uuid).
        public var id: String
        /// Nina's diary day (`WeightEntry.day`); empty or broken: the day of `time`.
        public var day: String
        public var time: Date
        public var kilograms: Double
        public var isDeleted: Bool
        /// Imported history (`HealthWeightSync.isImported(note:)`): Nina doesn't write it to Health,
        /// but it is the person's own weigh-in in Nina's diary, so it counts for Thalia.
        public var isImported: Bool
        /// A weight from Apple Health – never counts. Nina stores none.
        public var isFromHealth: Bool

        public init(id: String, day: String, time: Date, kilograms: Double, isDeleted: Bool = false,
                    isImported: Bool = false, isFromHealth: Bool = false) {
            self.id = id
            self.day = day
            self.time = time
            self.kilograms = kilograms
            self.isDeleted = isDeleted
            self.isImported = isImported
            self.isFromHealth = isFromHealth
        }
    }

    /// Which weigh-in is a day's weight: Nina's morning rule (`WeightSignal`) – the earliest weigh-in
    /// of the diary day before the morning cutoff, else the day's earliest.
    public struct WeighInRule: Equatable, Sendable {
        /// Minutes after midnight before which a weigh-in counts as the morning weight
        /// (`plan.routine.morningCutoffMinutes`, 660 = 11:00).
        public var cutoffMinutes: Int
        /// The profile's day start, so a weigh-in after midnight can still belong to the evening before.
        public var dayStartHour: Int

        public init(cutoffMinutes: Int = 660, dayStartHour: Int = 0) {
            self.cutoffMinutes = cutoffMinutes
            self.dayStartHour = dayStartHour
        }
    }

    /// Whether a diary entry's `source` marks it as taken from Apple Health. Nina writes to Health
    /// but never imports foods or water from it, so no entry has such a source today; should one
    /// ever exist, it never reaches Thalia.
    public static func isHealthSource(_ source: String) -> Bool {
        ["health", "healthkit", "apple-health", "applehealth"].contains(source.lowercased())
    }

    /// The facts of the window `today` − `BinisoftExchange.keepDays` … `today`, by day: one per metric
    /// and day.
    ///
    /// - kcal, protein, carbs, fat: the sum of the day's eaten entries that have a value for the
    ///   metric. A metric no entry of the day has a value for is left out that day (quick entries
    ///   with calories only give no protein); a 0 that was entered stays 0.
    /// - water: the sum of the day's water logs (a real 0 stays 0).
    /// - body weight: the day's morning weigh-in by `rule` (see `WeighInRule`), 25–300 kg only,
    ///   to 0.1 kg, `at` = that weigh-in's time.
    ///
    /// Planned, skipped, deleted and Health records never count; days after `today` and before the
    /// window are left out. `at` of a sum is the time of the day's latest record with a value for
    /// that metric. Times are in `timeZone`, cut to the whole second. The same records in any order
    /// give the same facts.
    public static func facts(food: [FoodRecord], water: [WaterRecord], weights: [WeightRecord] = [],
                             rule: WeighInRule = WeighInRule(), today: String,
                             timeZone: TimeZone = .current) -> [String: [ExchangeFact]] {
        guard BinisoftExchange.isDay(today), let first = BinisoftExchange.day(today, adding: -BinisoftExchange.keepDays) else { return [:] }
        func day(_ raw: String, _ time: Date) -> String? {
            let day = BinisoftExchange.isDay(raw) ? raw : ExchangeDate.day(wholeSecond(time), timeZone: timeZone)
            return day >= first && day <= today ? day : nil
        }

        // Sums in a fixed order (by id), so every device gets the same bits: day → metric → sum.
        var sums: [String: [String: Sum]] = [:]
        func add(_ metric: String, _ value: Double?, day key: String, time: Date) {
            guard let value, value.isFinite else { return }
            var sum = sums[key]?[metric] ?? Sum(total: 0, latest: time)
            sum.total += value
            sum.latest = max(sum.latest, time)
            sums[key, default: [:]][metric] = sum
        }
        for record in food.sorted(by: { $0.id < $1.id })
        where record.isEaten && !record.isDeleted && !record.isFromHealth {
            guard let key = day(record.day, record.time) else { continue }
            add("kcal", record.energy, day: key, time: record.time)
            add("protein_g", record.protein, day: key, time: record.time)
            add("carbs_g", record.carbs, day: key, time: record.time)
            add("fat_g", record.fat, day: key, time: record.time)
        }
        for record in water.sorted(by: { $0.id < $1.id }) where !record.isDeleted && !record.isFromHealth {
            guard let key = day(record.day, record.time) else { continue }
            // A water log always has its amount: a broken one counts as 0, so the day still shows.
            add("water_ml", record.milliliters.isFinite ? record.milliliters : 0, day: key, time: record.time)
        }

        var result: [String: [ExchangeFact]] = [:]
        for (key, metricSums) in sums {
            for metric in metrics {
                guard let sum = metricSums[metric.id] else { continue }
                result[key, default: []].append(fact(metric, day: key, value: sum.total, at: sum.latest, timeZone: timeZone))
            }
        }
        if let metric = ExchangeMetric.named("body_weight_kg") {
            for (key, weighIn) in morningWeighIns(weights, rule: rule, timeZone: timeZone, day: day) {
                result[key, default: []].append(fact(metric, day: key, value: weighIn.kilograms, at: weighIn.time, timeZone: timeZone))
            }
        }
        return result.mapValues { $0.sorted { ($0.at ?? "", $0.id) < ($1.at ?? "", $1.id) } }
    }

    /// A running sum of one metric on one day.
    private struct Sum {
        var total: Double
        var latest: Date
    }

    /// The weigh-in that is each day's weight: the earliest live, plausible (`WeightSignal.plausibleRange`)
    /// weigh-in of the diary day before `rule`'s cutoff, else the day's earliest. Imported history
    /// counts; Health never does. Ties in the same second go by id, so every device picks the same one.
    static func morningWeighIns(_ weights: [WeightRecord], rule: WeighInRule, timeZone: TimeZone,
                                day: (String, Date) -> String?) -> [String: WeightRecord] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var byDay: [String: [WeightRecord]] = [:]
        for record in weights where !record.isDeleted && !record.isFromHealth && record.kilograms.isFinite
            && WeightSignal.plausibleRange.contains(record.kilograms) {
            guard let key = day(record.day, record.time) else { continue }
            byDay[key, default: []].append(record)
        }
        var result: [String: WeightRecord] = [:]
        for (key, list) in byDay {
            guard let diaryDay = DayKey(key) else { continue }
            let sorted = list.sorted { (wholeSecond($0.time), $0.id) < (wholeSecond($1.time), $1.id) }
            let morning = sorted.first { record in
                WeightSignal.Reading(day: diaryDay, time: wholeSecond(record.time), kilograms: record.kilograms)
                    .isMorning(cutoffMinutes: rule.cutoffMinutes, dayStartHour: rule.dayStartHour, calendar: calendar)
            }
            if let chosen = morning ?? sorted.first { result[key] = chosen }
        }
        return result
    }

    /// One day's figure: id "<metric>-<day>" (the same on every device), kind `value`, ref = the metric.
    static func fact(_ metric: ExchangeMetric, day: String, value: Double, at: Date, timeZone: TimeZone) -> ExchangeFact {
        ExchangeFact(id: "\(metric.id)-\(day)", kind: ExchangeKind.value.rawValue, ref: metric.id, refTitle: metric.title,
                     value: rounded(value, unit: metric.unit), unit: metric.unit, metric: metric.id,
                     at: ExchangeDate.string(wholeSecond(at), timeZone: timeZone), origin: .app)
    }

    /// `date` without its fraction of a second (cut, never rounded up). CloudKit keeps dates to the
    /// millisecond, so another device may hold 19:00:30.999 for this device's 19:00:30.9996 – both
    /// become 19:00:30 (`ExchangeDate.string` alone would round the second one up to 19:00:31).
    static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// kcal and ml to whole numbers, grams and kilograms to 0.1 – so every device writes the same
    /// bytes. Never "-0".
    public static func rounded(_ value: Double, unit: String) -> Double {
        let result = unit == "g" || unit == "kg" ? (value * 10).rounded() / 10 : value.rounded()
        return result == 0 || !result.isFinite ? 0 : result
    }

    // MARK: source.json and the catalog

    /// `source.json` as Nina writes it: source "nina", app "Nina", the version, the six refs.
    public static func sourceInfo(appVersion: String, now: Date, timeZone: TimeZone = .current) -> ExchangeSourceInfo {
        ExchangeSourceInfo(source: source, app: folderName, appVersion: appVersion,
                           generatedAt: ExchangeDate.string(now, timeZone: timeZone), refs: refs)
    }

    /// `<group>/Thalia/exchange/catalog.json` – Thalia's structure. Nina uses nothing from it (no
    /// category choice), it may only read it.
    public static func catalogURL(groupRoot: URL) -> URL {
        BinisoftExchange.exchangeFolder(appFolder: groupRoot.appendingPathComponent(thaliaFolderName, isDirectory: true))
            .appendingPathComponent(BinisoftExchange.catalogFileName)
    }

    /// Thalia's catalog, read tolerantly; nil when it is missing or can't be used.
    public static func catalog(_ data: Data?) -> ExchangeCatalog? {
        guard let data, case .success(let catalog) = ExchangeReader.catalog(data) else { return nil }
        return catalog
    }

    // MARK: Settings → Thalia

    /// The line under the switch in Settings, in German like the section: "Aus" when off, "Noch
    /// nichts geschrieben" before the first write on this device, else "Zuletzt geschrieben: 22. Nov.
    /// 2030, 21:15" (de_AT).
    public static func statusLine(isOn: Bool, lastWritten: Date?, timeZone: TimeZone = .current) -> String {
        guard isOn else { return "Aus" }
        guard let lastWritten else { return "Noch nichts geschrieben" }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "de_AT"),
                                     calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
        return "Zuletzt geschrieben: \(lastWritten.formatted(style))"
    }
}
