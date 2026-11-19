import Foundation
import Testing
@testable import NinaCore

// Made-up numbers, nothing from a real person: gym Mon/Wed/Fri 2600 kcal, rest 2400 (protein
// 160 g); a gain phase started Mon 2030-01-07.

private var editsUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func editsDay(_ raw: String) -> DayKey { DayKey(raw)! }

private enum EditsFixture {
    static let gym = DailyTargets(energy: 2600, protein: 160, carbs: 310, fat: 80)
    static let rest = DailyTargets(energy: 2400, protein: 160, carbs: 260, fat: 80)
    static let start = editsDay("2030-01-07")

    static func plan(revisions: [CoachPlan.Revision]? = nil) -> CoachPlan {
        CoachPlan(
            dayTypes: [
                .init(id: "gym", name: "Gym", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
                .init(id: "rest", name: "Rest", schedule: .default),
            ],
            phases: [
                .init(id: "1", name: "Lean gain", goal: .gain, start: start, rateMin: 0.1, rateMax: 0.2,
                      startedAt: start.date(calendar: editsUTC), status: .active,
                      revisions: revisions ?? [.init(from: start, baseline: rest, byType: ["gym": gym, "rest": rest], reason: "import")]),
            ]
        )
    }
}

@Suite("Plan editor changes")
struct PlanEditsTests {
    @Test func idsAreLowercaseLettersAndDigitsAndUnique() {
        #expect(PlanEdits.newID(for: "Gym", existing: []) == "gym")
        #expect(PlanEdits.newID(for: "Gym", existing: ["gym"]) == "gym2")
        #expect(PlanEdits.newID(for: "gym", existing: ["gym", "gym2"]) == "gym3")
        #expect(PlanEdits.newID(for: "Käse-Tag 2", existing: []) == "kasetag2")
        #expect(PlanEdits.newID(for: "🎾", existing: [], fallback: "day") == "day")
        #expect(PlanEdits.newID(for: "", existing: ["check"], fallback: "check") == "check2")
    }

    @Test func newDayTypesAreFlexibleAndRestIsTheDefault() throws {
        let gym = try #require(PlanEdits.addingDayType(named: "Gym", to: CoachPlan()))
        #expect(gym.id == "gym")
        #expect(gym.plan.dayType(id: "gym")?.schedule == .flexible)
        #expect(gym.plan.dayType(id: "gym")?.emoji == "🏋️")
        let rest = try #require(PlanEdits.addingDayType(named: "Rest", to: gym.plan))
        #expect(rest.plan.dayType(id: "rest")?.schedule == .default)
        #expect(rest.plan.dayType(id: "rest")?.emoji == "🛋️")
        let second = try #require(PlanEdits.addingDayType(named: " Tennis ", to: rest.plan))
        let tennis = try #require(second.plan.dayType(id: "tennis"))
        #expect(tennis.name == "Tennis")
        #expect(tennis.schedule == .flexible)
        #expect(tennis.perWeek == 1)
        #expect(tennis.emoji == "🎾")
        // A second rest-like type isn't a second default.
        let off = try #require(PlanEdits.addingDayType(named: "Off", to: second.plan))
        #expect(off.plan.dayType(id: "off")?.schedule == .flexible)
        #expect(off.plan.dayTypes.count == PlanEdits.maxDayTypes)
        #expect(PlanEdits.addingDayType(named: "Swim", to: off.plan) == nil)
    }

    @Test func onlyOneDefaultDayType() throws {
        var gym = try #require(EditsFixture.plan().dayType(id: "gym"))
        gym.schedule = .default
        let plan = PlanEdits.updatingDayType(gym, in: EditsFixture.plan())
        #expect(plan.dayType(id: "gym")?.schedule == .default)
        #expect(plan.dayType(id: "rest")?.schedule == .flexible)
        #expect(plan.defaultDayType?.id == "gym")
        // Unknown ids change nothing.
        let unknown = CoachPlan.DayType(id: "swim", name: "Swim", schedule: .default)
        #expect(PlanEdits.updatingDayType(unknown, in: EditsFixture.plan()) == EditsFixture.plan())
    }

