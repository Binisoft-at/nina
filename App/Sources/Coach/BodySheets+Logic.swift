import Foundation
import SwiftData
import NinaCore

// Glue for the body sheets (weigh-in, tape measurements, body-fat assessment): Foundation,
// SwiftData and NinaCore only, so it type-checks without SwiftUI. Weigh-ins read from Apple
// Health are only used live here (sanity check, body math), never stored or prefilled.

// MARK: - Numbers in fields

enum BodySheetNumber {
    /// A value the way people type it here ("74.2", "74,2"), without grouping.
    static func text(_ value: Double, decimals: Int = 1) -> String {
        guard value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
    }

    /// A typed value; nil when empty, not a number or not above zero.
    static func parse(_ text: String) -> Double? {
        guard let value = NumberText.parse(text), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// cm as typed and shown: "84.0", "84.15" (one or two decimals, no grouping).
    static func cm(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(1...2)).grouping(.never))
    }

    /// Typed but not a number ("7a").
    static func isInvalid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && parse(text) == nil
    }

    /// The text moved by `step` (±0.1), from `fallback` while the field is empty, kept in `range`.
    static func stepped(_ text: String, by step: Double, fallback: Double?, range: ClosedRange<Double>) -> String {
        guard let base = parse(text) ?? fallback else { return text }
        let value = ((base + step) * 10).rounded() / 10
        return self.text(min(max(value, range.lowerBound), range.upperBound))
    }
}

// MARK: - Weigh-in

/// A weigh-in's editable values (also what Undo of an edit puts back).
struct BodySheetWeighIn: Equatable {
    var kilograms: Double
    var day: DayKey
    var time: Date
    var bodyFat: Double
    var note: String
}

extension WeightEntry {
    var bodySheetValues: BodySheetWeighIn {
        BodySheetWeighIn(kilograms: kilograms, day: dayKey, time: time, bodyFat: bodyFat, note: note)
    }
}

extension NinaStore {
    /// Changes a weigh-in, its time included; returns the values before (for Undo).
    @discardableResult
    func update(_ weight: WeightEntry, to values: BodySheetWeighIn) -> BodySheetWeighIn {
        let previous = weight.bodySheetValues
        weight.time = values.time
        update(weight, kilograms: values.kilograms, day: values.day, bodyFat: values.bodyFat, note: values.note)
        return previous
    }

    /// The weight signal over the typed weigh-ins without `entry` (the one being edited) and the
    /// live Health weigh-ins.
    func bodySheetSignal(excluding entry: WeightEntry?, health: [WeightSignal.Reading], settings: NinaSettings) -> WeightSignal {
        let typed = weights().filter { $0.uuid != entry?.uuid }.map(\.reading)
        return WeightSignal(typed + health, cutoffMinutes: settings.plan.routine.morningCutoffMinutes,
                            dayStartHour: settings.dayStartHour, calendar: calendar)
    }

    /// Something eaten is logged on `day` at or before `time` (a tape reading then isn't fasted).
    func bodySheetHasEaten(on day: DayKey, before time: Date) -> Bool {
        entries(on: day).contains { $0.entryStatus == .eaten && $0.time <= time }
    }
}

extension AppModel {
    /// Saves an edited weigh-in with an Undo toast. When the weight or its time changed, the
    /// sample Nina wrote to Apple Health is replaced (old out, new in), and Undo swaps it back.
    func bodySheetUpdate(_ entry: WeightEntry, to values: BodySheetWeighIn) {
        let previous = store.update(entry, to: values)
        let changed = previous.kilograms != values.kilograms || previous.time != values.time
        let health = self.health
        let replace: Task<Void, Never>? = changed
            ? Task { await health.replaceWeight(old: (previous.kilograms, previous.time), new: (values.kilograms, values.time)) }
            : nil
        toasts.show("Weigh-in updated", symbol: "scalemass.fill") { [weak self] in
            _ = self?.store.update(entry, to: previous)
            guard let replace else { return }
            Task {
                await replace.value
                await health.replaceWeight(old: (values.kilograms, values.time), new: (previous.kilograms, previous.time))
            }
        }
    }
}

