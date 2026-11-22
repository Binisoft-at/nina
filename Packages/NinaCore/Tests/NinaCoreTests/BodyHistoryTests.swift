import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

// The weight & body history file. All numbers and dates are made up.

@Suite("Weight & body history CSV")
struct BodyHistoryCSVTests {
    static let today = DayKey(year: 2030, month: 3, day: 1)

    static func day(_ text: String) -> DayKey { DayKey(text)! }

    static func records(_ text: String, cutoff: Int = 660) -> [BodyHistoryRecord] {
        BodyHistoryCSV.parse(text, cutoffMinutes: cutoff, today: today).records
    }

    // MARK: Parsing

    @Test func readsTheOwnFormat() throws {
        let file = BodyHistoryCSV.header.joined(separator: ",") + "\n"
            + BodyHistoryCSV.exampleRows.map { $0.map { CSV.escape($0) }.joined(separator: ",") }.joined(separator: "\n")
        let parsed = BodyHistoryCSV.parse(file, today: Self.today)
        #expect(parsed.notes.isEmpty, "\(parsed.notes)")
        #expect(parsed.records.map(\.kind) == [.weight, .tape, .weight, .tape, .weight, .assessment, .tape, .assessment])
        let weigh = parsed.records[0]
        #expect(weigh.day == Self.day("2030-01-07") && weigh.minutes == 430 && weigh.kilograms == 78.4 && weigh.bodyFat == 0)
        #expect(parsed.records[1].values[.waist] == 84.5)
        #expect(parsed.records[1].conditions == "morning,fasted")
        let session = parsed.records[3]
        #expect(session.values.sites == [.neck: 38.5, .chest: 101, .arm: 35, .waist: 84, .hip: 98.5, .thigh: 58])
        let dexa = parsed.records[5]
        #expect(dexa.method == .dexa && dexa.device == "Hologic Horizon")
        #expect(dexa.values.bodyFat == 19.8 && dexa.values.leanKg == 60.1 && dexa.values.fatKg == 15.6 && dexa.values.boneKg == 2.9)
        #expect(dexa.note == "Visceral fat 410 g")
        // The 3D scan has no time: 07:00, a morning reading.
        let scan = parsed.records[7]
        #expect(scan.method == .scan3D && scan.device == "Styku" && scan.minutes == 420 && scan.conditions == "morning,fasted")
        #expect(parsed.records[6].values[.calf] == 37)
        #expect(ImportKind.detect(file) == .measurements)
    }

    @Test func germanHeadersAndDecimalCommas() throws {
        let file = """
        Datum;Uhrzeit;Gewicht (kg);KFA (%);Methode;Bauchumfang;Oberarm links;Notiz
        07.01.2030;7:15;78,4;;;84,5;34,0;
        14.01.2030;;78,1;;;;;
        20.01.2030;09:30;;19,8;DXA;;;Klinik
        """
        #expect(ImportKind.detect(file) == .measurements)
        let parsed = BodyHistoryCSV.parse(file, today: Self.today)
        #expect(parsed.notes.isEmpty, "\(parsed.notes)")
        #expect(parsed.records.map(\.kind) == [.weight, .tape, .weight, .assessment])
        #expect(parsed.records[0].kilograms == 78.4 && parsed.records[0].minutes == 435)
        #expect(parsed.records[1].values.sites == [.waist: 84.5, .armLeft: 34])
        #expect(parsed.records[2].kilograms == 78.1 && parsed.records[2].minutes == BodyHistoryCSV.defaultMinutes)
        let dexa = parsed.records[3]
        #expect(dexa.method == .dexa && dexa.values.bodyFat == 19.8 && dexa.note == "Klinik" && dexa.minutes == 570)
    }

