import Foundation
import NinaCore

// The numbers behind the weekly check-in sheet and its save. Glue only: every rule lives in
// NinaCore (`CheckInEngine`, `Adherence`, `WeightSignal`); this file picks the values the sheet
// shows and writes the person's decision through the store. Foundation and NinaCore only.

/// What the weekly check-in sheet shows for one week: the week's evaluation
/// (`CheckInEvaluation`), the weight card numbers on the check-in day, the waist measured that
/// week and the note saved with it.
@MainActor
struct CheckInSheetFacts {
    /// Whether a check-in can run for the week.
    enum State: Equatable {
        /// No plan set up yet.
        case noPlan
        /// Coaching is paused on the check-in day.
        case paused
        /// No phase is running on the check-in day.
        case noPhase
        case ready
    }

    let evaluation: CheckInEvaluation
    let plan: CoachPlan
    let state: State
    /// The weight numbers on the check-in day (7-day average, rate, status), as Progress shows them.
    let summary: WeightSignal.Summary
    /// Mornings weighed in the 7 days ending on the check-in day.
    let mornings: Int
    /// The waist site this person measures (the narrow waist for women who use it).
    let waistSite: BodySite
    /// The latest waist reading of the check-in (the 7 days up to the check-in day, or up to
    /// today while the check-in is open late; standard or not).
    let waist: GirthReading?
    /// Its change since the standard reading before (both standard).
    let waistChange: GirthChange?
    /// The latest waist reading before today (any conditions): a new reading that moved more
    /// than 1 cm from it asks for a second one (`BodyReadings`).
    let lastWaist: GirthReading?
    /// Hints from the tape and body fat (F6, F7), never a change: the waist guard in a gain
    /// phase, the waist note in a loss phase, a low lean share of the gain.
    let bodyHints: [String]
    /// The protein target per kg: "160 g = 2.0 g/kg · 2.5 g/kg lean mass"; nil without a weight.
    let proteinRatio: String?
    /// The note saved with this week's check-in ("" without one).
    let savedNote: String
    /// The full set and the body-fat assessment when due within the next 7 days (or overdue),
    /// for "Next week".
    let nextFull: BodySchedule.Due?
    let nextAssessment: BodySchedule.Due?

    var day: DayKey { evaluation.day }
    var today: DayKey { evaluation.today }
    var result: CheckInResult { evaluation.result }
    /// "How it went": the 7 days before the check-in day.
    var week: AdherenceSummary { evaluation.weekSummary }
    var saved: CheckInSnapshot? { evaluation.saved }
    var phase: CoachPlan.Phase? { evaluation.phase }

    /// The Waist step is done: the waist was measured today.
    var waistMeasuredToday: Bool { waist?.day == today }

    /// A full set is due today or overdue: the Waist step offers it instead of the waist alone.
    var fullSetDue: Bool { nextFull.map { $0.day <= today } ?? false }

    /// The Waist step is skipped (and shown as done): measured today, with no full set due and
    /// no tape or body-fat hint to read there.
    var skipsWaistStep: Bool { waistMeasuredToday && !fullSetDue && bodyHints.isEmpty }

    /// The pages of the live check-in (F11).
    static let pageTitles = ["Your Week", "Waist", "How It Went", "Next Week"]

    /// The direction of the proposal (+1 more food, −1 less).
    var deltaSign: Double { result.delta < 0 ? -1 : 1 }

    /// The sizes "Edit" offers for the change: the plan's step range in 50 kcal steps (only up to
    /// the proposal when a guardrail made it smaller), always with the proposal's own size.
    var stepOptions: [Double] {
        let size = abs(result.delta)
        guard size > 0 else { return [] }
        let adjust = plan.adjust
        let low = max(50, (min(adjust.stepMin, adjust.stepMax) / 50).rounded() * 50)
        let high = max(low, adjust.stepMin, adjust.stepMax)
        var options: [Double] = []
        var value = low
        while value <= high + 1e-9, options.count < 20 {
            options.append(value)
            value += 50
        }
        if size + 1e-9 < abs(result.step) { options = options.filter { $0 <= size + 1e-9 } }
        if !options.contains(where: { abs($0 - size) < 1e-9 }) { options.append(size) }
        return options.sorted()
    }

