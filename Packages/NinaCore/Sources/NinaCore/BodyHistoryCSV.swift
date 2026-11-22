import Foundation
import BinisoftKitCore

// The weight & body history file (docs/IMPORT.md, "Weight & body history"): past weigh-ins, tape
// sessions and body-fat results – an old spreadsheet, another app's export, or a DEXA, InBody or
// 3D-scan report turned into rows by the person's AI. One row is one moment; it may carry only a
// weight, only tape values, only body fat, or any mix. Each row becomes up to three records: a
// weigh-in (`WeightEntry`), a tape session and a body-fat value (`BodyMeasurement` tape or
// assessment). Importing the same file again adds nothing.

// MARK: - Records

/// One weigh-in, tape session or body-fat value as it travels through the history import and export.
public struct BodyHistoryRecord: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case weight, tape, assessment

        /// The `BodyMeasurement.kind` (nil for a weigh-in).
        public var recordKind: BodyRecordKind? {
            switch self {
            case .weight: nil
            case .tape: .tape
            case .assessment: .assessment
            }
        }
    }

    public var kind: Kind
    public var day: DayKey
    /// Wall-clock minutes after midnight on `day`.
    public var minutes: Int
    /// Weigh-ins: kg (0 otherwise).
    public var kilograms: Double
    /// Weigh-ins: the body fat % the scale gave with it (0 = none), the "Weigh-in body fat" series.
    public var bodyFat: Double
    /// Tape: cm per site. Body-fat values: `bodyFat`, `leanKg`, `fatKg`, `boneKg`.
    public var values: BodyValues
    /// Body-fat values: how it was measured.
    public var method: BodyMethod?
    /// Body-fat values: the machine ("InBody 570"); each device is its own series.
    public var device: String
    /// Tape and body-fat values: `BodyProtocol` tags ("morning,fasted").
    public var conditions: String
    /// Weigh-ins: with the reason tokens (`WeightSignal.Tag`, "#salty").
    public var note: String

    public init(kind: Kind, day: DayKey, minutes: Int, kilograms: Double = 0, bodyFat: Double = 0, values: BodyValues = BodyValues(),
                method: BodyMethod? = nil, device: String = "", conditions: String = "", note: String = "") {
        self.kind = kind
        self.day = day
        self.minutes = minutes
        self.kilograms = kilograms
        self.bodyFat = bodyFat
        self.values = values
        self.method = method
        self.device = device.trimmingCharacters(in: .whitespacesAndNewlines)
        self.conditions = conditions
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A weigh-in, with the body fat a smart scale gave with it (0 = none).
    public static func weight(day: DayKey, minutes: Int, kilograms: Double, bodyFat: Double = 0, note: String = "") -> BodyHistoryRecord {
        BodyHistoryRecord(kind: .weight, day: day, minutes: minutes, kilograms: kilograms, bodyFat: max(0, bodyFat), note: note)
    }

    /// A tape session: only the values of known sites are kept.
    public static func tape(day: DayKey, minutes: Int, values: BodyValues, conditions: String = "", note: String = "") -> BodyHistoryRecord {
        BodyHistoryRecord(kind: .tape, day: day, minutes: minutes, values: BodyValues(values.sites), conditions: conditions, note: note)
    }

    /// A body-fat value: body fat %, lean, fat and bone kg are kept (no method counts as an estimate).
    public static func assessment(day: DayKey, minutes: Int, values: BodyValues, method: BodyMethod?, device: String = "",
                                  conditions: String = "", note: String = "") -> BodyHistoryRecord {
        var kept = BodyValues()
        for key in [BodyValues.bodyFatKey, BodyValues.leanKey, BodyValues.fatKey, BodyValues.boneKey] {
            kept[key] = values[key].flatMap { $0 > 0 ? $0 : nil }
        }
        return BodyHistoryRecord(kind: .assessment, day: day, minutes: minutes, values: kept, method: method ?? .estimate,
                                 device: device, conditions: conditions, note: note)
    }

    /// Stable from the date, time, kind and values: the same row always gives the same key, so
    /// importing a file again finds what it added (`BodyMeasurement.importKey`).
    public var importKey: String {
        let moment = "history:\(day.rawValue)T\(ClockTime.text(minutes))"
        switch kind {
        case .weight: return "\(moment):weight:\(NumberText.plain(kilograms, decimals: 2))"
        case .tape: return "\(moment):tape:\(values.encoded)"
        case .assessment: return "\(moment):assessment:\((method ?? .estimate).rawValue):\(values.encoded)"
        }
    }

    /// The same kind on the same day with the same values (within 0.05): a weigh-in of the same
    /// weight, a tape session whose every value `other` has too, a body-fat value of the same
    /// method whose every value `other` has too. The time doesn't matter.
    public func repeats(_ other: BodyHistoryRecord) -> Bool {
        guard kind == other.kind, day == other.day else { return false }
        switch kind {
        case .weight:
            return abs(kilograms - other.kilograms) <= BodyHistoryRecord.tolerance
        case .tape:
            return values.isPart(of: other.values, tolerance: BodyHistoryRecord.tolerance)
        case .assessment:
            return (method ?? .estimate) == (other.method ?? .estimate)
                && values.isPart(of: other.values, tolerance: BodyHistoryRecord.tolerance)
        }
    }

    /// kg, cm and % closer than this are the same reading.
    static let tolerance = 0.05 + 1e-9

    /// Kind and day: records that can repeat each other.
    var groupKey: String { "\(kind.rawValue)|\(day.rawValue)" }
}

extension BodyValues {
    /// Every value here is also in `other` (within `tolerance`); false when empty.
    func isPart(of other: BodyValues, tolerance: Double) -> Bool {
        guard !storage.isEmpty else { return false }
        return storage.allSatisfy { key, value in
            other.storage[key].map { abs($0 - value) <= tolerance } ?? false
        }
    }
}

