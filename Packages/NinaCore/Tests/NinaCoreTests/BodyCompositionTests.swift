import Foundation
import Testing
@testable import NinaCore

// Made-up people and numbers throughout.

private var compositionUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func compDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func compTape(_ raw: String, _ sites: [BodySite: Double], standard: Bool = true) -> BodyTapeRecord {
    BodyTapeRecord(day: compDay(raw), values: BodyValues(sites), conditions: standard ? "morning,fasted" : "later")
}

private func compRounded(_ value: Double?) -> Double? { value.map { ($0 * 10).rounded() / 10 } }

@Suite("Body composition")
struct BodyCompositionTests {
    @Test func navyVectors() {
        #expect(compRounded(NavyBodyFat.male(heightCm: 180, waistCm: 90, neckCm: 39)) == 19.1)
        #expect(compRounded(NavyBodyFat.male(heightCm: 180, waistCm: 85, neckCm: 39)) == 15.3)
        #expect(compRounded(NavyBodyFat.female(heightCm: 165, waistCm: 75, hipCm: 100, neckCm: 33)) == 29.4)
        #expect(compRounded(NavyBodyFat.bodyFat(.female, heightCm: 165, waistCm: 75, neckCm: 33, hipCm: 100)) == 29.4)
        #expect(compRounded(NavyBodyFat.bodyFat(.male, heightCm: 180, waistCm: 90, neckCm: 39)) == 19.1)
        // Impossible input and implausible results.
        #expect(NavyBodyFat.male(heightCm: 0, waistCm: 90, neckCm: 39) == nil)
        #expect(NavyBodyFat.male(heightCm: 180, waistCm: 39, neckCm: 39) == nil)
        #expect(NavyBodyFat.male(heightCm: 195, waistCm: 60, neckCm: 45) == nil)
        #expect(NavyBodyFat.Formula(sex: .male) == .male)
        #expect(NavyBodyFat.Formula(sex: .unspecified) == nil)
        #expect(NavyBodyFat.Formula.female.sites == [.waistNarrow, .hip, .neck])
        #expect(NavyBodyFat.Formula.male.waistSite == .waist)
        #expect(NavyBodyFat.label == "tape estimate ±3.5 points")
        #expect(NavyBodyFat.errorBand == BodyMethod.navy.errorBand)
    }

    @Test func navyAvailability() {
        let cal = compositionUTC
        let records = [
            compTape("2030-01-07", [.neck: 39, .waist: 92, .hip: 100]),
            compTape("2030-02-04", [.waist: 91]),
            compTape("2030-03-25", [.waist: 90]), // 77 days after the neck
            compTape("2030-04-08", [.waist: 89]), // 91 days: the neck is too old
            compTape("2030-04-09", [.waist: 80], standard: false),
        ]
        #expect(NavyBodyFat.estimate(formula: .male, heightCm: 0, records: records, calendar: cal) == .needsHeight)
        #expect(NavyBodyFat.estimate(formula: nil, heightCm: 180, records: records, calendar: cal) == .needsFormula)
        #expect(NavyBodyFat.estimate(formula: .male, heightCm: 180, records: records, calendar: cal) == .needsSites([.neck]))
        #expect(NavyBodyFat.estimate(formula: .male, heightCm: 180, records: [], calendar: cal) == .needsSites([.waist, .neck]))

        let march = NavyBodyFat.estimate(formula: .male, heightCm: 180, records: records, on: compDay("2030-03-31"), calendar: cal).estimate
        #expect(march?.day == compDay("2030-03-25"))
        #expect(march?.neckDay == compDay("2030-01-07"))
        #expect(march?.waistCm == 90)
        #expect(compRounded(march?.bodyFat) == 19.1)

        // Women: the narrow waist and the hip; a neck taken after the waist counts too.
        #expect(NavyBodyFat.estimate(formula: .female, heightCm: 165, records: records, calendar: cal) == .needsSites([.waistNarrow]))
        let later = [compTape("2030-05-06", [.waistNarrow: 75]), compTape("2030-05-13", [.neck: 33, .hip: 100])]
        let woman = NavyBodyFat.estimate(formula: .female, heightCm: 165, records: later, calendar: cal).estimate
        #expect(compRounded(woman?.bodyFat) == 29.4)
        #expect(woman?.hipDay == compDay("2030-05-13"))
        #expect(NavyBodyFat.estimate(formula: .female, heightCm: 165, records: [later[0]], calendar: cal) == .needsSites([.hip, .neck]))

        // Readings that aren't standard count only when asked for.
        let withNeck = records + [compTape("2030-04-01", [.neck: 39.5], standard: false)]
        #expect(NavyBodyFat.estimate(formula: .male, heightCm: 180, records: withNeck, calendar: cal) == .needsSites([.neck]))
        let all = NavyBodyFat.estimate(formula: .male, heightCm: 180, records: withNeck, includeNonStandard: true, calendar: cal)
        #expect(all.estimate?.day == compDay("2030-04-09"))
        #expect(all.estimate?.neckDay == compDay("2030-04-01"))

        // A typo gives no value.
        let typo = [compTape("2030-06-03", [.waist: 60, .neck: 45])]
        #expect(NavyBodyFat.estimate(formula: .male, heightCm: 195, records: typo, calendar: cal) == .implausible)

        // The tape-estimate series: one value per waist day that has a neck within 12 weeks.
        let series = NavyBodyFat.series(formula: .male, heightCm: 180, records: records, calendar: cal)
        #expect(series.map(\.day) == [compDay("2030-01-07"), compDay("2030-02-04"), compDay("2030-03-25")])
        #expect(NavyBodyFat.series(formula: nil, heightCm: 180, records: records, calendar: cal).isEmpty)
        let reading = BodyFatReading(navy: series[2])
        #expect(reading.method == .navy && reading.day == compDay("2030-03-25"))
    }

