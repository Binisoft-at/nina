import Foundation
import Testing
@testable import NinaCore

/// What Nina hands Thalia (Binisoft exchange, format v1): the day facts, the day files and
/// `source.json`. Neutral made-up records; the fixtures in Fixtures/exchange are Thalia's.
@Suite("Thalia exchange")
struct ThaliaExchangeTests {
    static let vienna = TimeZone(identifier: "Europe/Vienna") ?? .current
    static let utc = TimeZone(identifier: "UTC") ?? .current
    static let today = "2026-11-22"

    static func time(_ text: String) -> Date {
        ExchangeDate.parse(text) ?? Date(timeIntervalSince1970: 0)
    }

    /// Breakfast, lunch and dinner on the 22nd: 1,785.6 kcal, 104.56 g protein, 182.48 g carbs, 60.64 g fat.
    static let meals: [ThaliaFeed.FoodRecord] = [
        ThaliaFeed.FoodRecord(id: "entry-1", day: today, time: time("2026-11-22T07:15:00+01:00"),
                              energy: 410, protein: 21.3, carbs: 52.15, fat: 12.04),
        ThaliaFeed.FoodRecord(id: "entry-2", day: today, time: time("2026-11-22T12:30:00+01:00"),
                              energy: 655.4, protein: 38.26, carbs: 70, fat: 20.5),
        ThaliaFeed.FoodRecord(id: "entry-3", day: today, time: time("2026-11-22T19:00:30.250+01:00"),
                              energy: 720.2, protein: 45, carbs: 60.33, fat: 28.1),
    ]

    /// Three glasses on the 22nd: 1,080.4 ml.
    static let drinks: [ThaliaFeed.WaterRecord] = [
        ThaliaFeed.WaterRecord(id: "water-1", day: today, time: time("2026-11-22T08:00:00+01:00"), milliliters: 250),
        ThaliaFeed.WaterRecord(id: "water-2", day: today, time: time("2026-11-22T14:10:00+01:00"), milliliters: 500),
        ThaliaFeed.WaterRecord(id: "water-3", day: today, time: time("2026-11-22T21:00:00+01:00"), milliliters: 330.4),
    ]

    static func facts(_ food: [ThaliaFeed.FoodRecord] = meals, _ water: [ThaliaFeed.WaterRecord] = drinks,
                      today: String = today, timeZone: TimeZone = vienna) -> [String: [ExchangeFact]] {
        ThaliaFeed.facts(food: food, water: water, today: today, timeZone: timeZone)
    }

    static func value(_ facts: [ExchangeFact]?, _ metric: String) -> Double? {
        facts?.first { $0.metric == metric }?.value
    }

    // MARK: 1. Facts