// MARK: - What an import adds

/// What a history file adds: new records only (re-imported rows and values Nina already has on the
/// same day are counted as duplicates), plus the notes for rows it couldn't read.
public struct BodyHistoryPlan: Equatable, Sendable {
    /// New records in file order.
    public var records: [BodyHistoryRecord]
    /// Records left out because Nina already has them.
    public var duplicates: Int
    /// Rows and cells that couldn't be read (shown in orange).
    public var notes: [String]

    public init(records: [BodyHistoryRecord], duplicates: Int, notes: [String]) {
        self.records = records
        self.duplicates = duplicates
        self.notes = notes
    }

    public var weighIns: Int { records.filter { $0.kind == .weight }.count }
    public var tapeSessions: Int { records.filter { $0.kind == .tape }.count }
    public var bodyFatValues: Int { records.filter { $0.kind == .assessment }.count }
    public var hasChanges: Bool { !records.isEmpty }

    /// "12 weigh-ins · 4 tape sessions · 2 body-fat values to add · 3 already saved"
    public var summary: String {
        let parts = countParts
        var text = parts.isEmpty ? "Nothing new to add" : parts.joined(separator: " · ") + " to add"
        if duplicates > 0 { text += " · \(duplicates) already saved" }
        return text
    }

    /// "Imported 12 weigh-ins, 4 tape sessions and 2 body-fat values"
    public var importedText: String {
        let parts = countParts
        guard let last = parts.last else { return "Nothing new imported" }
        if parts.count == 1 { return "Imported \(last)" }
        return "Imported \(parts.dropLast().joined(separator: ", ")) and \(last)"
    }

    private var countParts: [String] {
        var parts: [String] = []
        if weighIns > 0 { parts.append(weighIns == 1 ? "1 weigh-in" : "\(weighIns) weigh-ins") }
        if tapeSessions > 0 { parts.append(tapeSessions == 1 ? "1 tape session" : "\(tapeSessions) tape sessions") }
        if bodyFatValues > 0 { parts.append(bodyFatValues == 1 ? "1 body-fat value" : "\(bodyFatValues) body-fat values") }
        return parts
    }
}

// MARK: - The file

/// Nina's weight & body history CSV: the import (with its AI prompt) and the export of every
/// weigh-in and measurement typed or imported in Nina.
public enum BodyHistoryCSV {
    /// A row without a time is a morning reading at 07:00.
    public static let defaultMinutes = 7 * 60
    /// The measuring routine's default morning cutoff (11:00).
    public static let defaultCutoffMinutes = 11 * 60
    /// A row without a time whose conditions say "later" is an evening reading at 18:00.
    static let laterMinutes = 18 * 60
    static let kilogramsPerPound = 0.45359237

    static let weightRange: ClosedRange<Double> = 20...400
    static let massRange: ClosedRange<Double> = 0.1...300
    static let boneRange: ClosedRange<Double> = 0.1...15

    public static let columns: [AIImportPrompt.Column] = [
        .init("date", "Day of the measurement in YYYY-MM-DD.", required: true),
        .init("time", "Time HH:MM (24 h), if known. Empty = 07:00."),
        .init("weight_kg", "Body weight in kg."),
        .init("body_fat_pct", "Body fat in %."),
        .init("body_fat_method", "How the body fat was measured: dexa, bodpod, bia_pro (InBody and other professional machines), scan_3d (3D body scanner: Styku, Fit3D …), scale (smart scale), skinfold, navy (tape formula) or estimate."),
        .init("device", "The machine or scale model (InBody 570, Styku), if known. Each device is its own series."),
        .init("lean_kg", "Lean mass in kg, if the report gives it (DEXA: lean without bone; InBody: fat-free mass)."),
        .init("fat_kg", "Fat mass in kg, if the report gives it."),
        .init("bone_kg", "Bone mineral mass in kg (DEXA: BMC), if the report gives it."),
        .init("neck_cm", "Neck in cm, just below the larynx."),
        .init("chest_cm", "Chest at nipple height in cm."),
        .init("arm_cm", "Relaxed upper arm in cm (right side, or the only side)."),
        .init("arm_flexed_cm", "Flexed upper arm in cm."),
        .init("waist_cm", "Waist at the navel in cm."),
        .init("waist_narrow_cm", "Narrowest waist in cm."),
        .init("hip_cm", "Hip at the widest point in cm."),
        .init("thigh_cm", "Thigh in cm (right side, or the only side)."),
        .init("calf_cm", "Calf in cm (right side, or the only side)."),
        .init("arm_l_cm", "Left upper arm in cm, only if I measure both sides."),
        .init("thigh_l_cm", "Left thigh in cm, only if I measure both sides."),
        .init("calf_l_cm", "Left calf in cm, only if I measure both sides."),
        .init("conditions", "How it was measured, separated by ; – morning, fasted, later, after_training, late_heavy_meal, high_salt, alcohol_yesterday, sick, menstrual_phase, not_fasted. Empty = Nina decides from the time (before the morning cutoff, 11:00 by default: morning;fasted)."),
        .init("note", "Anything else worth keeping (visceral fat, skeletal muscle mass, where it was measured)."),
    ]

    public static var header: [String] { columns.map(\.name) }

    /// The tape columns and their sites, in the file's order.
    static let siteColumns: [(column: String, site: BodySite)] = [
        ("neck_cm", .neck), ("chest_cm", .chest), ("arm_cm", .arm), ("arm_flexed_cm", .armFlexed), ("waist_cm", .waist),
        ("waist_narrow_cm", .waistNarrow), ("hip_cm", .hip), ("thigh_cm", .thigh), ("calf_cm", .calf),
        ("arm_l_cm", .armLeft), ("thigh_l_cm", .thighLeft), ("calf_l_cm", .calfLeft),
    ]