    @Test func fatAndLeanMass() {
        let plain = BodyComposition(weightKg: 80, bodyFat: 20)
        #expect(plain.fatKg == 16 && plain.leanKg == 64 && !plain.isMeasured)

        // The device's own kg: FFM = lean + bone.
        let dexa = BodyComposition(fatKg: 14.2, leanKg: 60.5, boneKg: 3.1, bodyFat: 18.2)
        #expect(abs(dexa.leanKg - 63.6) < 1e-9 && abs(dexa.weightKg - 77.8) < 1e-9)
        #expect(dexa.bodyFat == 18.2 && dexa.isMeasured)
        #expect(BodyComposition(fatKg: 15, leanKg: 60).bodyFat == 20)

        let day = compDay("2030-02-04")
        let values = BodyValues(encoded: "bodyFat=18.2;boneKg=3.1;fatKg=14.2;leanKg=60.5")
        let reading = BodyFatReading(assessmentOn: day, method: .dexa, device: " Clinic scanner ", values: values)
        #expect(reading?.device == "Clinic scanner")
        #expect(reading.flatMap { BodyComposition(reading: $0, weightKg: nil) }?.isMeasured == true)

        let percentOnly = BodyFatReading(assessmentOn: day, method: .biaPro, values: BodyValues(encoded: "bodyFat=20"))
        #expect(percentOnly.flatMap { BodyComposition(reading: $0, weightKg: nil) } == nil)
        #expect(percentOnly.flatMap { BodyComposition(reading: $0, weightKg: 80) }?.leanKg == 64)

        // Body fat from the kg when the percent is missing; nothing without either.
        let fromKg = BodyFatReading(assessmentOn: day, method: .dexa, values: BodyValues(encoded: "fatKg=16;leanKg=61;boneKg=3"))
        #expect(compRounded(fromKg?.bodyFat) == 20)
        #expect(BodyFatReading(assessmentOn: day, method: .dexa, values: BodyValues(encoded: "leanKg=61")) == nil)
        #expect(BodyFatReading.weighIn(day: day, kilograms: 80, bodyFat: 0) == nil)
        let weighIn = BodyFatReading.weighIn(day: day, kilograms: 80, bodyFat: 24)
        #expect(weighIn?.method == .scale && weighIn?.isWeighIn == true && weighIn?.weightKg == 80)

        // FFMI and the version normalised to 1.8 m.
        #expect(compRounded(BodyComposition.ffmi(leanKg: 64, heightCm: 175)) == 20.9)
        #expect(compRounded(BodyComposition.normalisedFFMI(leanKg: 64, heightCm: 175)) == 21.2)
        #expect(compRounded(plain.ffmi(heightCm: 180)) == 19.8)
        #expect(plain.ffmi(heightCm: 180) == plain.normalisedFFMI(heightCm: 180))
        #expect(BodyComposition.ffmi(leanKg: 64, heightCm: 0) == nil)
    }