/// What the weigh-in sheet reads once when it opens.
struct BodySheetWeighInContext {
    /// Typed weigh-ins (without the one being edited) and live Health weigh-ins.
    var signal: WeightSignal
    var sex: Sex
    var dayStartHour: Int
    var calendar: Calendar
    /// The newest weigh-in typed in Nina: the prefilled number. (Never one from Health: a
    /// prefilled Health value saved with one tap would copy Health data into iCloud.)
    var latest: Double?

    @MainActor
    static func load(app: AppModel, editing entry: WeightEntry?) -> BodySheetWeighInContext {
        let store = app.store
        let settings = app.settings
        let signal = store.bodySheetSignal(excluding: entry, health: app.healthWeightReadings, settings: settings)
        let latest = BodySheetWeight.latest(typed: store.weights())
        return BodySheetWeighInContext(signal: signal, sex: settings.body.sex, dayStartHour: settings.dayStartHour,
                                       calendar: store.calendar, latest: latest)
    }

    /// The diary day a weigh-in at `time` counts for.
    func day(for time: Date) -> DayKey {
        DayKey(date: time, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// The 7-day average on that day (the trend while there is none): what a new weight is checked against.
    func reference(at time: Date) -> Double? {
        let day = day(for: time)
        return signal.average(on: day).value ?? signal.trend(on: day)
    }

    /// The weight signal's sanity check (25–300 kg, within 3 kg of the 7-day average).
    func sanity(_ kilograms: Double, at time: Date) -> WeightSignal.Sanity {
        signal.sanity(kilograms, on: day(for: time))
    }

    /// More than 1.5 % of body weight from the trend: "anything special?".
    func isUnusual(_ kilograms: Double, at time: Date) -> Bool {
        signal.isUnusual(kilograms, on: day(for: time))
    }
}

/// A weight that failed the sanity check, and what Nina suggests instead.
struct BodySheetWeightCheck: Equatable {
    var kilograms: Double
    /// Outside 25–300 kg: never saved.
    var isOutOfRange: Bool
    /// The 7-day average (or trend) it is far from.
    var reference: Double?
    /// "Did you mean …?"
    var suggestion: Double?

    init?(_ kilograms: Double, sanity: WeightSignal.Sanity, reference: Double?) {
        switch sanity {
        case .ok:
            return nil
        case .outOfRange:
            self.kilograms = kilograms
            isOutOfRange = true
            self.reference = reference
        case .typo(let average):
            self.kilograms = kilograms
            isOutOfRange = false
            self.reference = average
        }
        suggestion = BodySheetWeight.suggestion(for: kilograms, reference: self.reference)
    }
}

enum BodySheetWeight {
    /// kg the number accepts at all (the weight signal's plausible range).
    static let range: ClosedRange<Double> = WeightSignal.plausibleRange

    /// "Did you mean …?" for a typed weight that failed the sanity check: a misplaced decimal
    /// point, one wrong digit or two swapped digits that bring it within 3 kg of `reference`
    /// (`WeightSignal.typoSuggestion`).
    static func suggestion(for kilograms: Double, reference: Double?) -> Double? {
        WeightSignal.typoSuggestion(for: kilograms, reference: reference)
    }

    /// The newest weigh-in typed in Nina (by time).
    static func latest(typed: [WeightEntry]) -> Double? {
        typed.max { $0.time < $1.time }?.kilograms
    }
}

// MARK: - Conditions (tape and assessments)

enum BodySheetConditions {
    /// The known tags of a conditions text, in order.
    static func parse(_ text: String) -> [BodyCondition] {
        BodyProtocol.tags(text).compactMap { BodyCondition(rawValue: $0) }
    }

    /// Tags in a conditions text Nina doesn't know (kept as they are when saving an edit).
    static func unknownTags(_ text: String) -> [String] {
        BodyProtocol.tags(text).filter { BodyCondition(rawValue: $0) == nil }
    }

    /// The chips: the automatic tags first, then the exceptions (no period for men).
    static func offered(for sex: Sex) -> [BodyCondition] {
        [.morning, .fasted, .later] + BodyCondition.exceptions(for: sex)
    }

    /// The tags after a tap on a chip: morning and later exclude each other, so do fasted and
    /// not fasted.
    static func toggling(_ condition: BodyCondition, in list: [BodyCondition]) -> [BodyCondition] {
        if list.contains(condition) { return list.filter { $0 != condition } }
        let opposite: [BodyCondition]
        switch condition {
        case .morning: opposite = [.later]
        case .later: opposite = [.morning]
        case .fasted: opposite = [.notFasted]
        case .notFasted: opposite = [.fasted]
        default: opposite = []
        }
        return list.filter { !opposite.contains($0) } + [condition]
    }

    /// The text to store: the tags in their usual order, unknown tags kept at the end.
    static func encode(_ list: [BodyCondition], keeping unknown: [String] = []) -> String {
        let known = BodyProtocol.encode(BodyCondition.allCases.filter { list.contains($0) })
        return ([known] + unknown).filter { !$0.isEmpty }.joined(separator: ",")
    }

    /// "Standard reading – counts in your trends", or why it doesn't.
    static func summary(_ list: [BodyCondition]) -> String {
        if BodyProtocol.isStandard(list) { return "Standard reading – it counts in your trends." }
        return "Not a standard reading – it's kept, but left out of trends and goal maths."
    }

    /// "Morning, Before eating": the chips that are on, in their usual order (the line at the
    /// top of each page of the measure pager).
    static func shortText(_ list: [BodyCondition]) -> String {
        let titles = BodyCondition.allCases.filter { list.contains($0) }.map(\.title)
        return titles.isEmpty ? "No conditions" : titles.joined(separator: ", ")
    }
}

// MARK: - Tape measurements

/// What the measure sheet reads once when it opens.
struct BodySheetTapeContext {
    /// The plan's routine, or the defaults for the person's sex without a plan.
    var routine: CoachPlan.Routine
    var sex: Sex
    /// From the profile; 0 = not set (no tape estimate).
    var heightCm: Double
    var dayStartHour: Int
    var calendar: Calendar
    /// The earlier tape records (without the one being edited), oldest first.
    var records: [BodyTapeRecord]
    /// A body-fat assessment is due today as well (offered after a full set).
    var assessmentDue: Bool

    @MainActor
    static func load(app: AppModel, editing record: BodyMeasurement?) -> BodySheetTapeContext {
        let context = CoachContext.load(app: app, day: app.today)
        let sex = context.settings.body.sex
        let plan = context.plan
        let routine = plan.isSetUp ? plan.routine : CoachPlan.Routine.defaults(for: sex)
        let records = context.tapeMeasurements.filter { $0.uuid != record?.uuid }.compactMap(\.tapeRecord)
        let due = context.dueItems.contains { $0.kind == .assessment || ($0.kind == .full && $0.includesAssessment) }
        let height = app.store.profile()?.heightCm ?? 0
        return BodySheetTapeContext(routine: routine, sex: sex, heightCm: max(0, height),
                                    dayStartHour: context.settings.dayStartHour, calendar: context.calendar,
                                    records: records, assessmentDue: due)
    }

    var cutoffMinutes: Int { routine.morningCutoffMinutes }

    /// The diary day a measurement at `time` counts for.
    func day(for time: Date) -> DayKey {
        DayKey(date: time, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// The sites of a mode with their side keys (weekly, full set, or one site with the other side
    /// when both are measured), plus every site an edited record already has, so nothing is lost.
    func sites(for mode: MeasureMode, keeping values: BodyValues? = nil) -> [BodySite] {
        let schedule = BodySchedule(routine: routine)
        var sites: [BodySite]
        switch mode {
        case .weekly: sites = schedule.weeklySites
        case .full: sites = schedule.fullSites
        case .site(let site): sites = site.measuredSites(side: routine.side)
        }
        if let values {
            for site in BodySite.allCases where values[site] != nil && !sites.contains(site) { sites.append(site) }
        }
        return sites
    }

    /// The latest earlier reading of a site on or before `day` (any conditions).
    func previous(_ site: BodySite, before day: DayKey) -> GirthReading? {
        GirthTrend.readings(site, in: records.filter { $0.day <= day }, includeNonStandard: true).last
    }

    /// The latest earlier session (for "Last time: Mon, 7 Jan, 07:15 · Morning, Before eating").
    var lastSession: BodyTapeRecord? { records.last }

    /// "Arm (right)" for a sided site on the right, else the site's title.
    func title(for site: BodySite) -> String {
        site.hasSides && !site.isLeft ? "\(site.title) (right)" : site.title
    }

    /// The side and where exactly the tape goes (the plan's thigh mark when it has one).
    func hint(for site: BodySite) -> String {
        var parts: [String] = []
        if site.hasSides { parts.append(site.isLeft ? "Left side" : "Right side") }
        let mark = routine.thighMark.trimmingCharacters(in: .whitespaces)
        if site.base == .thigh, !mark.isEmpty {
            parts.append("At your mark: \(mark), weight on both legs")
        } else {
            parts.append(site.landmark)
        }
        return parts.joined(separator: " · ")
    }

    /// The state of one site's fields. `recheck`: a single reading that moved more than 1 cm
    /// since last time asks for a second one (new measurements only).
    func state(for site: BodySite, texts: [String], base: Int, twoReadings: Bool, recheck: Bool,
               day: DayKey) -> BodySheetSiteState {
        BodySheetSiteState(site: site, texts: texts, base: base, twoReadings: twoReadings,
                           previous: previous(site, before: day), recheck: recheck, day: day, calendar: calendar)
    }

    /// The formula of the tape estimate: from the sex, else the one chosen in the sheet.
    func formula(chosen: String) -> NavyBodyFat.Formula? {
        NavyBodyFat.Formula(sex: sex) ?? NavyBodyFat.Formula(rawValue: chosen)
    }

    /// What the sheet shows about the tape estimate; nil to show nothing (no waist value yet, or
    /// a missing site the person doesn't measure in this set).
    func estimateLine(values: BodyValues, sites: [BodySite], day: DayKey, time: Date, conditions: String,
                      formula: NavyBodyFat.Formula?) -> BodySheetEstimateLine? {
        guard let availability = navyEstimate(values: values, day: day, time: time, conditions: conditions,
                                              formula: formula) else { return nil }
        switch availability {
        case .available(let estimate): return .value(estimate.bodyFat)
        case .needsHeight: return .needsHeight
        case .needsFormula: return .needsFormula
        case .needsSites(let missing): return missing.contains { sites.contains($0) } ? .needsSites(missing) : nil
        case .implausible: return .implausible
        }
    }

    /// The live tape estimate with this sheet's values and the earlier readings (neck, hip within
    /// 12 weeks). nil while the sheet has no waist value for the formula.
    func navyEstimate(values: BodyValues, day: DayKey, time: Date, conditions: String,
                      formula: NavyBodyFat.Formula?) -> NavyBodyFat.Availability? {
        let waists: [BodySite] = formula.map { [$0.waistSite] } ?? [.waist, .waistNarrow]
        guard waists.contains(where: { values[$0] != nil }) else { return nil }
        let draft = BodyTapeRecord(day: day, time: time, values: values, conditions: conditions)
        return NavyBodyFat.estimate(formula: formula, heightCm: heightCm, records: records + [draft], on: day,
                                    includeNonStandard: !BodyProtocol.isStandard(conditions), calendar: calendar)
    }
}

/// The tape estimate line of the measure sheet.
enum BodySheetEstimateLine: Equatable {
    /// Body fat %, unrounded.
    case value(Double)
    /// No height in the profile.
    case needsHeight
    /// Sex not set and no formula chosen yet.
    case needsFormula
    case needsSites([BodySite])
    case implausible

    /// "Add your neck for a tape estimate."
    static func sitesText(_ sites: [BodySite]) -> String {
        let names = sites.map { $0.title.lowercased() }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : (names.first ?? "")
        return "Add your \(list) for a tape estimate."
    }

    /// The small print under the estimate.
    var footer: String {
        switch self {
        case .value: return "US Navy \(NavyBodyFat.label), worked out from your tape values and never saved."
        case .needsFormula: return "The tape estimate has a formula for men and one for women. Nina remembers your choice."
        case .needsSites: return "Neck and waist (women: also hip) within 12 weeks of each other."
        case .needsHeight, .implausible: return "Worked out live from your tape values, never saved."
        }
    }
}

/// One site in the measure sheet: its readings and what to say about them.
struct BodySheetSiteState {
    var site: BodySite
    /// The readings typed, in order.
    var values: [Double]
    /// Fields shown (one more while another reading is wanted).
    var fieldCount: Int
    /// Fields every site starts with (two in a full set).
    var base: Int
    /// The value to store.
    var merged: Double?
    /// The latest earlier reading.
    var previous: GirthReading?
    /// A reading isn't a number or is outside the site's plausible range (not saved then).
    var isInvalid: Bool
    /// More than 3 cm from a reading within the last 7 days.
    var isJump: Bool
    var calendar: Calendar

    init(site: BodySite, texts: [String], base: Int, twoReadings: Bool, previous: GirthReading?, recheck: Bool,
         day: DayKey, calendar: Calendar) {
        let values = BodySheetReadings.values(texts)
        let count = BodySheetReadings.fieldCount(values, base: base, twoReadings: twoReadings,
                                                 previous: recheck ? previous?.value : nil)
        let merged = BodySheetReadings.merged(values, count: count)
        let invalidText = texts.prefix(count).contains { BodySheetNumber.isInvalid($0) }
        let outside = values.prefix(count).contains { !site.isPlausible($0) }
        let daysApart = previous.map { $0.day.days(to: day, calendar: calendar) } ?? 0
        var jump = false
        if let merged { jump = BodyReadings.isSuspiciousJump(merged, previous: previous?.value, daysApart: daysApart) }
        self.site = site
        self.values = values
        self.fieldCount = count
        self.base = base
        self.merged = merged
        self.previous = previous
        self.isInvalid = invalidText || outside
        self.isJump = jump
        self.calendar = calendar
    }

    /// "Last 84.2 cm · 7 Jan", or the change once there is a value: "−0.3 cm since 7 Jan".
    var previousText: String? {
        guard let previous else { return nil }
        let date = Fmt.shortDay(previous.day, calendar: calendar)
        guard let merged, !isInvalid else { return "Last \(BodySheetNumber.cm(previous.value)) cm · \(date)" }
        let change = merged - previous.value
        let sign = change >= 0.05 ? "+" : (change <= -0.05 ? "−" : "±")
        return "\(sign)\(BodySheetNumber.cm(abs(change))) cm since \(date)"
    }

    /// The line under the fields: a typo, another reading wanted, a big jump, or the value saved.
    var message: String? {
        if isInvalid {
            let range = site.plausibleRange
            return "Check this value – \(site.title.lowercased()) is usually "
                + "\(Fmt.number(range.lowerBound))–\(Fmt.number(range.upperBound)) cm."
        }
        if fieldCount > base, values.count >= 1, values.count < fieldCount {
            return fieldCount == 3 ? "The readings differ by more than 0.5 cm – take a third one."
                : "That's over 1 cm from last time – measure once more."
        }
        if isJump, let previous {
            return "Over 3 cm from \(Fmt.shortDay(previous.day, calendar: calendar)) – same spot as last time?"
        }
        if min(values.count, fieldCount) > 1, let merged {
            let how = min(values.count, fieldCount) >= 3 ? "the middle reading" : "the average"
            return "Saved as \(BodySheetNumber.cm(merged)) cm (\(how))."
        }
        return nil
    }
}

enum BodySheetReadings {
    /// The readings typed for a site, in order (empty and invalid fields skipped, at most three).
    static func values(_ texts: [String]) -> [Double] {
        texts.prefix(3).compactMap { BodySheetNumber.parse($0) }
    }

    /// How many reading fields a site shows: `base` (two in a full set, else one), and one more
    /// while `BodyReadings.needsAnother` asks for it (they differ by more than 0.5 cm, or a
    /// single reading moved more than 1 cm since last time); at most three.
    static func fieldCount(_ values: [Double], base: Int, twoReadings: Bool, previous: Double?) -> Int {
        var count = max(1, base)
        while count < 3, values.count >= count,
              BodyReadings.needsAnother(Array(values.prefix(count)), twoReadings: twoReadings, previous: previous) {
            count += 1
        }
        return count
    }

    /// The value stored for a site: the mean of two readings, the median of three.
    static func merged(_ values: [Double], count: Int) -> Double? {
        BodyReadings.merged(Array(values.prefix(count)))
    }

    /// The record's values with the sheet's sites set (a cleared site is removed); other keys stay.
    static func values(base: BodyValues, merged: [BodySite: Double], sites: [BodySite]) -> BodyValues {
        var storage = base.storage
        for site in sites {
            if let value = merged[site] {
                storage[site.rawValue] = value
            } else {
                storage.removeValue(forKey: site.rawValue)
            }
        }
        return BodyValues(storage)
    }

    /// "Last time: Mon, 7 Jan, 07:15 · Morning, Before eating"
    static func lastTimeText(_ record: BodyTapeRecord, calendar: Calendar) -> String {
        let date = record.time ?? record.day.date(calendar: calendar)
        let when = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        let tags = BodySheetConditions.parse(record.conditions).map(\.title)
        return tags.isEmpty ? "Last time: \(when)" : "Last time: \(when) · \(tags.joined(separator: ", "))"
    }

    /// No reading typed in field `index` (missing, empty or blanks).
    static func isEmpty(_ texts: [String], at index: Int) -> Bool {
        index >= texts.count || texts[index].trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// "2nd Reading", "3rd Reading" (field 1 and 2 of a site).
    static func readingTitle(_ index: Int) -> String {
        index >= 2 ? "3rd Reading" : "2nd Reading"
    }
}

// MARK: - Measure pager (a new tape session, one site per page)

/// A page of the measure pager: the start page (measuring guide, conditions, time and note) or
/// one site.
enum BodySheetMeasurePage: Hashable {
    case start
    case site(BodySite)

    var site: BodySite? {
        if case .site(let site) = self { return site }
        return nil
    }
}

/// The reading field with the keyboard: a site's first reading (the big number), 2nd or 3rd.
struct BodySheetMeasureFocus: Hashable {
    var site: BodySite
    var index: Int
}

/// What Next does on a page of the measure pager.
enum BodySheetNextStep: Equatable {
    /// To another reading of this site (wanted and still empty): field 1 or 2.
    case reading(Int)
    /// To the next page.
    case page(BodySheetMeasurePage)
    /// The last page: save the session.
    case done
}

/// The order of the measure pager: the start page, then one page per site.
struct BodySheetPager: Equatable {
    var sites: [BodySite]

    var pages: [BodySheetMeasurePage] { [.start] + sites.map { BodySheetMeasurePage.site($0) } }

    var lastPage: BodySheetMeasurePage { pages.last ?? .start }

    func next(after page: BodySheetMeasurePage) -> BodySheetMeasurePage? {
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else { return nil }
        return pages[index + 1]
    }

    func previous(before page: BodySheetMeasurePage) -> BodySheetMeasurePage? {
        guard let index = pages.firstIndex(of: page), index > 0 else { return nil }
        return pages[index - 1]
    }

    /// Where the sheet opens: the start page while the measuring guide is shown (the first time,
    /// or with nothing to measure), else the first site.
    func firstPage(showsGuide: Bool) -> BodySheetMeasurePage {
        guard !showsGuide, let first = sites.first else { return .start }
        return .site(first)
    }

    /// What Next does on `page`: once the first reading is in, to a reading field the site still
    /// wants and that is empty (unless it already has the keyboard), then to the next page, and
    /// Done on the last one.
    func step(after page: BodySheetMeasurePage, texts: [String] = [], fieldCount: Int = 1,
              focusedIndex: Int? = nil) -> BodySheetNextStep {
        if page.site != nil, fieldCount > 1, BodySheetNumber.parse(texts.first ?? "") != nil {
            for index in 1..<min(fieldCount, 3) where index != focusedIndex && BodySheetReadings.isEmpty(texts, at: index) {
                return .reading(index)
            }
        }
        guard let next = next(after: page) else { return .done }
        return .page(next)
    }
}

// MARK: - Body-fat assessment

/// What the assessment sheet reads once when it opens.
struct BodySheetAssessmentContext {
    var sex: Sex
    /// Typed and live Health weigh-ins, for the fat and lean mass.
    var signal: WeightSignal
    var today: DayKey
    /// The weight for body math today (7-day average, else trend, else latest).
    var bodyWeight: WeightSignal.Estimate?
    var dayStartHour: Int
    var cutoffMinutes: Int
    var calendar: Calendar
    /// The plan's tracking method, else the last one used, else a smart scale.
    var defaultMethod: BodyMethod
    /// The last device name used per method ("InBody 570").
    var devices: [BodyMethod: String]
    /// No body-fat value yet: show the first-use tip.
    var isFirst: Bool

    @MainActor
    static func load(app: AppModel, editing record: BodyMeasurement?) -> BodySheetAssessmentContext {
        let context = CoachContext.load(app: app, day: app.today)
        let assessments = context.assessments.filter { $0.uuid != record?.uuid }
        var devices: [BodyMethod: String] = [:]
        for assessment in assessments {
            let device = assessment.device.trimmingCharacters(in: .whitespaces)
            if let method = assessment.bodyMethod, !device.isEmpty { devices[method] = device }
        }
        let tracking = context.plan.routine.bodyFatMethod.flatMap { BodySheetAssessment.methods.contains($0) ? $0 : nil }
        let last = assessments.last?.bodyMethod.flatMap { BodySheetAssessment.methods.contains($0) ? $0 : nil }
        return BodySheetAssessmentContext(
            sex: context.settings.body.sex, signal: context.signal, today: context.today, bodyWeight: context.bodyWeight,
            dayStartHour: context.settings.dayStartHour, cutoffMinutes: context.plan.routine.morningCutoffMinutes,
            calendar: context.calendar, defaultMethod: tracking ?? last ?? .scale, devices: devices,
            isFirst: context.bodyFatReadings.isEmpty)
    }

    /// The diary day an assessment at `time` counts for.
    func day(for time: Date) -> DayKey {
        DayKey(date: time, calendar: calendar, dayStartHour: dayStartHour)
    }

    /// The value with its fat and lean mass: the device's kg when it gave both, else the body
    /// weight around that day (the morning weights' mean, the 7-day average for today) × body fat.
    /// Bone mass (DEXA) is added to the device's lean mass.
    func point(bodyFat: Double, method: BodyMethod, device: String, leanKg: Double?, fatKg: Double?, boneKg: Double?,
               time: Date) -> BodyCompositionPoint? {
        guard bodyFat > 0 else { return nil }
        let reading = BodyFatReading(day: day(for: time), time: time, bodyFat: bodyFat, method: method, device: device,
                                     leanKg: leanKg, fatKg: fatKg, boneKg: boneKg)
        return signal.compositionPoints([reading], today: today, typedWeight: bodyWeight?.kilograms).first
    }
}

enum BodySheetAssessment {
    /// The methods to pick from, most accurate first (the tape estimate is computed live from
    /// tape values and never stored as an assessment).
    static let methods: [BodyMethod] = BodyMethod.accuracyOrder.filter { $0 != .navy }

    /// Body fat % accepted (anything else is a typo).
    static let bodyFatRange: ClosedRange<Double> = NavyBodyFat.plausibleRange

    /// Methods whose device name starts a series of its own (a 3D scanner too: Styku and Fit3D
    /// differ).
    static func usesDevice(_ method: BodyMethod) -> Bool {
        method == .scale || method == .biaPro || method == .scan3D
    }

    /// "DEXA scan · ±1.5"
    static func label(_ method: BodyMethod) -> String {
        method.errorBand == nil ? method.title : "\(method.title) · \(method.errorText)"
    }

    /// The record's values with body fat, lean, fat and bone mass set (cleared ones removed);
    /// other keys (skinfolds) stay.
    static func values(base: BodyValues, bodyFat: Double, leanKg: Double?, fatKg: Double?, boneKg: Double?) -> BodyValues {
        var storage = base.storage
        storage[BodyValues.bodyFatKey] = bodyFat
        let optional: [(String, Double?)] = [(BodyValues.leanKey, leanKg), (BodyValues.fatKey, fatKg),
                                             (BodyValues.boneKey, boneKg)]
        for (key, value) in optional {
            if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
        }
        return BodyValues(storage)
    }

    /// Where fat and lean mass came from (one sentence).
    static func weightText(_ weight: CompositionWeight?) -> String {
        guard let weight else { return "From the lean and fat mass your device gave." }
        let kg = Fmt.kilograms(weight.kg)
        switch weight.source {
        case .morningAverage: return "Worked out from \(kg), the average of \(weight.count) morning weigh-ins."
        case .trend: return "Worked out from \(kg), your weight trend."
        case .typed: return "Worked out from \(kg), your latest weigh-in."
        }
    }
}
