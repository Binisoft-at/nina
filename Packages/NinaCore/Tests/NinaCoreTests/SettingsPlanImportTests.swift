import Foundation
import Testing
@testable import NinaCore

// All numbers and dates here are made up (an 80 kg person at 20 % body fat, phases in 2030).

private var planImportUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func planImportDay(_ raw: String) -> DayKey { DayKey(raw)! }

/// 2030-01-07 08:00 UTC, a Monday: the day phase 1 starts.
private let planImportNow = Date(timeIntervalSince1970: 1_894_003_200)

@Suite("Settings import: coach plan")
struct SettingsPlanImportTests {
    /// Shaped like a real plan an AI wrote from a coach's notes – with invented numbers.
    static let file = """
    setting,value
    weight_kg,80
    activity,moderate
    goal,gain
    rate_kg_per_week,0.1-0.2
    target_weight_kg,83
    macro_split,25/50/25
    calories,2600
    protein_g,160
    carbs_g,328
    fat_g,72
    fiber_g,30
    water_ml,2500
    focus_nutrients,protein;carbs;fat;fiber
    body_fat_percent,20
    body_fat_method,estimate
    long_term.weight_kg,78
    long_term.body_fat_percent,14
    long_term.note,Leaner and stronger
    day_type.gym.name,Gym
    day_type.gym.days,mon;wed;fri
    day_type.gym.workouts,strength
    day_type.tennis.name,Tennis
    day_type.tennis.days,flexible
    day_type.tennis.per_week,2
    day_type.tennis.workouts,tennis
    day_type.rest.name,Rest
    day_type.rest.days,default
    phase.1.name,Lean gain
    phase.1.goal,gain
    phase.1.start,2030-01-07
    phase.1.end,~2030-05-31
    phase.1.rate_kg_per_week,0.1-0.2
    phase.1.review_weight_kg,82-83
    phase.1.target_weight_kg,83
    phase.1.gym.calories,2600
    phase.1.gym.macros_g,160/328/72
    phase.1.tennis.calories,2800
    phase.1.tennis.macros_g,160/378/72
    phase.1.rest.calories,2400
    phase.1.rest.macros_g,160/278/72
    phase.2.name,Fat loss
    phase.2.goal,lose
    phase.2.start,~2030-06
    phase.2.end,~2030-08
    phase.2.target_weight_kg,78
    phase.2.target_body_fat_percent,14
    checkin.day,mon
    checkin.adjust_after_weeks,2-3
    checkin.step_kcal,100-150
    measure.weigh_in,daily 07:00
    measure.weekly,waist
    measure.full,waist;chest;arm;thigh;hip
    measure.full_every_weeks,8
    measure.body_fat_every_weeks,8
    check.creatine.name,Creatine monohydrate
    check.creatine.dose,3-5 g
    check.creatine.when,breakfast
    check.creatine.optional,yes
    meal_protein_g,35-45
    protein_meals,4
    note,An extra gym session counts as a gym day: pick Gym on that day.
    note,Keep sleep and recovery in mind on tennis days.
    note,The fat-loss start depends on progress.
    not_supported,Show a shopping list for my week
    """

    static let today = planImportDay("2030-01-07")

    static func imported(_ text: String = file, to state: SettingsState = SettingsState(sex: .male), today: DayKey = today,
                         now: Date = planImportNow) -> SettingsResult {
        SettingsCSV.apply(SettingsCSV.parse(text), to: state, year: today.year, today: today, now: now, calendar: planImportUTC)
    }

    @Test func everyFormerWishHasAKey() {
        let draft = SettingsCSV.parse(Self.file)
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        #expect(draft.wishes == ["Show a shopping list for my week"])
        #expect(draft.rateRange == 0.1...0.2)
        #expect(draft.ratePerWeek == 0.15)
        let plan = draft.plan
        #expect(plan.bodyFat == 20)
        #expect(plan.bodyFatMethod == .estimate)
        #expect(plan.longTerm.weightKg == 78)
        #expect(plan.longTerm.bodyFat == 14)
        #expect(plan.longTerm.note == "Leaner and stronger")
        #expect(plan.dayTypes?.map(\.id) == ["gym", "tennis", "rest"])
        #expect(plan.dayTypes?.map(\.schedule) == [.fixed, .flexible, .default])
        #expect(plan.dayTypes?.first?.weekdays == Weekdays([1, 3, 5]))
        #expect(plan.dayTypes?[1].perWeek == 2)
        #expect(plan.dayTypes?[1].workouts == ["tennis"])
        #expect(plan.phases?.map(\.id) == ["1", "2"])
        let first = plan.phases?.first
        #expect(first?.start == planImportDay("2030-01-07"))
        #expect(first?.startApprox == false)
        #expect(first?.end == planImportDay("2030-05-31"))
        #expect(first?.endApprox == true)
        #expect(first?.rate == 0.1...0.2)
        #expect(first?.review == 82...83)
        #expect(first?.typeOrder == ["gym", "tennis", "rest"])
        #expect(first?.byType["tennis"] == SettingsPlanDraft.Targets(calories: 2800, protein: 160, carbs: 378, fat: 72))
        let second = plan.phases?.last
        #expect(second?.goal == .lose)
        #expect(second?.start == planImportDay("2030-06-01"))
        #expect(second?.end == planImportDay("2030-08-31"))
        #expect(second?.startApprox == true)
        #expect(second?.targetBodyFat == 14)
        #expect(second?.hasTargets == false)
        #expect(plan.checkIn.weekday == 1)
        #expect(plan.checkIn.windowDays == 14...21)
        #expect(plan.checkIn.step == 100...150)
        #expect(plan.measure.weighInMinutes == 7 * 60)
        #expect(plan.measure.weeklySites == [.waist])
        #expect(plan.measure.fullSites == [.waist, .chest, .arm, .thigh, .hip])
        #expect(plan.measure.fullEveryWeeks == 8)
        #expect(plan.measure.bodyFatEveryWeeks == 8)
        #expect(plan.checks?.map(\.id) == ["creatine"])
        #expect(plan.checks?.first?.dose == "3-5 g")
        #expect(plan.checks?.first?.timing == .meal("breakfast"))
        #expect(plan.checks?.first?.isOptional == true)
        #expect(plan.mealProtein == 35...45)
        #expect(plan.proteinMeals == SettingsPlanDraft.ProteinMealCount(count: 4, names: []))
        #expect(plan.notes?.count == 3)
        #expect(plan.hasPlanRows)
        #expect(!draft.isEmpty)
    }