    public static let rules: [String] = [
        "One row per moment: a weigh-in, a tape session or a scan. A row may have only a weight, only tape values, only body fat, or any mix – leave the other cells empty.",
        "A scan or lab report (DEXA, InBody, Bod Pod, 3D scan): one row with its date, weight_kg, body_fat_pct, body_fat_method, device, lean_kg, fat_kg, bone_kg and any girths it lists. Other numbers worth keeping (visceral fat, skeletal muscle mass, segment values) go into note.",
        "Smart-scale weigh-ins with body fat: weight_kg and body_fat_pct with body_fat_method scale.",
        "Lean mass is not skeletal muscle mass: skeletal muscle mass goes into note.",
        "Copy the values as written; don't calculate missing ones (Nina works out lean and fat mass itself).",
        "Decimal point, not comma (84.5). Only kg, cm and %: convert pounds (× 0.4536), inches (× 2.54) and grams from a DEXA report (÷ 1000).",
        "Tape values are circumferences in cm. arm, thigh and calf are the right side (or the only side measured); the _l columns are the left side.",
    ]

    /// Made-up example rows: a morning weigh-in with the waist, a weekly tape session, a DEXA
    /// report and a 3D scan without a time.
    static let exampleRows: [[String]] = [
        ["2030-01-07", "07:10", "78.4", "", "", "", "", "", "", "", "", "", "", "84.5", "", "", "", "", "", "", "", "morning;fasted", ""],
        ["2030-01-14", "07:05", "78.1", "", "", "", "", "", "", "38.5", "101", "35", "", "84", "", "98.5", "58", "", "", "", "", "morning;fasted", ""],
        ["2030-01-20", "09:30", "78.6", "19.8", "dexa", "Hologic Horizon", "60.1", "15.6", "2.9", "", "", "", "", "", "", "", "", "", "", "", "", "morning;fasted", "Visceral fat 410 g"],
        ["2030-02-03", "", "", "21.5", "scan_3d", "Styku", "", "", "", "", "100.5", "35.2", "", "83.6", "", "98", "57.5", "37", "", "", "", "", ""],
    ]

    public static func prompt(appName: String) -> AIImportPrompt {
        AIImportPrompt(
            appName: appName,
            task: "Turn my weight and body history – weigh-ins, tape measurements and body-fat results from a DEXA, InBody or 3D-scan report, an old spreadsheet, another app's export or my notes – into rows.",
            columns: columns,
            rules: rules,
            exampleRows: exampleRows
        )
    }

    // MARK: Reading

    /// What a file says, before it is compared with what Nina has.
    public struct Parsed: Equatable, Sendable {
        /// The records of every row, in file order.
        public var records: [BodyHistoryRecord]
        /// Rows and cells that couldn't be read.
        public var notes: [String]
    }

    /// Reads the rows. Rows without a time are taken at 07:00; rows without conditions get them
    /// from the time like the measure sheet (before `cutoffMinutes`: morning and fasted, else
    /// later). Rows after `today` are left out.
    public static func parse(_ text: String, cutoffMinutes: Int = defaultCutoffMinutes, today: DayKey? = nil) -> Parsed {
        let table = CSV.parse(text)
        guard let first = table.first else { return Parsed(records: [], notes: ["Nothing to import."]) }
        let columns = first.map(column)
        let expected = "expected: \(header.joined(separator: ","))"
        guard columns.contains(where: { $0.field == Field.date }) else {
            return Parsed(records: [], notes: ["The first line needs a \u{201C}date\u{201D} column (\(expected))."])
        }
        guard columns.contains(where: { $0.field?.isValue == true }) else {
            return Parsed(records: [], notes: ["The first line needs a weight_kg, body_fat_pct or *_cm column (\(expected))."])
        }
        var records: [BodyHistoryRecord] = []
        var notes: [String] = []
        var withoutMethod: [Int] = []
        for (offset, cells) in table.dropFirst().enumerated() {
            let line = offset + 2
            var reader = RowReader(line: line, columns: columns, cells: cells)
            guard !reader.isEmpty else { continue }
            let row = reader.records(cutoffMinutes: cutoffMinutes, today: today)
            records += row.records
            notes += reader.notes
            if row.withoutMethod { withoutMethod.append(line) }
        }
        if !withoutMethod.isEmpty { notes.append(noMethodNote(withoutMethod)) }
        return Parsed(records: records, notes: notes)
    }

    /// The new records of a file. `existing`: every live weigh-in and measurement as records;
    /// `existingKeys`: the import keys stored with them. A record whose key Nina has, or that
    /// repeats one of the same kind on the same day (`BodyHistoryRecord.repeats`), is a duplicate –
    /// in the file too, so importing the same file twice adds nothing.
    public static func plan(_ text: String, existing: [BodyHistoryRecord], existingKeys: Set<String> = [],
                            cutoffMinutes: Int = defaultCutoffMinutes, today: DayKey? = nil) -> BodyHistoryPlan {
        let parsed = parse(text, cutoffMinutes: cutoffMinutes, today: today)
        var keys = existingKeys.union(existing.map(\.importKey))
        var groups: [String: [BodyHistoryRecord]] = [:]
        for record in existing { groups[record.groupKey, default: []].append(record) }
        var added: [BodyHistoryRecord] = []
        var duplicates = 0
        for record in parsed.records {
            let key = record.importKey
            let same = groups[record.groupKey] ?? []
            if keys.contains(key) || same.contains(where: { record.repeats($0) }) {
                duplicates += 1
                continue
            }
            keys.insert(key)
            groups[record.groupKey, default: []].append(record)
            added.append(record)
        }
        return BodyHistoryPlan(records: added, duplicates: duplicates, notes: parsed.notes)
    }

