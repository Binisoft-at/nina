import Foundation

// What Nina hands Thalia through the Binisoft exchange (format v1, ExchangeFormat.swift): one `value`
// fact per metric and day – the day's eaten kcal, protein, carbs and fat, and its water – built from
// plain records, and `source.json` with the five metrics as refs. `ThaliaExchangeWriter` writes them;
// the app (App/Sources/Services/ThaliaExchange.swift) fetches the records from the synced store and
// runs the passes. Never values from Apple Health, never on the watch. Owner doc: docs/THALIA.md.

/// Nina's side of the exchange with Thalia.
public enum ThaliaFeed {
    /// Nina's folder in the App Group (the app's display name): `<group>/Nina/exchange/…`.
    public static let folderName = "Nina"
    /// The `source` of every file Nina writes ("nina").
    public static let source = BinisoftExchange.sourceID(folderName)
    /// Thalia's folder (its `catalog.json`, which Nina may read but doesn't need).
    public static let thaliaFolderName = "Thalia"

    /// The metrics Nina delivers, in this order (all summed per day).
    public static let metricIDs = ["kcal", "protein_g", "carbs_g", "fat_g", "water_ml"]
    public static let metrics: [ExchangeMetric] = metricIDs.compactMap(ExchangeMetric.named)

    /// `source.json` → `refs`: the five metrics, kind "metric", with their German titles.
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
        /// kcal – stored values are always kcal, whatever unit Nina shows.
        public var energy: Double
        /// Grams.
        public var protein: Double
        public var carbs: Double
        public var fat: Double
        /// Eaten (not planned, not skipped).
        public var isEaten: Bool
        public var isDeleted: Bool
        /// Came from Apple Health – never counts. Nina records none today.
        public var isFromHealth: Bool

        public init(id: String, day: String, time: Date, energy: Double, protein: Double, carbs: Double, fat: Double,
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

    /// Whether a diary entry's `source` marks it as taken from Apple Health. Nina writes to Health
    /// but never imports foods or water from it, so no entry has such a source today; should one
    /// ever exist, it never reaches Thalia.
    public static func isHealthSource(_ source: String) -> Bool {
        ["health", "healthkit", "apple-health", "applehealth"].contains(source.lowercased())
    }

    /// The facts of the window `today` − `BinisoftExchange.keepDays` … `today`, by day: one per metric
    /// and day with the day's total. kcal, protein, carbs and fat only on days with eaten entries,
    /// water only on days with water logs (a real 0 stays 0). Planned, skipped, deleted and Health
    /// records never count; days after `today` and before the window are left out. `at` is the time
    /// of the day's latest record of that metric, in `timeZone`, cut to the whole second. The same
    /// records in any order give the same facts.
    public static func facts(food: [FoodRecord], water: [WaterRecord], today: String,
                             timeZone: TimeZone = .current) -> [String: [ExchangeFact]] {
        guard BinisoftExchange.isDay(today), let first = BinisoftExchange.day(today, adding: -BinisoftExchange.keepDays) else { return [:] }
        func day(_ raw: String, _ time: Date) -> String? {
            let day = BinisoftExchange.isDay(raw) ? raw : ExchangeDate.day(wholeSecond(time), timeZone: timeZone)
            return day >= first && day <= today ? day : nil
        }

        // Sums in a fixed order (by id), so every device gets the same bits.
        var meals: [String: (energy: Double, protein: Double, carbs: Double, fat: Double, latest: Date)] = [:]
        for record in food.sorted(by: { $0.id < $1.id })
        where record.isEaten && !record.isDeleted && !record.isFromHealth {
            guard let key = day(record.day, record.time) else { continue }
            var sums = meals[key] ?? (0, 0, 0, 0, record.time)
            sums.energy += finite(record.energy)
            sums.protein += finite(record.protein)
            sums.carbs += finite(record.carbs)
            sums.fat += finite(record.fat)
            sums.latest = max(sums.latest, record.time)
            meals[key] = sums
        }
        var drinks: [String: (milliliters: Double, latest: Date)] = [:]
        for record in water.sorted(by: { $0.id < $1.id }) where !record.isDeleted && !record.isFromHealth {
            guard let key = day(record.day, record.time) else { continue }
            var sums = drinks[key] ?? (0, record.time)
            sums.milliliters += finite(record.milliliters)
            sums.latest = max(sums.latest, record.time)
            drinks[key] = sums
        }

        var result: [String: [ExchangeFact]] = [:]
        for (key, sums) in meals {
            let values = ["kcal": sums.energy, "protein_g": sums.protein, "carbs_g": sums.carbs, "fat_g": sums.fat]
            for metric in metrics {
                guard let value = values[metric.id] else { continue }
                result[key, default: []].append(fact(metric, day: key, value: value, at: sums.latest, timeZone: timeZone))
            }
        }
        for (key, sums) in drinks {
            guard let metric = ExchangeMetric.named("water_ml") else { continue }
            result[key, default: []].append(fact(metric, day: key, value: sums.milliliters, at: sums.latest, timeZone: timeZone))
        }
        return result.mapValues { $0.sorted { ($0.at ?? "", $0.id) < ($1.at ?? "", $1.id) } }
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

    /// kcal and ml to whole numbers, grams to 0.1 – so every device writes the same bytes. Never "-0".
    public static func rounded(_ value: Double, unit: String) -> Double {
        let result = unit == "g" ? (value * 10).rounded() / 10 : value.rounded()
        return result == 0 || !result.isFinite ? 0 : result
    }

    static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

    // MARK: source.json and the catalog

    /// `source.json` as Nina writes it: source "nina", app "Nina", the version, the five refs.
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
}