    /// "Gathering data – first adjustment check on Mon 7 Dec" while the rate window is too short.
    var gatheringLine: String? {
        guard result.rule == .gathering, let first = result.firstAdjustmentCheck else { return nil }
        return "Gathering data – first adjustment check on \(CheckInSheetText.day(first))"
    }

    /// The phase's rate range with its direction (kg/week), for the corridor bar; nil without one.
    var rateRange: ClosedRange<Double>? {
        guard let phase else { return nil }
        return WeightSignal.range(for: phase)
    }

    /// The Waist page's typed readings: how many fields to show (one; a second when the first
    /// moved more than 1 cm since `previous`, as `BodyReadings` asks) and the value to save (the
    /// mean of two). nil while nothing usable is typed or a reading is outside the site's range.
    static func waistEntry(_ first: String, _ second: String, site: BodySite, previous: Double?) -> (fields: Int, value: Double?) {
        // The first field leads: without a number there, nothing counts (a hidden second field neither).
        guard let one = BodySheetNumber.parse(first) else { return (fields: 1, value: nil) }
        let two: Double? = BodySheetNumber.parse(second)
        let values: [Double] = two.map { (value: Double) -> [Double] in [one, value] } ?? [one]
        let fields = min(2, BodySheetReadings.fieldCount(values, base: 1, twoReadings: false, previous: previous))
        if fields > 1, BodySheetNumber.isInvalid(second) { return (fields: fields, value: nil) }
        let used = Array(values.prefix(fields))
        guard used.allSatisfy({ (value: Double) -> Bool in site.isPlausible(value) }) else { return (fields: fields, value: nil) }
        return (fields: fields, value: BodySheetReadings.merged(used, count: fields))
    }

    /// The phase's planned range ("+0.15 to +0.25 kg/week"); nil without a range.
    var plannedRange: String? {
        guard let phase, let range = WeightSignal.range(for: phase) else { return nil }
        return CheckInSheetText.range(range)
    }

    static func load(context: CoachContext, week: DayKey, store: NinaStore) -> CheckInSheetFacts {
        let calendar = context.calendar
        let evaluation = context.evaluateCheckIn(week: week)
        let plan = context.plan
        let day = evaluation.day
        let state: State
        if !plan.isSetUp {
            state = .noPlan
        } else if plan.isPaused(on: day) {
            state = .paused
        } else if evaluation.phase == nil {
            state = .noPhase
        } else {
            state = .ready
        }
        let fallback = CoachContext.startWeightFallback(phase: evaluation.phase, weights: context.weights,
                                                        health: context.healthReadings)
        let summary = context.signal.summary(on: day, plan: plan, fallbackWeight: fallback)
        let mornings = context.signal.morningCount(from: day.adding(days: -6, calendar: calendar), through: day)

        let site = waistSite(sex: context.settings.body.sex, records: context.tapeRecords)
        let readings = GirthTrend.readings(site, in: context.tapeRecords, includeNonStandard: true)
        // The week's waist: the 7 days up to the check-in day, and the days after it while the
        // check-in is still open (at most 6), so this morning's reading counts.
        let firstDay = day.adding(days: -6, calendar: calendar)
        let lastDay = max(day, min(context.today, day.adding(days: 6, calendar: calendar)))
        let waist = readings.last { $0.day >= firstDay && $0.day <= lastDay }
        var change: GirthChange?
        if let waist, waist.isStandard, let before = readings.last(where: { $0.day < waist.day && $0.isStandard }) {
            change = GirthChange(site: site, from: before, to: waist)
        }
        let horizon = context.today.adding(days: 7, calendar: calendar)
        let nextFull = context.nextFull.flatMap { $0.day <= horizon ? $0 : nil }
        let nextAssessment = context.nextAssessment.flatMap { $0.day <= horizon ? $0 : nil }
        let heightCm = store.profile()?.heightCm ?? 0
        let hints = bodyHints(context: context, phase: evaluation.phase, site: site, day: day,
                              rate: summary.rate.value, heightCm: heightCm)
        let ratio = proteinRatio(context: context, week: evaluation.weekSummary, day: day,
                                 weightKg: summary.average.value ?? context.bodyWeight?.kilograms)
        return CheckInSheetFacts(evaluation: evaluation, plan: plan, state: state, summary: summary, mornings: mornings,
                                 waistSite: site, waist: waist, waistChange: change,
                                 lastWaist: readings.last(where: { $0.day < context.today }), bodyHints: hints, proteinRatio: ratio,
                                 savedNote: store.checkInSheetNote(week: day),
                                 nextFull: nextFull, nextAssessment: nextAssessment)
    }