    /// Whether a header line is this format: a date and at least one weight, body-fat or tape
    /// column, and nothing of the diary or food formats.
    public static func isHeader(_ cells: [String]) -> Bool {
        let fields = cells.compactMap { column($0).field }
        guard fields.contains(.date), fields.contains(where: \.isValue) else { return false }
        let others: Set<String> = ["food", "meal", "kcal", "kj", "recipe", "ingredient", "name", "protein", "carbs"]
        return !cells.contains { others.contains(ImportColumns.canonical($0)) }
    }

    // MARK: Writing

    /// The file: one row per record, oldest first (a weigh-in before the tape and the body fat of
    /// the same moment). Reading it back adds nothing.
    public static func export(_ records: [BodyHistoryRecord]) -> String {
        let order = BodyHistoryRecord.Kind.allCases
        let sorted = records.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            if l.day != r.day { return l.day < r.day }
            if l.minutes != r.minutes { return l.minutes < r.minutes }
            let lk = order.firstIndex(of: l.kind) ?? 0, rk = order.firstIndex(of: r.kind) ?? 0
            return lk != rk ? lk < rk : lhs.offset < rhs.offset
        }.map(\.element)
        return CSV.write([header] + sorted.map(row))
    }

    static func row(_ record: BodyHistoryRecord) -> [String] {
        func cell(_ value: Double?) -> String { value.map { NumberText.plain($0, decimals: 2) } ?? "" }
        var cells: [String: String] = ["date": record.day.rawValue, "time": ClockTime.text(record.minutes), "note": record.note]
        switch record.kind {
        case .weight:
            cells["weight_kg"] = cell(record.kilograms)
            if record.bodyFat > 0 {
                cells["body_fat_pct"] = cell(record.bodyFat)
                cells["body_fat_method"] = BodyMethod.scale.rawValue
            }
        case .tape:
            for (column, site) in siteColumns { cells[column] = cell(record.values[site]) }
            cells["conditions"] = BodyProtocol.tags(record.conditions).joined(separator: ";")
        case .assessment:
            cells["body_fat_pct"] = cell(record.values.bodyFat)
            cells["body_fat_method"] = (record.method ?? .estimate).rawValue
            cells["device"] = record.device
            cells["lean_kg"] = cell(record.values.leanKg)
            cells["fat_kg"] = cell(record.values.fatKg)
            cells["bone_kg"] = cell(record.values.boneKg)
            cells["conditions"] = BodyProtocol.tags(record.conditions).joined(separator: ";")
        }
        return header.map { cells[$0] ?? "" }
    }

    // MARK: Columns

    enum Field: Hashable, Sendable {
        case date, time, weight, bodyFat, method, device, lean, fat, bone, conditions, note, ignored
        case site(BodySite)

        /// A measured value (what a row must have at least one of).
        var isValue: Bool {
            switch self {
            case .weight, .bodyFat, .lean, .fat, .bone, .site: true
            default: false
            }
        }
    }

    /// A header cell: what it holds and the factor its numbers are multiplied with (g → kg,
    /// pounds → kg, inches → cm). `field` nil: an unknown column, whose values go into the note.
    struct Column: Equatable, Sendable {
        var field: Field?
        var factor: Double
        var title: String
    }

    static let fieldAliases: [String: Field] = {
        let groups: [(Field, [String])] = [
            (.date, ["date", "datum", "day", "date_time", "datetime", "date_and_time", "timestamp", "zeitpunkt", "measured_on",
                     "measurement_date", "messdatum", "scan_date", "date_of_scan", "test_date", "untersuchungsdatum", "when", "wann"]),
            (.time, ["time", "uhrzeit", "zeit", "clock", "time_of_day", "messzeit"]),
            (.weight, ["weight_kg", "weight", "gewicht", "body_weight", "bodyweight", "korpergewicht", "kg", "total_mass",
                       "total_body_mass", "body_mass", "gesamtmasse", "gesamtgewicht", "mass", "scale_weight", "morning_weight",
                       "morgengewicht", "weigh_in", "weighin"]),
            (.bodyFat, ["body_fat_pct", "body_fat", "body_fat_percent", "body_fat_percentage", "bodyfat", "fat_pct", "fat_percent",
                        "fat_percentage", "fat_ratio", "percent_body_fat", "percent_fat", "pbf", "bf", "%_bf", "%bf", "%_fat",
                        "%_body_fat", "total_body_fat", "body_fat_rate", "kfa", "korperfett", "korperfettanteil", "korperfett_anteil",
                        "fettanteil", "fett_%", "total_fat_%"]),
            (.method, ["body_fat_method", "method", "methode", "messmethode", "measurement_method", "bf_method", "body_fat_source",
                       "korperfett_methode", "korperfettmethode", "technique", "measured_with", "measured_by", "test_type", "scan_type"]),
            (.device, ["device", "device_name", "gerat", "geraet", "machine", "maschine", "scanner", "model", "modell", "scale", "waage",
                       "source", "source_name", "quelle", "app"]),
            (.lean, ["lean_kg", "lean", "lean_mass", "lean_body_mass", "lbm", "fat_free_mass", "ffm", "fettfreie_masse",
                     "fettfreie_korpermasse", "magermasse", "lean_tissue", "lean_tissue_mass", "total_lean_mass", "total_lean",
                     "lean_weight", "fat_free_weight"]),
            (.fat, ["fat_kg", "fat_mass", "body_fat_mass", "bfm", "fettmasse", "korperfettmasse", "fat_tissue", "fat_tissue_mass",
                    "total_fat_mass", "fat_weight", "fett_kg"]),
            (.bone, ["bone_kg", "bone", "bone_mass", "bone_mineral_content", "bone_mineral_mass", "bone_mineral", "bmc", "knochen",
                     "knochenmasse", "knochenmineralgehalt", "mineral", "minerals"]),
            (.conditions, ["conditions", "condition", "bedingungen", "bedingung", "umstande", "context", "kontext", "tags", "situation",
                           "protocol", "protokoll"]),
            (.note, ["note", "notes", "notiz", "notizen", "comment", "comments", "kommentar", "kommentare", "bemerkung", "bemerkungen",
                     "remarks", "remark", "memo", "description", "beschreibung", "anmerkung", "anmerkungen"]),
            (.ignored, ["id", "nr", "no", "number", "row", "row_id", "key", "bmi", "weekday", "wochentag", "day_of_week", "week",
                        "woche", "kw", "calendar_week", "unit", "units", "einheit"]),
            (.site(.armLeft), ["oberarm_links", "arm_links", "linker_arm", "linker_oberarm"]),
            (.site(.arm), ["oberarm_rechts", "arm_rechts", "rechter_arm", "rechter_oberarm"]),
            (.site(.thighLeft), ["oberschenkel_links", "bein_links", "linker_oberschenkel"]),
            (.site(.thigh), ["oberschenkel_rechts", "bein_rechts", "rechter_oberschenkel"]),
            (.site(.calfLeft), ["wade_links", "linke_wade"]),
            (.site(.calf), ["wade_rechts", "rechte_wade"]),
            (.site(.armFlexed), ["bizeps_angespannt", "arm_angespannt", "oberarm_angespannt", "biceps_flexed", "flexed_biceps", "arm_flexed"]),
            (.site(.waistNarrow), ["taille_schmal", "schmalste_stelle", "waist_narrowest", "narrowest_waist", "waist_min"]),
            (.site(.waist), ["abdomen", "bauchnabel", "navel_waist", "waist_navel", "waist_at_navel"]),
        ]
        var map: [String: Field] = [:]
        for (field, names) in groups {
            for name in names { map[ImportColumns.normalize(name)] = field }
        }
        return map
    }()

    /// Units after a column name ("waist (in)" → waist_in): the factor to kg, cm or % and whether
    /// it suits a weight, a girth or a percentage.
    private static let unitSuffixes: [(suffix: String, factor: Double, unit: String)] = [
        ("_kg", 1, "mass"), ("_kilogram", 1, "mass"), ("_kilograms", 1, "mass"),
        ("_g", 0.001, "mass"), ("_gram", 0.001, "mass"), ("_grams", 0.001, "mass"), ("_gramm", 0.001, "mass"),
        ("_lb", kilogramsPerPound, "mass"), ("_lbs", kilogramsPerPound, "mass"), ("_pounds", kilogramsPerPound, "mass"),
        ("_cm", 1, "length"), ("_in", 2.54, "length"), ("_inch", 2.54, "length"), ("_inches", 2.54, "length"), ("_zoll", 2.54, "length"),
        ("_%", 1, "percent"), ("_pct", 1, "percent"), ("_percent", 1, "percent"), ("_prozent", 1, "percent"),
    ]

    /// What a header cell holds: "Weight (lb)" → weight × 0.4536, "Lean (g)" → lean ÷ 1000,
    /// "Oberarm links" → arm_l, "Visceral fat" → unknown (goes into the note).
    static func column(_ header: String) -> Column {
        let title = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ImportColumns.normalize(title)
        guard !key.isEmpty else { return Column(field: .ignored, factor: 1, title: title) }
        if let field = baseField(key) { return Column(field: field, factor: 1, title: title) }
        for item in unitSuffixes where key.hasSuffix(item.suffix) && key.count > item.suffix.count {
            let base = String(key.dropLast(item.suffix.count))
            // "Fat (g)" on a DEXA report is fat mass; a bare "fat" column stays unknown.
            let fatMass: Field? = item.unit == "mass" && ["fat", "fett"].contains(base) ? .fat : nil
            guard let field = baseField(base) ?? fatMass else { continue }
            switch (field, item.unit) {
            case (.weight, "mass"), (.lean, "mass"), (.fat, "mass"), (.bone, "mass"), (.site, "length"), (.bodyFat, "percent"):
                return Column(field: field, factor: item.factor, title: title)
            default:
                continue
            }
        }
        return Column(field: nil, factor: 1, title: title)
    }

    private static func baseField(_ key: String) -> Field? {
        if let field = fieldAliases[key] { return field }
        return SettingsCSV.bodySite(named: key).map { .site($0) }
    }

    // MARK: Cells

    /// "84,5", "84.5 cm", "~20 %", "ca. 80"; nil for text.
    static func number(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["~", "≈", "ca.", "ca", "approx.", "approx", "about", "etwa"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return ImportColumns.number(text)
    }

    /// Cells that mean "nothing" ("-", "n/a", "?").
    static func isBlank(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return ["", "-", "–", "—", "n/a", "na", "?", "/", "none", "keine", "x"].contains(text)
    }

    /// "07:30", "7.30", "7:30 pm", "19 Uhr" → minutes after midnight.
    static func clock(_ raw: String) -> Int? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "uhr", with: "").trimmingCharacters(in: .whitespaces)
        var isPM = false
        var isAM = false
        for (suffix, pm) in [("a.m.", false), ("p.m.", true), ("am", false), ("pm", true)] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if pm { isPM = true } else { isAM = true }
            break
        }
        guard text.first?.isNumber == true, var minutes = ClockTime.parse(text) else { return nil }
        if isPM, minutes < 12 * 60 { minutes += 12 * 60 }
        if isAM, minutes >= 12 * 60 { minutes -= 12 * 60 }
        return minutes
    }

    /// The day of a date cell and the time in it, if any: "2030-01-07", "07.01.2030", "7.1.30",
    /// "07/01/2030", "2030/01/07", "7 Jan 2030", "Jan 7, 2030", "7. Jänner 2030", "Mo, 07.01.2030",
    /// "2030-01-07T07:15:00Z", "07.01.2030 07:15". A day that comes first is the day (European);
    /// "01/13/2030" is read as 13 January.
    static func moment(_ raw: String) -> (day: DayKey, minutes: Int?)? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var minutes: Int?
        let pattern = #"\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?\s*([ap]\.?m\.?)?"#
        if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            minutes = clock(String(text[range]))
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,@").union(.whitespaces))
            if text.hasSuffix("T"), text.dropLast().last?.isNumber == true { text.removeLast() }
        }
        guard let day = day(text) else { return nil }
        return (day, minutes)
    }

    static func day(_ raw: String) -> DayKey? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let day = DiaryCSV.parseDate(text) { return valid(day.year, day.month, day.day) }
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let numbers = tokens.filter { $0.allSatisfy(\.isNumber) }
        if let month = tokens.lazy.compactMap(monthNumber).first {
            guard let yearIndex = numbers.firstIndex(where: { $0.count == 4 }) ?? (numbers.count >= 2 ? numbers.count - 1 : nil),
                  var year = Int(numbers[yearIndex]) else { return nil }
            if year < 100 { year += 2000 }
            var rest = numbers
            rest.remove(at: yearIndex)
            guard let first = rest.first, let day = Int(first) else { return nil }
            return valid(year, month, day)
        }
        guard numbers.count >= 3, let a = Int(numbers[0]), let b = Int(numbers[1]), let c = Int(numbers[2]) else { return nil }
        if numbers[0].count == 4 { return valid(a, b, c) }
        guard let day = DiaryCSV.parseDate("\(a).\(b).\(c)") else { return nil }
        return valid(day.year, day.month, day.day)
    }

    /// "Jan", "Jänner", "März", "Okt", "December" → 1…12.
    static func monthNumber(_ token: String) -> Int? {
        let word = SearchText.normalize(token)
        guard word.count >= 3, word.first?.isLetter == true else { return nil }
        let names: [[String]] = [
            ["jan", "january", "januar", "janner", "jaenner"], ["feb", "february", "februar", "feber"],
            ["mar", "march", "marz", "maerz", "mrz"], ["apr", "april"], ["may", "mai"], ["jun", "june", "juni"],
            ["jul", "july", "juli"], ["aug", "august"], ["sep", "sept", "september"], ["oct", "okt", "october", "oktober"],
            ["nov", "november"], ["dec", "dez", "december", "dezember"],
        ]
        for (index, list) in names.enumerated() where list.contains(word) || list.contains(where: { $0.count > 3 && $0.hasPrefix(word) }) {
            return index + 1
        }
        return nil
    }

    /// A real calendar day (no 30 February).
    static func valid(_ year: Int, _ month: Int, _ day: Int) -> DayKey? {
        guard (1900...2200).contains(year), (1...12).contains(month) else { return nil }
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...lengths[month - 1]).contains(day) else { return nil }
        return DayKey(year: year, month: month, day: day)
    }

    // MARK: Conditions

    static let conditionAliases: [String: BodyCondition] = {
        let groups: [(BodyCondition, [String])] = [
            (.morning, ["morgens", "morgen", "fruh", "fruhmorgens", "am", "after_waking", "upon_waking", "on_waking",
                        "nach_dem_aufstehen", "nach_dem_aufwachen", "after_toilet"]),
            (.fasted, ["fasting", "nuchtern", "before_breakfast", "vor_dem_fruhstuck", "vorm_fruhstuck", "empty_stomach",
                       "before_eating", "vor_dem_essen", "before_food", "ohne_fruhstuck"]),
            (.later, ["evening", "abends", "abend", "afternoon", "nachmittags", "nachmittag", "pm", "midday", "mittags", "mittag",
                      "noon", "later_in_the_day", "night", "nachts"]),
            (.afterTraining, ["post_workout", "after_workout", "after_gym", "after_exercise", "post_training", "nach_dem_training",
                              "nach_training", "nach_dem_sport", "nach_sport", "pump"]),
            (.lateHeavyMeal, ["late_meal", "heavy_meal", "late_dinner", "spates_essen", "spaetes_essen", "spat_gegessen"]),
            (.highSalt, ["salty", "salt", "salzig", "viel_salz", "salty_food"]),
            (.alcoholYesterday, ["alcohol", "alkohol", "drinks", "alkohol_gestern", "alcohol_last_night", "wine", "beer", "bier", "wein"]),
            (.sick, ["ill", "krank", "illness", "cold", "erkaltet", "fever", "fieber"]),
            (.menstrualPhase, ["period", "menstruation", "periode", "regel", "mens", "menstrual", "pms"]),
            (.notFasted, ["fed", "after_breakfast", "after_eating", "after_food", "after_meal", "nach_dem_essen",
                          "nach_dem_fruhstuck", "nicht_nuchtern", "gegessen"]),
        ]
        var map: [String: BodyCondition] = [:]
        for condition in BodyCondition.allCases { map[condition.rawValue] = condition }
        for (condition, names) in groups {
            for name in names { map[ImportColumns.normalize(name)] = condition }
        }
        return map
    }()

    /// Words that may sit between conditions ("morning and fasted").
    private static let fillerWords: Set<String> = ["and", "und", "the", "a", "an", "with", "mit", "very", "sehr"]

    /// "morning, fasted", "nüchtern; nach dem Training", "after workout + salty" → the tags, and the
    /// words that aren't conditions (they go into the note).
    static func conditions(_ text: String) -> (tags: [BodyCondition], rest: [String]) {
        var tags: [BodyCondition] = []
        var rest: [String] = []
        let separators: Set<Character> = [",", ";", "|", "/", "+", "&"]
        for part in text.split(whereSeparator: { separators.contains($0) }) {
            let original = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = SearchText.normalize(original).split(separator: " ").map(String.init)
            guard !words.isEmpty else { continue }
            var index = 0
            var unknown = false
            while index < words.count {
                var matched = false
                for length in stride(from: min(4, words.count - index), through: 1, by: -1) {
                    let phrase = words[index..<(index + length)].joined(separator: "_")
                    if let tag = conditionAliases[phrase] {
                        if !tags.contains(tag) { tags.append(tag) }
                        index += length
                        matched = true
                        break
                    }
                }
                if !matched {
                    if !fillerWords.contains(words[index]) { unknown = true }
                    index += 1
                }
            }
            if unknown { rest.append(original) }
        }
        return (tags, rest)
    }

    /// The stored conditions of a tape session or body-fat value: the given tags, completed like
    /// the measure sheet does it. Without morning, fasted or later the time decides (before the
    /// cutoff: morning and fasted, unless not fasted; else later); "morning" alone counts as
    /// morning and fasted, "fasted" alone before the cutoff as morning and fasted.
    static func storedConditions(_ given: [BodyCondition], minutes: Int, cutoffMinutes: Int) -> String {
        var tags = given
        let isEarly = minutes < cutoffMinutes
        let hasBase = tags.contains(.morning) || tags.contains(.fasted) || tags.contains(.later)
        if !hasBase {
            let automatic: [BodyCondition] = isEarly && !tags.contains(.notFasted) ? [.morning, .fasted] : [.later]
            tags = automatic + tags
        } else if tags.contains(.morning), !tags.contains(.fasted), !tags.contains(.later), !tags.contains(.notFasted) {
            tags.append(.fasted)
        } else if tags.contains(.fasted), !tags.contains(.morning), !tags.contains(.later), isEarly {
            tags.append(.morning)
        }
        let order = BodyCondition.allCases
        return BodyProtocol.encode(tags.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) })
    }

    /// The weigh-in reasons the conditions name (salty, late meal, alcohol, ill, period).
    static func weightTags(_ conditions: [BodyCondition]) -> [WeightSignal.Tag] {
        conditions.compactMap { (condition: BodyCondition) -> WeightSignal.Tag? in
            switch condition {
            case .highSalt: return .salty
            case .lateHeavyMeal: return .lateMeal
            case .alcoholYesterday: return .alcohol
            case .sick: return .ill
            case .menstrualPhase: return .period
            default: return nil
            }
        }
    }

    // MARK: Body-fat methods

    /// "dexa", "DXA", "InBody 770", "Styku 3D scan", "Withings scale" → the method; nil when unknown.
    static func method(named text: String) -> BodyMethod? {
        if let method = SettingsCSV.bodyMethod(named: text) { return method }
        let key = SearchText.normalize(text)
        let words = Set(key.split(separator: " ").map(String.init))
        let squashed = key.replacingOccurrences(of: " ", with: "")
        func has(_ parts: [String]) -> Bool { parts.contains { squashed.contains($0) } }
        if has(["dexa"]) || words.contains("dxa") { return .dexa }
        if has(["bodpod", "airdisplacement"]) { return .bodpod }
        if has(["3d", "styku", "bodyscan", "korperscan"]) { return .scan3D }
        if has(["scale", "waage", "withings", "garmin", "eufy", "renpho", "fitbit", "omron", "xiaomi", "tanita"]) { return .scale }
        if has(["inbody", "seca", "bioimped", "bia"]) { return .biaPro }
        if has(["caliper", "skinfold", "hautfalt"]) { return .skinfold }
        if has(["navy", "tape", "massband"]) { return .navy }
        if has(["estim", "guess", "schatz"]) { return .estimate }
        return nil
    }

    static func noMethodNote(_ lines: [Int]) -> String {
        let reason = "no body_fat_method – saved as an estimate (\(SettingsCSV.methodNames))"
        guard lines.count > 1 else { return "Row \(lines.first ?? 0): \(reason)" }
        let shown = lines.prefix(5).map(String.init).joined(separator: ", ")
        let more = lines.count > 5 ? " and \(lines.count - 5) more" : ""
        return "Rows \(shown)\(more): \(reason)"
    }
}

