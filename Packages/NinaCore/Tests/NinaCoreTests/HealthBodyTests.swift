import Foundation
import Testing
@testable import NinaCore

// Made-up people, apps and numbers throughout.

private var hbUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func hbDay(_ raw: String) -> DayKey { DayKey(raw)! }

/// `raw` day at `hour:minute` UTC.
private func hbTime(_ raw: String, _ hour: Int, _ minute: Int = 0) -> Date {
    hbDay(raw).date(calendar: hbUTC).addingTimeInterval(Double(hour * 3600 + minute * 60))
}

private func hbSample(_ raw: String, _ hour: Int, _ value: Double, source: String = "com.example.scale",
                      name: String = "Example Scale", minute: Int = 0) -> HealthBodySample {
    HealthBodySample(date: hbTime(raw, hour, minute), value: value, sourceID: source, sourceName: name)
}

@Suite("Apple Health body data")
struct HealthBodyTests {
    @Test func bodyFatSeriesPerSource() {
        let fat = [
            hbSample("2030-01-07", 7, 21.0),
            hbSample("2030-01-07", 19, 23.5), // later the same day: the morning value counts
            hbSample("2030-01-14", 7, 20.4),
            hbSample("2030-01-21", 7, 20.0),
            hbSample("2030-01-10", 9, 18.2, source: "com.example.clinic", name: "Example Clinic"),
        ]
        let lean = [
            hbSample("2030-01-07", 7, 60.0, minute: 1),   // within 10 minutes: paired
            hbSample("2030-01-14", 8, 61.0),              // an hour later: not paired
        ]
        let series = HealthBody.bodyFatSeries(bodyFat: fat, leanMass: lean, calendar: hbUTC)
        #expect(series.count == 2)
        // Both default to the smart-scale method: the longer series first.
        #expect(series.map(\.sourceID) == ["com.example.scale", "com.example.clinic"])
        let scale = series[0]
        #expect(scale.method == .scale)
        #expect(scale.id == "health:com.example.scale")
        #expect(scale.title == "Smart scale · Example Scale (Health)")
        #expect(scale.readings.map(\.bodyFat) == [21.0, 20.4, 20.0])
        #expect(scale.readings.map(\.day) == [hbDay("2030-01-07"), hbDay("2030-01-14"), hbDay("2030-01-21")])
        let allScale = scale.readings.allSatisfy { $0.method == .scale && $0.device == "Example Scale" && !$0.isWeighIn }
        #expect(allScale)
        #expect(scale.readings[0].leanKg == 60.0)
        #expect(scale.readings[1].leanKg == nil)
        #expect(scale.errorBand == BodyMethod.scale.errorBand)
        #expect(scale.latest?.bodyFat == 20.0)

        // Lean mass and body fat give the device's own split: fat = lean × BF ÷ (100 − BF).
        let first = scale.readings[0]
        let fatKg = first.fatKg ?? 0
        #expect(abs(fatKg - 60.0 * 21.0 / 79.0) < 1e-9)
        let composition = BodyComposition(reading: first, weightKg: nil)
        #expect(composition?.isMeasured == true)
        #expect(composition.map { abs($0.bodyFat - 21.0) < 1e-9 } == true)
        #expect(composition.map { abs($0.leanKg - 60.0) < 1e-9 } == true)
    }

    @Test func relabelledSourcesSortByAccuracy() {
        let fat = [
            hbSample("2030-01-07", 7, 21.0),
            hbSample("2030-01-14", 7, 20.4),
            hbSample("2030-01-10", 9, 18.2, source: "com.example.clinic", name: "Example Clinic"),
        ]
        let series = HealthBody.bodyFatSeries(bodyFat: fat, labels: ["com.example.clinic": .dexa], calendar: hbUTC)
        #expect(series.map(\.method) == [.dexa, .scale])
        #expect(series[0].title == "DEXA scan · Example Clinic (Health)")
        #expect(series[0].readings.first?.method == .dexa)
        #expect(series[0].errorBand == 1.5)
    }