    @Test func otherUnitsAndAppExports() throws {
        let file = """
        Date,Time,Weight (lb),Body Fat %,Waist (in),Visceral Fat
        "Jan 7, 2030",7:10 AM,172.8,18.5,33.5,8
        2030-01-08 18:45,,173.2,,,
        """
        let records = Self.records(file)
        #expect(records.map(\.kind) == [.weight, .tape, .weight])
        // A smart scale's body fat stays with the weigh-in ("Weigh-in body fat").
        #expect(records[0].kilograms == 78.38 && records[0].bodyFat == 18.5 && records[0].minutes == 430)
        #expect(records[1].values[.waist] == 85.09)
        #expect(records[1].note == "Visceral Fat: 8")
        #expect(records[2].day == Self.day("2030-01-08") && records[2].minutes == 18 * 60 + 45)
    }

    @Test func dexaReportInGrams() throws {
        let file = """
        Scan Date,Total Mass (kg),% Fat,Fat (g),Lean (g),BMC (g),Method
        20.01.2030,78.6,19.8,15600,60100,2900,DEXA (Hologic)
        """
        let records = Self.records(file)
        #expect(records.map(\.kind) == [.weight, .assessment])
        let dexa = records[1]
        #expect(dexa.method == .dexa)
        #expect(dexa.values.fatKg == 15.6 && dexa.values.leanKg == 60.1 && dexa.values.boneKg == 2.9 && dexa.values.bodyFat == 19.8)
        #expect(records[0].bodyFat == 0)
    }

    @Test func mixedRowsAndNotes() throws {
        let file = """
        date,time,weight_kg,body_fat_pct,body_fat_method,waist_cm,chest_cm,note
        2030-01-07,07:00,78.4,,,,,
        2030-01-08,,,,,84.5,-,
        2030-01-09,,,21,,,,guess from a photo
        someday,,79,,,,,
        2030-01-10,,,,,840,,
        2030-01-11,,,,,,,
        2030-01-12,,7x,,,,,
        2030-04-01,,78,,,,,
        2030-01-13,,,20,clinic,,,
        2030-01-14,,,,,,,only a note
        """
        let parsed = BodyHistoryCSV.parse(file, today: Self.today)
        #expect(parsed.records.map(\.kind) == [.weight, .tape, .assessment, .assessment])
        #expect(parsed.records[1].values.sites == [.waist: 84.5])
        #expect(parsed.records[2].method == .estimate && parsed.records[2].note == "guess from a photo")
        #expect(parsed.records[3].method == .estimate)
        let notes = parsed.notes
        #expect(notes.contains { $0.hasPrefix("Row 5: date") })
        #expect(notes.contains { $0.hasPrefix("Row 6: waist_cm 840") })
        #expect(notes.contains { $0.hasPrefix("Row 8: weight_kg") })
        #expect(notes.contains { $0.hasPrefix("Row 9: 2030-04-01 is in the future") })
        #expect(notes.contains { $0.hasPrefix("Row 10: body_fat_method \u{201C}clinic\u{201D} not known") })
        #expect(notes.contains { $0.hasPrefix("Row 11: no weight") })
        #expect(notes.contains { $0.hasPrefix("Row 4: no body_fat_method") })
        // The row with only a date says nothing.
        #expect(!notes.contains { $0.hasPrefix("Row 7") })
        #expect(notes.count == 7, "\(notes)")
    }

    @Test func headerProblems() {
        #expect(BodyHistoryCSV.parse("weight_kg\n78").notes.first?.contains("date") == true)
        #expect(BodyHistoryCSV.parse("date,mood\n2030-01-07,good").notes.first?.contains("weight_kg") == true)
        #expect(BodyHistoryCSV.parse("").records.isEmpty)
    }