// MARK: - One row

/// Reads one row into its records and collects its notes.
private struct RowReader {
    typealias Field = BodyHistoryCSV.Field

    let line: Int
    /// The first non-empty cell per field, with its column's factor.
    private var cells: [Field: (text: String, factor: Double, title: String)] = [:]
    /// The sites in the order of the file's columns.
    private var sites: [BodySite] = []
    /// Unknown columns: "Visceral fat: 8".
    private var extras: [String] = []
    private(set) var notes: [String] = []

    init(line: Int, columns: [BodyHistoryCSV.Column], cells row: [String]) {
        self.line = line
        for (index, column) in columns.enumerated() where index < row.count {
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard let field = column.field else {
                if !BodyHistoryCSV.isBlank(value) { extras.append("\(column.title): \(value)") }
                continue
            }
            guard field != .ignored, cells[field] == nil else { continue }
            cells[field] = (value, column.factor, column.title)
            if case .site(let site) = field { sites.append(site) }
        }
    }

    var isEmpty: Bool { cells.isEmpty && extras.isEmpty }

    /// The row's records; `withoutMethod`: a body-fat value saved as an estimate for want of a method.
    mutating func records(cutoffMinutes: Int, today: DayKey?) -> (records: [BodyHistoryRecord], withoutMethod: Bool) {
        // A row with only a date (a prepared spreadsheet line) is an empty row.
        guard cells.keys.contains(where: \.isValue) else {
            if !extras.isEmpty || cells[.note] != nil { notes.append("Row \(line): no weight, tape or body-fat value") }
            return ([], false)
        }
        guard let dateText = cells[.date]?.text else {
            notes.append("Row \(line): no date")
            return ([], false)
        }
        guard let moment = BodyHistoryCSV.moment(dateText) else {
            notes.append("Row \(line): date \u{201C}\(dateText)\u{201D} not understood (use YYYY-MM-DD)")
            return ([], false)
        }
        let day = moment.day
        if let today, day > today {
            notes.append("Row \(line): \(day.rawValue) is in the future – left out")
            return ([], false)
        }

        // Conditions (also words in the time column such as "morning"), then the time.
        var conditionText = cells[.conditions]?.text ?? ""
        var minutes = moment.minutes == 0 ? nil : moment.minutes
        if let timeText = cells[.time]?.text, !BodyHistoryCSV.isBlank(timeText) {
            if let clock = BodyHistoryCSV.clock(timeText) {
                minutes = clock
            } else if BodyHistoryCSV.conditions(timeText).rest.isEmpty {
                conditionText += conditionText.isEmpty ? timeText : ";" + timeText
            } else {
                notes.append("Row \(line): time \u{201C}\(timeText)\u{201D} not understood – 07:00 used")
            }
        }
        let parsedConditions = BodyHistoryCSV.conditions(conditionText)
        let tags = parsedConditions.tags
        let time = minutes ?? (tags.contains(.later) ? max(cutoffMinutes, BodyHistoryCSV.laterMinutes) % 1440 : BodyHistoryCSV.defaultMinutes)
        let stored = BodyHistoryCSV.storedConditions(tags, minutes: time, cutoffMinutes: cutoffMinutes)

        // Values.
        let weight = number(.weight, name: "weight_kg", range: BodyHistoryCSV.weightRange)
        let bodyFat = percent()
        let lean = mass(.lean, name: "lean_kg", range: BodyHistoryCSV.massRange)
        let fat = mass(.fat, name: "fat_kg", range: BodyHistoryCSV.massRange)
        let bone = mass(.bone, name: "bone_kg", range: BodyHistoryCSV.boneRange)
        var girths: [BodySite: Double] = [:]
        for site in sites {
            if let value = number(.site(site), name: site.rawValue + "_cm", range: site.plausibleRange) { girths[site] = value }
        }
        let methodText = cells[.method]?.text.trimmingCharacters(in: .whitespaces) ?? ""
        let method = BodyHistoryCSV.isBlank(methodText) ? nil : BodyHistoryCSV.method(named: methodText)
        let device = cells[.device]?.text ?? ""

        // Notes: the person's note, then other columns and condition words that aren't tags.
        let ownNote = cells[.note]?.text ?? ""
        let extraNote = (extras + parsedConditions.rest).joined(separator: " · ")

        let hasMass = lean != nil || fat != nil || bone != nil
        let methodMissing = BodyHistoryCSV.isBlank(methodText)
        let fatWithWeighIn = weight != nil && bodyFat != nil && !hasMass && (methodMissing || method == .scale)
        let hasAssessment = !fatWithWeighIn && (bodyFat != nil || (lean != nil && fat != nil))
        let hasTape = !girths.isEmpty

        var records: [BodyHistoryRecord] = []
        var withoutMethod = false
        if let weight {
            let note = Self.joined(ownNote, hasAssessment || hasTape ? "" : extraNote)
            let reasons = WeightSignal.Tag.parse(note) + BodyHistoryCSV.weightTags(tags)
            records.append(.weight(day: day, minutes: time, kilograms: weight, bodyFat: fatWithWeighIn ? (bodyFat ?? 0) : 0,
                                   note: WeightSignal.Tag.note(note, setting: reasons)))
        }
        if hasTape {
            let note = Self.joined(ownNote, hasAssessment ? "" : extraNote)
            records.append(.tape(day: day, minutes: time, values: BodyValues(girths), conditions: stored, note: note))
        }
        if hasAssessment {
            var values = BodyValues()
            values.bodyFat = bodyFat
            values.leanKg = lean
            values.fatKg = fat
            values.boneKg = bone
            var resolved = method
            if resolved == nil {
                if methodMissing {
                    withoutMethod = true
                } else {
                    notes.append("Row \(line): body_fat_method \u{201C}\(methodText)\u{201D} not known – saved as an estimate (\(SettingsCSV.methodNames))")
                }
                resolved = .estimate
            }
            records.append(.assessment(day: day, minutes: time, values: values, method: resolved, device: device, conditions: stored,
                                       note: Self.joined(ownNote, extraNote)))
        } else if hasMass, bodyFat == nil {
            notes.append("Row \(line): lean, fat or bone mass without body fat % – left out")
        }
        if records.isEmpty, notes.isEmpty {
            notes.append("Row \(line): no weight, tape or body-fat value")
        }
        return (records, withoutMethod)
    }

