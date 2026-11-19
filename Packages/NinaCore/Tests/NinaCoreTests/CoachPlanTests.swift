import Foundation
import Testing
@testable import NinaCore

// Made-up plan: gym Mon/Wed/Fri 2600 kcal, tennis twice a week 2800, rest 2400 (protein 154 g and
// fat 76 g on every type, carbs take the rest); a gain phase in 2030, then a planned cut.

private var coachUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func coachDay(_ raw: String) -> DayKey { DayKey(raw)! }

@Suite("Coach plan")
struct CoachPlanTests {
    static let gym = DailyTargets(energy: 2600, protein: 154, carbs: 325, fat: 76, fiber: 30, water: 2500)
    static let tennis = DailyTargets(energy: 2800, protein: 154, carbs: 375, fat: 76, fiber: 30, water: 2500)
    static let rest = DailyTargets(energy: 2400, protein: 154, carbs: 275, fat: 76, fiber: 30, water: 2500)
    static let baseline = DailyTargets(energy: 2600, protein: 154, carbs: 325, fat: 76, fiber: 30, water: 2500)
    static let profile = DailyTargets(energy: 2200, protein: 120, carbs: 250, fat: 70)
    static let startedAt = Date(timeIntervalSince1970: 1_894_006_800) // 2030-01-07 09:00 UTC