    @Test func implausibleValuesAndEmptySourcesAreDropped() {
        let fat = [
            hbSample("2030-01-07", 7, 0.21),      // a fraction that wasn't turned into percent
            hbSample("2030-01-08", 7, 90),
            hbSample("2030-01-09", 7, .nan),
            HealthBodySample(date: hbTime("2030-01-10", 7), value: 20, sourceID: ""),
        ]
        #expect(HealthBody.bodyFatSeries(bodyFat: fat, calendar: hbUTC).isEmpty)
        // A source without a name reads "Apple Health".
        let unnamed = HealthBody.bodyFatSeries(bodyFat: [hbSample("2030-01-07", 7, 19, name: "")], calendar: hbUTC)
        #expect(unnamed.first?.sourceName == "Apple Health")
        #expect(unnamed.first?.readings.first?.device == "Apple Health")
        // Lean mass alone makes no series.
        #expect(HealthBody.bodyFatSeries(bodyFat: [], leanMass: [hbSample("2030-01-07", 7, 60)], calendar: hbUTC).isEmpty)
    }

    @Test func dayStartHourKeepsANightValueOnTheDayBefore() {
        let fat = [hbSample("2030-01-08", 1, 20.0)]
        let series = HealthBody.bodyFatSeries(bodyFat: fat, dayStartHour: 3, calendar: hbUTC)
        #expect(series.first?.readings.first?.day == hbDay("2030-01-07"))
    }

    @Test func neverMergedWithNinasSeries() {
        // A typed assessment with the same method and device name stays a series of its own.
        let typed = BodyFatReading(day: hbDay("2030-01-07"), bodyFat: 22, method: .scale, device: "Example Scale")
        let nina = BodyFatSeries.group([typed])
        let health = HealthBody.bodyFatSeries(bodyFat: [hbSample("2030-01-07", 7, 21.0)], calendar: hbUTC)
        #expect(nina.count == 1 && health.count == 1)
        #expect(nina[0].id != health[0].id)
        #expect(health[0].id.hasPrefix("health:"))
        #expect(nina[0].readings.count == 1)
        #expect(nina[0].title != health[0].title)
    }

    @Test func relabelChoices() {
        #expect(!HealthBody.methods.contains(.navy))
        #expect(HealthBody.methods.contains(.scale))
        #expect(HealthBody.methods.contains(.dexa))
        #expect(HealthBody.methods.count == BodyMethod.allCases.count - 1)
        #expect(HealthBody.defaultMethod == .scale)
    }

    @Test func sourcesNewestFirst() {
        let fat = [
            hbSample("2030-01-07", 7, 21.0),
            hbSample("2030-01-14", 7, 20.4),
            hbSample("2030-01-10", 9, 18.2, source: "com.example.clinic", name: ""),
        ]
        let sources = HealthBody.sources(fat)
        #expect(sources.map(\.id) == ["com.example.scale", "com.example.clinic"])
        #expect(sources.map(\.count) == [2, 1])
        #expect(sources.map(\.name) == ["Example Scale", "Apple Health"])
        #expect(sources[0].latest == hbTime("2030-01-14", 7))
    }

    @Test func waistIsItsOwnSeries() {
        let samples = [
            hbSample("2030-01-07", 7, 84.0, source: "com.example.tape"),
            hbSample("2030-01-07", 20, 85.1, source: "com.example.tape"),  // the latest of the day counts, like the tape
            hbSample("2030-01-21", 7, 82.6, source: "com.example.other"),
            hbSample("2030-01-22", 7, 8.4, source: "com.example.tape"),    // implausible (mm or a typo)
        ]
        let waist = HealthBody.waist(samples, calendar: hbUTC)
        #expect(waist.map(\.value) == [85.1, 82.6])
        #expect(waist.map(\.day) == [hbDay("2030-01-07"), hbDay("2030-01-21")])
        #expect(waist.allSatisfy { $0.isStandard })
        let change = HealthBody.waistChange(waist, calendar: hbUTC)
        #expect(change.map { abs($0.change - (82.6 - 85.1)) < 1e-9 } == true)
        #expect(change?.isClear == true)
        #expect(HealthBody.waistChange([], calendar: hbUTC) == nil)
        let snapshot = HealthBodySnapshot(waist: waist)
        #expect(snapshot.latestWaist?.value == 82.6)
        #expect(!snapshot.isEmpty)
        #expect(HealthBodySnapshot.empty.isEmpty)
    }

    @Test func heightHint() {
        let samples = [
            hbSample("2030-01-07", 7, 176.4),
            hbSample("2030-01-01", 7, 174.0),
            hbSample("2030-01-09", 7, 1.76),   // metres: ignored
        ]
        #expect(HealthBody.latestHeight(samples) == 176.4)
        #expect(HealthBody.latestHeight([]) == nil)
        #expect(HealthBody.heightHint(health: 176.4, profileCm: 0) == 176)
        #expect(HealthBody.heightHint(health: 176.4, profileCm: 172) == 176)
        #expect(HealthBody.heightHint(health: 176.4, profileCm: 176) == nil)
        #expect(HealthBody.heightHint(health: nil, profileCm: 0) == nil)
        #expect(HealthBody.heightHint(health: 240, profileCm: 0) == nil)
        #expect(HealthBody.heightHintText(176) == "Health: 176 cm")
    }
}