    /// What the tape and body fat say up to the check-in day, as hints only (F6, F7): in a gain
    /// phase the waist guard and a lean share of the gain below 30 %, in a loss phase the waist
    /// note. The plan never changes from them.
    static func bodyHints(context: CoachContext, phase: CoachPlan.Phase?, site: BodySite, day: DayKey, rate: Double?,
                          heightCm: Double) -> [String] {
        guard let phase else { return [] }
        let calendar = context.calendar
        let records = context.tapeRecords.filter { $0.day <= day }
        var hints: [String] = []
        switch phase.goal {
        case .gain:
            if GirthTrend.waistGuard(phase: phase, records: records, waistSite: site, calendar: calendar) {
                hints.append(GirthTrend.waistGuardMessage + ".")
            }
            if let start = phase.start,
               let change = PhaseBodyFat.change(context: context, since: start, through: day, heightCm: heightCm),
               change.leanShareRating?.suggestsLowEndOfRate == true {
                hints.append(lowLeanShareHint)
            }
        case .lose:
            let waist = GirthTrend.readings(site, in: records)
            if GirthTrend.waistNote(waist: waist, ratePerWeek: rate, site: site, calendar: calendar) {
                hints.append(GirthTrend.waistNoteMessage + ".")
            }
        case .maintain:
            break
        }
        return hints
    }

    /// F7: below 30 % lean share the check-in suggests the low end of the rate range.
    static let lowLeanShareHint = "Less than 30 % of your gain was lean mass – consider the low end of your rate."

    /// The week's protein target per kg body weight (and lean mass once a body-fat value exists):
    /// "160 g = 2.0 g/kg · 2.5 g/kg lean mass". The target is the week's average (the day's
    /// without logged days); nil without a weight.
    static func proteinRatio(context: CoachContext, week: AdherenceSummary, day: DayKey, weightKg: Double?) -> String? {
        guard let weightKg else { return nil }
        let grams = week.averageProteinTarget > 0 ? week.averageProteinTarget
            : context.settings.targets(for: day, calendar: context.calendar).protein
        let latest = context.bodyFatReadings.last { $0.day <= day }
        guard grams > 0, let ratio = ProteinMeals.ratio(grams: grams, weightKg: weightKg, leanKg: latest?.leanKg,
                                                        bodyFat: latest?.bodyFat) else { return nil }
        return "\(Fmt.number(grams.rounded())) g = \(ratio.text)"
    }

    /// The waist site to follow: the narrow waist for women, the navel waist otherwise – or the
    /// other one when only that one was ever measured.
    static func waistSite(sex: Sex, records: [BodyTapeRecord]) -> BodySite {
        let preferred: BodySite = sex == .female ? .waistNarrow : .waist
        let other: BodySite = preferred == .waist ? .waistNarrow : .waist
        let hasPreferred = records.contains { $0.values[preferred] != nil }
        let hasOther = records.contains { $0.values[other] != nil }
        return !hasPreferred && hasOther ? other : preferred
    }
}

// MARK: - Text