    /// A cell's number × its column's factor, within `range`; a note when it isn't a number or a typo.
    private mutating func number(_ field: Field, name: String, range: ClosedRange<Double>, grams: Bool = false,
                                 fraction: Bool = false) -> Double? {
        guard let cell = cells[field], !BodyHistoryCSV.isBlank(cell.text) else { return nil }
        guard var value = BodyHistoryCSV.number(cell.text) else {
            notes.append("Row \(line): \(name) \u{201C}\(cell.text)\u{201D} isn't a number – left out")
            return nil
        }
        value *= cell.factor
        // A DEXA report's grams in a kg column; a spreadsheet's 0.198 for 19.8 %.
        if grams, cell.factor == 1, value > 1000 { value /= 1000 }
        if fraction, value > 0, value < 1 { value *= 100 }
        if cell.factor != 1 || grams || fraction { value = (value * 100).rounded() / 100 }
        guard range.contains(value) else {
            let low = NumberText.plain(range.lowerBound), high = NumberText.plain(range.upperBound)
            notes.append("Row \(line): \(name) \(NumberText.plain(value, decimals: 2)) looks like a typo (\(low)–\(high)) – left out")
            return nil
        }
        return value
    }

    private mutating func mass(_ field: Field, name: String, range: ClosedRange<Double>) -> Double? {
        number(field, name: name, range: range, grams: true)
    }

    private mutating func percent() -> Double? {
        number(.bodyFat, name: "body_fat_pct", range: NavyBodyFat.plausibleRange, fraction: true)
    }

    private static func joined(_ parts: String...) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
