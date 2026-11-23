import Foundation
import SwiftData
import NinaCore

// The coach & body data: body measurements, day marks (day types, daily checks, check-ins, phase
// decisions) and the plan, read and written through NinaStore. Compiled into the app and the
// watch, so Foundation and SwiftData only. Values from Apple Health are never written here.

// MARK: - Bridges to Core

extension WeightEntry {
    /// The weigh-in as the weight signal reads it (typed in Nina).
    var reading: WeightSignal.Reading {
        WeightSignal.Reading(day: dayKey, time: time, kilograms: kilograms, note: note, source: .nina)
    }

    /// The body fat typed with the weigh-in ("Weigh-in body fat" series); nil without one.
    var bodyFatReading: BodyFatReading? {
        guard bodyFat > 0 else { return nil }
        return BodyFatReading.weighIn(day: dayKey, time: time, kilograms: kilograms, bodyFat: bodyFat)
    }
}

extension BodyMeasurement {
    /// A tape record for trends, the tape estimate and the schedule; nil for an assessment.
    var tapeRecord: BodyTapeRecord? {
        guard recordKind == .tape else { return nil }
        return BodyTapeRecord(day: dayKey, time: time, values: bodyValues, conditions: conditions)
    }

    /// An assessment's body-fat value (method "" counts as an estimate); nil for tape or without a value.
    var bodyFatReading: BodyFatReading? {
        guard recordKind == .assessment else { return nil }
        return BodyFatReading(assessmentOn: dayKey, time: time, method: bodyMethod ?? .estimate, device: device, values: bodyValues)
    }

    /// The editable values.
    var draft: BodyMeasurementDraft {
        BodyMeasurementDraft(day: dayKey, time: time, kind: recordKind, values: bodyValues, method: bodyMethod, device: device,
                             conditions: conditions, note: note)
    }
}

extension DayMark {
    /// A check mark's state ("state=done").
    var checkState: CheckState? { CheckState(rawValue: metaText["state"] ?? "") }
    /// A phase mark's decision ("event=review-keep").
    var phaseEvent: PhaseEvent? { PhaseEvent(rawValue: metaText["event"] ?? "") }

    /// A check-in mark's snapshot; nil for other kinds.
    var checkInSnapshot: CheckInSnapshot? {
        guard markKind == .checkIn else { return nil }
        return CheckInSnapshot(day: dayKey, values: values, meta: meta)
    }
}

extension Sequence where Element == DayMark {
    /// The marks of `kind` that win by the newest-wins rule (`DayMarks.newest`): of the live marks
    /// and the ones cleared in the last 30 days in the same group, the one changed last; a newer
    /// clear means none. Without cleared marks among them it is simply the newest live one per group.
    func winning(_ kind: DayMarkKind, groupedBy group: (DayMark) -> String, now: Date = Date()) -> [DayMark] {
        let cutoff = now.addingTimeInterval(-Double(DayMarks.clearedDays) * 86_400)
        let marks = filter { mark in
            mark.kind == kind.rawValue && (mark.deletedAt.map { $0 >= cutoff } ?? true)
        }
        return DayMarks.newest(marks, group: group, modifiedAt: { $0.modifiedAt }, isTrashed: { $0.deletedAt != nil })
    }

    /// Day-type marks as the plan resolvers want them: DayKey raw value → type id, the newest
    /// mark per day ("Back to schedule" newer than a mark from another device wins).
    var dayTypeMap: [String: String] {
        var types: [String: String] = [:]
        for mark in winning(.dayType, groupedBy: { $0.day }) where !mark.key.isEmpty {
            types[mark.day] = mark.key
        }
        return types
    }

    /// The check states of a day: check id → done or skipped, the newest mark per check.
    func checkStates(on day: DayKey) -> [String: CheckState] {
        var states: [String: CheckState] = [:]
        let raw = day.rawValue
        for mark in winning(.check, groupedBy: { "\($0.day)|\($0.key)" }) where mark.day == raw {
            if let state = mark.checkState { states[mark.key] = state }
        }
        return states
    }