    @Test func importSetsUpThePlan() throws {
        let result = Self.imported()
        #expect(result.notes.isEmpty, "\(result.notes)")
        let plan = try #require(result.plan)
        #expect(plan.isSetUp)
        #expect(plan.dayTypes.map(\.emoji) == ["🏋️", "🎾", "🛋️"])
        #expect(plan.dayTypes.map(\.workouts) == [["strength"], ["tennis"], []])

        // A start today counts as the confirmation; the later phase stays planned.
        let first = try #require(plan.phase(id: "1"))
        #expect(first.startedAt == planImportNow)
        #expect(first.status == .active)
        #expect(first.maxWaistGainCm == 4)
        #expect(first.rateRange == 0.1...0.2)
        #expect(first.reviewMin == 82 && first.reviewMax == 83)
        let second = try #require(plan.phase(id: "2"))
        #expect(second.startedAt == nil)
        #expect(second.status == .planned)
        #expect(second.startApprox && second.endApprox)
        #expect(second.revisions.isEmpty) // targets are proposed when it starts
        #expect(second.targetWeight == 78)
        #expect(plan.activePhase(on: Self.today)?.id == "1")

        // Flat targets are the phase's baseline; each day type has its own, the rest from the baseline.
        let revision = try #require(plan.revision(on: Self.today))
        #expect(revision.from == Self.today)
        #expect(revision.reason == "import")
        let baseline = try #require(revision.baseline)
        #expect(baseline.energy == 2600 && baseline.protein == 160 && baseline.carbs == 328 && baseline.fat == 72)
        #expect(baseline.fiber == 30 && baseline.water == 2500)
        let tennis = try #require(revision.byType["tennis"])
        #expect(tennis.energy == 2800 && tennis.carbs == 378 && tennis.fiber == 30 && tennis.water == 2500)
        #expect(revision.byType["rest"]?.energy == 2400)
        #expect(plan.plannedWeekAverage(revision) == 2600)

        // The profile mirrors the plan: the default type's targets, training = the fixed type.
        #expect(result.state.targets.energy == 2400)
        #expect(result.state.trainingTargets?.energy == 2600)
        #expect(result.state.trainingDays == Weekdays([1, 3, 5]))
        #expect(result.state.goal == .gain)
        #expect(abs(result.state.ratePerWeek - 0.15) < 0.0001)
        #expect(result.state.targetWeight == 83)

        // A new long-term goal counts from the import day.
        #expect(plan.longTerm == CoachPlan.LongTerm(weightKg: 78, bodyFat: 14, note: "Leaner and stronger", since: Self.today))
        #expect(plan.protein == CoachPlan.Protein(mealMin: 35, mealMax: 45, count: 4))
        let creatine = try #require(plan.check(id: "creatine"))
        #expect(creatine.timing == .meal("breakfast"))
        #expect(creatine.affectsWeight)
        #expect(creatine.isOptional)
        #expect(plan.routine.fullSites == [.waist, .chest, .arm, .thigh, .hip])
        #expect(plan.routine.checkInWeekday == 1)
        #expect(plan.adjust.windowMinDays == 14 && plan.adjust.windowMaxDays == 21)
        #expect(plan.notes.count == 3)

        // Today's body values and the preview.
        #expect(result.bodyRecords == [SettingsBodyRecord(day: Self.today, kind: .assessment, values: BodyValues([BodyValues.bodyFatKey: 20]), method: .estimate)])
        #expect(result.bodyRecords.first?.importKey == "settings:2030-01-07:assessment")
        #expect(result.newWeight == 80)
        #expect(result.hasChanges)
        #expect(result.changes.first?.title == "Weight (logged today)")
        #expect(result.changes.contains { $0.title == "Body fat (today)" && $0.group == .body })
        #expect(result.changes.contains { $0.title == "Calories" && $0.old == "2000 kcal" && $0.new == "2600 kcal" })
        #expect(result.changes.contains { $0.title == "Phase 1 · Tennis days" && $0.new == "2800 kcal · 160/378/72 g" })
        #expect(!result.changes.contains { $0.title == "Goal" }) // shown with the phase
        let titles = result.sections.map(\.title)
        for title in ["Body", "Targets", "Day types (3)", "Phases (2)", "Daily checks (1)", "Measuring", "Long-term goal", "Notes", "Not supported"] {
            #expect(titles.contains(title), "\(titles)")
        }
        #expect(result.sections.last?.changes.map(\.title) == ["Show a shopping list for my week"])
    }