    @Test func weightAroundAnAssessment() {
        let cal = compositionUTC
        let weights: [DayKey: Double] = [
            compDay("2030-03-01"): 80.4,
            compDay("2030-03-03"): 79.8,
            compDay("2030-03-04"): 80.0,
            compDay("2030-03-06"): 80.2,
            compDay("2030-03-08"): 81.0, // outside ±3 days
        ]
        let day = compDay("2030-03-04")
        let centred = BodyComposition.weight(on: day, morningWeights: weights, today: compDay("2030-03-10"), calendar: cal)
        #expect(centred?.source == .morningAverage && centred?.count == 4)
        #expect(abs((centred?.kg ?? 0) - 80.1) < 1e-9)

        // The days after haven't all happened yet: the 7 days ending on the day.
        let recent = BodyComposition.weight(on: day, morningWeights: weights, today: compDay("2030-03-05"), calendar: cal)
        #expect(recent?.count == 3)
        #expect(abs((recent?.kg ?? 0) - 240.2 / 3) < 1e-9)

        // Fewer than 3: the EMA trend on that day, else the typed weight.
        let sparse: [DayKey: Double] = [compDay("2030-03-01"): 80.0, compDay("2030-03-20"): 81.0]
        let trend = BodyComposition.weight(on: compDay("2030-03-20"), morningWeights: sparse, today: compDay("2030-03-30"), calendar: cal)
        #expect(trend?.source == .trend)
        #expect(abs((trend?.kg ?? 0) - 80.1) < 1e-9)
        let given = BodyComposition.weight(on: compDay("2030-03-20"), morningWeights: sparse, today: compDay("2030-03-30"), trend: 80.5,
                                           calendar: cal)
        #expect(given == CompositionWeight(kg: 80.5, source: .trend))
        let typed = BodyComposition.weight(on: compDay("2030-02-01"), morningWeights: sparse, today: compDay("2030-03-30"), typed: 79.5,
                                           calendar: cal)
        #expect(typed == CompositionWeight(kg: 79.5, source: .typed))
        #expect(BodyComposition.weight(on: compDay("2030-02-01"), morningWeights: [:], today: compDay("2030-03-30"), calendar: cal) == nil)
    }

    @Test func compositionPoints() {
        let cal = compositionUTC
        let weights: [DayKey: Double] = [
            compDay("2030-03-01"): 80.4, compDay("2030-03-03"): 79.8, compDay("2030-03-04"): 80.0, compDay("2030-03-06"): 80.2,
        ]
        let readings = [
            BodyFatReading(day: compDay("2030-03-05"), bodyFat: 19, method: .dexa, leanKg: 61, fatKg: 15, boneKg: 3),
            BodyFatReading(day: compDay("2030-03-04"), bodyFat: 20, method: .navy),
            BodyFatReading.weighIn(day: compDay("2029-06-01"), kilograms: 81, bodyFat: 23)!,
            BodyFatReading(day: compDay("2029-05-01"), bodyFat: 22, method: .estimate),
        ]
        let points = BodyComposition.points(readings, morningWeights: weights, today: compDay("2030-03-10"), typedWeight: 82,
                                            calendar: cal)
        #expect(points.map(\.day) == ["2029-05-01", "2029-06-01", "2030-03-04", "2030-03-05"].map(compDay))
        #expect(points[0].weight == CompositionWeight(kg: 82, source: .typed))
        #expect(points[1].weight == CompositionWeight(kg: 81, source: .typed))
        #expect(points[2].weight?.source == .morningAverage)
        #expect(abs(points[2].composition.fatKg - 16.02) < 1e-9)
        #expect(points[3].weight == nil && points[3].composition.leanKg == 64)
        // Without a typed weight the estimate has nothing to split.
        #expect(BodyComposition.points(readings, morningWeights: weights, today: compDay("2030-03-10"), calendar: cal).count == 3)
        // Points of different series are never compared.
        #expect(CompositionChange(from: points[2], to: points[3]) == nil)
        let again = BodyComposition.points([readings[1], BodyFatReading(day: compDay("2030-03-06"), bodyFat: 19.5, method: .navy)],
                                           morningWeights: weights, today: compDay("2030-03-10"), calendar: cal)
        #expect(CompositionChange(from: again[0], to: again[1])?.method == .navy)
    }