/// Display pieces for the check-in and phase sheets (locale numbers via `Fmt`).
enum CheckInSheetText {
    /// "+100 kcal", "−150 kcal"
    static func signedKcal(_ value: Double) -> String {
        sign(value) + Fmt.number(abs(value).rounded()) + " kcal"
    }

    /// "+0.4 kg", "−1.2 kg", "±0 kg"
    static func signedKg(_ value: Double, decimals: Int = 1) -> String {
        sign(value, decimals: decimals) + Fmt.number(abs(value), decimals: decimals) + " kg"
    }

    /// "+0.5 %"
    static func signedPercent(_ value: Double) -> String {
        sign(value, decimals: 1) + Fmt.number(abs(value), decimals: 1) + " %"
    }

    /// "+1.2 cm"
    static func signedCm(_ value: Double) -> String {
        sign(value, decimals: 1) + Fmt.number(abs(value), decimals: 1) + " cm"
    }

    /// "+0.15" (two decimals, signed).
    static func signedNumber(_ value: Double, decimals: Int = 2) -> String {
        sign(value, decimals: decimals) + Fmt.number(abs(value), decimals: decimals)
    }

    /// "+0.15 kg/week"
    static func rate(_ value: Double) -> String {
        sign(value, decimals: 2) + Fmt.number(abs(value), decimals: 2) + " kg/week"
    }

    /// "+0.15 to +0.25 kg/week" (signed range).
    static func range(_ range: ClosedRange<Double>) -> String {
        let low = sign(range.lowerBound, decimals: 2) + Fmt.number(abs(range.lowerBound), decimals: 2)
        let high = sign(range.upperBound, decimals: 2) + Fmt.number(abs(range.upperBound), decimals: 2)
        return "\(low) to \(high) kg/week"
    }