    @Test func exportReadsBackWithAPlan() throws {
        let first = Self.imported()
        let text = SettingsCSV.export(first.state, today: Self.today)
        #expect(text.contains("phase.1.tennis.macros_g,160/378/72"))
        #expect(text.contains("rate_kg_per_week,0.1-0.2"))
        #expect(text.contains("calories,2600")) // the baseline, not the mirrored rest-day targets
        #expect(!text.contains("training_days"))
        let draft = SettingsCSV.parse(text)
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        let later = planImportNow.addingTimeInterval(3600)
        let again = Self.imported(text, to: first.state, now: later)
        #expect(again.changes.isEmpty, "\(again.changes)")
        #expect(again.notes.isEmpty, "\(again.notes)")
        #expect(again.bodyRecords.isEmpty)
        #expect(!again.hasChanges)
        var expected = first.state
        expected.meals.sort { $0.minutes < $1.minutes } // the import keeps meals in time order
        #expect(again.state == expected)
        #expect(again.plan?.longTerm.since == Self.today)

        // Months later, with phase 2 due but not confirmed: re-importing doesn't start it.
        let june = planImportDay("2030-06-03")
        let juneText = SettingsCSV.export(first.state, today: june)
        #expect(SettingsCSV.parse(juneText).skipped.isEmpty)
        let inJune = Self.imported(juneText, to: first.state, today: june, now: later)
        #expect(inJune.changes.isEmpty, "\(inJune.changes)")
        #expect(inJune.plan?.phase(id: "2")?.isStarted == false)
        // The unchanged goal keeps its day; a new goal weight counts from the day it came in.
        #expect(inJune.plan?.longTerm.since == Self.today)
        let lighter = Self.imported("setting,value\nlong_term.weight_kg,77\n", to: first.state, today: june, now: later)
        #expect(lighter.plan?.longTerm.weightKg == 77)
        #expect(lighter.plan?.longTerm.since == june)
    }

    @Test func groupsReplaceAndListRemovals() throws {
        let first = Self.imported()
        let text = """
        setting,value
        day_type.gym.name,Gym
        day_type.gym.days,mon;thu
        day_type.rest.name,Rest
        day_type.rest.days,default
        note,Only this note now.
        """
        let result = Self.imported(text, to: first.state, today: planImportDay("2030-01-08"))
        let plan = try #require(result.plan)
        #expect(plan.dayTypes.map(\.id) == ["gym", "rest"])
        #expect(plan.phases.count == 2) // not in the file: unchanged
        #expect(plan.notes == ["Only this note now."])
        #expect(result.changes.contains { $0.group == .dayTypes && $0.title == "Tennis" && $0.isRemoval })
        #expect(result.changes.contains { $0.group == .dayTypes && $0.title == "Gym" && $0.new.contains("Mon, Thu") })
        #expect(result.changes.contains { $0.group == .notes && $0.isRemoval })
        #expect(result.sections.contains { $0.title == "Day types (2)" })
        // The mirror follows: Gym is now on Mon and Thu.
        #expect(result.state.trainingDays == Weekdays([1, 4]))
    }

    @Test func flatTargetsGoToTheActivePhaseFromToday() throws {
        let first = Self.imported()
        let nextWeek = planImportDay("2030-01-14")
        let result = Self.imported("setting,value\ncalories,2700\nprotein_g,160\ncarbs_g,353\nfat_g,72\n", to: first.state, today: nextWeek)
        let plan = try #require(result.plan)
        #expect(plan.revision(on: nextWeek)?.baseline?.energy == 2700)
        #expect(plan.revision(on: nextWeek)?.byType["gym"]?.energy == 2600) // own targets stay
        #expect(plan.revision(on: planImportDay("2030-01-10"))?.baseline?.energy == 2600) // past days keep theirs
        #expect(result.changes.map(\.title) == ["Calories", "Carbohydrates"], "\(result.changes)")
        #expect(result.state.targets.energy == 2400) // the mirror is still the rest day
    }

    @Test func flatRateAndGoalMoveTheActivePhase() throws {
        let first = Self.imported()
        let result = Self.imported("setting,value\nrate_kg_per_week,0.15 to 0.25\ntarget_weight_kg,84\n", to: first.state)
        let phase = try #require(result.plan?.phase(id: "1"))
        #expect(phase.rateRange == 0.15...0.25)
        #expect(phase.targetWeight == 84)
        #expect(result.state.targetWeight == 84)
        #expect(result.changes.contains { $0.title == "Phase 1 · Rate" && $0.new == "0.15–0.25 kg/week" })
    }