    @Test func typeTargetsChangeFromTheDayOn() throws {
        let edit = editsDay("2030-01-20")
        var gym = EditsFixture.gym
        gym.energy = 2700
        gym.carbs = 335
        let plan = PlanEdits.settingTargets(gym, forType: "gym", in: EditsFixture.plan(), on: edit)
        let phase = try #require(plan.phase(id: "1"))
        #expect(phase.revisions.count == 2)
        #expect(phase.revisions.last?.from == edit)
        #expect(phase.revisions.last?.reason == "edit")
        #expect(phase.revisions.last?.baseline == EditsFixture.rest)
        // Past Mondays keep their targets; from the edit on gym days follow the new ones.
        #expect(plan.targets(on: editsDay("2030-01-14"), marks: [:], fallback: .standard, calendar: editsUTC).energy == 2600)
        #expect(plan.targets(on: editsDay("2030-01-21"), marks: [:], fallback: .standard, calendar: editsUTC).energy == 2700)
        #expect(plan.targets(on: editsDay("2030-01-22"), marks: [:], fallback: .standard, calendar: editsUTC).energy == 2400)

        // "Same as baseline": no own targets any more.
        let same = PlanEdits.settingTargets(nil, forType: "gym", in: plan, on: edit)
        #expect(same.phase(id: "1")?.revisions.count == 2)
        #expect(same.phase(id: "1")?.revisions.last?.byType["gym"] == nil)
        #expect(same.targets(on: editsDay("2030-01-21"), marks: [:], fallback: .standard, calendar: editsUTC).energy == 2400)

        // Nothing changes: the same plan.
        #expect(PlanEdits.settingTargets(EditsFixture.gym, forType: "gym", in: EditsFixture.plan(), on: edit) == EditsFixture.plan())
        // No active phase on the day: unchanged.
        #expect(PlanEdits.settingTargets(gym, forType: "gym", in: EditsFixture.plan(), on: editsDay("2030-01-01")) == EditsFixture.plan())
    }

    @Test func laterRevisionsFollowAndSameDayRevisionsKeepTheirReason() throws {
        let adjusted = CoachPlan.Revision(from: editsDay("2030-01-22"), baseline: EditsFixture.rest,
                                          byType: ["gym": EditsFixture.gym, "rest": EditsFixture.rest], reason: "adjust:+100")
        let base = EditsFixture.plan(revisions: [
            .init(from: EditsFixture.start, baseline: EditsFixture.rest, byType: ["gym": EditsFixture.gym, "rest": EditsFixture.rest], reason: "import"),
            adjusted,
        ])
        var gym = EditsFixture.gym
        gym.energy = 2750
        let plan = PlanEdits.settingTargets(gym, forType: "gym", in: base, on: editsDay("2030-01-21"))
        let revisions = try #require(plan.phase(id: "1")?.revisions)
        #expect(revisions.map(\.from.rawValue) == ["2030-01-07", "2030-01-21", "2030-01-22"])
        #expect(revisions[2].byType["gym"]?.energy == 2750)
        #expect(revisions[2].reason == "adjust:+100")

        // A second edit on the 22nd replaces that day's revision but keeps the adjustment's reason.
        var rest = EditsFixture.rest
        rest.energy = 2450
        let again = PlanEdits.settingBaseline(rest, in: plan, on: editsDay("2030-01-22"))
        let latest = try #require(again.phase(id: "1")?.revisions.last)
        #expect(again.phase(id: "1")?.revisions.count == 3)
        #expect(latest.reason == "adjust:+100")
        #expect(latest.baseline?.energy == 2450)
        #expect(latest.byType["gym"]?.energy == 2750)
    }

