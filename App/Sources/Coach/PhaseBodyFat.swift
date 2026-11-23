import Foundation
import NinaCore

/// The body-fat values the phase review, the check-in and the body-fat ceiling compare (F7): the
/// assessments and weigh-in body fat the store holds, plus the live tape estimate (US Navy,
/// computed from the tape records and the height, never stored), grouped into series the way
/// the Body page groups them. The tracking series follows `routine.bodyFatMethod`, so a person
/// who tracks with the tape estimate gets lean and fat mass here too. Foundation and NinaCore only.
enum PhaseBodyFat {
    /// The formula people with sex "Prefer not to say" picked in the measure sheet (device-only).
    static let formulaKey = NinaStore.navyFormulaKey

    /// The tape-estimate formula: from the sex, else the one picked on this device; nil = none yet.
    static func formula(sex: Sex) -> NavyBodyFat.Formula? {
        NinaStore.navyFormula(sex: sex)
    }

    /// `stored` (assessments and weigh-in body fat) plus the tape-estimate series. `heightCm` 0
    /// (not set) leaves the tape estimate out.
    static func readings(_ stored: [BodyFatReading], tape: [BodyTapeRecord], sex: Sex, heightCm: Double,
                         calendar: Calendar) -> [BodyFatReading] {
        let navy = NavyBodyFat.series(formula: formula(sex: sex), heightCm: heightCm, records: tape, calendar: calendar)
            .map { (estimate: NavyBodyFat.Estimate) -> BodyFatReading in BodyFatReading(navy: estimate) }
        return stored + navy
    }

    /// The series that drives goal progress (`BodyFatSeries.tracking`), with the tape estimate.
    static func tracking(_ stored: [BodyFatReading], tape: [BodyTapeRecord], sex: Sex, heightCm: Double,
                         method: BodyMethod?, calendar: Calendar) -> BodyFatSeries? {
        let all = readings(stored, tape: tape, sex: sex, heightCm: heightCm, calendar: calendar)
        return BodyFatSeries.tracking(BodyFatSeries.group(all), method: method)
    }

    /// The latest body fat (%) of the tracking series on or before `day` – what the optional
    /// body-fat ceiling of a gain phase is compared with (`BodyCeiling.latestBodyFat`). nil without one.
    static func latest(_ stored: [BodyFatReading], tape: [BodyTapeRecord], sex: Sex, heightCm: Double,
                       method: BodyMethod?, on day: DayKey, calendar: Calendar) -> Double? {
        BodyCeiling.latestBodyFat(stored, tape: tape, formula: formula(sex: sex), heightCm: heightCm, method: method, on: day,
                                  calendar: calendar)
    }

    /// The gain-phase ceilings with the body-fat ceiling added when `phase` has one and the
    /// latest tracking value reached it (`BodyCeiling.reached`); `ceilings` as they are otherwise.
    static func ceilings(_ ceilings: [BodyCeiling], phase: CoachPlan.Phase?, latestBodyFat: Double?) -> [BodyCeiling] {
        guard let phase, phase.bodyFatCeiling > 0, !ceilings.contains(.bodyFat) else { return ceilings }
        let reached = BodyCeiling.reached(phase: phase, waistChangeSinceStart: nil, waistToHeight: nil,
                                          bodyFat: latestBodyFat, bodyFatCeiling: phase.bodyFatCeiling)
        return reached.contains(.bodyFat) ? ceilings + [.bodyFat] : ceilings
    }

    /// The change in body composition from a phase's start to `day` in the tracking series: from
    /// the last value on or before the start – no older than the routine's body-fat interval (at
    /// least 7 days), so a scan from months before never becomes the base – else the first after
    /// it (`GirthTrend.base`), to the latest value on or before `day`. nil without two values of
    /// the series in that span.
    @MainActor
    static func change(context: CoachContext, since start: DayKey, through day: DayKey, heightCm: Double) -> CompositionChange? {
        let calendar = context.calendar
        let stored = context.bodyFatReadings.filter { $0.day <= day }
        let tape = context.tapeRecords.filter { $0.day <= day }
        guard let series = tracking(stored, tape: tape, sex: context.settings.body.sex, heightCm: heightCm,
                                    method: context.plan.routine.bodyFatMethod, calendar: calendar) else { return nil }
        let points = context.signal.compositionPoints(series.readings, today: day)
        let grace = max(GirthTrend.baseGraceDays, context.plan.routine.bodyFatEveryWeeks * 7)
        let first = GirthTrend.base(points, day: { $0.day }, since: start, graceDays: grace, calendar: calendar)
        guard let first, let latest = points.last(where: { $0.day <= day }), first.day < latest.day else { return nil }
        return CompositionChange(from: first, to: latest)
    }
}