    @Test func withoutAPlanTheRangeMidpointGoesToTheProfile() {
        let result = SettingsCSV.apply(SettingsCSV.parse("setting,value\ngoal,gain\nrate_kg_per_week,0.1–0.2\n"), to: SettingsState(), year: 2030,
                                       today: planImportDay("2030-01-07"))
        #expect(result.state.ratePerWeek == 0.15)
        #expect(result.plan == nil)
        #expect(result.changes.contains { $0.title == "Pace" && $0.new == "0.15 kg/week" })
        for text in ["0.15", "0.1-0.2", "0.1–0.2", "0.1 to 0.2", "0,1 - 0,2", "+0.1 to +0.2 kg/week"] {
            let range = SettingsCSV.planRange(text, 0.05...1.0)
            #expect(range != nil, "\(text)")
        }
        let tooSlow = SettingsCSV.parse("setting,value\nrate_kg_per_week,0.02\nphase.1.rate_kg_per_week,1.5\nphase.2.rate_kg_per_week,0\n")
        #expect(tooSlow.skipped.count == 2, "\(tooSlow.skipped)")
        #expect(tooSlow.plan.phases?.first { $0.id == "2" }?.rate == 0...0)
    }

    @Test func percentRatesUseTheWeight() {
        let text = "setting,value\nweight_kg,80\nphase.1.goal,lose\nphase.1.start,2030-01-07\nphase.1.rate_percent_per_week,0.5-0.75\n"
        let result = Self.imported(text)
        #expect(result.plan?.phase(id: "1")?.rateRange == 0.4...0.6)
    }

    @Test func datesWithMonthsAndApproximations() {
        #expect(SettingsCSV.planDate("2030-04", end: false)?.day == planImportDay("2030-04-01"))
        #expect(SettingsCSV.planDate("2030-04", end: true)?.day == planImportDay("2030-04-30"))
        #expect(SettingsCSV.planDate("~2030-02", end: true)?.day == planImportDay("2030-02-28"))
        #expect(SettingsCSV.planDate("~2030-02", end: true)?.approx == true)
        #expect(SettingsCSV.planDate("2032-02", end: true)?.day == planImportDay("2032-02-29"))
        #expect(SettingsCSV.planDate("about April 2030", end: false)?.day == planImportDay("2030-04-01"))
        #expect(SettingsCSV.planDate("about April 2030", end: false)?.approx == true)
        #expect(SettingsCSV.planDate("07.01.2030", end: false)?.day == planImportDay("2030-01-07"))
        #expect(SettingsCSV.planDate("2030-01-07", end: false)?.approx == false)
        #expect(SettingsCSV.planDate("soon", end: false) == nil)
    }

    @Test func validationNotes() {
        let text = """
        setting,value
        day_type.gym.days,mon;wed;fri
        day_type.tennis.days,flexible
        day_type.rest.days,default
        day_type.run.days,flexible
        day_type.swim.days,flexible
        phase.1.start,2030-01-07
        phase.1.end,2030-06-15
        phase.1.tennis.calories,2800
        phase.1.tennis.macros_g,160/450/72
        phase.1.gymm.calories,2600
        phase.2.start,2030-06-01
        check.fish.days,gym;sauna
        """
        let draft = SettingsCSV.parse(text)
        #expect(draft.skipped.contains("day_type.swim: only 4 day types fit"), "\(draft.skipped)")
        #expect(draft.skipped.contains("phase.1.gymm.calories: gymm isn't a day type"), "\(draft.skipped)")
        #expect(draft.skipped.contains("check.fish.days: sauna isn't a day type"), "\(draft.skipped)")
        #expect(draft.plan.checks?.first?.days == .dayTypes(["gym"]))
        let result = Self.imported(text)
        #expect(result.notes.contains("phase.1.tennis: macros add up to 3,088 kcal, not 2,800"), "\(result.notes)")
        #expect(result.notes.contains { $0.contains("overlap") }, "\(result.notes)")
        #expect(result.plan?.phase(id: "1")?.end == planImportDay("2030-05-31"))
        #expect(result.plan?.dayTypes.count == 4)
        #expect(result.plan?.dayTypes.first { $0.id == "run" }?.emoji == "🏃")

        // Without day_type rows the ids are checked against the plan there is.
        let first = Self.imported()
        let later = Self.imported("setting,value\nphase.1.start,2030-01-07\nphase.1.gymm.calories,2600\n", to: first.state)
        #expect(later.notes.contains("phase.1.gymm.calories: gymm isn't a day type"), "\(later.notes)")
    }

    @Test func legacyTrainingDaysBecomeADayType() throws {
        let text = "setting,value\ncalories,2500\nprotein_g,150\ncarbs_g,300\nfat_g,80\ntraining_days,mon;thu\ntraining_extra_kcal,300\nphase.1.goal,gain\nphase.1.start,2030-01-07\nphase.1.rate_kg_per_week,0.25\n"
        let result = Self.imported(text)
        let plan = try #require(result.plan)
        #expect(plan.dayTypes.map(\.id) == ["training", "rest"])
        #expect(plan.dayType(id: "training")?.weekdays == Weekdays([1, 4]))
        let revision = try #require(plan.revision(on: Self.today))
        #expect(revision.byType["training"]?.energy == 2800)
        #expect(revision.byType["training"]?.carbs == 353) // 300 g + 70 % of 300 kcal
        #expect(revision.byType["rest"]?.energy == 2500)
        #expect(result.state.trainingTargets?.energy == 2800)

        // With day_type rows the legacy keys are skipped with a note.
        let typed = Self.imported(text + "day_type.gym.days,mon;wed\nday_type.rest.days,default\n")
        #expect(typed.notes.contains("training_days: skipped – the day_type rows set the day types"), "\(typed.notes)")
        #expect(typed.plan?.dayTypes.map(\.id) == ["gym", "rest"])
    }