    @Test func seriesPerMethodAndDevice() {
        let readings: [BodyFatReading] = [
            BodyFatReading(day: compDay("2030-01-07"), bodyFat: 21, method: .estimate),
            BodyFatReading(day: compDay("2030-01-08"), bodyFat: 22.4, method: .biaPro, device: "inbody 570"),
            BodyFatReading(day: compDay("2030-03-04"), bodyFat: 21.6, method: .biaPro, device: " InBody 570"),
            BodyFatReading(day: compDay("2030-02-04"), bodyFat: 19.0, method: .biaPro, device: "Gym scanner"),
            BodyFatReading(day: compDay("2030-01-09"), bodyFat: 20.5, method: .dexa),
            BodyFatReading.weighIn(day: compDay("2030-01-10"), kilograms: 80, bodyFat: 24)!,
            BodyFatReading.weighIn(day: compDay("2030-01-11"), kilograms: 80.2, bodyFat: 23.5)!,
            BodyFatReading(day: compDay("2030-01-12"), bodyFat: 23, method: .scale),
            BodyFatReading(day: compDay("2030-01-14"), bodyFat: 20.8, method: .navy),
            BodyFatReading(day: compDay("2030-01-07"), bodyFat: 21.0, method: .navy),
        ]
        let series = BodyFatSeries.group(readings)
        #expect(series.map(\.id) == ["dexa", "bia_pro:inbody 570", "bia_pro:gym scanner", "navy", "scale", "scale:weigh-in", "estimate"])
        #expect(series[1].title == "Professional BIA (InBody …) · InBody 570")
        #expect(series[1].readings.map(\.bodyFat) == [22.4, 21.6])
        #expect(series[3].readings.map(\.day) == [compDay("2030-01-07"), compDay("2030-01-14")])
        #expect(series[5].title == "Weigh-in body fat")
        #expect(series[0].title == "DEXA scan" && series[0].errorBand == 1.5)

        // Default tracking: the most accurate series with at least 2 values.
        #expect(BodyFatSeries.tracking(series, method: nil)?.id == "bia_pro:inbody 570")
        // A chosen method: its longest series, or none yet.
        #expect(BodyFatSeries.tracking(series, method: .scale)?.id == "scale:weigh-in")
        #expect(BodyFatSeries.tracking(series, method: .bodpod) == nil)
        // Nothing with 2 values yet: the most accurate one, so the baseline shows.
        #expect(BodyFatSeries.tracking(BodyFatSeries.group([readings[0], readings[4]]), method: nil)?.method == .dexa)
        #expect(BodyFatSeries.tracking([], method: nil) == nil)
        #expect(BodyFatSeries.newSeriesNote == "new series – compare like with like")
    }

    @Test func changesWithinASeries() {
        let start = BodyComposition(weightKg: 80, bodyFat: 20)
        let later = BodyComposition(weightKg: 82, bodyFat: 20.5)
        let tape = CompositionChange(from: start, to: later, method: .navy)
        #expect(abs(tape.weight - 2) < 1e-9 && abs(tape.fat - 0.81) < 1e-9 && abs(tape.lean - 1.19) < 1e-9)
        #expect(abs(tape.bodyFat - 0.5) < 1e-9)
        #expect(tape.isLeanWithinError && tape.isFatWithinError)
        #expect(abs((tape.leanShare ?? 0) - 0.595) < 1e-9)
        #expect(tape.leanShareRating == .good)
        #expect(!CompositionChange(from: start, to: later, method: .dexa).isLeanWithinError)

        let fatty = CompositionChange(from: start, to: BodyComposition(weightKg: 82, bodyFat: 21.8), method: .dexa)
        #expect(fatty.leanShareRating == .low && fatty.leanShareRating?.suggestsLowEndOfRate == true)
        let fair = CompositionChange(from: start, to: BodyComposition(weightKg: 82, bodyFat: 21), method: .dexa)
        #expect(fair.leanShareRating == .fair)
        // Too small a gain, or a loss: no share.
        #expect(CompositionChange(from: start, to: BodyComposition(weightKg: 80.3, bodyFat: 20), method: .dexa).leanShare == nil)
        #expect(CompositionChange(from: later, to: start, method: .dexa).leanShare == nil)
        #expect(LeanShareRating(share: 0.5) == .good && LeanShareRating(share: 0.3) == .fair && LeanShareRating(share: 0.29) == .low)
        #expect(BodyMethod.dexa.leanNoiseKg == 0.5 && BodyMethod.navy.leanNoiseKg == 1.5 && BodyMethod.scale.leanNoiseKg == 1.5)
        #expect(CompositionChange.withinErrorText == "within measurement error")
    }