    @Test func calculatedTargetsMoveEveryDayTypeTheSame() throws {
        let calculated = DailyTargets(energy: 2500, protein: 160, carbs: 285, fat: 80)
        let plan = PlanEdits.applyingCalculated(calculated, to: EditsFixture.plan(), on: editsDay("2030-01-20"),
                                                weightKg: 80, fallback: .standard)
        let revision = try #require(plan.phase(id: "1")?.revisions.last)
        #expect(revision.from == editsDay("2030-01-20"))
        #expect(revision.baseline == calculated)
        #expect(revision.byType["gym"]?.energy == 2700)
        #expect(revision.byType["gym"]?.carbs == 335)
        #expect(revision.byType["rest"]?.energy == 2500)
        #expect(revision.byType["gym"]?.protein == 160)
    }

    @Test func checksAreAddedAndChanged() throws {
        let added = PlanEdits.addingCheck(named: "Creatine", to: CoachPlan())
        #expect(added.id == "creatine")
        var check = try #require(added.plan.check(id: "creatine"))
        #expect(check.affectsWeight)
        #expect(check.days == .daily)
        check.dose = "3-5 g"
        check.timing = .meal("breakfast")
        let plan = PlanEdits.updatingCheck(check, in: added.plan)
        #expect(plan.check(id: "creatine")?.timing == .meal("breakfast"))
        #expect(PlanEdits.addingCheck(named: "Creatine", to: plan).id == "creatine2")
    }

    @Test func pausingAndResuming() throws {
        let today = editsDay("2030-02-04")
        let paused = PlanEdits.pausing(EditsFixture.plan(), from: today, until: editsDay("2030-02-10"), reason: .holiday)
        #expect(paused.isPaused(on: editsDay("2030-02-05")))
        #expect(!paused.isPaused(on: editsDay("2030-02-11")))
        #expect(paused.pause(on: today)?.reason == .holiday)
        // Pausing again the same day replaces it; an end before the start is the start.
        let again = PlanEdits.pausing(paused, from: today, until: editsDay("2030-02-01"), reason: .sick)
        #expect(again.pauses.count == 1)
        #expect(again.pauses.first?.end == today)
        #expect(again.pauses.first?.reason == .sick)
        // Resuming on the first day removes the pause.
        #expect(PlanEdits.resuming(paused, on: today, calendar: editsUTC).pauses.isEmpty)
        // Resuming later ends it the day before; open-ended pauses too.
        let open = PlanEdits.pausing(EditsFixture.plan(), from: editsDay("2030-02-01"), until: nil, reason: .other)
        let resumed = PlanEdits.resuming(open, on: today, calendar: editsUTC)
        #expect(resumed.pauses.first?.end == editsDay("2030-02-03"))
        #expect(!resumed.isPaused(on: today))
        #expect(resumed.isPaused(on: editsDay("2030-02-02")))
        // Not paused: unchanged.
        #expect(PlanEdits.resuming(EditsFixture.plan(), on: today, calendar: editsUTC) == EditsFixture.plan())
    }

    @Test func settingUpKeepsWhatThePlanHolds() throws {
        var notes = CoachPlan()
        notes.notes = ["Sleep well"]
        notes.checks = [.init(id: "creatine", name: "Creatine")]
        let state = SettingsState(sex: .female, goal: .lose, ratePerWeek: 0.3, targets: EditsFixture.rest,
                                  trainingTargets: EditsFixture.gym, trainingDays: Weekdays([2, 4]))
        let day = editsDay("2030-02-04")
        let plan = PlanEdits.settingUp(notes, from: state, on: day, now: day.date(calendar: editsUTC))
        #expect(plan.isSetUp)
        #expect(plan.notes == ["Sleep well"])
        #expect(plan.checks.map(\.id) == ["creatine"])
        #expect(plan.dayTypes.map(\.id) == ["training", "rest"])
        #expect(plan.phases.first?.goal == .lose)
        #expect(plan.activePhase(on: day)?.rateMid == 0.3)
        #expect(plan.routine.weeklySites == [.waistNarrow])
        // A plan that is set up stays as it is.
        #expect(PlanEdits.settingUp(EditsFixture.plan(), from: state, on: day) == EditsFixture.plan())
    }
}