    @Test func aProfileWithTrainingDaysIsMigrated() throws {
        var start = SettingsState(sex: .female, goal: .lose, ratePerWeek: 0.4, targets: DailyTargets(energy: 1800, protein: 120, carbs: 180, fat: 60),
                                  trainingDays: Weekdays([2, 4]))
        start.trainingTargets = SettingsState.training(start.targets, extra: 200)
        let result = Self.imported("setting,value\ncheck.vitd.name,Vitamin D\nday_type.training.name,Training\nday_type.training.days,tue;thu\nday_type.rest.days,default\n", to: start)
        let plan = try #require(result.plan)
        // One open-ended phase from the profile goal, started today, with the old training targets.
        let phase = try #require(plan.phase(id: "1"))
        #expect(phase.goal == .lose)
        #expect(phase.isStarted)
        #expect(phase.end == nil)
        #expect(plan.revision(on: Self.today)?.byType["training"]?.energy == 2000)
        #expect(plan.revision(on: Self.today)?.byType["rest"]?.energy == 1800)
        #expect(plan.routine.weeklySites == [.waistNarrow])
        #expect(result.state.targets.energy == 1800)
        #expect(result.state.trainingTargets?.energy == 2000)
        #expect(plan.check(id: "vitd")?.name == "Vitamin D")
    }

    @Test func bodyRowsAreTodaysBaseline() {
        let text = "setting,value\nbody_fat_percent,22\nbody_fat_method,InBody\nwaist_cm,90\nOberarm,34\nhüfte,100\nwade,40\n"
        let result = Self.imported(text, to: SettingsState())
        #expect(result.plan == nil) // body values alone don't make a plan
        #expect(result.bodyRecords.count == 2)
        #expect(result.bodyRecords.first?.method == .biaPro)
        #expect(result.bodyRecords.last?.kind == .tape)
        #expect(result.bodyRecords.last?.values.sites == [.waist: 90, .arm: 34, .hip: 100, .calf: 40])
        #expect(result.hasChanges)
        #expect(result.changes.map(\.title) == ["Body fat (today)", "Waist (today)", "Hip (today)", "Arm (today)", "Calf (today)"])
        // Unticked in the preview: the body fat and the waist.
        let fewer = result.removingBodyValues(["bodyFat", "waist"])
        #expect(fewer.bodyRecords.map(\.kind) == [.tape])
        #expect(fewer.bodyRecords.first?.values.sites == [.arm: 34, .hip: 100, .calf: 40])
        #expect(fewer.changes.map(\.title) == ["Hip (today)", "Arm (today)", "Calf (today)"])
        #expect(!result.removingBodyValues(["bodyFat", "waist", "arm", "hip", "calf"]).hasChanges)
        let bad = SettingsCSV.parse("setting,value\nwaist_cm,500\nbody_fat_method,crystal ball\n")
        #expect(bad.skipped.count == 2)
    }

    @Test func notesAreNotWishesAnyMore() throws {
        let result = Self.imported("setting,value\nnote,Walk after dinner.\nnot_supported,Track my allergies\n", to: SettingsState())
        let plan = try #require(result.plan)
        #expect(plan.notes == ["Walk after dinner."])
        #expect(!plan.isSetUp) // notes alone set nothing else up
        #expect(result.wishes == ["Track my allergies"])
        #expect(result.state.targets == DailyTargets.standard)
        #expect(result.changes.map(\.title) == ["Note 1"])
    }

    @Test func keysAreForgiving() throws {
        let text = """
        Setting;Value
        Day Type.Gym Day.Name;Gym
        Day Type.Gym Day.Days;Mo, Mi, Fr
        Day-Type.Rest.Days;default
        PHASE.1.START;2030-01-07
        PHASE.1.GYMDAY.KCAL;2600
        Phase 1 Rest Macros;150/250/70
        supplement.vitd.name;Vitamin D
        supplement.vitd.when;08:00
        supplement.vitd.days;gymday
        check-in.day;thu
        Long-term.Waist;82
        measure.side;links
        measure.body_fat_method;navy
        protein_meals;3;Frühstück;Mittagessen;Abendessen
        meal_protein_g;30
        """
        let draft = SettingsCSV.parse(text)
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        #expect(draft.plan.dayTypes?.map(\.id) == ["gymday", "rest"])
        #expect(draft.plan.dayTypes?.first?.weekdays == Weekdays([1, 3, 5]))
        #expect(draft.plan.phases?.first?.byType["gymday"]?.calories == 2600)
        #expect(draft.plan.phases?.first?.byType["rest"] == SettingsPlanDraft.Targets(protein: 150, carbs: 250, fat: 70))
        #expect(draft.plan.checks?.first?.timing == .time(8 * 60))
        #expect(draft.plan.checks?.first?.days == .dayTypes(["gymday"]))
        #expect(draft.plan.checkIn.weekday == 4)
        #expect(draft.plan.longTerm.waistCm == 82)
        #expect(draft.plan.measure.side == .left)
        #expect(draft.plan.measure.bodyFatMethod == .some(.navy))
        #expect(draft.plan.proteinMeals == SettingsPlanDraft.ProteinMealCount(count: 3, names: ["Frühstück", "Mittagessen", "Abendessen"]))
        #expect(draft.plan.mealProtein == 30...30)
        let result = Self.imported(text)
        let plan = try #require(result.plan)
        #expect(plan.protein.meals == ["breakfast", "lunch", "dinner"])
        #expect(plan.protein.mealMax == 0)
        // Rest macros only: the calories follow (150×4 + 250×4 + 70×9 = 2230).
        #expect(plan.revision(on: Self.today)?.byType["rest"]?.energy == 2230)
        let unknown = SettingsCSV.parse("setting,value\nphase.1.colour,blue\ncheck.fish\n")
        #expect(unknown.skipped == ["phase.1.colour: not a setting Nina knows", "check.fish: not a setting Nina knows"])
    }