    /// The checks ticked done, by day (for `DayAdherence(doneChecks:)`).
    var doneChecks: [DayKey: Set<String>] {
        var done: [DayKey: Set<String>] = [:]
        for mark in winning(.check, groupedBy: { "\($0.day)|\($0.key)" }) where mark.checkState == .done {
            done[mark.dayKey, default: []].insert(mark.key)
        }
        return done
    }

    /// (day, check id) of every done tick, for `CheckInEngine.weightCheck(in:ticks:)`.
    var checkTicks: [(day: DayKey, checkID: String)] {
        winning(.check, groupedBy: { "\($0.day)|\($0.key)" }).filter { $0.checkState == .done }
            .map { (day: $0.dayKey, checkID: $0.key) }
    }

    /// The days with an event mark of `key` ("incompleteLog"), the newest mark per day.
    func eventDays(_ key: String) -> Set<DayKey> {
        Set(winning(.event, groupedBy: { "\($0.day)|\($0.key)" }).filter { $0.key == key }.map(\.dayKey))
    }
}

// MARK: - Values for writing

/// A body measurement's values, for adding and editing (and for Undo of an edit).
struct BodyMeasurementDraft: Equatable {
    var day: DayKey
    var time: Date
    var kind: BodyRecordKind
    /// Tape values in cm; assessments: bodyFat, leanKg, fatKg, boneKg.
    var values: BodyValues
    /// Assessments: how the body fat was measured.
    var method: BodyMethod?
    /// "InBody 570": each device is its own series.
    var device: String
    /// Comma tags ("morning,fasted"), `BodyProtocol.encode`.
    var conditions: String
    var note: String

    init(day: DayKey, time: Date, kind: BodyRecordKind, values: BodyValues, method: BodyMethod? = nil, device: String = "",
         conditions: String = "", note: String = "") {
        self.day = day
        self.time = time
        self.kind = kind
        self.values = values
        self.method = method
        self.device = device
        self.conditions = conditions
        self.note = note
    }

    func write(to measurement: BodyMeasurement) {
        measurement.day = day.rawValue
        measurement.time = time
        measurement.kind = kind.rawValue
        measurement.values = values.encoded
        measurement.method = kind == .assessment ? (method?.rawValue ?? "") : ""
        measurement.device = device.trimmingCharacters(in: .whitespacesAndNewlines)
        measurement.conditions = conditions
        measurement.note = note
    }
}

/// The plan and the profile fields it mirrors, as they were before a plan change.
struct CoachProfileFields: Equatable {
    var coachPlan: String
    var targets: String
    var trainingTargets: String
    var trainingDays: String
    var goal: String
    var ratePerWeek: Double
    var targetWeight: Double

    init(_ profile: NinaProfile) {
        coachPlan = profile.coachPlan
        targets = profile.targets
        trainingTargets = profile.trainingTargets
        trainingDays = profile.trainingDays
        goal = profile.goal
        ratePerWeek = profile.ratePerWeek
        targetWeight = profile.targetWeight
    }

    var plan: CoachPlan { CoachPlan(encoded: coachPlan) }

    func write(to profile: NinaProfile) {
        profile.coachPlan = coachPlan
        profile.targets = targets
        profile.trainingTargets = trainingTargets
        profile.trainingDays = trainingDays
        profile.goal = goal
        profile.ratePerWeek = ratePerWeek
        profile.targetWeight = targetWeight
    }
}

/// A day mark as it was before an edit.
struct DayMarkState {
    let mark: DayMark
    let day: String
    let key: String
    let values: String
    let meta: String
    let note: String

    init(_ mark: DayMark) {
        self.mark = mark
        day = mark.day
        key = mark.key
        values = mark.values
        meta = mark.meta
        note = mark.note
    }

    func restore(now: Date) {
        mark.day = day
        mark.key = key
        mark.values = values
        mark.meta = meta
        mark.note = note
        mark.modifiedAt = now
    }
}

/// What a coach write changed, so a toast's Undo can put it back with `store.undo(_:)`.
struct CoachUndo {
    /// The plan and its mirrored profile fields before (nil = the plan wasn't changed).
    var profile: CoachProfileFields?
    var inserted: [DayMark] = []
    var trashed: [DayMark] = []
    var edited: [DayMarkState] = []

