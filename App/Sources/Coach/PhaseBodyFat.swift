import Foundation
import NinaCore

/// The body-fat values the phase review, the check-in and the body-fat ceiling compare (F7): the
/// assessments and weigh-in body fat the store holds, plus the live tape estimate (US Navy,
/// computed from the tape records and the height, never stored), grouped into series the way
/// the Body page groups them. The tracking series follows `routine.bodyFatMethod`, so a person
/// who tracks with the tape estimate gets lean and fat mass here too. Foundation and NinaCore only.
enum PhaseBodyFat {
    /// The formula people with sex "Prefer not to say" picked in the measure sheet (device-only).
    static let formulaKey = "nina.coach.navyFormula"

    /// The tape-estimate formula: from the sex, else the one picked on this device; nil = none yet.
    static func formula(sex: Sex) -> NavyBodyFat.Formula? {
        if let formula = NavyBodyFat.Formula(sex: sex) { return formula }
        return NavyBodyFat.Formula(rawValue: UserDefaults.standard.string(forKey: formulaKey) ?? "")
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
    /// body-fat ceiling of a gain phase is compared with. nil without one.
    static func latest(_ stored: [BodyFatReading], tape: [BodyTapeRecord], sex: Sex, heightCm: Double,
                       method: BodyMethod?, on day: DayKey, calendar: Calendar) -> Double? {
        let upTo = stored.filter { $0.day <= day }
        let tapeUpTo = tape.filter { $0.day <= day }
        guard let series = tracking(upTo, tape: tapeUpTo, sex: sex, heightCm: heightCm, method: method, calendar: calendar) else {
            return nil
        }
        return series.readings.last { $0.day <= day }?.bodyFat
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
    /// the last value on or before the start (else the first after it) to the latest value on or
    /// before `day`. nil without two values of the series in that span.
    @MainActor
    static func change(context: CoachContext, since start: DayKey, through day: DayKey, heightCm: Double) -> CompositionChange? {
        let calendar = context.calendar
        let stored = context.bodyFatReadings.filter { $0.day <= day }
        let tape = context.tapeRecords.filter { $0.day <= day }
        guard let series = tracking(stored, tape: tape, sex: context.settings.body.sex, heightCm: heightCm,
                                    method: context.plan.routine.bodyFatMethod, calendar: calendar) else { return nil }
        let points = context.signal.compositionPoints(series.readings, today: day)
        let first = points.last { $0.day <= start } ?? points.first { $0.day >= start }
        guard let first, let latest = points.last(where: { $0.day <= day }), first.day < latest.day else { return nil }
        return CompositionChange(from: first, to: latest)
    }
}