    @Test func aMaintainPhaseReadsBack() throws {
        // Setting up a plan from a maintain profile whose old pace was 0.5 kg/week.
        let start = SettingsState(sex: .male, goal: .maintain, ratePerWeek: 0.5)
        let first = Self.imported("setting,value\nday_type.gym.days,mon;wed;fri\nday_type.rest.days,default\n", to: start)
        #expect(first.plan?.phase(id: "1")?.goal == .maintain)
        #expect(first.plan?.phase(id: "1")?.rateRange == 0...0)
        let text = SettingsCSV.export(first.state, today: Self.today)
        #expect(text.contains("phase.1.rate_kg_per_week,0"))
        #expect(!text.split(separator: "\n").contains { $0.hasPrefix("rate_kg_per_week,") }) // the profile's old pace
        let again = Self.imported(text, to: first.state, now: planImportNow.addingTimeInterval(3600))
        #expect(again.changes.isEmpty, "\(again.changes)")
        #expect(!again.hasChanges)
        #expect(again.plan?.phase(id: "1")?.rateRange == 0...0)
        #expect(WeightSignal.range(for: try #require(again.plan?.phase(id: "1"))) == -0.1...0.1)

        // A fresh file with a flat pace and a maintain phase: the pace isn't the phase's band.
        let file = "setting,value\ngoal,maintain\nrate_kg_per_week,0.5\nphase.1.goal,maintain\nphase.1.start,2030-01-07\n"
        let fresh = Self.imported(file, to: start)
        #expect(fresh.plan?.phase(id: "1")?.rateRange == 0...0)
        let back = Self.imported(SettingsCSV.export(fresh.state, today: Self.today), to: fresh.state)
        #expect(back.changes.isEmpty, "\(back.changes)")
        // Its own rate row still sets a band.
        let band = Self.imported(file + "phase.1.rate_kg_per_week,0.2\n", to: start)
        #expect(band.plan?.phase(id: "1")?.rateRange == 0.2...0.2)
    }

    @Test func aBackDatedStartKeepsThePastTargets() throws {
        // Profile targets of 2200 kcal; on 7 Jan a file confirms a phase that began on ~1 Dec.
        let profile = DailyTargets(energy: 2200, protein: 120, carbs: 250, fat: 70)
        let start = SettingsState(sex: .male, goal: .gain, targets: profile)
        let text = "setting,value\nphase.1.goal,gain\nphase.1.start,~2029-12\ncalories,2600\nprotein_g,160\ncarbs_g,328\nfat_g,72\n"
        let result = Self.imported(text, to: start)
        let plan = try #require(result.plan)
        let phase = try #require(plan.phase(id: "1"))
        #expect(phase.start == planImportDay("2029-12-01"))
        #expect(phase.isStarted)
        #expect(phase.revisions.map(\.from) == [planImportDay("2029-12-01"), Self.today])
        #expect(phase.revisions.first?.reason == SettingsCSV.keptRevisionReason)
        let fallback = result.state.targets
        #expect(plan.targets(on: planImportDay("2029-12-15"), marks: [:], fallback: fallback, calendar: planImportUTC).energy == 2200)
        #expect(plan.targets(on: planImportDay("2030-01-06"), marks: [:], fallback: fallback, calendar: planImportUTC).energy == 2200)
        #expect(plan.targets(on: Self.today, marks: [:], fallback: fallback, calendar: planImportUTC).energy == 2600)
        // The export and import again change nothing.
        let again = Self.imported(SettingsCSV.export(result.state, today: Self.today), to: result.state)
        #expect(again.changes.isEmpty, "\(again.changes)")

        // A next phase that began before today while another runs: the running one's last weeks
        // keep its day types' targets; the new phase's own targets start today.
        let first = Self.imported()
        let march = planImportDay("2030-03-11")
        let next = "setting,value\nphase.1.goal,gain\nphase.1.start,2030-01-07\nphase.2.goal,maintain\nphase.2.start,2030-03-01\nphase.2.calories,2700\nphase.2.macros_g,160/353/72\n"
        let switched = Self.imported(next, to: first.state, today: march)
        let both = try #require(switched.plan)
        #expect(both.phase(id: "1")?.status == .done)
        #expect(both.phase(id: "1")?.end == planImportDay("2030-02-28"))
        #expect(both.activePhase(on: planImportDay("2030-03-05"))?.id == "2")
        let rest = switched.state.targets
        #expect(both.targets(on: planImportDay("2030-03-05"), marks: [:], fallback: rest, calendar: planImportUTC).energy == 2400) // Tue: rest
        #expect(both.targets(on: planImportDay("2030-03-06"), marks: [:], fallback: rest, calendar: planImportUTC).energy == 2600) // Wed: gym
        #expect(both.targets(on: march, marks: [:], fallback: rest, calendar: planImportUTC).energy == 2700)
        // Without targets of its own the new phase has none from today (the transition proposal
        // fills them), but its past days keep theirs.
        let bare = Self.imported("setting,value\nphase.1.goal,gain\nphase.1.start,2030-01-07\nphase.2.goal,maintain\nphase.2.start,2030-03-01\n",
                                 to: first.state, today: march)
        let empty = try #require(bare.plan?.phase(id: "2"))
        #expect(empty.revision(on: planImportDay("2030-03-05"))?.byType["rest"]?.energy == 2400)
        #expect(empty.revision(on: march)?.baseline == nil)
        #expect(empty.revision(on: march)?.byType.isEmpty == true)
    }