    /// Phase 1 (gain) started 2030-01-07; phase 2 (cut) planned for 2030-06-03.
    static var plan: CoachPlan {
        CoachPlan(
            dayTypes: [
                .init(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5]), workouts: ["strength"]),
                .init(id: "tennis", name: "Tennis", emoji: "🎾", schedule: .flexible, perWeek: 2, workouts: ["tennis"]),
                .init(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
            ],
            phases: [
                .init(id: "1", name: "Lean gain", goal: .gain, start: coachDay("2030-01-07"), end: coachDay("2030-05-26"), endApprox: true,
                      rateMin: 0.15, rateMax: 0.25, reviewMin: 82, reviewMax: 83, targetWeight: 83, startedAt: startedAt, status: .active,
                      revisions: [.init(from: coachDay("2030-01-07"), baseline: baseline,
                                        byType: ["gym": gym, "tennis": tennis, "rest": rest], reason: "import")]),
                .init(id: "2", name: "Cut", goal: .lose, start: coachDay("2030-06-03"), startApprox: true, end: coachDay("2030-08-25"),
                      endApprox: true, targetWeight: 78, targetBodyFat: 14),
            ],
            longTerm: .init(weightKg: 78, bodyFat: 14, note: "More muscle"),
            protein: .init(mealMin: 35, mealMax: 45, count: 4, meals: ["breakfast", "lunch", "snack", "dinner"]),
            checks: [.init(id: "creatine", name: "Creatine monohydrate", emoji: "💊", dose: "3–5 g", timing: .meal("breakfast"),
                           isOptional: true, remind: true)],
            routine: .init(weeklySites: [.waist], fullSites: [.neck, .chest, .arm, .waist, .hip, .thigh], side: .both),
            pauses: [.init(start: coachDay("2030-03-01"), end: coachDay("2030-03-08"), reason: .holiday)],
            notes: ["Drink a glass of water before training.", "Sleep well, eat enough."]
        )
    }

    // MARK: JSON

    @Test func roundTripsThroughJSON() {
        let plan = Self.plan
        let text = plan.encoded
        #expect(!text.isEmpty)
        let decoded = CoachPlan(encoded: text)
        #expect(decoded == plan)
        #expect(decoded.encoded == text)
        // Sorted keys, every group present, targets as DailyTargets.encoded text, the check's "optional" key.
        #expect(text.hasPrefix("{\"adjust\":"))
        #expect(text.contains("\"baseline\":\"energy=2600;protein=154;carbs=325;fat=76"))
        #expect(text.contains("\"weekdays\":\"1,3,5\""))
        #expect(text.contains("\"optional\":true"))
        #expect(text.contains("\"timing\":\"meal:breakfast\""))
        #expect(text.contains("\"startedAt\":\"2030-01-07T09:00:00Z\""))
        #expect(decoded.checks.first?.affectsWeight == true)
        #expect(decoded.routine.side == .both)
    }

    @Test func emptyAndBrokenTextIsAnEmptyPlan() {
        #expect(CoachPlan(encoded: "") == CoachPlan())
        #expect(CoachPlan(encoded: "   ") == CoachPlan())
        #expect(CoachPlan(encoded: "not json") == CoachPlan())
        #expect(CoachPlan(encoded: "[1,2]") == CoachPlan())
        #expect(CoachPlan(encoded: "{}") == CoachPlan())
        #expect(CoachPlan().encoded == "")
        #expect(CoachPlan().isEmpty)
        #expect(!CoachPlan().isSetUp)
        #expect(Self.plan.isSetUp)
        let defaults = CoachPlan()
        #expect(defaults.v == 1)
        #expect(defaults.routine.weighInMinutes == 420)
        #expect(defaults.routine.morningCutoffMinutes == 660)
        #expect(defaults.routine.weeklySites == [.waist])
        #expect(defaults.routine.fullSites == [.neck, .chest, .arm, .waist, .hip, .thigh])
        #expect(defaults.routine.fullEveryWeeks == 8)
        #expect(defaults.routine.twoReadings)
        #expect(defaults.routine.checkInWeekday == 1)
        #expect(defaults.adjust == CoachPlan.Adjust(windowMinDays: 14, windowMaxDays: 21, stepMin: 100, stepMax: 150, intakeTolerance: 150,
                                                    lockDays: 14, confirmChecks: 2, tolerance: 0.03, gainCapOverMaintenance: 500))
    }

    @Test func decodingIsLenient() {
        let json = """
        { "v": 1, "future": {"x": [1, 2]},
          "dayTypes": [ {"id": "gym", "name": "Gym", "schedule": "fixed", "weekdays": [1, 3, 5], "colour": "red"},
                        {"name": "no id, dropped"},
                        {"id": "rest", "name": "Rest", "schedule": "default"},
                        {"id": "swim", "name": "Swim", "schedule": "sometimes", "perWeek": "2"} ],
          "phases": [ {"id": 1, "name": "Gain", "goal": "gain", "start": "2030-01-07", "end": "", "rateMin": "0.1", "rateMax": 0.2,
                       "startedAt": "2030-01-07T09:00:00.250Z", "status": "weird", "endApprox": "yes",
                       "revisions": [ {"from": "2030-01-07", "baseline": "energy=2500;protein=140", "byType": {"gym": "energy=2700"}, "reason": "import"},
                                      {"from": "someday", "baseline": "energy=1"} ] } ],
          "protein": {"mealMin": 30, "meals": "breakfast;dinner"},
          "checks": [ {"id": "creatine", "name": "Kreatin", "timing": "08:00", "days": "1,3,5"} ],
          "routine": {"weeklySites": ["waist", "elbow"], "side": "sideways", "checkInWeekday": 9, "bodyFatMethod": "dexa"},
          "adjust": {"stepMin": "120", "lockDays": 10.0},
          "pauses": [ {"start": "2030-02-01", "end": "", "reason": "sick"}, {"end": "2030-02-03"} ],
          "notes": "One note, with a comma" }
        """
        let plan = CoachPlan(encoded: json)
        #expect(plan.dayTypes.map(\.id) == ["gym", "rest", "swim"])
        #expect(plan.dayType(id: "gym")?.weekdays == Weekdays([1, 3, 5]))
        #expect(plan.dayType(id: "swim")?.schedule == .flexible)
        #expect(plan.dayType(id: "swim")?.perWeek == 2)
        let phase = plan.phases.first
        #expect(phase?.id == "1")
        #expect(phase?.goal == .gain)
        #expect(phase?.end == nil)
        #expect(phase?.endApprox == true)
        #expect(phase?.rateMin == 0.1)
        #expect(phase?.status == .planned)
        #expect(phase?.maxWaistGainCm == 4)
        #expect(phase?.startedAt == Date(timeIntervalSince1970: 1_894_006_800))
        #expect(phase?.revisions.count == 1)
        #expect(phase?.revisions.first?.baseline?.energy == 2500)
        #expect(phase?.revisions.first?.byType["gym"]?.energy == 2700)
        #expect(plan.protein.meals == ["breakfast", "dinner"])
        #expect(plan.protein.mealMax == 0)
        let check = plan.checks.first
        #expect(check?.timing == .time(8 * 60))
        #expect(check?.days == .weekdays(Weekdays([1, 3, 5])))
        #expect(check?.affectsWeight == true)
        #expect(plan.routine.weeklySites == [.waist])
        #expect(plan.routine.fullSites == CoachPlan.Routine.defaultFullSites)
        #expect(plan.routine.side == .right)
        #expect(plan.routine.checkInWeekday == 1)
        #expect(plan.routine.bodyFatMethod == .dexa)
        #expect(plan.adjust.stepMin == 120)
        #expect(plan.adjust.lockDays == 10)
        #expect(plan.adjust.stepMax == 150)
        #expect(plan.pauses == [CoachPlan.Pause(start: coachDay("2030-02-01"), end: nil, reason: .sick)])
        #expect(plan.notes == ["One note, with a comma"])
        // Re-encoding gives a plan that reads back the same.
        #expect(CoachPlan(encoded: plan.encoded) == plan)
    }

    @Test func checkTimingAndDaysText() {
        for timing in [CoachPlan.CheckTiming.anytime, .meal("lunch"), .time(7 * 60 + 30)] {
            #expect(CoachPlan.CheckTiming(encoded: timing.encoded) == timing)
        }
        #expect(CoachPlan.CheckTiming.time(450).encoded == "time:07:30")
        #expect(CoachPlan.CheckTiming(encoded: "") == .anytime)
        #expect(CoachPlan.CheckTiming(encoded: "breakfast") == .meal("breakfast"))
        for days in [CoachPlan.CheckDays.daily, .weekdays(Weekdays([2, 4])), .dayTypes(["gym", "tennis"])] {
            #expect(CoachPlan.CheckDays(encoded: days.encoded) == days)
        }
        #expect(CoachPlan.CheckDays(encoded: "gym;tennis") == .dayTypes(["gym", "tennis"]))
        let check = CoachPlan.Check(id: "magnesium", name: "Magnesium", days: .dayTypes(["gym"]))
        #expect(!check.affectsWeight)
        #expect(check.isDue(on: coachDay("2030-01-07"), dayTypeID: "gym", calendar: coachUTC))
        #expect(!check.isDue(on: coachDay("2030-01-08"), dayTypeID: "rest", calendar: coachUTC))
        let weekly = CoachPlan.Check(id: "d3", name: "Vitamin D", days: .weekdays(Weekdays([1])))
        #expect(weekly.isDue(on: coachDay("2030-01-07"), dayTypeID: nil, calendar: coachUTC))
        #expect(!weekly.isDue(on: coachDay("2030-01-08"), dayTypeID: nil, calendar: coachUTC))
    }

    // MARK: Resolvers

    @Test func activePhaseNeedsAConfirmedStart() {
        var plan = Self.plan
        #expect(plan.activePhase(on: coachDay("2030-01-06")) == nil)
        #expect(plan.activePhase(on: coachDay("2030-01-07"))?.id == "1")
        // Phase 2's date has come but it isn't started: phase 1 keeps running, phase 2 is due.
        #expect(plan.activePhase(on: coachDay("2030-06-10"))?.id == "1")
        #expect(plan.duePhase(on: coachDay("2030-06-02")) == nil)
        #expect(plan.duePhase(on: coachDay("2030-06-03"))?.id == "2")
        // Not started at all: nothing is active.
        plan.phases[0].startedAt = nil
        #expect(plan.activePhase(on: coachDay("2030-02-01")) == nil)
        #expect(plan.targets(on: coachDay("2030-02-01"), marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.profile)
    }

    @Test func startingAPhase() {
        let now = Date(timeIntervalSince1970: 1_907_046_000) // 2030-06-07 07:00 UTC
        var plan = Self.plan.addingRevision(phase: "2", from: coachDay("2030-06-03"), baseline: Self.rest, byType: [:], reason: "edit")
        plan = plan.starting(phase: "2", on: coachDay("2030-05-31"), now: now, calendar: coachUTC)
        let cut = plan.phase(id: "2")
        #expect(cut?.start == coachDay("2030-05-31"))
        #expect(cut?.startApprox == false)
        #expect(cut?.startedAt == now)
        #expect(cut?.status == .active)
        #expect(cut?.revisions.first?.from == coachDay("2030-05-31"))
        let gain = plan.phase(id: "1")
        #expect(gain?.status == .done)
        #expect(gain?.end == coachDay("2030-05-30"))
        #expect(gain?.endApprox == false)
        #expect(plan.activePhase(on: coachDay("2030-05-30"))?.id == "1")
        #expect(plan.activePhase(on: coachDay("2030-05-31"))?.id == "2")
        #expect(plan.duePhase(on: coachDay("2030-06-10")) == nil)
        // A done phase stops after its end when nothing follows.
        var ended = Self.plan
        ended.phases.removeLast()
        ended.phases[0].status = .done
        ended.phases[0].endApprox = false
        #expect(ended.activePhase(on: coachDay("2030-05-26"))?.id == "1")
        #expect(ended.activePhase(on: coachDay("2030-05-27")) == nil)
    }

    @Test func revisionByDate() {
        let plan = Self.plan.addingRevision(phase: "1", from: coachDay("2030-02-04"), baseline: Self.profile, byType: [:], reason: "edit")
        let phase = plan.phase(id: "1")!
        #expect(plan.revision(of: phase, on: coachDay("2030-01-06")) == nil)
        #expect(plan.revision(of: phase, on: coachDay("2030-02-03"))?.from == coachDay("2030-01-07"))
        #expect(plan.revision(of: phase, on: coachDay("2030-02-04"))?.from == coachDay("2030-02-04"))
        #expect(plan.revision(on: coachDay("2030-03-01"))?.reason == "edit")
        // Same day again: replaced, not stacked.
        let again = plan.addingRevision(phase: "1", from: coachDay("2030-02-04"), baseline: Self.rest, byType: [:], reason: "edit")
        #expect(again.phase(id: "1")?.revisions.count == 2)
        #expect(again.revision(on: coachDay("2030-02-04"))?.baseline == Self.rest)
        // Unknown phase: unchanged.
        #expect(plan.addingRevision(phase: "9", from: coachDay("2030-02-04"), baseline: nil, byType: [:], reason: "edit") == plan)
    }

    @Test func dayTypePrecedence() {
        let plan = Self.plan
        let monday = coachDay("2030-01-07"), tuesday = coachDay("2030-01-08"), saturday = coachDay("2030-01-12")
        #expect(plan.dayType(on: monday, marks: [:], calendar: coachUTC)?.id == "gym")
        #expect(plan.dayType(on: tuesday, marks: [:], calendar: coachUTC)?.id == "rest")
        #expect(plan.dayType(on: saturday, marks: [:], calendar: coachUTC)?.id == "rest")
        // A mark beats the fixed weekday and the default.
        let marks = [monday.rawValue: "tennis", tuesday.rawValue: "gym", saturday.rawValue: "gone"]
        #expect(plan.dayType(on: monday, marks: marks, calendar: coachUTC)?.id == "tennis")
        #expect(plan.dayType(on: tuesday, marks: marks, calendar: coachUTC)?.id == "gym")
        #expect(plan.isManualDayType(on: monday, marks: marks))
        // A mark for a type that no longer exists is ignored.
        #expect(plan.dayType(on: saturday, marks: marks, calendar: coachUTC)?.id == "rest")
        #expect(!plan.isManualDayType(on: saturday, marks: marks))
        #expect(plan.fixedType(for: 3)?.id == "gym")
        #expect(plan.fixedType(for: 4) == nil)
        #expect(plan.defaultDayType?.id == "rest")
        // Without a default type, an unmarked off day has no type.
        var noDefault = plan
        noDefault.dayTypes.removeLast()
        #expect(noDefault.dayType(on: tuesday, marks: [:], calendar: coachUTC) == nil)
    }

    @Test func targetsPrecedence() {
        var plan = Self.plan
        let monday = coachDay("2030-01-14"), thursday = coachDay("2030-01-17")
        #expect(plan.targets(on: monday, marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.gym)
        #expect(plan.targets(on: thursday, marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.rest)
        #expect(plan.targets(on: thursday, marks: [thursday.rawValue: "tennis"], fallback: Self.profile, calendar: coachUTC) == Self.tennis)
        // Before the phase: the profile's targets.
        #expect(plan.targets(on: coachDay("2030-01-06"), marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.profile)
        // A type without its own targets uses the baseline.
        plan.phases[0].revisions[0].byType["tennis"] = nil
        #expect(plan.targets(on: thursday, marks: [thursday.rawValue: "tennis"], fallback: Self.profile, calendar: coachUTC) == Self.baseline)
        // No baseline either: the profile's.
        plan.phases[0].revisions[0].baseline = nil
        #expect(plan.targets(on: thursday, marks: [thursday.rawValue: "tennis"], fallback: Self.profile, calendar: coachUTC) == Self.profile)
        // A phase without revisions: the profile's.
        plan.phases[0].revisions = []
        #expect(plan.targets(on: monday, marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.profile)
    }

    @Test func pauses() {
        var plan = Self.plan
        #expect(!plan.isPaused(on: coachDay("2030-02-28")))
        #expect(plan.isPaused(on: coachDay("2030-03-01")))
        #expect(plan.isPaused(on: coachDay("2030-03-08")))
        #expect(plan.pause(on: coachDay("2030-03-05"))?.reason == .holiday)
        #expect(!plan.isPaused(on: coachDay("2030-03-09")))
        plan.pauses.append(.init(start: coachDay("2030-04-01")))
        #expect(plan.isPaused(on: coachDay("2031-01-01")))
    }

    @Test func weekHelpers() {
        let plan = Self.plan
        let phase = plan.phase(id: "1")!
        #expect(phase.weeks(calendar: coachUTC) == 20)
        #expect(phase.week(on: coachDay("2030-01-06"), calendar: coachUTC) == nil)
        #expect(phase.week(on: coachDay("2030-01-07"), calendar: coachUTC) == 1)
        #expect(phase.week(on: coachDay("2030-01-13"), calendar: coachUTC) == 1)
        #expect(phase.week(on: coachDay("2030-01-14"), calendar: coachUTC) == 2)
        #expect(plan.phase(id: "2")?.weeks(calendar: coachUTC) == 12)
        #expect(abs(phase.rateMid - 0.2) < 1e-9)
        #expect(abs(phase.energyAdjustment - 220) < 1e-9)
        #expect(phase.signedRateRange == 0.15...0.25)
        let cut = CoachPlan.Phase(id: "c", goal: .lose, rateMin: 0.5, rateMax: 0.3)
        #expect(cut.signedRateRange == -0.5...(-0.3))
        #expect(abs(cut.energyAdjustment + 440) < 1e-9)
        #expect(cut.maxWaistGainCm == 0)
        // "Tennis · 1 of 2 this week" (ISO week Mon–Sun), a mark in the next week doesn't count.
        let marks = ["2030-01-08": "tennis", "2030-01-14": "tennis", "2030-01-10": "gym"]
        #expect(plan.flexibleCount(of: "tennis", inWeekOf: coachDay("2030-01-12"), marks: marks, calendar: coachUTC) == 1)
        #expect(plan.flexibleCount(of: "gym", inWeekOf: coachDay("2030-01-07"), marks: marks, calendar: coachUTC) == 4)
        // Planned week: 3 × 2600 + 2 × 2800 + 2 × 2400 = 18,200 → 2,600 a day; macros add up on every type.
        #expect(plan.plannedWeekAverage(plan.phases[0].revisions[0]) == 2600)
        for targets in [Self.gym, Self.tennis, Self.rest] {
            #expect(targets.protein * 4 + targets.carbs * 4 + targets.fat * 9 == targets.energy)
        }
    }

    // MARK: Mirror and migration

    @Test func mirrorWritesTheLegacyValues() {
        let plan = Self.plan
        let mirror = plan.mirror(on: coachDay("2030-01-20"))
        #expect(mirror?.targets == Self.rest)
        #expect(mirror?.trainingTargets == Self.gym)
        #expect(mirror?.trainingDays == Weekdays([1, 3, 5]))
        #expect(mirror?.goal == .gain)
        #expect(abs((mirror?.ratePerWeek ?? 0) - 0.2) < 1e-9)
        #expect(mirror?.targetWeight == 83)
        #expect(plan.mirror(on: coachDay("2030-01-06")) == nil)
        let state = mirror!.applied(to: SettingsState(goal: .lose, ratePerWeek: 0.5, targetWeight: 70, targets: Self.profile))
        #expect(state.targets == Self.rest)
        #expect(state.trainingTargets == Self.gym)
        #expect(state.trainingDays == Weekdays([1, 3, 5]))
        #expect(state.goal == .gain)
        #expect(state.targetWeight == 83)
        // A phase without targets keeps the profile's targets and turns training targets off.
        var bare = plan
        bare.phases[0].revisions = []
        let kept = bare.mirror(on: coachDay("2030-01-20"))!.applied(to: SettingsState(targets: Self.profile, trainingTargets: Self.gym,
                                                                                       trainingDays: Weekdays([2])))
        #expect(kept.targets == Self.profile)
        #expect(kept.trainingTargets == nil)
        #expect(kept.trainingDays.isEmpty)
    }

    @Test func migrationFromTheProfile() {
        let training = SettingsState.training(Self.profile, extra: 300)
        let state = SettingsState(sex: .female, goal: .gain, ratePerWeek: 0.25, targetWeight: 64, targets: Self.profile,
                                  trainingTargets: training, trainingDays: Weekdays([2, 4]))
        let today = coachDay("2030-01-09")
        let plan = CoachPlan.migrated(from: state, on: today, now: Self.startedAt)
        #expect(plan.dayTypes.map(\.id) == ["training", "rest"])
        #expect(plan.dayType(id: "training")?.schedule == .fixed)
        #expect(plan.dayType(id: "training")?.weekdays == Weekdays([2, 4]))
        #expect(plan.defaultDayType?.name == "Rest")
        #expect(plan.phases.count == 1)
        let phase = plan.phases[0]
        #expect(phase.goal == .gain)
        #expect(phase.start == today)
        #expect(phase.end == nil)
        #expect(phase.isStarted)
        #expect(phase.status == .active)
        #expect(phase.rateMin == 0.25 && phase.rateMax == 0.25)
        #expect(phase.targetWeight == 64)
        #expect(phase.maxWaistGainCm == 4)
        #expect(plan.routine.weeklySites == [.waistNarrow])
        // Same numbers as before on every day.
        let thursday = coachDay("2030-01-10"), friday = coachDay("2030-01-11")
        #expect(plan.targets(on: thursday, marks: [:], fallback: .standard, calendar: coachUTC) == training)
        #expect(plan.targets(on: friday, marks: [:], fallback: .standard, calendar: coachUTC) == Self.profile)
        // And the mirror gives the profile back unchanged.
        #expect(plan.mirror(on: today)?.applied(to: state) == state)
        // Without training targets: no day types, one phase with the profile's targets.
        let simple = CoachPlan.migrated(from: SettingsState(goal: .maintain, targets: Self.profile), on: today, now: Self.startedAt)
        #expect(simple.dayTypes.isEmpty)
        #expect(simple.phases.first?.rateMax == 0)
        #expect(simple.phases.first?.name == "Maintenance")
        #expect(simple.targets(on: friday, marks: [:], fallback: .standard, calendar: coachUTC) == Self.profile)
        #expect(simple.routine.weeklySites == [.waist])
        #expect(CoachPlan(encoded: plan.encoded) == plan)
    }

    // MARK: Changing targets

    @Test func applyingDeltaKeepsTheCycling() {
        let plan = Self.plan
        let tomorrow = coachDay("2030-02-05")
        let adjusted = plan.applyingDelta(100, from: tomorrow, weightKg: 80)
        let revision = adjusted.revision(on: tomorrow)
        #expect(revision?.from == tomorrow)
        #expect(revision?.reason == "adjust:+100")
        #expect(revision?.byType["gym"]?.energy == 2700)
        #expect(revision?.byType["gym"]?.carbs == 350)
        #expect(revision?.byType["gym"]?.protein == 154)
        #expect(revision?.byType["gym"]?.fat == 76)
        #expect(revision?.byType["tennis"]?.energy == 2900)
        #expect(revision?.byType["rest"]?.energy == 2500)
        #expect(revision?.baseline?.energy == 2700)
        let gym = revision?.byType["gym"] ?? .standard
        #expect(gym.protein * 4 + gym.carbs * 4 + gym.fat * 9 == gym.energy)
        // Differences between the types stay the same.
        let gap = (revision?.byType["tennis"]?.energy ?? 0) - (revision?.byType["rest"]?.energy ?? 0)
        #expect(gap == Self.tennis.energy - Self.rest.energy)
        // Past days keep their targets.
        let monday = coachDay("2030-02-04")
        #expect(adjusted.targets(on: monday, marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.gym)
        #expect(adjusted.targets(on: coachDay("2030-02-06"), marks: [:], fallback: Self.profile, calendar: coachUTC).energy == 2700)
        // No active phase on that day: unchanged.
        #expect(plan.applyingDelta(100, from: coachDay("2029-12-01")) == plan)
    }

    @Test func lossDeltaUsesCarbsAndFatWithAFatFloor() {
        let targets = DailyTargets(energy: 2400, protein: 160, carbs: 250, fat: 70)
        let cut = CoachPlan.shifted(targets, by: -150, macros: .carbsAndFat, weightKg: 80)
        #expect(cut.energy == 2250)
        #expect(cut.protein == 160)
        #expect(cut.fat == 65)
        #expect(cut.carbs == 225)
        // Fat already near the floor (max(0.6 × 80, 20 % of 2250 ÷ 9) = 50 g): carbs take the rest.
        let lean = CoachPlan.shifted(DailyTargets(energy: 2400, protein: 160, carbs: 330, fat: 52), by: -150, macros: .carbsAndFat, weightKg: 80)
        #expect(lean.fat == 50)
        #expect(lean.carbs == 295)
        // Gain: all of it in carbs, 5 g steps.
        let gain = CoachPlan.shifted(targets, by: 150, macros: .carbs)
        #expect(gain.carbs == 290)
        #expect(gain.fat == 70)
        #expect(CoachPlan.MacroRule(goal: .lose) == .carbsAndFat)
        #expect(CoachPlan.MacroRule(goal: .gain) == .carbs)
        // In a loss phase the rule follows the goal.
        var plan = Self.plan.starting(phase: "2", on: coachDay("2030-06-03"), now: Self.startedAt, calendar: coachUTC)
        plan = plan.addingRevision(phase: "2", from: coachDay("2030-06-03"), baseline: targets, byType: [:], reason: "edit")
        let adjusted = plan.applyingDelta(-150, from: coachDay("2030-06-20"), weightKg: 80)
        #expect(adjusted.revision(on: coachDay("2030-06-20"))?.baseline == cut)
        #expect(adjusted.revision(on: coachDay("2030-06-20"))?.reason == "adjust:-150")
    }

    @Test func applyingDeltaWithoutRevisionStartsFromTheProfile() {
        var plan = Self.plan
        plan.phases[0].revisions = []
        let adjusted = plan.applyingDelta(100, from: coachDay("2030-02-05"), fallback: Self.profile)
        #expect(adjusted.revision(on: coachDay("2030-02-05"))?.baseline?.energy == Self.profile.energy + 100)
        #expect(adjusted.targets(on: coachDay("2030-02-04"), marks: [:], fallback: Self.profile, calendar: coachUTC) == Self.profile)
    }

    // MARK: Day marks and key=value text

    @Test func dayMarksNewestWins() {
        let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)
        let marks = DayMarks.dayTypes([
            (day: "2030-01-08", key: "tennis", modifiedAt: late),
            (day: "2030-01-08", key: "gym", modifiedAt: early),
            (day: "2030-01-09", key: "rest", modifiedAt: early),
            (day: "", key: "gym", modifiedAt: late),
        ])
        #expect(marks == ["2030-01-08": "tennis", "2030-01-09": "rest"])
        #expect(DayMarks.checkInKey(week: coachDay("2030-01-10"), calendar: coachUTC) == "week-2030-01-07")
        #expect(PhaseEvent(rawValue: "review-hold") == .reviewHold)
        #expect(DayMarkKind(rawValue: "checkIn") == .checkIn)
    }

    @Test func keyValueText() {
        var meta = KeyValueText(encoded: " verdict = slower ;state=done;broken;=x;applied=")
        #expect(meta["state"] == "done")
        #expect(meta["verdict"] == "slower")
        #expect(meta["applied"] == nil)
        #expect(meta.keys == ["state", "verdict"])
        #expect(meta.encoded == "state=done;verdict=slower")
        meta["note"] = "a;b\nc"
        #expect(meta["note"] == "a,b c")
        meta.setNumber(0.15, for: "rate")
        meta.setNumber(2.0, for: "weighIns")
        #expect(meta.number("rate") == 0.15)
        #expect(meta.encoded == "note=a,b c;rate=0.15;state=done;verdict=slower;weighIns=2")
        #expect(KeyValueText(encoded: meta.encoded) == meta)
        meta["state"] = nil
        #expect(meta["state"] == nil)
        #expect(meta.number("verdict") == nil)
    }
}