    @Test func longTermGoalGap() {
        let now = BodyComposition(weightKg: 80, bodyFat: 20) // 16 kg fat, 64 kg lean
        let gap = BodyGoalGap(goal: CoachPlan.LongTerm(weightKg: 78, bodyFat: 14), now: now)
        #expect(abs((gap?.targetFatKg ?? 0) - 10.92) < 1e-9)
        #expect(abs((gap?.targetLeanKg ?? 0) - 67.08) < 1e-9)
        #expect(abs((gap?.leanToGo ?? 0) - 3.08) < 1e-9)
        #expect(abs((gap?.fatToGo ?? 0) + 5.08) < 1e-9)
        #expect(abs((gap?.weightToGo ?? 0) + 2) < 1e-9)
        #expect(compRounded(gap?.weightAtGoalBodyFat) == 74.4)
        #expect(gap?.dependsOnLeanGain == true)
        #expect(gap?.honestLine == "Reaching 78 kg at 14 % depends on gaining about 3 kg of lean mass.")

        let bodyFatOnly = BodyGoalGap(goal: CoachPlan.LongTerm(bodyFat: 15), now: now)
        #expect(bodyFatOnly?.leanToGo == nil && bodyFatOnly?.weightToGo == nil)
        #expect(compRounded(bodyFatOnly?.weightAtGoalBodyFat) == 75.3)
        #expect(bodyFatOnly?.honestLine == nil)
        #expect(BodyGoalGap(goal: CoachPlan.LongTerm(note: "later"), now: now) == nil)

        // A goal that needs no lean gain.
        let cut = BodyGoalGap(goal: CoachPlan.LongTerm(weightKg: 74, bodyFat: 14), now: now)
        #expect(cut?.dependsOnLeanGain == false && cut?.honestLine == nil)
    }

    @Test func leanGainRealism() {
        let cal = compositionUTC
        let today = compDay("2030-01-07")
        let soon = LeanGainOutlook(leanToGo: 3, today: today, goalDate: compDay("2030-05-07"), calendar: cal)
        #expect(soon?.isGoalDateLikelyLater == true)
        #expect(abs((soon?.neededPerMonth ?? 0) - 0.761) < 1e-9)
        #expect(soon?.monthsFast == 6 && soon?.monthsSlow == 12)
        #expect(soon?.likelyDay == compDay("2030-09-08"))
        #expect(soon?.text == "goal date likely later (~Sep 2030)")

        let fits = LeanGainOutlook(leanToGo: 3, today: today, goalDate: compDay("2031-01-07"), calendar: cal)
        #expect(fits?.isGoalDateLikelyLater == false && fits?.text == nil)
        let open = LeanGainOutlook(leanToGo: 1.5, today: today, calendar: cal)
        #expect(open?.neededPerMonth == nil && open?.isGoalDateLikelyLater == false)
        #expect(open?.earliestDay == compDay("2030-04-08"))
        let passed = LeanGainOutlook(leanToGo: 1, today: today, goalDate: compDay("2029-12-01"), calendar: cal)
        #expect(passed?.isGoalDateLikelyLater == true)
        #expect(LeanGainOutlook(leanToGo: 0, today: today) == nil)
    }