    @Test func importedTargetsReplaceAChangePlannedForLater() throws {
        // "Apply from tomorrow" (+100), then the same day an import with new targets.
        var state = Self.imported().state
        state.plan = state.plan?.applyingDelta(100, from: planImportDay("2030-01-08"), weightKg: 80, fallback: state.targets)
        let result = Self.imported("setting,value\ncalories,2500\nprotein_g,160\ncarbs_g,303\nfat_g,72\n", to: state)
        let plan = try #require(result.plan)
        #expect(plan.revision(on: planImportDay("2030-01-08"))?.baseline?.energy == 2500)
        #expect(plan.phase(id: "1")?.revisions.map(\.reason) == ["import"])
        #expect(result.notes.contains("phase.1: these targets replace the change planned from 2030-01-08"), "\(result.notes)")
        // The same with the phase's own rows.
        let rows = "setting,value\nphase.1.goal,gain\nphase.1.start,2030-01-07\nphase.1.gym.calories,2700\nphase.1.gym.macros_g,160/353/72\n"
        let own = Self.imported(rows, to: state)
        #expect(own.plan?.revision(on: planImportDay("2030-01-08"))?.byType["gym"]?.energy == 2700)
        #expect(own.notes.contains("phase.1: these targets replace the change planned from 2030-01-08"), "\(own.notes)")
        // Re-importing the unchanged export keeps the planned change.
        let same = Self.imported(SettingsCSV.export(state, today: Self.today), to: state)
        #expect(same.changes.isEmpty, "\(same.changes)")
        #expect(same.plan?.revision(on: planImportDay("2030-01-08"))?.reason == "adjust:+100")
    }

    @Test func checkTimesAreOnlyRealTimes() throws {
        #expect(SettingsCSV.checkTiming("Snack 2") == .meal("Snack 2"))
        #expect(SettingsCSV.checkTiming("5 g with breakfast") == .meal("breakfast"))
        #expect(SettingsCSV.checkTiming("2.5 g at lunch") == .meal("lunch"))
        #expect(SettingsCSV.checkTiming("with breakfast") == .meal("breakfast"))
        #expect(SettingsCSV.checkTiming("vor dem Frühstück") == .meal("Frühstück"))
        #expect(SettingsCSV.checkTiming("08:00") == .time(8 * 60))
        #expect(SettingsCSV.checkTiming("7.30") == .time(7 * 60 + 30))
        #expect(SettingsCSV.checkTiming("7 am") == .time(7 * 60))
        #expect(SettingsCSV.checkTiming("9pm") == .time(21 * 60))
        #expect(SettingsCSV.checkTiming("19 Uhr") == .time(19 * 60))
        #expect(SettingsCSV.checkTiming("21h") == .time(21 * 60))
        #expect(SettingsCSV.checkTiming("anytime") == .anytime)
        // The weigh-in time still takes a bare hour.
        #expect(SettingsCSV.clockTime(in: "7") == 7 * 60)
        #expect(SettingsCSV.clockTime(in: "7", strict: true) == nil)

        // A meal with a number in its name reads back as that meal.
        var state = SettingsState(sex: .male)
        state.meals.append(MealSlot(id: "meal-snack-2", name: "Snack 2", emoji: "🍎", minutes: 21 * 60))
        let result = Self.imported("setting,value\ncheck.late.name,Casein\ncheck.late.when,Snack 2\ncheck.fish.name,Fish oil\ncheck.fish.when,2 g with dinner\n",
                                   to: state)
        let plan = try #require(result.plan)
        #expect(plan.check(id: "late")?.timing == .meal("meal-snack-2"))
        #expect(plan.check(id: "fish")?.timing == .meal("dinner"))
        let text = SettingsCSV.export(result.state, today: Self.today)
        #expect(text.contains("check.late.when,Snack 2"))
        #expect(Self.imported(text, to: result.state).changes.isEmpty)
    }

    @Test func trainingExtraWithAPlanSaysWhy() {
        let first = Self.imported()
        let result = Self.imported("setting,value\ntraining_extra_kcal,200\n", to: first.state)
        #expect(result.notes == ["training_extra_kcal: your plan's day types set the calories – use phase.N.<type>.calories rows"], "\(result.notes)")
        #expect(!result.hasChanges)
    }