    /// "Mon 7 Dec"
    static func day(_ day: DayKey, calendar: Calendar = .current) -> String {
        day.date(calendar: calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "6 of 7"
    static func count(_ value: Int, of total: Int) -> String {
        "\(value) of \(total)"
    }

    /// "+25 g carbs", "+20 g carbs · +5 g fat"; "" without a change.
    static func macroChange(protein: Double, carbs: Double, fat: Double) -> String {
        var parts: [String] = []
        if abs(protein) >= 0.5 { parts.append(sign(protein) + Fmt.number(abs(protein).rounded()) + " g protein") }
        if abs(carbs) >= 0.5 { parts.append(sign(carbs) + Fmt.number(abs(carbs).rounded()) + " g carbs") }
        if abs(fat) >= 0.5 { parts.append(sign(fat) + Fmt.number(abs(fat).rounded()) + " g fat") }
        return parts.joined(separator: " · ")
    }

    /// A day type's label: "🏋️ Gym"; `empty` for "" (the baseline, or days without a type).
    static func dayType(_ id: String, plan: CoachPlan, empty: String) -> String {
        guard !id.isEmpty else { return empty }
        guard let type = plan.dayType(id: id) else { return id }
        let emoji = type.emoji.isEmpty ? CoachPlan.DayType.suggestedEmoji(for: type.name) : type.emoji
        let name = type.name.isEmpty ? type.id : type.name
        return [emoji, name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A phase's name, or the default one for its goal ("Weight gain").
    static func phaseName(_ phase: CoachPlan.Phase) -> String {
        let trimmed = phase.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CoachPlan.Phase.defaultName(for: phase.goal) : trimmed
    }

    /// The rating titles of `CheckInRatings.keys`.
    static func rating(_ key: String) -> String {
        switch key {
        case "hunger": "Hunger"
        case "energy": "Energy"
        case "sleep": "Sleep"
        case "performance": "Training"
        case "digestion": "Digestion"
        case "stress": "Stress"
        case "mood": "Mood"
        default: key.capitalized
        }
    }

    /// "Hunger 3 · Energy 4" (only the rated ones); "" without ratings.
    static func ratings(_ ratings: CheckInRatings) -> String {
        CheckInRatings.keys.compactMap { key in ratings[key].map { "\(rating(key)) \($0)" } }.joined(separator: " · ")
    }

    private static func sign(_ value: Double, decimals: Int = 0) -> String {
        let scale = pow(10, Double(max(0, decimals)))
        let rounded = (value * scale).rounded() / scale
        if rounded > 0 { return "+" }
        if rounded < 0 { return "−" }
        return "±"
    }
}

// MARK: - Draft

/// What the person entered in a live check-in, kept in memory while they leave it to take a full
/// measurement set (the sheet closes for that), so the ratings, note and page are back when they
/// open the check-in again. Cleared when the check-in is saved.
struct CheckInSheetDraft {
    var ratings: CheckInRatings
    var note: String
    var page: Int
    /// The week was saved already and this is a redo.
    var redo: Bool

    /// By week (the Monday the sheet was opened with). Memory only.
    @MainActor static var byWeek: [DayKey: CheckInSheetDraft] = [:]
}

// MARK: - Saving

extension NinaStore {
    /// The note saved with a week's check-in ("" without one).
    func checkInSheetNote(week day: DayKey) -> String {
        checkInMark(week: day)?.note ?? ""
    }

    /// Sets the note of a week's saved check-in (the mark `saveCheckIn` wrote; call it after).
    /// Undo puts the old note back.
    @discardableResult
    func checkInSheetSetNote(_ note: String, week day: DayKey) -> CoachUndo {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mark = checkInMark(week: day), mark.note != text else { return CoachUndo() }
        let undo = CoachUndo(edited: [DayMarkState(mark)])
        mark.note = text
        mark.modifiedAt = Date()
        save()
        return undo
    }
}

extension AppModel {
    /// Saves the check-in's waist reading now: a tape record of the waist site with the
    /// automatic conditions (morning and fasted before the cutoff with nothing eaten logged yet),
    /// like the measure sheet. Its toast's Undo moves it to the trash.
    func checkInSaveWaist(_ centimetres: Double, site: BodySite) {
        let store = self.store
        let calendar = store.calendar
        let now = Date()
        let settings = self.settings
        let day = DayKey(date: now, calendar: calendar, dayStartHour: settings.dayStartHour)
        let eaten = store.bodySheetHasEaten(on: day, before: now)
        let conditions = BodyProtocol.automatic(at: now, cutoffMinutes: settings.plan.routine.morningCutoffMinutes,
                                                hasEaten: eaten, calendar: calendar)
        let draft = BodyMeasurementDraft(day: day, time: now, kind: .tape, values: BodyValues([site: centimetres]),
                                         conditions: BodyProtocol.encode(conditions))
        saveMeasurement(draft)
    }

    /// Saves the week's check-in from the sheet with the ratings, the waist and the note, and the
    /// person's decision: `.applied`/`.edited` moves the active phase by `delta` kcal a day from
    /// tomorrow (`store.applyCheckIn`), `.kept` ("Not now") and nil (no proposal) only save it.
    /// One toast; its Undo puts back the plan, the check-in and the note.
    func checkInCommit(_ evaluation: CheckInEvaluation, ratings: CheckInRatings, note: String, waist: Double?,
                       decision: CheckInDecision?, delta: Double) {
        let store = self.store
        var snapshot = evaluation.snapshot
        snapshot.ratings = ratings
        snapshot.waist = waist
        var change: CoachUndo
        let message: String
        switch decision {
        case .applied?, .edited?:
            change = store.applyCheckIn(snapshot, delta: delta, from: evaluation.applyFrom, weightKg: evaluation.input.weightKg,
                                        decision: decision ?? .applied)
            message = "\(CheckInSheetText.signedKcal(delta)) a day from tomorrow"
        case .kept?:
            snapshot.decision = .kept
            change = store.saveCheckIn(snapshot)
            message = "Check-in saved – targets kept"
        case nil:
            snapshot.decision = nil
            change = store.saveCheckIn(snapshot)
            message = "Check-in saved"
        }
        change.merge(store.checkInSheetSetNote(note, week: snapshot.day))
        showUndo(change, message, symbol: "checkmark.circle.fill")
    }
}