    @Test func factsHaveTheExchangeShape() throws {
        let day = try #require(Self.facts()[Self.today])
        #expect(day.map(\.id).sorted() == ["carbs_g-2026-11-22", "fat_g-2026-11-22", "kcal-2026-11-22", "protein_g-2026-11-22",
                                           "water_ml-2026-11-22"])
        let pattern = try Regex(#"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})"#)
        for fact in day {
            let metric = try #require(fact.knownMetric)
            #expect(fact.kind == "value")
            #expect(fact.knownKind == .value)
            #expect(fact.ref == metric.id)
            #expect(fact.metric == metric.id)
            #expect(fact.refTitle == metric.title)
            #expect(fact.unit == metric.unit)
            #expect(fact.origin == "app")
            #expect(fact.isFromApp)
            #expect(fact.title == nil)
            #expect(fact.thalia == nil)
            let at = try #require(fact.at)
            #expect(at.wholeMatch(of: pattern) != nil, "\(at)")
            #expect(!at.contains("."))
        }
        #expect(day.first { $0.metric == "kcal" }?.refTitle == "Kalorien")
        #expect(day.first { $0.metric == "carbs_g" }?.refTitle == "Kohlenhydrate")
        #expect(day.first { $0.metric == "fat_g" }?.refTitle == "Fett")
        #expect(day.first { $0.metric == "water_ml" }?.refTitle == "Wasser")
    }

    @Test func factsAreStableOnEveryDevice() throws {
        let first = Self.facts()
        let again = Self.facts()
        // Another device fetches the same records in another order.
        let shuffled = Self.facts(Self.meals.reversed(), [Self.drinks[1], Self.drinks[2], Self.drinks[0]])
        #expect(first == again)
        #expect(first == shuffled)
        let file = ExchangeDayFile(source: "nina", day: Self.today, generatedAt: "2026-11-22T21:15:00+01:00", facts: first[Self.today] ?? [])
        let other = ExchangeDayFile(source: "nina", day: Self.today, generatedAt: "2026-11-22T21:15:00+01:00", facts: shuffled[Self.today] ?? [])
        #expect(try file.encoded() == other.encoded())
    }

    @Test func atIsTheLatestRecordOfTheMetric() throws {
        let day = try #require(Self.facts()[Self.today])
        // The dinner at 19:00:30.250 without its fraction; water has its own latest time.
        #expect(day.first { $0.metric == "kcal" }?.at == "2026-11-22T19:00:30+01:00")
        #expect(day.first { $0.metric == "fat_g" }?.at == "2026-11-22T19:00:30+01:00")
        #expect(day.first { $0.metric == "water_ml" }?.at == "2026-11-22T21:00:00+01:00")
        // Sorted by at, then id.
        #expect(day.map(\.metric) == ["carbs_g", "fat_g", "kcal", "protein_g", "water_ml"])
    }

    @Test func atIsCutToTheWholeSecond() {
        // This device holds the dinner at …30.9996; another one got it through iCloud to the
        // millisecond (…30.999). Both write :30 – never :31 on one of them.
        var here = Self.meals
        here[2].time = Self.time("2026-11-22T19:00:30.9996+01:00")
        var there = Self.meals
        there[2].time = Self.time("2026-11-22T19:00:30.999+01:00")
        let mine = Self.facts(here, Self.drinks)
        #expect(mine == Self.facts(there, Self.drinks))
        #expect(mine[Self.today]?.first { $0.metric == "kcal" }?.at == "2026-11-22T19:00:30+01:00")
        // The same for the day of a record without a stored day: 23:59:59.9996 stays on its day.
        let late = ThaliaFeed.FoodRecord(id: "late", day: "", time: Self.time("2026-11-22T23:59:59.9996+01:00"),
                                         energy: 100, protein: 1, carbs: 2, fat: 3)
        #expect(Self.facts([late], [])[Self.today]?.first?.at == "2026-11-22T23:59:59+01:00")
    }

    /// The exact bytes: keys sorted, compact, numbers without ".0", dates without fractions, facts
    /// by (at, id) – what every device writes for the same diary.
    @Test func theFilesAreTheseBytes() throws {
        let folder = TemporaryFolder()
        let now = Self.time("2026-11-22T21:15:00.700+01:00")
        try ThaliaExchangeWriter.sync(Self.facts(), source: ThaliaFeed.source, appFolder: folder.app, today: Self.today, now: now,
                                      timeZone: Self.vienna)
        let day = try String(decoding: Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today)),
                             as: UTF8.self)
        func fact(_ metric: String, _ title: String, _ unit: String, _ value: String, at: String) -> String {
            #"{"at":"\#(at)","id":"\#(metric)-2026-11-22","kind":"value","metric":"\#(metric)","origin":"app","ref":"\#(metric)","refTitle":"\#(title)","unit":"\#(unit)","value":\#(value)}"#
        }
        let dinner = "2026-11-22T19:00:30+01:00"
        let facts = [
            fact("carbs_g", "Kohlenhydrate", "g", "182.5", at: dinner), fact("fat_g", "Fett", "g", "60.6", at: dinner),
            fact("kcal", "Kalorien", "kcal", "1786", at: dinner), fact("protein_g", "Protein", "g", "104.6", at: dinner),
            fact("water_ml", "Wasser", "ml", "1080", at: "2026-11-22T21:00:00+01:00"),
        ]
        #expect(day == #"{"day":"2026-11-22","facts":["# + facts.joined(separator: ",")
            + #"],"generatedAt":"2026-11-22T21:15:00+01:00","source":"nina","v":1}"#)

        try ThaliaExchangeWriter.syncSource(ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: now, timeZone: Self.vienna),
                                            appFolder: folder.app, today: Self.today, timeZone: Self.vienna)
        let source = try String(decoding: Data(contentsOf: BinisoftExchange.exchangeFolder(appFolder: folder.app)
            .appendingPathComponent("source.json")), as: UTF8.self)
        let refs = [("kcal", "Kalorien"), ("protein_g", "Protein"), ("carbs_g", "Kohlenhydrate"), ("fat_g", "Fett"), ("water_ml", "Wasser")]
            .map { #"{"id":"\#($0.0)","kind":"metric","title":"\#($0.1)"}"# }
        #expect(source == #"{"app":"Nina","appVersion":"1.1.0","generatedAt":"2026-11-22T21:15:00+01:00","refs":["#
            + refs.joined(separator: ",") + #"],"source":"nina","v":1}"#)
    }

    @Test func valuesAreRoundedTheSameEverywhere() {
        #expect(ThaliaFeed.rounded(1785.6, unit: "kcal") == 1786)
        #expect(ThaliaFeed.rounded(104.56, unit: "g") == 104.6)
        #expect(ThaliaFeed.rounded(182.46, unit: "g") == 182.5)
        #expect(ThaliaFeed.rounded(1080.4, unit: "ml") == 1080)
        #expect(ThaliaFeed.rounded(-0.01, unit: "g").sign == .plus)
        #expect(ThaliaFeed.rounded(.nan, unit: "kcal") == 0)
        let day = Self.facts()[Self.today]
        #expect(Self.value(day, "kcal") == 1786)
        #expect(Self.value(day, "water_ml") == 1080)
    }

    // MARK: 2. The day in the device's time zone

    @Test func theDayFollowsTheTimeZone() throws {
        let late = Self.time("2026-11-22T23:30:00Z")
        #expect(ExchangeDate.day(late, timeZone: Self.vienna) == "2026-11-23")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.vienna
        // The diary day Nina stores for it when it is logged in Vienna.
        #expect(DayKey(date: late, calendar: calendar).rawValue == "2026-11-23")

        // A record without a stored day falls back to the time's day.
        let snack = ThaliaFeed.FoodRecord(id: "late", day: "", time: late, energy: 200, protein: 4, carbs: 30, fat: 7)
        let inVienna = Self.facts([snack], [], today: "2026-11-23")
        #expect(inVienna["2026-11-22"] == nil)
        #expect(inVienna["2026-11-23"]?.first { $0.metric == "kcal" }?.at == "2026-11-23T00:30:00+01:00")
        let inUTC = Self.facts([snack], [], today: "2026-11-23", timeZone: Self.utc)
        #expect(inUTC["2026-11-22"]?.first { $0.metric == "kcal" }?.at == "2026-11-22T23:30:00Z")

        // A stored diary day wins (the day-start hour already chose it).
        let stored = ThaliaFeed.FoodRecord(id: "late", day: "2026-11-22", time: late, energy: 200, protein: 4, carbs: 30, fat: 7)
        #expect(Self.facts([stored], [], today: "2026-11-23")["2026-11-22"]?.count == 4)
    }

    // MARK: 3. Write and read back

    @Test func writtenFilesReadBack() throws {
        let folder = TemporaryFolder()
        let facts = Self.facts()
        let now = Self.time("2026-11-22T21:15:00.700+01:00")
        #expect(try ThaliaExchangeWriter.sync(facts, source: ThaliaFeed.source, appFolder: folder.app, today: Self.today, now: now,
                                              timeZone: Self.vienna))
        let data = try Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today))
        let read = try ExchangeReader.dayFile(data, folder: "Nina", fileName: "2026-11-22.json").get()
        #expect(read.skipped.isEmpty)
        #expect(read.file.source == "nina")
        #expect(read.file.day == Self.today)
        #expect(read.file.v == 1)
        #expect(read.file.generatedAt == "2026-11-22T21:15:00+01:00")
        #expect(read.file.facts == facts[Self.today])
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("\n"))
        #expect(!text.contains("\\/"))

        let info = ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: now, timeZone: Self.vienna)
        #expect(try ThaliaExchangeWriter.syncSource(info, appFolder: folder.app, today: Self.today, timeZone: Self.vienna))
        let sourceURL = BinisoftExchange.exchangeFolder(appFolder: folder.app).appendingPathComponent("source.json")
        let source = try ExchangeReader.source(try Data(contentsOf: sourceURL), folder: "Nina").get()
        #expect(source.source == "nina")
        #expect(source.app == "Nina")
        #expect(source.appVersion == "1.1.0")
        #expect(source.refs == ThaliaFeed.refs)
    }

    @Test func sourceRefsAreTheFiveMetrics() {
        #expect(ThaliaFeed.source == "nina")
        #expect(ThaliaFeed.refs.map(\.id) == ["kcal", "protein_g", "carbs_g", "fat_g", "water_ml"])
        #expect(ThaliaFeed.refs.map(\.title) == ["Kalorien", "Protein", "Kohlenhydrate", "Fett", "Wasser"])
        #expect(ThaliaFeed.refs.allSatisfy { $0.kind == "metric" })
        #expect(!ThaliaFeed.metricIDs.contains("body_weight_kg"))
    }

    // MARK: 4. Syncing the day files

    @Test func unchangedFactsLeaveTheFileAlone() throws {
        let folder = TemporaryFolder()
        let url = BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today)
        try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        let before = try Data(contentsOf: url)
        let changed = try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                                    now: Self.time("2026-11-22T21:00:00+01:00"), timeZone: Self.vienna)
        #expect(!changed)
        let after = try Data(contentsOf: url)
        #expect(after == before)
        #expect(try ExchangeReader.dayFile(after).get().file.generatedAt == "2026-11-22T20:00:00+01:00")
    }

    @Test func aRemovedFactIsGoneFromTheFile() throws {
        let folder = TemporaryFolder()
        try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        // The water logs were deleted.
        let changed = try ThaliaExchangeWriter.sync(Self.facts(Self.meals, []), source: "nina", appFolder: folder.app,
                                                    today: Self.today, now: Self.time("2026-11-22T21:00:00+01:00"), timeZone: Self.vienna)
        #expect(changed)
        let file = try ExchangeReader.dayFile(Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today))).get().file
        #expect(file.facts.count == 4)
        #expect(!file.facts.contains { $0.metric == "water_ml" })
        #expect(file.generatedAt == "2026-11-22T21:00:00+01:00")
    }

    @Test func daysWithoutFactsOrFileGetNoFile() throws {
        let folder = TemporaryFolder()
        try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        let names = try FileManager.default.contentsOfDirectory(atPath: BinisoftExchange.daysFolder(appFolder: folder.app).path)
        #expect(names == ["2026-11-22.json"])
        // Nothing at all: no folder either.
        let empty = TemporaryFolder()
        #expect(try !ThaliaExchangeWriter.sync([:], source: "nina", appFolder: empty.app, today: Self.today, now: Date()))
        #expect(!FileManager.default.fileExists(atPath: BinisoftExchange.daysFolder(appFolder: empty.app).path))
    }

    @Test func aDayThatLostItsFactsGetsAnEmptyList() throws {
        let folder = TemporaryFolder()
        let url = BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today)
        try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        #expect(try ThaliaExchangeWriter.sync([:], source: "nina", appFolder: folder.app, today: Self.today,
                                              now: Self.time("2026-11-22T21:00:00+01:00"), timeZone: Self.vienna))
        let data = try Data(contentsOf: url)
        #expect(String(decoding: data, as: UTF8.self).contains("\"facts\":[]"))
        #expect(try ExchangeReader.dayFile(data, folder: "Nina", fileName: "2026-11-22.json").get().file.facts.isEmpty)
        // Switched off stays off: the next empty pass writes nothing.
        #expect(try !ThaliaExchangeWriter.sync([:], source: "nina", appFolder: folder.app, today: Self.today,
                                               now: Self.time("2026-11-22T22:00:00+01:00"), timeZone: Self.vienna))
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func expiredDayFilesAreDeleted() throws {
        let names = ["2026-09-20.json", "2026-09-21.json", "2026-11-22.json", ".x.json"]
        #expect(BinisoftExchange.expiredDayFiles(names, today: "2026-11-22") == ["2026-09-20.json"])

        let folder = TemporaryFolder()
        let days = BinisoftExchange.daysFolder(appFolder: folder.app)
        try FileManager.default.createDirectory(at: days, withIntermediateDirectories: true)
        for name in names {
            try Data("{}".utf8).write(to: days.appendingPathComponent(name))
        }
        #expect(try ThaliaExchangeWriter.sync(Self.facts(), source: "nina", appFolder: folder.app, today: Self.today,
                                              now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna))
        let left = try FileManager.default.contentsOfDirectory(atPath: days.path).sorted()
        #expect(left == [".x.json", "2026-09-21.json", "2026-11-22.json"])
        #expect(try !ThaliaExchangeWriter.removeExpired(appFolder: folder.app, today: Self.today))
    }

    @Test func aDayThatCantBeWrittenDoesntStopTheOthers() throws {
        let folder = TemporaryFolder()
        let yesterday = "2026-11-21"
        // A folder (not a file) sits where yesterday's file goes, so it can't be written.
        let blocked = BinisoftExchange.dayFileURL(appFolder: folder.app, day: yesterday)
        try FileManager.default.createDirectory(at: blocked.appendingPathComponent("x", isDirectory: true),
                                                withIntermediateDirectories: true)
        let old = BinisoftExchange.dayFileURL(appFolder: folder.app, day: "2026-09-01")
        try Data("{}".utf8).write(to: old)
        var records = Self.meals
        records.append(ThaliaFeed.FoodRecord(id: "entry-0", day: yesterday, time: Self.time("2026-11-21T13:00:00+01:00"),
                                             energy: 500, protein: 30, carbs: 50, fat: 15))
        do {
            try ThaliaExchangeWriter.sync(Self.facts(records, []), source: "nina", appFolder: folder.app, today: Self.today,
                                          now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
            Issue.record("yesterday's file can't be written")
        } catch let failure as ThaliaExchangeWriter.SyncFailure {
            #expect(failure.changed, "today was written, so the notification is still due")
            #expect(failure.reason.hasPrefix("2026-11-21.json"), "\(failure.reason)")
        }
        // Today was written and the expired file deleted all the same.
        let today = try ExchangeReader.dayFile(Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today))).get()
        #expect(today.file.facts.count == 4)
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func factsOutsideTheWindowAreIgnored() throws {
        let folder = TemporaryFolder()
        let fact = ExchangeFact(id: "kcal-2026-12-01", kind: "value", ref: "kcal", refTitle: "Kalorien", value: 100, unit: "kcal",
                                metric: "kcal", origin: .app)
        #expect(try !ThaliaExchangeWriter.sync(["2026-12-01": [fact], "2026-09-01": [fact]], source: "nina", appFolder: folder.app,
                                               today: Self.today, now: Date()))
    }

    // MARK: 5. Thalia's fixtures

    @Test func thaliasFixturesRead() throws {
        let nina = try ExchangeReader.dayFile(Fixture.data("Nina/exchange/days/2026-11-22.json"), folder: "Nina",
                                              fileName: "2026-11-22.json").get()
        #expect(nina.skipped.isEmpty)
        #expect(nina.file.source == "nina")
        #expect(nina.file.facts.count == 5)
        #expect(nina.file.generatedDate != nil)
        #expect(nina.file.facts.first { $0.metric == "fiber_g" }?.isKnown == false)
        #expect(nina.file.facts.first { $0.id == "kcal-hk" }?.isFromApp == false)

        for name in ["Theo", "George", "Demo"] {
            let info = try ExchangeReader.source(Fixture.data("\(name)/exchange/source.json"), folder: name).get()
            #expect(!info.refs.isEmpty)
            #expect(info.displayName == name)
        }

        let catalog = try #require(ThaliaFeed.catalog(try Fixture.data("Thalia/exchange/catalog.json")))
        #expect(catalog.source == "thalia")
        #expect(catalog.measures.count == 3)
        #expect(catalog.categories.count == 3)
        // Found where Nina looks for it.
        let url = ThaliaFeed.catalogURL(groupRoot: try Fixture.root())
        #expect(url.path.hasSuffix("Thalia/exchange/catalog.json"))
        #expect(ThaliaFeed.catalog(try? Data(contentsOf: url)) == catalog)
        #expect(ThaliaFeed.catalog(nil) == nil)
        #expect(ThaliaFeed.catalog(Data("no".utf8)) == nil)
    }

    @Test func ninasFilesHaveTheShapeOfTheFixtures() throws {
        // The demo day's dinner: 1,850 kcal and 120 g protein at 19:00.
        let dinner = ThaliaFeed.FoodRecord(id: "dinner", day: Self.today, time: Self.time("2026-11-22T19:00:00+01:00"),
                                           energy: 1850, protein: 120, carbs: 0, fat: 0)
        let folder = TemporaryFolder()
        try ThaliaExchangeWriter.sync(Self.facts([dinner], []), source: ThaliaFeed.source, appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        let ours = try Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: Self.today))
        let demo = try Fixture.data("Demo/exchange/days/2026-11-22.json")
        #expect(try Fixture.keys(ours) == Fixture.keys(demo))
        #expect(try Fixture.factKeys(ours) == Fixture.factKeys(demo))

        let mine = try ExchangeReader.dayFile(ours, folder: "Nina").get().file.facts
        let theirs = try ExchangeReader.dayFile(demo).get().file.facts
        for metric in ["kcal", "protein_g"] {
            var expected = try #require(theirs.first { $0.metric == metric })
            expected.id = "\(metric)-2026-11-22"
            #expect(mine.first { $0.metric == metric } == expected)
        }
        // A real 0 (no carbs, no fat) is written as 0.
        #expect(Self.value(mine, "carbs_g") == 0)
        #expect(Self.value(mine, "fat_g") == 0)

        let info = ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        let source = try BinisoftExchange.encode(info)
        let theo = try Fixture.data("Theo/exchange/source.json")
        #expect(try Fixture.keys(source) == Fixture.keys(theo))
        #expect(try Fixture.refKeys(source) == Fixture.refKeys(theo))
    }

    // MARK: 6. No Apple Health values

    @Test func healthRecordsGiveNoFacts() {
        let fromHealth = ThaliaFeed.FoodRecord(id: "entry-hk", day: Self.today, time: Self.time("2026-11-22T22:00:00+01:00"),
                                               energy: 300, protein: 10, carbs: 40, fat: 9, isFromHealth: true)
        let waterFromHealth = ThaliaFeed.WaterRecord(id: "water-hk", day: Self.today, time: Self.time("2026-11-22T22:00:00+01:00"),
                                                     milliliters: 400, isFromHealth: true)
        #expect(Self.facts(Self.meals + [fromHealth], Self.drinks + [waterFromHealth]) == Self.facts())
        // A day with only Health records has no facts.
        var otherDay = fromHealth
        otherDay.day = "2026-11-20"
        var otherWater = waterFromHealth
        otherWater.day = "2026-11-20"
        #expect(Self.facts([otherDay], [otherWater]).isEmpty)
        #expect(Self.facts().values.joined().allSatisfy { $0.origin == "app" })

        #expect(ThaliaFeed.isHealthSource("health"))
        #expect(ThaliaFeed.isHealthSource("HealthKit"))
        for source in ["", "search", "quick", "barcode", "plan", "watch", "import", "copy", "recipe", "shortcut"] {
            #expect(!ThaliaFeed.isHealthSource(source), "\(source)")
        }
    }

    // MARK: 7. FNV-1a

    @Test func fnv1aHashes() {
        #expect(ExchangeHash.hex("") == "cbf29ce484222325")
        #expect(ExchangeHash.hex("a") == "af63dc4c8601ec8c")
        #expect(ExchangeHash.hex("foobar") == "85944171f73967e8")
    }

    // MARK: 8. Nina's diary

    @Test func threeMealsGiveOneSumPerMetric() throws {
        let day = try #require(Self.facts()[Self.today])
        for metric in ThaliaFeed.metricIDs {
            #expect(day.filter { $0.metric == metric }.count == 1, "\(metric)")
        }
        #expect(Self.value(day, "kcal") == 1786)
        #expect(Self.value(day, "protein_g") == 104.6)
        #expect(Self.value(day, "carbs_g") == 182.5)
        #expect(Self.value(day, "fat_g") == 60.6)
        #expect(Self.value(day, "water_ml") == 1080)
    }

    @Test func onlyEatenEntriesCount() {
        var planned = Self.meals[0]
        planned.id = "planned"
        planned.isEaten = false
        var deleted = Self.meals[1]
        deleted.id = "deleted"
        deleted.isDeleted = true
        var deletedWater = Self.drinks[0]
        deletedWater.id = "water-deleted"
        deletedWater.isDeleted = true
        #expect(Self.facts(Self.meals + [planned, deleted], Self.drinks + [deletedWater]) == Self.facts())
        // A day with only planned food and no water has nothing.
        var plannedOnly = planned
        plannedOnly.day = "2026-11-21"
        #expect(Self.facts([plannedOnly], []).isEmpty)
    }

    @Test func eachMetricNeedsItsOwnRecords() throws {
        let onlyWater = Self.facts([], Self.drinks)
        #expect(onlyWater[Self.today]?.map(\.metric) == ["water_ml"])
        let onlyFood = Self.facts(Self.meals, [])
        #expect(onlyFood[Self.today]?.compactMap(\.metric).sorted() == ["carbs_g", "fat_g", "kcal", "protein_g"])
        // A day without entries has no facts.
        #expect(Self.facts()["2026-11-21"] == nil)
        // A real 0 with records present stays 0.
        let glass = ThaliaFeed.WaterRecord(id: "w0", day: Self.today, time: Self.time("2026-11-22T09:00:00+01:00"), milliliters: 0)
        let tea = ThaliaFeed.FoodRecord(id: "f0", day: Self.today, time: Self.time("2026-11-22T09:00:00+01:00"),
                                        energy: 0, protein: 0, carbs: 0, fat: 0)
        let zero = try #require(Self.facts([tea], [glass])[Self.today])
        #expect(zero.count == 5)
        #expect(zero.allSatisfy { $0.value == 0 })
    }

    @Test func daysAfterTodayAndBeforeTheWindowAreLeftOut() {
        var tomorrow = Self.meals[0]
        tomorrow.day = "2026-11-23"
        var lastDay = Self.meals[0]
        lastDay.day = "2026-09-21"
        var tooOld = Self.meals[0]
        tooOld.day = "2026-09-20"
        let facts = Self.facts([tomorrow, lastDay, tooOld], [])
        #expect(Array(facts.keys) == ["2026-09-21"])
        #expect(Self.facts(today: "not a day").isEmpty)
    }

    @Test func aMovedMealRewritesBothDays() throws {
        let folder = TemporaryFolder()
        let yesterday = "2026-11-21"
        var records = Self.meals
        records.append(ThaliaFeed.FoodRecord(id: "entry-0", day: yesterday, time: Self.time("2026-11-21T13:00:00+01:00"),
                                             energy: 500, protein: 30, carbs: 50, fat: 15))
        try ThaliaExchangeWriter.sync(Self.facts(records, []), source: "nina", appFolder: folder.app, today: Self.today,
                                      now: Self.time("2026-11-22T20:00:00+01:00"), timeZone: Self.vienna)
        // The dinner moves to yesterday.
        records[2].day = yesterday
        let moved = Self.facts(records, [])
        #expect(try ThaliaExchangeWriter.sync(moved, source: "nina", appFolder: folder.app, today: Self.today,
                                              now: Self.time("2026-11-22T21:00:00+01:00"), timeZone: Self.vienna))
        for day in [Self.today, yesterday] {
            let file = try ExchangeReader.dayFile(Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder.app, day: day))).get().file
            #expect(file.generatedAt == "2026-11-22T21:00:00+01:00", "\(day)")
            #expect(file.facts == moved[day])
        }
        #expect(Self.value(moved[Self.today], "kcal") == 1065)
        #expect(Self.value(moved[yesterday], "kcal") == 1220)
        // The dinner's time is the later one on yesterday's file.
        #expect(moved[yesterday]?.first { $0.metric == "kcal" }?.at == "2026-11-22T19:00:30+01:00")
    }

    @Test func onlyMetricsOfTheTable() {
        let all = Self.facts().values.joined()
        #expect(!all.isEmpty)
        for fact in all {
            #expect(fact.isKnown)
            #expect(ThaliaFeed.metricIDs.contains(fact.metric ?? ""))
        }
        #expect(!all.contains { $0.metric == "fiber_g" })
        #expect(ThaliaFeed.metrics.count == 5)
        #expect(ThaliaFeed.metrics.allSatisfy { $0.agg == .sum })
    }

    // MARK: source.json heartbeat

    @Test func sourceIsWrittenOnChangesAndOnceADay() throws {
        let now = Self.time("2026-11-22T08:00:00+01:00")
        let info = ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: now, timeZone: Self.vienna)
        let written = try BinisoftExchange.encode(info)
        func needs(_ next: ExchangeSourceInfo, today: String = Self.today, existing: Data? = written) -> Bool {
            ThaliaExchangeWriter.needsSourceWrite(next, existing: existing, today: today, timeZone: Self.vienna)
        }
        let later = ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: Self.time("2026-11-22T22:00:00+01:00"), timeZone: Self.vienna)
        #expect(!needs(later))
        #expect(needs(later, existing: nil))
        #expect(needs(later, existing: Data("broken".utf8)))
        #expect(needs(ThaliaFeed.sourceInfo(appVersion: "1.2.0", now: now, timeZone: Self.vienna)))
        var fewerRefs = later
        fewerRefs.refs.removeLast()
        #expect(needs(fewerRefs))
        // The next day: the heartbeat.
        #expect(needs(later, today: "2026-11-23"))

        let folder = TemporaryFolder()
        #expect(try ThaliaExchangeWriter.syncSource(info, appFolder: folder.app, today: Self.today, timeZone: Self.vienna))
        #expect(try !ThaliaExchangeWriter.syncSource(later, appFolder: folder.app, today: Self.today, timeZone: Self.vienna))
        let tomorrow = ThaliaFeed.sourceInfo(appVersion: "1.1.0", now: Self.time("2026-11-23T08:00:00+01:00"), timeZone: Self.vienna)
        #expect(try ThaliaExchangeWriter.syncSource(tomorrow, appFolder: folder.app, today: "2026-11-23", timeZone: Self.vienna))
    }
}

/// A folder in the temporary directory, removed again; `app` is `<folder>/Nina`.
final class TemporaryFolder {
    let url: URL
    var app: URL { url.appendingPathComponent(ThaliaFeed.folderName, isDirectory: true) }

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("nina-exchange-\(UUID().uuidString)", isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Thalia's exchange fixtures (Fixtures/exchange, laid out like the App Group).
enum Fixture {
    struct Missing: Error {}

    static func root() throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else { throw Missing() }
        return fixtures.appendingPathComponent("exchange", isDirectory: true)
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root().appendingPathComponent(path))
    }

    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Missing() }
        return object
    }

    static func keys(_ data: Data) throws -> Set<String> { Set(try object(data).keys) }

    static func factKeys(_ data: Data) throws -> Set<String> {
        let facts = try object(data)["facts"] as? [[String: Any]] ?? []
        return Set(facts.flatMap(\.keys))
    }

    static func refKeys(_ data: Data) throws -> Set<String> {
        let refs = try object(data)["refs"] as? [[String: Any]] ?? []
        return Set(refs.flatMap(\.keys))
    }
}