    @Test func previewLinesHaveUniqueIDs() throws {
        let first = Self.imported()
        // A new day type with an old one's name, and two checks with the same name.
        let text = """
        setting,value
        day_type.strength.name,Gym
        day_type.strength.days,mon;wed;fri
        day_type.tennis.name,Tennis
        day_type.tennis.days,flexible
        day_type.rest.days,default
        check.vitd.name,Vitamin D
        check.vitd2.name,Vitamin D
        not_supported,A wish
        not_supported,A wish
        """
        let result = Self.imported(text, to: first.state)
        let gym = result.changes.filter { $0.group == .dayTypes && $0.title == "Gym" }
        #expect(gym.count == 2 && gym.contains { $0.isRemoval })
        let ids = result.sections.flatMap(\.changes).map(\.id)
        #expect(Set(ids).count == ids.count, "\(ids)")
    }

    @Test func numbersReadBackExactly() throws {
        let first = Self.imported()
        var state = first.state
        var plan = try #require(state.plan)
        plan.longTerm.weightKg = 78.25
        plan.longTerm.bodyFat = 14.25
        plan.phases[0].targetWeight = 83.25
        plan.phases[0].reviewMin = 82
        plan.phases[0].reviewMax = 0
        plan.phases[1].reviewMin = 0
        plan.phases[1].reviewMax = 79.5
        plan.phases[1].targetBodyFat = 14.25
        plan.dayTypes[0].emoji = ""
        plan.checks[0].emoji = ""
        state.plan = plan
        state.targetWeight = 83.25 // the mirror of the active phase
        let text = SettingsCSV.export(state, today: Self.today)
        #expect(text.contains("long_term.weight_kg,78.25"))
        #expect(text.contains("phase.1.target_weight_kg,83.25"))
        #expect(text.contains("phase.1.review_weight_kg,82\n"))
        #expect(text.contains("phase.2.review_weight_kg,79.5"))
        #expect(SettingsCSV.parse(text).skipped.isEmpty, "\(SettingsCSV.parse(text).skipped)")
        let again = Self.imported(text, to: state, now: planImportNow.addingTimeInterval(3600))
        #expect(again.changes.isEmpty, "\(again.changes)")
        var expected = state
        expected.meals.sort { $0.minutes < $1.minutes }
        #expect(again.state == expected)
    }

    @Test func approximateNumbersAndUnitsInBrackets() {
        let about = SettingsCSV.parse("setting,value\nbody_fat_percent,~20\nwaist_cm,ca. 90\nphase.1.target_weight_kg,~83\nlong_term.weight_kg,about 78\n")
        #expect(about.skipped.isEmpty, "\(about.skipped)")
        #expect(about.plan.bodyFat == 20)
        #expect(about.plan.tape[.waist] == 90)
        #expect(about.plan.phases?.first?.targetWeight == 83)
        #expect(about.plan.longTerm.weightKg == 78)

        let labels = SettingsCSV.parse("Einstellung,Wert\nBrustumfang (cm),100\nHals (cm),39\nHüftumfang (cm),98\nBauchumfang (cm),90\nKFA (%),20\nGewicht (kg),80\n")
        #expect(labels.skipped.isEmpty, "\(labels.skipped)")
        #expect(labels.plan.tape == [.chest: 100, .neck: 39, .hip: 98, .waist: 90])
        #expect(labels.plan.bodyFat == 20)
        #expect(labels.weightKg == 80)
        // A unit that doesn't fit the setting isn't guessed.
        #expect(SettingsCSV.parse("setting,value\nHals (kg),39\n").skipped == ["Hals (kg): not a setting Nina knows"])
    }

    @Test func importedTapeIsAStandardBaseline() throws {
        let result = Self.imported("setting,value\nwaist_cm,90\nneck_cm,39\nbody_fat_percent,20\n", to: SettingsState(sex: .male, heightCm: 180))
        let tape = try #require(result.bodyRecords.first { $0.kind == .tape })
        #expect(tape.conditions == "morning,fasted")
        #expect(result.bodyRecords.first { $0.kind == .assessment }?.conditions == "")
        let record = try #require(tape.tapeRecord)
        #expect(record.isStandard)
        #expect(GirthTrend.readings(.waist, in: [record]).count == 1)
        let estimate = NavyBodyFat.estimate(formula: .male, heightCm: 180, records: [record], calendar: planImportUTC).estimate
        #expect(estimate.map { ($0.bodyFat * 10).rounded() / 10 } == 19.1)
    }

    @Test func promptsExplainThePlan() {
        let prompt = SettingsCSV.prompt(appName: "Nina")
        let setup = SetupPrompt.text(appName: "Nina")
        for key in SettingsCSV.planKeys {
            #expect(prompt.contains("| \(key.name) |"), "\(key.name)")
            #expect(setup.contains("| \(key.name) |"), "\(key.name)")
        }
        for text in [prompt, setup] {
            #expect(text.contains("Coach plan"))
            #expect(text.contains("phase.1.gym.macros_g,160/328/72"))
            #expect(text.contains("not_supported is only for real wishes"))
        }
        // The example reads without a skipped row or a note.
        let example = SettingsCSV.planExample.joined(separator: "\n")
        let draft = SettingsCSV.parse(example)
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
        let result = Self.imported(example)
        #expect(result.notes.isEmpty, "\(result.notes)")
        #expect(result.plan?.phases.count == 2)
    }
}
