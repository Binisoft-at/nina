import Foundation

/// Writes a source's files of the Binisoft exchange (format v1) into its folder `<group>/<App>`:
/// the day files `exchange/days/<YYYY-MM-DD>.json` and `exchange/source.json`. File system only, so
/// any folder works (tests use temporary ones). The caller posts `BinisoftExchange.changedNotification`
/// once per pass when something was written.
public enum ThaliaExchangeWriter {
    /// Brings the day files in line with `facts` (day → that day's facts) for `today` and the
    /// `BinisoftExchange.keepDays` days before it:
    ///
    /// - facts sorted by (`at`, `id`), so every device writes the same content;
    /// - a day without facts and without a file stays without one ("no information");
    /// - a day whose file holds the same facts is left alone (compared without `generatedAt`);
    /// - every other day is written atomically with `generatedAt` = `now` – a day that had a file and
    ///   now has no facts gets `"facts":[]`, so the reader removes them;
    /// - day files older than `keepDays` are deleted.
    ///
    /// Facts for days outside the window are ignored. Returns whether a file was written or deleted.
    @discardableResult
    public static func sync(_ facts: [String: [ExchangeFact]], source: String, appFolder: URL, today: String, now: Date,
                            timeZone: TimeZone = .current) throws -> Bool {
        guard BinisoftExchange.isDay(today) else { return false }
        var changed = false
        let generatedAt = ExchangeDate.string(now, timeZone: timeZone)
        for offset in 0...BinisoftExchange.keepDays {
            guard let day = BinisoftExchange.day(today, adding: -offset) else { continue }
            let dayFacts = (facts[day] ?? []).sorted { ($0.at ?? "", $0.id) < ($1.at ?? "", $1.id) }
            let url = BinisoftExchange.dayFileURL(appFolder: appFolder, day: day)
            let old = try? Data(contentsOf: url)
            if old == nil, dayFacts.isEmpty { continue }
            if let old, case .success(let read) = ExchangeReader.dayFile(old, fileName: BinisoftExchange.dayFileName(day)) {
                let same = ExchangeDayFile(source: source, day: day, generatedAt: read.file.generatedAt, facts: dayFacts)
                if try same.encoded() == old { continue }
            }
            let file = ExchangeDayFile(source: source, day: day, generatedAt: generatedAt, facts: dayFacts)
            try BinisoftExchange.write(try file.encoded(), to: url)
            changed = true
        }
        return try removeExpired(appFolder: appFolder, today: today) || changed
    }

    /// Deletes the day files older than `BinisoftExchange.keepDays` before `today`; whether one went.
    @discardableResult
    public static func removeExpired(appFolder: URL, today: String) throws -> Bool {
        let folder = BinisoftExchange.daysFolder(appFolder: appFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let expired = BinisoftExchange.expiredDayFiles(names, today: today)
        for name in expired {
            try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        return !expired.isEmpty
    }

    /// The heartbeat rule for `source.json`: write when there is none (or it can't be read), when its
    /// format version, source, app, app version or refs differ from `info`, or when the last one was
    /// written on another day than `today` (at most once a day otherwise).
    public static func needsSourceWrite(_ info: ExchangeSourceInfo, existing: Data?, today: String,
                                        timeZone: TimeZone = .current) -> Bool {
        guard let existing, case .success(let old) = ExchangeReader.source(existing) else { return true }
        guard old.v == info.v, old.source == info.source, old.app == info.app, old.appVersion == info.appVersion,
              old.refs == info.refs, let date = old.generatedDate else { return true }
        return ExchangeDate.day(date, timeZone: timeZone) != today
    }

    /// Writes `exchange/source.json` atomically when `needsSourceWrite` says so; whether it was written.
    @discardableResult
    public static func syncSource(_ info: ExchangeSourceInfo, appFolder: URL, today: String,
                                  timeZone: TimeZone = .current) throws -> Bool {
        let url = BinisoftExchange.exchangeFolder(appFolder: appFolder).appendingPathComponent(BinisoftExchange.sourceFileName)
        guard needsSourceWrite(info, existing: try? Data(contentsOf: url), today: today, timeZone: timeZone) else { return false }
        try BinisoftExchange.write(try BinisoftExchange.encode(info), to: url)
        return true
    }
}