    init(profile: CoachProfileFields? = nil, inserted: [DayMark] = [], trashed: [DayMark] = [], edited: [DayMarkState] = []) {
        self.profile = profile
        self.inserted = inserted
        self.trashed = trashed
        self.edited = edited
    }

    /// The plan before the change (nil = the plan wasn't changed).
    var previousPlan: CoachPlan? { profile?.plan }

    var isEmpty: Bool { profile == nil && inserted.isEmpty && trashed.isEmpty && edited.isEmpty }

    mutating func merge(_ other: CoachUndo) {
        if profile == nil { profile = other.profile }
        inserted += other.inserted
        trashed += other.trashed
        edited += other.edited
    }
}

// MARK: - Reading

extension NinaStore {
    /// Every live body measurement, oldest first.
    func measurements() -> [BodyMeasurement] {
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func measurements(kind: BodyRecordKind) -> [BodyMeasurement] {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.kind == raw && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func measurements(from start: DayKey, through end: DayKey) -> [BodyMeasurement] {
        let first = start.rawValue, last = end.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.day >= first && $0.day <= last && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func measurement(_ id: UUID) -> BodyMeasurement? {
        let descriptor = FetchDescriptor<BodyMeasurement>(predicate: #Predicate<BodyMeasurement> { $0.uuid == id })
        return try? context.fetch(descriptor).first
    }

    /// Live day marks of a kind, oldest day first (newest change last within a day).
    func dayMarks(_ kind: DayMarkKind) -> [DayMark] {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<DayMark>(
            predicate: #Predicate<DayMark> { $0.kind == raw && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.modifiedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func dayMarks(_ kind: DayMarkKind, from start: DayKey, through end: DayKey) -> [DayMark] {
        let raw = kind.rawValue, first = start.rawValue, last = end.rawValue
        let descriptor = FetchDescriptor<DayMark>(
            predicate: #Predicate<DayMark> { $0.kind == raw && $0.day >= first && $0.day <= last && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.modifiedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func dayMarks(_ kind: DayMarkKind, on day: DayKey) -> [DayMark] {
        dayMarks(kind, from: day, through: day)
    }

    func dayMarks(_ kind: DayMarkKind, key: String) -> [DayMark] {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<DayMark>(
            predicate: #Predicate<DayMark> { $0.kind == raw && $0.key == key && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.modifiedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Day marks of a kind, live and in the trash (the newest-wins readers drop the trashed ones
    /// older than 30 days), oldest day first.
    func dayMarksIncludingCleared(_ kind: DayMarkKind, from start: DayKey? = nil, through end: DayKey? = nil) -> [DayMark] {
        let raw = kind.rawValue
        let first = start?.rawValue ?? "", last = end?.rawValue ?? "9999-12-31"
        let descriptor = FetchDescriptor<DayMark>(
            predicate: #Predicate<DayMark> { $0.kind == raw && $0.day >= first && $0.day <= last },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.modifiedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Every day-type mark as DayKey raw value → type id (what `NinaSettings.dayTypeMarks` holds):
    /// the newest per day, a newer "Back to schedule" included.
    func dayTypeMarks() -> [String: String] {
        dayMarksIncludingCleared(.dayType).dayTypeMap
    }

    /// The check states of a day: check id → done or skipped (missing = open).
    func checkStates(on day: DayKey) -> [String: CheckState] {
        dayMarksIncludingCleared(.check, from: day, through: day).checkStates(on: day)
    }

    /// The checks ticked done, by day.
    func doneChecks(from start: DayKey, through end: DayKey) -> [DayKey: Set<String>] {
        dayMarksIncludingCleared(.check, from: start, through: end).doneChecks
    }

    /// Every done tick (day, check id), for the creatine hold (`CheckInEngine.weightCheck`).
    func checkTicks() -> [(day: DayKey, checkID: String)] {
        dayMarksIncludingCleared(.check).checkTicks
    }

    /// The check-in mark of the ISO week `day` falls in (the newest, if two devices saved one).
    func checkInMark(week day: DayKey) -> DayMark? {
        dayMarks(.checkIn, key: DayMarks.checkInKey(week: day, calendar: calendar)).max { $0.modifiedAt < $1.modifiedAt }
    }

    /// Every saved check-in, oldest first (one per week).
    func checkIns() -> [CheckInSnapshot] {
        var newest: [String: DayMark] = [:]
        for mark in dayMarks(.checkIn) {
            if let current = newest[mark.key], current.modifiedAt >= mark.modifiedAt { continue }
            newest[mark.key] = mark
        }
        return newest.values.compactMap(\.checkInSnapshot).sorted { $0.day < $1.day }
    }

    /// The keys of the saved check-ins ("week-2030-01-07").
    func checkInKeys() -> Set<String> {
        Set(dayMarks(.checkIn).map(\.key))
    }

    /// Live phase marks (decisions), of one phase or all, oldest first.
    func phaseMarks(_ phaseID: String? = nil) -> [DayMark] {
        guard let phaseID else { return dayMarks(.phase) }
        return dayMarks(.phase, key: phaseID)
    }

    /// The review decisions (keep, hold or cut): the day of the newest one per phase and the
    /// ceilings they answered (meta "ceilings=…"; older decisions answered every ceiling). The
    /// checkpoint needs a decision on or after the day it was reached, a ceiling a decision made
    /// while it was reached (`PhaseReviews`).
    func phaseReviews() -> PhaseReviews {
        let decisions = dayMarks(.phase).compactMap { mark -> (phaseID: String, event: PhaseEvent, day: DayKey, ceilings: [BodyCeiling]?)? in
            guard let event = mark.phaseEvent else { return nil }
            return (phaseID: mark.key, event: event, day: mark.dayKey,
                    ceilings: PhaseReviews.ceilings(fromMeta: mark.metaText[PhaseReviews.ceilingsKey]))
        }
        return PhaseReviews(decisions: decisions)
    }

    /// Days from `start` through `end` marked "Log Is Incomplete" on Today: left out of logged
    /// days (week average, check-in, Insights). The newest mark per day decides.
    func incompleteDays(from start: DayKey, through end: DayKey) -> Set<DayKey> {
        guard start <= end else { return [] }
        return dayMarksIncludingCleared(.event, from: start, through: end).eventDays("incompleteLog")
    }

    /// Tape records for trends, the tape estimate and the measuring schedule.
    func tapeRecords() -> [BodyTapeRecord] {
        measurements(kind: .tape).compactMap(\.tapeRecord)
    }

    /// Days with a body-fat assessment, oldest first.
    func assessmentDays() -> [DayKey] {
        Array(Set(measurements(kind: .assessment).map(\.dayKey))).sorted()
    }

    /// Every body-fat value: assessments, and the body fat typed with weigh-ins.
    func bodyFatReadings(includingWeighIns: Bool = true) -> [BodyFatReading] {
        var readings = measurements(kind: .assessment).compactMap(\.bodyFatReading)
        if includingWeighIns { readings += weights().compactMap(\.bodyFatReading) }
        return readings.sorted { $0.day < $1.day }
    }

    /// The typed weigh-ins as readings, plus the ones read live from Apple Health.
    func weightReadings(adding health: [WeightSignal.Reading] = []) -> [WeightSignal.Reading] {
        weights().map(\.reading) + health
    }

    /// The morning weight signal over the typed weigh-ins and `health` (live Apple Health
    /// readings, `WeightSignal.Reading(time:kilograms:source: .health, dayStartHour:)`), with the
    /// plan's morning cutoff.
    func weightSignal(adding health: [WeightSignal.Reading] = [], settings: NinaSettings? = nil) -> WeightSignal {
        let resolved = settings ?? self.settings
        return WeightSignal(weightReadings(adding: health), cutoffMinutes: resolved.plan.routine.morningCutoffMinutes,
                            dayStartHour: resolved.dayStartHour, calendar: calendar)
    }

    /// The measuring schedule of the plan: tape and assessment days, and the review checkpoint
    /// once the 7-day average reached it (through `today`). Nothing is due before the plan was set
    /// up, or before a planned first phase starts (`BodySchedule.measuringStart`).
    func bodySchedule(plan: CoachPlan, signal: WeightSignal, today: DayKey) -> BodySchedule {
        bodySchedule(plan: plan, checkpoint: signal.checkpointCrossing(in: plan, through: today))
    }

    /// The same with the checkpoint crossing already worked out.
    func bodySchedule(plan: CoachPlan, checkpoint: DayKey?) -> BodySchedule {
        BodySchedule(plan: plan, start: BodySchedule.measuringStart(of: plan, calendar: calendar), tape: tapeRecords(),
                     assessmentDays: assessmentDays(), checkpoint: checkpoint)
    }

    /// The tape-estimate formula people with sex "Prefer not to say" picked (device-only).
    nonisolated static let navyFormulaKey = "nina.coach.navyFormula"

    /// The tape-estimate formula: from the sex, else the one picked on this device; nil = none yet.
    nonisolated static func navyFormula(sex: Sex) -> NavyBodyFat.Formula? {
        if let formula = NavyBodyFat.Formula(sex: sex) { return formula }
        return NavyBodyFat.Formula(rawValue: UserDefaults.standard.string(forKey: navyFormulaKey) ?? "")
    }

    /// The gain-phase ceilings reached on `day` in phase `phaseID` (the active one when nil), from
    /// the stored records (`BodyCeiling.reached`): what Today's review card and the review sheet
    /// compare, and what a review decision records as answered.
    func reachedCeilings(phaseID: String? = nil, on day: DayKey) -> [BodyCeiling] {
        let settings = self.settings
        let plan = settings.plan
        let phase = phaseID.flatMap { plan.phase(id: $0) } ?? plan.activePhase(on: day)
        guard let phase, phase.goal == .gain else { return [] }
        let sex = settings.body.sex
        return BodyCeiling.reached(phase: phase, bodyFatMethod: plan.routine.bodyFatMethod, on: day, tape: tapeRecords(),
                                   fatReadings: bodyFatReadings(), sex: sex, heightCm: profile()?.heightCm ?? 0,
                                   formula: NinaStore.navyFormula(sex: sex), calendar: calendar)
    }

    /// The settings with the day-type marks and the real body weight (`WeightSignal.bodyWeight`
    /// today over typed and `health` weigh-ins).
    func coachSettings(adding health: [WeightSignal.Reading] = [], now: Date = Date()) -> NinaSettings {
        var settings = self.settings
        let signal = weightSignal(adding: health, settings: settings)
        settings.bodyWeightKg = signal.bodyWeight(on: settings.today(now: now, calendar: calendar))?.kilograms
        return settings
    }

    /// Eaten kcal of the logged days from `start` through `end` (days without a log left out).
    func loggedEnergy(from start: DayKey, through end: DayKey) -> [DayKey: Double] {
        guard start <= end else { return [:] }
        let byDay = Dictionary(grouping: entries(from: start, through: end), by: \.dayKey)
        var energy: [DayKey: Double] = [:]
        for (day, entries) in byDay {
            let totals = DayTotals(day: day, entries: entries.map(\.facts))
            if totals.isLogged { energy[day] = totals.eaten.energy }
        }
        return energy
    }

    /// Everything Today's coach parts show for `day` (`CoachBoard`): day-type chip, checks strip,
    /// coach card and week average. `signal`: `weightSignal(adding:)` with the live Health
    /// weigh-ins. `dismissed`: the device's "Later" taps (card key → day). `ceilings`: reached
    /// gain-phase ceilings, if the caller checks them. `prepared`: the schedule and checkpoint
    /// crossing the caller already worked out for today (else they are worked out here).
    func coachBoard(for day: DayKey, settings: NinaSettings, signal: WeightSignal, now: Date = Date(),
                    dismissed: [String: DayKey] = [:], ceilings: [BodyCeiling] = [],
                    prepared: (schedule: BodySchedule, checkpoint: DayKey?)? = nil) -> CoachBoard {
        let plan = settings.plan
        guard plan.isSetUp else { return .empty }
        let today = settings.today(now: now, calendar: calendar)
        let hasMorningWeighIn = signal.morning(on: today) != nil
        let checkpoint = prepared.map(\.checkpoint) ?? signal.checkpointCrossing(in: plan, through: today)
        let schedule = prepared?.schedule ?? bodySchedule(plan: plan, checkpoint: checkpoint)
        let monday = day.startOfWeek(calendar: calendar)
        let weekEnd = min(today, monday.adding(days: 6, calendar: calendar))
        let input = CoachBoard.Input(
            plan: plan, day: day, today: today, now: now, mealSlots: settings.meals,
            fallback: settings.legacyTargets(for: day, calendar: calendar), dayTypeMarks: settings.dayTypeMarks,
            checkStates: checkStates(on: day), hasMorningWeighIn: hasMorningWeighIn,
            bodyItems: CoachBoard.bodyItems(schedule, on: day, today: today, now: now, hasMorningWeighIn: hasMorningWeighIn,
                                            calendar: calendar),
            checkInKeys: checkInKeys(), checkpoint: checkpoint, ceilings: ceilings,
            reviews: phaseReviews(), dismissed: dismissed, eaten: loggedEnergy(from: monday, through: weekEnd),
            incompleteDays: incompleteDays(from: monday, through: weekEnd), calendar: calendar)
        return CoachBoard(input)
    }
}

/// An earlier version of the plan (`DayMark` kind `planVersion`).
struct CoachPlanVersion: Identifiable {
    let mark: DayMark
    /// When it was replaced.
    let replacedAt: Date
    /// "edit", "checkIn", "import" …
    let reason: String
    /// The plan's JSON as it was.
    let text: String

    var id: UUID { mark.uuid }
    var plan: CoachPlan { CoachPlan(encoded: text) }
}

extension NinaStore {
    /// The earlier versions of the plan, newest first (put one back with `updatePlan(version.plan,
    /// reason: "restore")`, which keeps the current plan as a version in turn).
    func planVersions() -> [CoachPlanVersion] {
        dayMarks(.planVersion).compactMap { mark -> CoachPlanVersion? in
            guard !mark.note.isEmpty else { return nil }
            return CoachPlanVersion(mark: mark, replacedAt: PlanHistory.date(fromKey: mark.key) ?? mark.time,
                                    reason: mark.metaText["reason"] ?? "", text: mark.note)
        }.sorted { $0.replacedAt > $1.replacedAt }
    }
}

// MARK: - Writing

extension NinaStore {
    /// Adds a body measurement (Undo: `trash([measurement])`).
    @discardableResult
    func addMeasurement(_ draft: BodyMeasurementDraft) -> BodyMeasurement {
        let measurement = BodyMeasurement(day: draft.day, time: draft.time, kind: draft.kind, values: draft.values)
        draft.write(to: measurement)
        context.insert(measurement)
        save()
        return measurement
    }

    /// Changes a body measurement; returns the values before (Undo: `update(measurement, to: previous)`).
    @discardableResult
    func update(_ measurement: BodyMeasurement, to draft: BodyMeasurementDraft) -> BodyMeasurementDraft {
        let previous = measurement.draft
        draft.write(to: measurement)
        measurement.modifiedAt = Date()
        save()
        return previous
    }

    /// Today's body values from a settings import (baseline tape and assessment): importing the
    /// same file again on the same day updates the record instead of adding one.
    @discardableResult
    func importBodyRecords(_ records: [SettingsBodyRecord], time: Date = Date()) -> [BodyMeasurement] {
        guard !records.isEmpty else { return [] }
        var saved: [BodyMeasurement] = []
        for record in records {
            let key = record.importKey
            let descriptor = FetchDescriptor<BodyMeasurement>(
                predicate: #Predicate<BodyMeasurement> { $0.importKey == key && $0.deletedAt == nil }
            )
            let measurement: BodyMeasurement
            if let existing = try? context.fetch(descriptor).first {
                measurement = existing
                measurement.modifiedAt = Date()
            } else {
                measurement = BodyMeasurement(day: record.day, time: time, kind: record.kind, values: record.values)
                measurement.importKey = key
                context.insert(measurement)
            }
            let draft = BodyMeasurementDraft(day: record.day, time: measurement.time, kind: record.kind, values: record.values,
                                             method: record.method, conditions: record.conditions, note: measurement.note)
            draft.write(to: measurement)
            saved.append(measurement)
        }
        save()
        return saved
    }

    /// Picks the day type of a day by hand (a filled chip); nil goes back to the schedule (the
    /// marks are moved to the trash).
    @discardableResult
    func setDayType(day: DayKey, typeID: String?) -> CoachUndo {
        let undo = writeMark(.dayType, on: day, key: typeID ?? "", remove: typeID == nil) { _ in }
        save()
        return undo
    }

    /// Ticks a daily check done or "not today" (skipped); nil = open again (the marks go to the trash).
    @discardableResult
    func setCheck(day: DayKey, checkID: String, state: CheckState?) -> CoachUndo {
        let undo = writeMark(.check, on: day, key: checkID, remove: state == nil) { mark in
            var meta = mark.metaText
            meta["state"] = state?.rawValue
            mark.meta = meta.encoded
        }
        save()
        return undo
    }

    /// Saves a weekly check-in: one mark per ISO week ("week-<Monday>"), updated when saved again.
    @discardableResult
    func saveCheckIn(_ snapshot: CheckInSnapshot) -> CoachUndo {
        let undo = writeCheckIn(snapshot)
        save()
        return undo
    }

    /// Records a phase decision (started, postponed, review-keep, -hold, -cut, ended). A review
    /// decision also records the ceilings reached in that phase right now (`reachedCeilings`):
    /// those are answered, one reached later opens the review again.
    @discardableResult
    func recordPhaseEvent(phaseID: String, event: PhaseEvent, day: DayKey) -> CoachUndo {
        let mark = DayMark(day: day, kind: .phase, key: phaseID)
        var meta = KeyValueText()
        meta["event"] = event.rawValue
        if PhaseReviews.events.contains(event) {
            meta[PhaseReviews.ceilingsKey] = PhaseReviews.metaValue(reachedCeilings(phaseID: phaseID, on: day))
        }
        mark.meta = meta.encoded
        context.insert(mark)
        save()
        return CoachUndo(inserted: [mark])
    }

    /// Saves the plan and mirrors it into the profile's own targets, goal, rate and target weight
    /// (`CoachPlan.mirror(on:)`), so older builds show near-correct numbers. Undo:
    /// `undo(result)` puts the previous plan and profile values back.
    /// `reason`: kept with the earlier version ("edit", "import", "restore" …).
    @discardableResult
    func updatePlan(_ plan: CoachPlan, on day: DayKey? = nil, reason: String = "edit") -> CoachUndo {
        let undo = writePlan(plan, on: day ?? settings.today(calendar: calendar), reason: reason)
        save()
        return undo
    }

    /// "Apply from tomorrow" (or an edited Δ) on a check-in: the active phase moves by `delta`
    /// kcal a day from `day` on (`CheckInEngine.applying`), and the check-in is saved with the
    /// decision and Δ. Undo: `undo(result)` restores the plan and the check-in as it was.
    @discardableResult
    func applyCheckIn(_ snapshot: CheckInSnapshot, delta: Double, from day: DayKey, weightKg: Double,
                      decision: CheckInDecision = .applied) -> CoachUndo {
        let settings = self.settings
        let plan = CheckInEngine.applying(delta, to: settings.plan, from: day, weightKg: weightKg, fallback: settings.targets)
        // The mirror follows the revision just added (it starts tomorrow): nothing re-mirrors on
        // the day it takes effect, and older builds would stay one step behind.
        var undo = writePlan(plan, on: max(day, settings.today(calendar: calendar)), reason: "checkIn")
        var decided = snapshot
        decided.decision = decision
        decided.deltaKcal = delta
        undo.merge(writeCheckIn(decided))
        save()
        return undo
    }

    /// Puts back what a coach write changed.
    func undo(_ change: CoachUndo) {
        guard !change.isEmpty else { return }
        let now = Date()
        for mark in change.inserted {
            mark.deletedAt = now
            mark.modifiedAt = now
        }
        for mark in change.trashed {
            mark.deletedAt = nil
            mark.modifiedAt = now
        }
        for state in change.edited.reversed() { state.restore(now: now) }
        if let fields = change.profile, let profile = profile() {
            fields.write(to: profile)
            profile.modifiedAt = now
        }
        save()
    }

    // MARK: Helpers (no save)

    /// Writes the plan and its mirror into the profile (creating it on first use). The fields a
    /// newer Nina added to the stored plan are kept (`CoachPlan.encoded(keepingUnknownFrom:)`),
    /// and the plan it replaces becomes an earlier version (`PlanHistory`). Returns what Undo
    /// needs: the fields as they were and the version mark.
    private func writePlan(_ plan: CoachPlan, on day: DayKey, reason: String) -> CoachUndo {
        let profile = profile() ?? {
            let created = NinaProfile()
            context.insert(created)
            return created
        }()
        let before = CoachProfileFields(profile)
        var undo = CoachUndo(profile: before)
        let text = plan.encoded(keepingUnknownFrom: profile.coachPlan)
        if text != profile.coachPlan, !profile.coachPlan.isEmpty {
            undo.merge(keepVersion(profile.coachPlan, reason: reason, on: day))
        }
        profile.coachPlan = text
        if let mirror = plan.mirror(on: day) {
            let state = mirror.applied(to: SettingsState(profile: profile, weight: 0))
            profile.targets = state.targets.encoded
            profile.trainingTargets = state.trainingTargets?.encoded ?? ""
            profile.trainingDays = state.trainingTargets == nil ? "" : state.trainingDays.encoded
            profile.goal = state.goal.rawValue
            profile.ratePerWeek = state.ratePerWeek
            profile.targetWeight = state.targetWeight
        }
        profile.modifiedAt = Date()
        return undo
    }

    /// Keeps `text` (the plan being replaced) as an earlier version, at most one every 10
    /// minutes; versions beyond the newest 30 go to the trash.
    private func keepVersion(_ text: String, reason: String, on day: DayKey) -> CoachUndo {
        let now = Date()
        var undo = CoachUndo()
        let versions = dayMarks(.planVersion)
        guard PlanHistory.records(newest: versions.map(\.time).max(), now: now) else { return undo }
        let mark = DayMark(day: day, kind: .planVersion, key: PlanHistory.key(now), time: now)
        mark.note = text
        var meta = KeyValueText()
        meta["reason"] = reason
        mark.meta = meta.encoded
        context.insert(mark)
        undo.inserted.append(mark)
        for old in PlanHistory.dropped(versions + [mark], time: { $0.time }) where old !== mark {
            old.deletedAt = now
            old.modifiedAt = now
            undo.trashed.append(old)
        }
        return undo
    }

    /// One live mark per day, kind and key: the newest is edited (`change`), other copies go to
    /// the trash; `remove` trashes them all. Day types keep one mark per day whatever its key.
    private func writeMark(_ kind: DayMarkKind, on day: DayKey, key: String, remove: Bool,
                           change: (DayMark) -> Void) -> CoachUndo {
        let now = Date()
        var undo = CoachUndo()
        let marks = dayMarks(kind, on: day).filter { kind == .dayType || $0.key == key }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        let keep = remove ? nil : marks.first
        for mark in marks where mark !== keep {
            mark.deletedAt = now
            mark.modifiedAt = now
            undo.trashed.append(mark)
        }
        guard !remove else { return undo }
        if let keep {
            undo.edited.append(DayMarkState(keep))
            keep.key = key
            change(keep)
            keep.modifiedAt = now
        } else {
            let mark = DayMark(day: day, kind: kind, key: key, time: now)
            change(mark)
            context.insert(mark)
            undo.inserted.append(mark)
        }
        return undo
    }

    private func writeCheckIn(_ snapshot: CheckInSnapshot) -> CoachUndo {
        let now = Date()
        var undo = CoachUndo()
        let marks = dayMarks(.checkIn, key: snapshot.key(calendar: calendar)).sorted { $0.modifiedAt > $1.modifiedAt }
        for mark in marks.dropFirst() {
            mark.deletedAt = now
            mark.modifiedAt = now
            undo.trashed.append(mark)
        }
        if let mark = marks.first {
            undo.edited.append(DayMarkState(mark))
            mark.day = snapshot.day.rawValue
            mark.values = snapshot.values
            mark.meta = snapshot.meta
            mark.modifiedAt = now
        } else {
            let mark = DayMark(day: snapshot.day, kind: .checkIn, key: snapshot.key(calendar: calendar), time: now)
            mark.values = snapshot.values
            mark.meta = snapshot.meta
            context.insert(mark)
            undo.inserted.append(mark)
        }
        return undo
    }
}