// MARK: - Workouts

private func hbPlan(paused: Bool = false) -> CoachPlan {
    let types = [
        CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5]), workouts: ["strength"]),
        CoachPlan.DayType(id: "tennis", name: "Tennis", schedule: .flexible, perWeek: 2, workouts: ["Tennis"]),
        CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default),
    ]
    let baseline = DailyTargets(energy: 2200, protein: 140, carbs: 250, fat: 70)
    var gym = baseline
    gym.energy = 2500
    var tennis = baseline
    tennis.energy = 2600
    let revision = CoachPlan.Revision(from: hbDay("2030-01-01"), baseline: baseline, byType: ["gym": gym, "tennis": tennis])
    let phase = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: hbDay("2030-01-01"), rateMin: 0.15, rateMax: 0.25,
                                startedAt: hbTime("2030-01-01", 8), status: .active, revisions: [revision])
    let pauses = paused ? [CoachPlan.Pause(start: hbDay("2030-01-08"))] : []
    return CoachPlan(dayTypes: types, phases: [phase], pauses: pauses)
}

private func hbWorkout(_ activity: String, _ raw: String, _ hour: Int, minutes: Int = 60) -> HealthWorkout {
    let start = hbTime(raw, hour)
    return HealthWorkout(activity: activity, start: start, end: start.addingTimeInterval(Double(minutes * 60)))
}

/// Tuesday 8 Jan 2030 (a rest day by the schedule) in the evening.
private let hbTuesday = hbDay("2030-01-08")
private let hbEvening = hbTime("2030-01-08", 21)

private func hbSuggest(_ workouts: [HealthWorkout], plan: CoachPlan = hbPlan(), day: DayKey = hbTuesday, today: DayKey = hbTuesday,
                       now: Date = hbEvening, marks: [String: String] = [:], dayStartHour: Int = 0,
                       dismissed: Set<String> = []) -> WorkoutSuggestion? {
    HealthWorkouts.suggestion(plan: plan, day: day, today: today, now: now, marks: marks, workouts: workouts,
                              fallback: .standard, dayStartHour: dayStartHour, dismissed: dismissed, calendar: hbUTC)
}

@Suite("Apple Health workouts")
struct HealthWorkoutsTests {
    @Test func kindsAndTitles() {
        let strength = HealthWorkouts.kinds(of: "traditionalStrengthTraining")
        #expect(strength.first == "traditional_strength_training")
        #expect(strength.contains("strength") && strength.contains("gym"))
        #expect(HealthWorkouts.kinds(of: "functionalStrengthTraining").contains("strength"))
        #expect(HealthWorkouts.kinds(of: "tennis") == ["tennis"])
        #expect(HealthWorkouts.kinds(of: "running").contains("running"))
        #expect(HealthWorkouts.kinds(of: "underwaterDiving") == ["underwater_diving"])
        #expect(HealthWorkouts.title(of: "tennis") == "Tennis")
        #expect(HealthWorkouts.title(of: "functionalStrengthTraining") == "Strength")
        #expect(HealthWorkouts.title(of: "tableTennis") == "Table tennis")
        #expect(HealthWorkouts.title(of: "underwaterDiving") == "Underwater diving")
        #expect(HealthWorkouts.title(of: "") == "Workout")
    }

    @Test func normalizesLikeTheImport() {
        #expect(HealthWorkouts.normalize("Strength Training") == "strength_training")
        #expect(HealthWorkouts.normalize("Fußball") == "fussball")
        #expect(HealthWorkouts.parse("Tennis; Strength Training, Fußball | tennis") == ["tennis", "strength_training", "fussball"])
        #expect(HealthWorkouts.parse(" ;, ") == [])
    }