    @Test func dates() {
        let expected = Self.day("2030-01-07")
        for text in ["2030-01-07", "07.01.2030", "7.1.30", "07/01/2030", "2030/01/07", "7 Jan 2030", "Jan 7, 2030",
                     "7. Jänner 2030", "Mo, 07.01.2030", "Montag, 7. Januar 2030", "2030-01-07T07:15:00Z"] {
            #expect(BodyHistoryCSV.moment(text)?.day == expected, "\(text)")
        }
        #expect(BodyHistoryCSV.moment("01/13/2030")?.day == Self.day("2030-01-13"))
        #expect(BodyHistoryCSV.moment("13 März 2030")?.day == Self.day("2030-03-13"))
        #expect(BodyHistoryCSV.moment("30.02.2030") == nil)
        #expect(BodyHistoryCSV.moment("someday") == nil)
        #expect(BodyHistoryCSV.moment("2030-01-07T07:15:00Z")?.minutes == 435)
        #expect(BodyHistoryCSV.moment("07.01.2030 18:30")?.minutes == 1110)
        #expect(BodyHistoryCSV.moment("07.01.2030")?.minutes == nil)
        #expect(BodyHistoryCSV.clock("7:30 pm") == 1170)
        #expect(BodyHistoryCSV.clock("12:15 am") == 15)
        #expect(BodyHistoryCSV.clock("19 Uhr") == 1140)
        #expect(BodyHistoryCSV.clock("morning") == nil)
        // A spreadsheet's midnight is no time.
        let midnight = Self.records("date,weight_kg\n07.01.2030 00:00:00,78")
        #expect(midnight.first?.minutes == BodyHistoryCSV.defaultMinutes)
    }

    // MARK: Conditions