    @Test func bodyGoalCard() {
        let goal = CoachPlan.LongTerm(weightKg: 78, bodyFat: 14)
        func point(_ raw: String, _ weight: Double, _ bodyFat: Double) -> BodyCompositionPoint {
            BodyCompositionPoint(reading: BodyFatReading(day: compDay(raw), bodyFat: bodyFat, method: .navy),
                                 weight: CompositionWeight(kg: weight, source: .morningAverage, count: 5),
                                 composition: BodyComposition(weightKg: weight, bodyFat: bodyFat))
        }
        let earlier = point("2029-12-02", 81, 21)
        let first = point("2030-01-07", 80, 20)
        let latest = point("2030-03-04", 81, 19.5)
        let card = BodyGoalCard(goal: goal, points: [latest, earlier, first], goalSetOn: compDay("2030-01-07"), phaseGoal: .gain)
        #expect(card.start?.day == compDay("2030-01-07") && card.now?.day == compDay("2030-03-04"))
        #expect(card.rows.map(\.kind) == [.lean, .fat, .bodyFat])
        #expect(card.rows[0].text == "+1.2 of +3.1 kg")
        #expect(abs(card.rows[0].progress - 1.205 / 3.08) < 1e-9)
        #expect(card.rows[1].text == "−0.2 of −5.1 kg")
        #expect(card.rows[2].text == "−0.5 of −6.0 %" && card.rows[2].errorBand == 3.5)
        #expect(card.caption == "Watch lean mass – a little fat gain is expected")
        #expect(abs((card.gap?.leanToGo ?? 0) - (67.08 - 65.205)) < 1e-9)
        #expect(!card.isEmpty)

        // No value on or after the goal day: the last one before it.
        #expect(BodyGoalCard(goal: goal, points: [earlier, first], goalSetOn: compDay("2030-02-01")).start?.day == compDay("2030-01-07"))
        #expect(BodyGoalCard(goal: goal, points: [earlier, first]).start?.day == compDay("2029-12-02"))
        // A goal with only a weight has no composition rows.
        #expect(BodyGoalCard(goal: CoachPlan.LongTerm(weightKg: 78), points: [first]).rows.isEmpty)

        // Moved away, past the target, at the goal.
        let away = BodyGoalRow(kind: .fat, start: 16, now: 16.3, target: 10.92)
        #expect(away.isMovedAway && away.progress == 0 && away.text == "+0.3 kg (moved away)")
        let beyond = BodyGoalRow(kind: .lean, start: 64, now: 68, target: 67.08)
        #expect(beyond.progress == 1 && !beyond.isMovedAway && beyond.text == "+4.0 of +3.1 kg")
        #expect(BodyGoalRow(kind: .bodyFat, start: 14, now: 14, target: 14).text == "at goal")
        #expect(BodyGoalRow(kind: .bodyFat, start: 14, now: 15, target: 14).isMovedAway)

        let empty = BodyGoalCard(goal: goal, points: [], phaseGoal: .lose)
        #expect(empty.isEmpty && empty.rows.isEmpty && empty.gap == nil)
        #expect(empty.caption == "Watch fat mass – keep lean mass")
        #expect(BodyGoalCard.caption(for: .maintain) == nil && BodyGoalCard.caption(for: nil) == nil)
        #expect(BodyGoalCard.emptyText == "Do your baseline check")

        let weight = BodyGoalWeightRow(now: 80.4, phaseTarget: 82, longTermTarget: 78)
        #expect(abs((weight.toPhaseTarget ?? 0) - 1.6) < 1e-9 && abs((weight.toLongTerm ?? 0) + 2.4) < 1e-9)
        #expect(BodyGoalWeightRow(now: 80, phaseTarget: 0, longTermTarget: 0).toPhaseTarget == nil)
    }