    @Test func matching() {
        #expect(HealthWorkouts.matches("tennis", workouts: ["Tennis"]))
        #expect(HealthWorkouts.matches("functionalStrengthTraining", workouts: ["gym"]))
        #expect(HealthWorkouts.matches("traditionalStrengthTraining", workouts: ["strength_training"]))
        #expect(HealthWorkouts.matches("traditionalStrengthTraining", workouts: ["krafttraining"]))
        #expect(!HealthWorkouts.matches("running", workouts: ["strength"]))
        #expect(!HealthWorkouts.matches("tennis", workouts: []))
        #expect(HealthWorkouts.types(matching: "tennis", in: hbPlan()).map(\.id) == ["tennis"])
        #expect(HealthWorkouts.mappedTypes(in: hbPlan()).map(\.id) == ["gym", "tennis"])
    }

    @Test func offersTheMatchingTypeOnADefaultDay() {
        let suggestion = hbSuggest([hbWorkout("tennis", "2030-01-08", 18)])
        #expect(suggestion?.typeID == "tennis")
        #expect(suggestion?.energy == 2600)
        #expect(suggestion?.emoji == "🎾")
        #expect(suggestion?.found == "Tennis workout found")
        #expect(suggestion?.question == "Make it a tennis day?")
        #expect(suggestion?.text == "Tennis workout found · Make it a tennis day?")
        #expect(suggestion?.key == "workout.2030-01-08.tennis")
        let gym = hbSuggest([hbWorkout("functionalStrengthTraining", "2030-01-08", 7)])
        #expect(gym?.typeID == "gym")
        #expect(gym?.text == "Strength workout found · Make it a gym day?")
        // Picked by hand as the default type: still a default day.
        #expect(hbSuggest([hbWorkout("tennis", "2030-01-08", 18)], marks: ["2030-01-08": "rest"])?.typeID == "tennis")
    }

    @Test func severalFitThePlanThenTheHigherOneWins() {
        let both = [hbWorkout("traditionalStrengthTraining", "2030-01-08", 7), hbWorkout("tennis", "2030-01-08", 18)]
        #expect(hbSuggest(both)?.typeID == "tennis")
        // "Not now" on tennis leaves the gym.
        #expect(hbSuggest(both, dismissed: ["workout.2030-01-08.tennis"])?.typeID == "gym")
        #expect(hbSuggest(both, dismissed: ["workout.2030-01-08.tennis", "workout.2030-01-08.gym"]) == nil)
    }

    @Test func nothingOtherwise() {
        let tennis = [hbWorkout("tennis", "2030-01-08", 18)]
        // A scheduled gym day (Monday) or a type picked by hand isn't a default day.
        #expect(hbSuggest([hbWorkout("tennis", "2030-01-07", 18)], day: hbDay("2030-01-07"), today: hbDay("2030-01-07"),
                          now: hbTime("2030-01-07", 21)) == nil)
        #expect(hbSuggest(tennis, marks: ["2030-01-08": "tennis"]) == nil)
        #expect(hbSuggest(tennis, marks: ["2030-01-08": "gym"]) == nil)
        // Only today.
        #expect(hbSuggest(tennis, day: hbTuesday, today: hbDay("2030-01-09"), now: hbTime("2030-01-09", 9)) == nil)
        // Still running, or from another day.
        #expect(hbSuggest(tennis, now: hbTime("2030-01-08", 18, 30)) == nil)
        #expect(hbSuggest([hbWorkout("tennis", "2030-01-07", 18)]) == nil)
        // A workout no day type lists.
        #expect(hbSuggest([hbWorkout("running", "2030-01-08", 7)]) == nil)
        // Paused, or without a plan.
        #expect(hbSuggest(tennis, plan: hbPlan(paused: true)) == nil)
        #expect(hbSuggest(tennis, plan: CoachPlan()) == nil)
        #expect(hbSuggest([]) == nil)
    }

    @Test func aLateWorkoutBelongsToTheDayBefore() {
        // Started 01:30 on Wednesday with the day starting at 3:00: still Tuesday.
        let late = HealthWorkout(activity: "tennis", start: hbTime("2030-01-09", 1, 30), end: hbTime("2030-01-09", 2, 30))
        #expect(late.day(dayStartHour: 3, calendar: hbUTC) == hbTuesday)
        #expect(hbSuggest([late], now: hbTime("2030-01-09", 2, 45), dayStartHour: 3)?.typeID == "tennis")
        #expect(hbSuggest([late], now: hbTime("2030-01-09", 2, 45), dayStartHour: 0) == nil)
    }

    @Test func dayNames() {
        #expect(HealthWorkouts.dayName("Tennis") == "tennis day")
        #expect(HealthWorkouts.dayName("Match day") == "match day")
        #expect(HealthWorkouts.dayName(" ") == "workout day")
    }
}