    @Test func conditions() throws {
        let file = """
        date,time,weight_kg,waist_cm,conditions
        2030-01-07,07:10,,84,"nüchtern, morgens"
        2030-01-08,18:30,79,84.5,after workout + salty
        2030-01-09,15:00,,84,
        2030-01-10,07:00,,84,morning
        2030-01-11,08:00,,84,fasted
        2030-01-12,08:00,,84,not fasted
        2030-01-13,07:00,,84,hotel scale
        2030-01-14,evening,,84.2,
        """
        let records = Self.records(file)
        let tape = records.filter { $0.kind == .tape }
        #expect(tape.map(\.conditions) == ["morning,fasted", "later,after_training,high_salt", "later", "morning,fasted",
                                           "morning,fasted", "later,not_fasted", "morning,fasted", "later"])
        #expect(BodyProtocol.isStandard(tape[0].conditions) && !BodyProtocol.isStandard(tape[1].conditions))
        // Salty food also tags the weigh-in.
        let weight = try #require(records.first { $0.kind == .weight })
        #expect(weight.note == "#salty")
        #expect(WeightSignal.Tag.parse(weight.note) == [.salty])
        // Words that aren't conditions go into the note; "evening" without a time is 18:00.
        #expect(tape[6].note == "hotel scale")
        #expect(tape[7].minutes == 18 * 60)
        // Before a later cutoff, 15:00 still counts as the morning.
        #expect(Self.records("date,time,waist_cm\n2030-01-09,15:00,84", cutoff: 16 * 60).first?.conditions == "morning,fasted")
    }

    // MARK: Mapping to records

    @Test func oneRowBecomesUpToThreeRecords() throws {
        let file = """
        date,time,weight_kg,body_fat_pct,body_fat_method,device,lean_kg,fat_kg,bone_kg,waist_cm,arm_flexed_cm
        2030-01-20,09:30,78.6,19.8,dexa,,60.1,15.6,2.9,84,37.5
        2030-01-21,07:00,78.2,21,scale,Withings,,,,,
        2030-01-22,07:00,,22,InBody 770,,,,,,
        2030-01-23,07:00,,,,,61,16,,,
        2030-01-24,07:00,,,,,61,,3,,
        """
        let parsed = BodyHistoryCSV.parse(file, today: Self.today)
        let records = parsed.records
        #expect(records.map(\.kind) == [.weight, .tape, .assessment, .weight, .assessment, .assessment])
        #expect(records[0].bodyFat == 0)
        #expect(records[1].values.sites == [.waist: 84, .armFlexed: 37.5])
        #expect(records[2].method == .dexa && records[2].values.boneKg == 2.9)
        // A smart scale's weigh-in keeps its body fat.
        #expect(records[3].kilograms == 78.2 && records[3].bodyFat == 21)
        #expect(records[4].method == .biaPro && records[4].values.bodyFat == 22)
        // Lean and fat mass without a percentage: the percentage follows from them.
        #expect(records[5].values.bodyFat == nil && records[5].values.leanKg == 61 && records[5].values.fatKg == 16)
        let reading = try #require(BodyFatReading(assessmentOn: records[5].day, method: .estimate, values: records[5].values))
        #expect(abs(reading.bodyFat - 16.0 / 77.0 * 100) < 0.01)
        #expect(parsed.notes.contains { $0.hasPrefix("Row 6: lean, fat or bone mass without body fat") })
    }

    @Test func importKeysAreStable() {
        let a = BodyHistoryRecord.tape(day: Self.day("2030-01-07"), minutes: 430, values: BodyValues([.waist: 84, .chest: 101.5]))
        let b = BodyHistoryRecord.tape(day: Self.day("2030-01-07"), minutes: 430, values: BodyValues([.chest: 101.5, .waist: 84]),
                                       conditions: "later", note: "other note")
        #expect(a.importKey == b.importKey)
        #expect(a.importKey == "history:2030-01-07T07:10:tape:chest=101.5;waist=84")
        let weight = BodyHistoryRecord.weight(day: Self.day("2030-01-07"), minutes: 430, kilograms: 78.4)
        #expect(weight.importKey == "history:2030-01-07T07:10:weight:78.4")
        let dexa = BodyHistoryRecord.assessment(day: Self.day("2030-01-07"), minutes: 430, values: BodyValues(["bodyFat": 19.8]), method: .dexa)
        let scan = BodyHistoryRecord.assessment(day: Self.day("2030-01-07"), minutes: 430, values: BodyValues(["bodyFat": 19.8]), method: .scan3D)
        #expect(dexa.importKey != scan.importKey)
        // Unknown keys are not part of a record.
        let extra = BodyHistoryRecord.assessment(day: Self.day("2030-01-07"), minutes: 430,
                                                 values: BodyValues(["bodyFat": 19.8, "sf_chest": 12]), method: nil)
        #expect(extra.values.keys == ["bodyFat"] && extra.method == .estimate)
    }

    // MARK: Duplicates

    static let sample = """
    date,time,weight_kg,body_fat_pct,body_fat_method,device,lean_kg,fat_kg,waist_cm,chest_cm,conditions,note
    2030-01-07,07:10,78.4,,,,,,84.5,101,morning;fasted,
    2030-01-14,07:05,78.1,,,,,,84,,,
    2030-01-20,09:30,78.6,19.8,dexa,Hologic,60.1,15.6,,,,Visceral fat 410 g
    2030-01-21,,78.2,21,scale,,,,,,,
    2030-02-03,,,21.5,scan_3d,Styku,,,83.6,100.5,,
    """

    @Test func importingAgainAddsNothing() {
        let first = BodyHistoryCSV.plan(Self.sample, existing: [], today: Self.today)
        #expect(first.records.count == 9)
        #expect(first.weighIns == 4 && first.tapeSessions == 3 && first.bodyFatValues == 2 && first.duplicates == 0)
        #expect(first.summary == "4 weigh-ins · 3 tape sessions · 2 body-fat values to add")
        #expect(first.importedText == "Imported 4 weigh-ins, 3 tape sessions and 2 body-fat values")
        // What Nina has after the import: the records, the measurements with their import keys.
        let keys = Set(first.records.filter { $0.kind != .weight }.map(\.importKey))
        let again = BodyHistoryCSV.plan(Self.sample, existing: first.records, existingKeys: keys, today: Self.today)
        #expect(again.records.isEmpty && !again.hasChanges)
        #expect(again.duplicates == 9)
        #expect(again.summary == "Nothing new to add · 9 already saved")
        // The same file twice in one paste.
        let lines = Self.sample.split(separator: "\n")
        let twice = Self.sample + "\n" + lines.dropFirst().joined(separator: "\n")
        let doubled = BodyHistoryCSV.plan(twice, existing: [], today: Self.today)
        #expect(doubled.records.count == 9 && doubled.duplicates == 9)
    }

    @Test func sameValuesOnTheSameDayAreDuplicates() {
        let day = Self.day("2030-01-07")
        let existing: [BodyHistoryRecord] = [
            .weight(day: day, minutes: 452, kilograms: 78.4),
            .tape(day: day, minutes: 455, values: BodyValues([.waist: 84.5, .chest: 101, .arm: 35])),
            .assessment(day: Self.day("2030-01-20"), minutes: 600, values: BodyValues(["bodyFat": 19.8]), method: .dexa),
        ]
        let file = """
        date,weight_kg,waist_cm,chest_cm,body_fat_pct,body_fat_method
        2030-01-07,78.4,84.5,101,,
        2030-01-07,78.45,85,,,
        2030-01-20,,,,19.8,dexa
        2030-01-20,,,,19.8,scan_3d
        2030-01-08,78.4,,,,
        """
        let plan = BodyHistoryCSV.plan(file, existing: existing, today: Self.today)
        // 78.4 and the waist/chest of the 7th are there (another time doesn't matter); 78.45 is the
        // same weight; the waist of 85 is new, so is the 3D scan and the weigh-in on the 8th.
        #expect(plan.duplicates == 4)
        #expect(plan.records.map(\.kind) == [.tape, .assessment, .weight])
        #expect(plan.records[0].values.sites == [.waist: 85])
        #expect(plan.records[1].method == .scan3D)
        #expect(plan.records[2].day == Self.day("2030-01-08"))
    }

    @Test func aSetupAnswerCountsTheWeightItsSettingsPartSaved() {
        // The history part is planned again after the settings part is applied, so today's weight
        // from block 1 (saved with the note "import") and a row for today in block 4 are one weigh-in.
        let file = "date,time,weight_kg\n2030-03-01,07:30,78.4\n2030-02-28,07:20,78.6\n"
        let before = BodyHistoryCSV.plan(file, existing: [], today: Self.today)
        #expect(before.records.count == 2)
        let saved: [BodyHistoryRecord] = [.weight(day: Self.today, minutes: 545, kilograms: 78.4, note: "import")]
        let after = BodyHistoryCSV.plan(file, existing: saved, today: Self.today)
        #expect(after.duplicates == 1)
        #expect(after.records.map(\.day) == [Self.day("2030-02-28")])
    }

    // MARK: Export

    @Test func exportReadsBackWithoutChanges() throws {
        let first = BodyHistoryCSV.parse(Self.sample, today: Self.today).records
        let exported = BodyHistoryCSV.export(first)
        #expect(exported.hasPrefix(BodyHistoryCSV.header.joined(separator: ",") + "\n"))
        let again = BodyHistoryCSV.parse(exported, today: Self.today)
        #expect(again.notes.isEmpty, "\(again.notes)")
        #expect(again.records.count == first.count)
        #expect(Set(again.records.map(\.importKey)) == Set(first.map(\.importKey)))
        let plan = BodyHistoryCSV.plan(exported, existing: first, today: Self.today)
        #expect(!plan.hasChanges && plan.notes.isEmpty && plan.duplicates == first.count)
    }

    @Test func exportOfWhatNinaHasReadsBack() throws {
        // Records as the app builds them from its weigh-ins and measurements (a settings-import
        // baseline without conditions, a typed estimate without a method, left-side and flexed
        // sites, a weigh-in with a reason and smart-scale body fat).
        let day = Self.day("2030-01-07")
        let records: [BodyHistoryRecord] = [
            .weight(day: day, minutes: 433, kilograms: 78.35, bodyFat: 20.5, note: "Hotel #salty"),
            .tape(day: day, minutes: 440, values: BodyValues([.waist: 84.25, .armLeft: 34.5, .armFlexed: 37]),
                  conditions: "later,after_training"),
            .assessment(day: day, minutes: 935, values: BodyValues(["bodyFat": 20, "leanKg": 61.2, "fatKg": 15.3, "boneKg": 3.1]),
                        method: .biaPro, device: "InBody 570", conditions: ""),
            .assessment(day: Self.day("2030-01-08"), minutes: 600, values: BodyValues(["bodyFat": 18]), method: nil),
        ]
        let exported = BodyHistoryCSV.export(records)
        let plan = BodyHistoryCSV.plan(exported, existing: records, today: Self.today)
        #expect(!plan.hasChanges && plan.notes.isEmpty, "\(plan.notes)")
        #expect(plan.duplicates == records.count)
        // Read back on its own, every value comes back.
        let again = BodyHistoryCSV.parse(exported, today: Self.today).records
        #expect(again.count == 4)
        #expect(again[0].kilograms == 78.35 && again[0].bodyFat == 20.5 && again[0].note == "Hotel #salty")
        #expect(again[1].values.sites == [.waist: 84.25, .armLeft: 34.5, .armFlexed: 37] && again[1].conditions == "later,after_training")
        #expect(again[2].device == "InBody 570" && again[2].method == .biaPro && again[2].values == records[2].values)
        #expect(again[3].method == .estimate)
        // Oldest first, a weigh-in before the tape of the same moment.
        let lines = exported.split(separator: "\n")
        #expect(lines.count == 5 && lines[1].hasPrefix("2030-01-07,07:13,78.35"))
    }

    // MARK: Detecting the format

    @Test func detectedBeforeTheDiary() {
        #expect(ImportKind.detect("date,weight_kg,waist_cm\n2030-01-07,78.4,84") == .measurements)
        #expect(ImportKind.detect("Datum;Gewicht\n07.01.2030;78,4") == .measurements)
        #expect(ImportKind.detect("Date,Weight\n2030-01-07,78.4") == .measurements)
        #expect(ImportKind.detect("date,body fat %\n2030-01-07,20") == .measurements)
        // Diary files stay diary files, even with a weight column.
        #expect(ImportKind.detect("id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat\n1,2030-01-07,,lunch,Soup,,1,bowl,,200,,,") == .diary)
        #expect(ImportKind.detect("date,food,weight,kcal\n2030-01-07,Bread,60,150") == .diary)
        #expect(ImportKind.detect("date,meal\n2030-01-07,lunch") == .diary)
        #expect(ImportKind.measurements.title == "Weight & Body")
    }

    @Test func setupAnswerWithFourBlocks() {
        let answer = """
        ```csv
        setting,value
        goal,gain
        ```
        ```csv
        id,name,kcal,protein,carbs,fat
        1,Protein bar,380,30,40,12
        ```
        ```csv
        recipe,kind,ingredient,amount,unit,grams
        Usual breakfast,meal,Oats,60,g,60
        ```
        ```csv
        \(BodyHistoryCSV.header.joined(separator: ","))
        2030-01-07,07:10,78.4,,,,,,,,,,,84.5,,,,,,,,morning;fasted,
        ```
        """
        #expect(ImportBundle.parts(answer).map(\.kind) == [.settings, .foods, .recipes, .measurements])
        let plain = "setting,value\ngoal,gain\n\ndate,weight_kg\n2030-01-07,78.4\n"
        #expect(ImportBundle.parts(plain).map(\.kind) == [.settings, .measurements])
    }

    // MARK: Prompts

    @Test func prompts() {
        let prompt = BodyHistoryCSV.prompt(appName: "Nina").text
        #expect(prompt.contains(BodyHistoryCSV.header.joined(separator: ",")))
        #expect(prompt.contains("scan_3d") && prompt.contains("DEXA") && prompt.contains("InBody"))
        for column in BodyHistoryCSV.header { #expect(prompt.contains("| \(column) |"), "\(column)") }
        let setup = SetupPrompt.text(appName: "Nina")
        #expect(setup.contains("4. My weight and body history – header: " + BodyHistoryCSV.header.joined(separator: ",")))
        #expect(setup.contains("## 4. My weight and body history"))
        #expect(setup.contains("up to FOUR csv code blocks"))
        for column in BodyHistoryCSV.header { #expect(setup.contains("| \(column) |"), "\(column)") }
        // Every tape column is a site, every site has a column.
        #expect(Set(BodyHistoryCSV.siteColumns.map(\.site)) == Set(BodySite.allCases))
        for (column, site) in BodyHistoryCSV.siteColumns { #expect(BodyHistoryCSV.column(column).field == .site(site)) }
    }
}

@Suite("3D body scan")
struct BodyScanMethodTests {
    @Test func theMethod() {
        let scan = BodyMethod.scan3D
        #expect(scan.rawValue == "scan_3d" && BodyMethod(rawValue: "scan_3d") == scan)
        #expect(scan.title == "3D body scan")
        #expect(scan.errorBand == 3.5 && scan.errorText == "±3–4")
        #expect(scan.leanNoiseKg == 1.5)
        #expect(scan.accuracyRank > BodyMethod.biaPro.accuracyRank && scan.accuracyRank < BodyMethod.skinfold.accuracyRank)
        #expect(BodyMethod.trackingDefault(counts: [.scan3D: 2, .navy: 6, .scale: 30]) == .scan3D)
    }

    @Test func names() {
        for name in ["3D scan", "3d body scan", "Styku", "fit3d", "Fit 3D", "body scan", "scan_3d", "3D-Körperscan"] {
            #expect(SettingsCSV.bodyMethod(named: name) == .scan3D, "\(name)")
        }
        #expect(SettingsCSV.bodyMethod(named: "dexa") == .dexa)
        #expect(SettingsCSV.bodyMethod(named: "DXA") == .dexa)
        #expect(BodyHistoryCSV.method(named: "Styku S100 3D scanner") == .scan3D)
        #expect(BodyHistoryCSV.method(named: "DEXA (Hologic)") == .dexa)
        #expect(BodyHistoryCSV.method(named: "InBody 770") == .biaPro)
        #expect(BodyHistoryCSV.method(named: "Withings Body+") == .scale)
        #expect(BodyHistoryCSV.method(named: "clinic") == nil)
    }

    @Test func ownSeries() {
        let day = DayKey(year: 2030, month: 1, day: 7)
        let readings = [
            BodyFatReading(day: day, bodyFat: 20, method: .scan3D, device: "Styku"),
            BodyFatReading(day: day.adding(days: 56), bodyFat: 19.4, method: .scan3D, device: "Styku"),
            BodyFatReading(day: day, bodyFat: 21, method: .biaPro, device: "InBody 570"),
            BodyFatReading(day: day, bodyFat: 22, method: .skinfold),
        ]
        let series = BodyFatSeries.group(readings)
        #expect(series.map(\.id) == ["bia_pro:inbody 570", "scan_3d:styku", "skinfold"])
        #expect(series[1].title == "3D body scan · Styku")
        #expect(BodyFatSeries.tracking(series, method: nil)?.id == "scan_3d:styku")
    }

    @Test func settingsImportTakesIt() {
        let draft = SettingsCSV.parse("setting,value\nbody_fat_percent,21\nbody_fat_method,3D scan\n")
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        #expect(draft.plan.bodyFatMethod == .scan3D)
    }
}