    @Test func goalValidation() {
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 78, bodyFat: 14), sex: .male).isEmpty)
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 78, bodyFat: 14), sex: .female) == [.contestLevel])
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 78, bodyFat: 7), sex: .unspecified) == [.contestLevel])
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(bodyFat: 3), sex: .male) == [.contestLevel])
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 25, bodyFat: 2), sex: .male) == [.bodyFatOutOfRange, .weightOutOfRange])
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 310, bodyFat: 55, waistCm: 30), sex: .female)
                == [.bodyFatOutOfRange, .weightOutOfRange, .waistOutOfRange])
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(weightKg: 30, bodyFat: 50), sex: .male).isEmpty)
        #expect(BodyGoalIssue.check(CoachPlan.LongTerm(), sex: .female).isEmpty)
        #expect(BodyGoalIssue.contestLevel.isWarning && !BodyGoalIssue.weightOutOfRange.isWarning)
        #expect(BodyGoalIssue.contestLevel.message == "contest-level target")
    }

    @Test func girthTrends() {
        let cal = compositionUTC
        let records = [
            compTape("2030-01-07", [.waist: 84.0, .arm: 34.0, .chest: 100.0, .thigh: 56.0]),
            compTape("2030-01-14", [.waist: 84.4]),
            compTape("2030-01-15", [.waist: 86.0], standard: false), // after training: left out
            compTape("2030-01-21", [.waist: 84.5]),
            compTape("2030-01-28", [.waist: 85.0]),
            compTape("2030-02-04", [.waist: 85.2, .arm: 34.3, .chest: 101.4, .thigh: 56.6]),
        ]
        let waist = GirthTrend.readings(.waist, in: records)
        #expect(waist.map(\.value) == [84.0, 84.4, 84.5, 85.0, 85.2])
        #expect(GirthTrend.readings(.waist, in: records, includeNonStandard: true).count == 6)
        #expect(abs((GirthTrend.fourWeekChange(waist, calendar: cal) ?? 0) - 1.2) < 1e-9)
        #expect(abs((GirthTrend.fourWeekChange(.waist, in: records, calendar: cal) ?? 0) - 1.2) < 1e-9)
        #expect(GirthTrend.fourWeekChange(Array(waist.prefix(3)), calendar: cal) == nil)
        // Only the last 6 readings count.
        let older = [GirthReading(day: compDay("2029-11-04"), value: 70), GirthReading(day: compDay("2029-11-11"), value: 99)]
        let withOld = older + [GirthReading(day: compDay("2029-12-31"), value: 83.6)] + waist
        let lastSix = Array(withOld.suffix(6))
        #expect(GirthTrend.fourWeekChange(withOld, calendar: cal) == GirthTrend.fourWeekChange(lastSix, calendar: cal))
        // Readings closer together than two weeks would be extrapolated noise.
        let daily = (0..<5).map { GirthReading(day: compDay("2030-03-01").adding(days: $0, calendar: cal), value: 84 + Double($0) / 10) }
        #expect(GirthTrend.fourWeekChange(daily, calendar: cal) == nil)
        #expect(GirthTrend.slopePerDay([waist[0]], calendar: cal) == nil)

        // Change since the start, against the MDC.
        let change = GirthTrend.change(.waist, in: records, since: compDay("2030-01-07"), calendar: cal)
        #expect(abs((change?.change ?? 0) - 1.2) < 1e-9 && change?.isClear == true)
        #expect(change?.label == "up 1.2 cm (7 Jan – 4 Feb)")
        let arm = GirthTrend.change(.arm, in: records, since: compDay("2030-01-07"), calendar: cal)
        #expect(arm?.isClear == false && arm?.label == GirthTrend.noClearChange)
        #expect(GirthTrend.label(-0.6, site: .arm) == "down 0.6 cm")
        #expect(GirthTrend.label(0.9, site: .waist) == "no clear change")
        #expect(GirthTrend.isClear(1.0, site: .waist) && !GirthTrend.isClear(0.45, site: .neck))
        let acrossYears = GirthChange(site: .waist, from: GirthReading(day: compDay("2030-12-16"), value: 84),
                                      to: GirthReading(day: compDay("2031-01-13"), value: 82.5))
        #expect(acrossYears.label == "down 1.5 cm (16 Dec 2030 – 13 Jan 2031)")

        // The start value: up to 7 days before `since`, else the first one after it.
        #expect(GirthTrend.change(.waist, in: records, since: compDay("2030-01-10"), calendar: cal)?.from.day == compDay("2030-01-07"))
        #expect(GirthTrend.change(.waist, in: records, since: compDay("2030-01-20"), calendar: cal)?.from.day == compDay("2030-01-14"))
        #expect(GirthTrend.change(.waist, in: records, since: compDay("2029-12-01"), calendar: cal)?.from.day == compDay("2030-01-07"))
        #expect(GirthTrend.change(.waist, in: records, calendar: cal)?.from.day == compDay("2030-01-07"))
        #expect(GirthTrend.change(.calf, in: records, calendar: cal) == nil)

        // Baseline table and the gain-phase line.
        let table = GirthTrend.baseline([.arm, .chest, .thigh, .waist, .hip], in: records, since: compDay("2030-01-07"), calendar: cal)
        #expect(table.map(\.site) == [.arm, .chest, .thigh, .waist])
        #expect(GirthTrend.gainLine(table) == "arm +0.3, chest +1.4, thigh +0.6 cm; waist +1.2 cm")
        func girth(_ site: BodySite, _ from: Double, _ to: Double) -> GirthChange {
            GirthChange(site: site, from: GirthReading(day: compDay("2030-01-07"), value: from),
                        to: GirthReading(day: compDay("2030-03-04"), value: to))
        }
        let line = GirthTrend.gainLine([girth(.waist, 84, 84.4), girth(.thigh, 56, 57.1), girth(.arm, 34, 34.8), girth(.chest, 100, 101.4)])
        #expect(line == "arm +0.8, chest +1.4, thigh +1.1 cm; waist +0.4 cm (no clear change)")
        #expect(GirthTrend.gainLine([girth(.hip, 98, 99)]) == nil)
    }

    @Test func waistGuardAndNote() {
        let cal = compositionUTC
        #expect(GirthTrend.waistGuard(waistFourWeekChange: 1.6, otherChanges: [.arm: 0.3, .chest: 0.5, .thigh: 0.4]))
        #expect(!GirthTrend.waistGuard(waistFourWeekChange: 1.6, otherChanges: [.arm: 0.3, .chest: 1.2]))
        #expect(GirthTrend.waistGuard(waistFourWeekChange: 1.5, otherChanges: [.arm: -0.8]))
        #expect(!GirthTrend.waistGuard(waistFourWeekChange: 1.4, otherChanges: [:]))
        #expect(!GirthTrend.waistGuard(waistFourWeekChange: nil, otherChanges: [:]))

        var phase = CoachPlan.Phase(id: "1", goal: .gain, start: compDay("2030-01-07"), startedAt: Date(timeIntervalSince1970: 0),
                                    status: .active)
        let records = [
            compTape("2029-12-02", [.waist: 80]), // before the phase: left out of the 4-week change
            compTape("2030-01-07", [.waist: 84.0, .arm: 34.0, .chest: 100.0, .thigh: 56.0]),
            compTape("2030-01-14", [.waist: 84.5]),
            compTape("2030-01-21", [.waist: 85.0]),
            compTape("2030-01-28", [.waist: 85.4]),
            compTape("2030-02-04", [.waist: 85.6, .arm: 34.2, .chest: 100.4, .thigh: 56.3]),
        ]
        #expect(GirthTrend.waistGuard(phase: phase, records: records, calendar: cal))
        #expect(GirthTrend.waistGuardMessage == "Waist is rising faster than other sites – consider the low end of your rate")
        phase.goal = .lose
        #expect(!GirthTrend.waistGuard(phase: phase, records: records, calendar: cal))

        // Loss phase: the weight falls, the waist stays flat for 4 weeks.
        let flat = [("2030-03-04", 84.0), ("2030-03-11", 84.3), ("2030-03-18", 83.8), ("2030-03-25", 84.1), ("2030-04-01", 83.6),
                    ("2030-04-08", 83.8)].map { GirthReading(day: compDay($0.0), value: $0.1) }
        #expect(GirthTrend.waistNote(waist: flat, ratePerWeek: -0.4, calendar: cal))
        #expect(!GirthTrend.waistNote(waist: flat, ratePerWeek: -0.2, calendar: cal)) // 0.8 kg over 4 weeks
        #expect(!GirthTrend.waistNote(waist: flat, ratePerWeek: 0.1, calendar: cal))
        #expect(!GirthTrend.waistNote(waist: flat, ratePerWeek: nil, calendar: cal))
        #expect(!GirthTrend.waistNote(waist: Array(flat.suffix(3)), ratePerWeek: -0.5, calendar: cal)) // less than 4 weeks
        let shrinking = [GirthReading(day: compDay("2030-03-04"), value: 84.0), GirthReading(day: compDay("2030-04-01"), value: 82.6)]
        #expect(!GirthTrend.waistNote(waist: shrinking, ratePerWeek: -0.5, calendar: cal))
    }

    @Test func ratiosAndCeilings() {
        #expect(abs((BodyComposition.waistToHeight(waistCm: 84, heightCm: 175) ?? 0) - 0.48) < 1e-9)
        #expect(abs((BodyComposition.waistToHip(waistCm: 84, hipCm: 100) ?? 0) - 0.84) < 1e-9)
        #expect(BodyComposition.waistToHeight(waistCm: 84, heightCm: 0) == nil)
        #expect(BodyComposition.waistToHip(waistCm: 0, hipCm: 100) == nil)
        #expect(BodyComposition.waistToHeightNote == "under 0.5 is the usual health guideline")
        let both = BodyValues([.waist: 84, .waistNarrow: 78])
        #expect(BodyComposition.waist(in: both, sex: .female) == 78)
        #expect(BodyComposition.waist(in: both, sex: .male) == 84)
        #expect(BodyComposition.waist(in: BodyValues([.waistNarrow: 78]), sex: .male) == 78)
        #expect(BodyComposition.waist(in: BodyValues([.hip: 98]), sex: .male) == nil)

        let gain = CoachPlan.Phase(id: "1", goal: .gain, start: compDay("2030-01-07"), startedAt: Date(timeIntervalSince1970: 0),
                                   status: .active)
        #expect(gain.maxWaistGainCm == 4)
        #expect(BodyCeiling.reached(phase: gain, waistChangeSinceStart: 4.1, waistToHeight: 0.49) == [.waistGain])
        #expect(BodyCeiling.reached(phase: gain, waistChangeSinceStart: 2, waistToHeight: 0.5) == [.waistToHeight])
        #expect(BodyCeiling.reached(phase: gain, waistChangeSinceStart: 2, waistToHeight: 0.45, bodyFat: 22, bodyFatCeiling: 22) == [.bodyFat])
        #expect(BodyCeiling.reached(phase: gain, waistChangeSinceStart: nil, waistToHeight: nil, bodyFat: 22).isEmpty)
        let loss = CoachPlan.Phase(id: "2", goal: .lose, start: compDay("2030-06-03"))
        #expect(BodyCeiling.reached(phase: loss, waistChangeSinceStart: 5, waistToHeight: 0.6).isEmpty)
    }
}
