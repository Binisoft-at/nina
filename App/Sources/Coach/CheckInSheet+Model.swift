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
    /// The latest waist reading in the check-in's week (standard or not).
    let waist: GirthReading?
    /// Its change since the standard reading before (both standard).
    let waistChange: GirthChange?
    /// The note saved with this week's check-in ("" without one).
    let savedNote: String

    var day: DayKey { evaluation.day }
    var result: CheckInResult { evaluation.result }
    /// "How it went": the 7 days before the check-in day.
    var week: AdherenceSummary { evaluation.weekSummary }
    var saved: CheckInSnapshot? { evaluation.saved }
    var phase: CoachPlan.Phase? { evaluation.phase }

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
        let monday = evaluation.week
        let sunday = monday.adding(days: 6, calendar: calendar)
        let waist = readings.last { $0.day >= monday && $0.day <= sunday }
        var change: GirthChange?
        if let waist, waist.isStandard, let before = readings.last(where: { $0.day < waist.day && $0.isStandard }) {
            change = GirthChange(site: site, from: before, to: waist)
        }
        return CheckInSheetFacts(evaluation: evaluation, plan: plan, state: state, summary: summary, mornings: mornings,
                                 waistSite: site, waist: waist, waistChange: change,
                                 savedNote: store.checkInSheetNote(week: day))
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
