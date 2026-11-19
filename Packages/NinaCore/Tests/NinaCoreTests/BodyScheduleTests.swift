import Foundation
import Testing
@testable import NinaCore

// A made-up plan set up on Thu 3 Jan 2030 with Monday check-ins.

private var scheduleUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func schedDay(_ raw: String) -> DayKey { DayKey(raw)! }

private let schedFullSites: [BodySite] = [.neck, .chest, .arm, .waist, .hip, .thigh]

private func schedTape(_ raw: String, _ sites: [BodySite]) -> BodyTapeRecord {
    BodyTapeRecord(day: schedDay(raw), values: BodyValues(Dictionary(uniqueKeysWithValues: sites.map { ($0, 50.0) })),
                   conditions: "morning,fasted")
}

/// A gain phase from 3 Jan to ~30 May 2030 (review at 82–83 kg), a planned cut after it.
private func schedPlan() -> CoachPlan {
    let gain = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: schedDay("2030-01-03"), end: schedDay("2030-05-30"),
                               endApprox: true, rateMin: 0.1, rateMax: 0.2, reviewMin: 82, reviewMax: 83, targetWeight: 83,
                               startedAt: Date(timeIntervalSince1970: 1_893_000_000), status: .active)
    let cut = CoachPlan.Phase(id: "2", name: "Cut", goal: .lose, start: schedDay("2030-06-03"), startApprox: true)
    let rest = CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default)
    return CoachPlan(dayTypes: [rest], phases: [gain, cut])
}

@Suite("Body schedule")
struct BodyScheduleTests {
    @Test func weekdays() {
        let cal = scheduleUTC
        #expect(schedDay("2030-01-03").weekday(calendar: cal) == 4)
        #expect(BodySchedule.nearest(weekday: 1, to: schedDay("2030-02-28"), calendar: cal) == schedDay("2030-02-25")) // Thu: 3 days back
        #expect(BodySchedule.nearest(weekday: 1, to: schedDay("2030-03-01"), calendar: cal) == schedDay("2030-03-04")) // Fri: 3 days on
        #expect(BodySchedule.nearest(weekday: 1, to: schedDay("2030-02-25"), calendar: cal) == schedDay("2030-02-25"))
        #expect(BodySchedule.onOrBefore(weekday: 1, schedDay("2030-01-03"), calendar: cal) == schedDay("2029-12-31"))
        #expect(BodySchedule.onOrAfter(weekday: 1, schedDay("2030-01-03"), calendar: cal) == schedDay("2030-01-07"))
        #expect(BodySchedule.onOrAfter(weekday: 4, schedDay("2030-01-03"), calendar: cal) == schedDay("2030-01-03"))
    }

    @Test func fullSetRhythm() {
        let cal = scheduleUTC
        let start = schedDay("2030-01-03")
        // The baseline on the set-up day, then the Monday nearest to 8 weeks later.
        #expect(BodySchedule.nextFull(lastFull: nil, everyWeeks: 8, checkInWeekday: 1, start: start, calendar: cal) == start)
        #expect(BodySchedule.nextFull(lastFull: start, everyWeeks: 8, checkInWeekday: 1, calendar: cal) == schedDay("2030-02-25"))
        #expect(BodySchedule.nextFull(lastFull: schedDay("2030-02-25"), everyWeeks: 8, checkInWeekday: 1, calendar: cal)
                == schedDay("2030-04-22"))
        #expect(BodySchedule.nextFull(lastFull: start, everyWeeks: 0, checkInWeekday: 1, calendar: cal) == nil)
        #expect(BodySchedule.nextFull(lastFull: nil, everyWeeks: 8, checkInWeekday: 1, calendar: cal) == nil)
        // An old full set never makes one due before the plan.
        #expect(BodySchedule.nextFull(lastFull: schedDay("2029-06-03"), everyWeeks: 8, checkInWeekday: 1, start: start, calendar: cal)
                == start)
    }

    @Test func weeklyRhythm() {
        let cal = scheduleUTC
        func next(_ last: String?, _ today: String) -> DayKey {
            BodySchedule.nextWeekly(lastMeasured: last.map(schedDay), today: schedDay(today), checkInWeekday: 1,
                                    start: schedDay("2030-01-03"), calendar: cal)
        }
        #expect(next("2030-01-03", "2030-01-03") == schedDay("2030-01-07")) // the baseline week
        #expect(next("2030-01-03", "2030-01-07") == schedDay("2030-01-07")) // due today
        #expect(next("2030-01-07", "2030-01-07") == schedDay("2030-01-14"))
        #expect(next("2030-01-03", "2030-01-10") == schedDay("2030-01-07")) // overdue
        #expect(next("2030-01-09", "2030-01-10") == schedDay("2030-01-14")) // late still counts for that week
        #expect(next("2030-01-03", "2030-01-15") == schedDay("2030-01-14")) // a missed week never shifts the weekday
        #expect(next(nil, "2030-01-01") == schedDay("2030-01-07")) // before the plan
        #expect(BodySchedule.nextWeekly(lastMeasured: nil, today: schedDay("2030-01-10"), checkInWeekday: 9, calendar: cal)
                == schedDay("2030-01-06")) // clamped to Sunday
    }

    @Test func whatCountsAsAFullSet() {
        let routine = CoachPlan.Routine()
        #expect(BodySchedule.isFullSet([.waist, .chest, .arm], routine: routine))
        #expect(!BodySchedule.isFullSet([.waist, .chest], routine: routine))
        #expect(!BodySchedule.isFullSet([.waist], routine: routine))
        #expect(BodySchedule.isFullSet([.armLeft, .thighLeft, .chest], routine: routine))
        let small = CoachPlan.Routine(weeklySites: [.waist, .hip], fullSites: [.waist, .hip, .chest])
        #expect(!BodySchedule.isFullSet([.waist, .hip], routine: small)) // only the weekly sites
        #expect(BodySchedule.isFullSet([.waist, .chest], routine: small))
        #expect(!BodySchedule.isFullSet([.waist, .chest], routine: CoachPlan.Routine(fullSites: [])))
        #expect(BodySchedule.coversWeekly([.waist, .neck], routine: routine))
        #expect(!BodySchedule.coversWeekly([.waistNarrow], routine: routine))
        #expect(BodySchedule.coversWeekly([.waistNarrow], routine: CoachPlan.Routine.defaults(for: .female)))
    }

    @Test func dueFromAPlan() {
        let cal = scheduleUTC
        let plan = schedPlan()
        let start = schedDay("2030-01-03")
        #expect(BodySchedule.setUpDay(of: plan) == start)

        // Before the baseline: one "Full measurement" pill with the body-fat step.
        let fresh = BodySchedule(plan: plan, start: start, tape: [], assessmentDays: [])
        #expect(fresh.nextFull(today: start, calendar: cal) == BodySchedule.Due(day: start, reason: .baseline))
        let first = fresh.dueItems(on: start, calendar: cal)
        #expect(first.map(\.kind) == [.full])
        #expect(first.first?.includesAssessment == true && first.first?.title == "Full measurement")
        #expect(first.first?.sites == schedFullSites && first.first?.reason == .baseline)
        let late = fresh.dueItems(on: schedDay("2030-01-08"), calendar: cal).first
        #expect(late?.overdueDays == 5 && late?.overdueText == "overdue 5 days" && late?.isOverdueNotice == true)

        // After the baseline: the waist every Monday, the next full set on 25 Feb.
        let tape = [schedTape("2030-01-03", schedFullSites), schedTape("2030-01-07", [.waist]), schedTape("2030-01-15", [.waist])]
        let schedule = BodySchedule(plan: plan, start: start, tape: tape, assessmentDays: [start])
        #expect(schedule.fullDays == [start])
        #expect(schedule.weeklyDays == ["2030-01-03", "2030-01-07", "2030-01-15"].map(schedDay))
        #expect(schedule.nextFull(today: schedDay("2030-01-04"), calendar: cal)
                == BodySchedule.Due(day: schedDay("2030-02-25"), reason: .schedule))
        #expect(schedule.nextAssessment(today: schedDay("2030-01-04"), calendar: cal)?.day == schedDay("2030-02-25"))
        #expect(schedule.dueItems(on: schedDay("2030-01-04"), calendar: cal).isEmpty)
        #expect(schedule.dueItems(on: schedDay("2030-01-07"), calendar: cal).isEmpty) // measured that morning
        #expect(schedule.dueItems(on: schedDay("2030-01-16"), calendar: cal).isEmpty) // measured on Tuesday
        #expect(schedule.dueItems(on: schedDay("2030-01-21"), calendar: cal).map(\.title) == ["Waist"])
        let overdue = schedule.dueItems(on: schedDay("2030-01-23"), calendar: cal).first
        #expect(overdue?.kind == .weekly && overdue?.dueDay == schedDay("2030-01-21") && overdue?.overdueDays == 2)
        #expect(overdue?.isOverdueNotice == false && overdue?.overdueText == "overdue 2 days")

        // The full set's week: one pill, no extra waist.
        let fullWeek = schedule.dueItems(on: schedDay("2030-02-25"), calendar: cal)
        #expect(fullWeek.map(\.kind) == [.full] && fullWeek.first?.includesAssessment == true)

        // A full set with one site skipped still counts, also as the weekly check; the skipped
        // body-fat step stays due on its own.
        let after = BodySchedule(plan: plan, start: start, tape: tape + [schedTape("2030-02-25", [.neck, .chest, .arm, .waist, .hip])],
                                 assessmentDays: [start])
        let next = after.dueItems(on: schedDay("2030-02-26"), calendar: cal)
        #expect(next.map(\.kind) == [.assessment] && next.first?.title == "Body fat" && next.first?.overdueDays == 1)
        #expect(after.nextWeekly(today: schedDay("2030-02-26"), calendar: cal) == schedDay("2030-03-04"))
        #expect(after.nextFull(today: schedDay("2030-02-26"), calendar: cal)?.day == schedDay("2030-04-22"))
    }

    @Test func phaseEventsAndCheckpoint() {
        let cal = scheduleUTC
        let plan = schedPlan()
        let start = schedDay("2030-01-03")
        let tape = [schedTape("2030-01-03", schedFullSites), schedTape("2030-02-25", schedFullSites), schedTape("2030-04-22", schedFullSites)]
        let assessments = ["2030-01-03", "2030-02-25", "2030-04-22"].map(schedDay)
        let schedule = BodySchedule(plan: plan, start: start, tape: tape, assessmentDays: assessments)
        // The rhythm says 17 Jun, but the phase ends on 30 May first. The planned cut isn't an event yet.
        #expect(schedule.nextFull(today: schedDay("2030-05-01"), calendar: cal)
                == BodySchedule.Due(day: schedDay("2030-05-30"), reason: .phaseEnd))
        #expect(schedule.dueItems(on: schedDay("2030-05-30"), calendar: cal).first?.reason == .phaseEnd)
        #expect(schedule.dueItems(on: schedDay("2030-05-30"), calendar: cal).first?.includesAssessment == true)

        // A full set up to 14 days before an event counts for it.
        let early = BodySchedule(plan: plan, start: start, tape: tape + [schedTape("2030-05-20", schedFullSites)],
                                 assessmentDays: assessments + [schedDay("2030-05-20")])
        #expect(early.nextFull(today: schedDay("2030-05-30"), calendar: cal)?.day == schedDay("2030-07-15"))
        #expect(early.dueItems(on: schedDay("2030-05-30"), calendar: cal).map(\.kind) == [.weekly]) // only this week's waist

        // The review checkpoint: the 7-day average reached 82 kg on 20 Mar.
        let history: [DayKey: Double] = [
            schedDay("2030-03-18"): 81.8, schedDay("2030-03-19"): 81.95, schedDay("2030-03-20"): 82.0,
            schedDay("2030-03-21"): 81.9, schedDay("2030-03-22"): 82.1,
        ]
        let checkpoint = BodySchedule.checkpointCrossed(avg7History: history, phase: plan.phases[0])
        #expect(checkpoint == schedDay("2030-03-20"))
        let twoSets = Array(tape.prefix(2))
        let review = BodySchedule(plan: plan, start: start, tape: twoSets, assessmentDays: Array(assessments.prefix(2)), checkpoint: checkpoint)
        #expect(review.nextFull(today: schedDay("2030-03-20"), calendar: cal)
                == BodySchedule.Due(day: schedDay("2030-03-20"), reason: .checkpoint))
        // A full set on 11 Mar (within 14 days) covers the checkpoint.
        let covered = BodySchedule(plan: plan, start: start, tape: twoSets + [schedTape("2030-03-11", schedFullSites)],
                                   assessmentDays: assessments, checkpoint: checkpoint)
        #expect(covered.nextFull(today: schedDay("2030-03-20"), calendar: cal)?.day == schedDay("2030-05-06"))
    }

    @Test func checkpointCrossing() {
        let gain: [DayKey: Double] = [
            schedDay("2030-03-18"): 81.8, schedDay("2030-03-19"): 81.95, schedDay("2030-03-20"): 82.0,
            schedDay("2030-03-21"): 81.9, schedDay("2030-03-22"): 82.1,
        ]
        #expect(BodySchedule.checkpointCrossed(avg7History: gain, threshold: 82, goal: .gain) == schedDay("2030-03-20"))
        #expect(BodySchedule.checkpointCrossed(avg7History: gain, threshold: 83, goal: .gain) == nil)
        #expect(BodySchedule.checkpointCrossed(avg7History: gain, threshold: 82, goal: .gain, since: schedDay("2030-03-21"))
                == schedDay("2030-03-22"))
        let loss: [DayKey: Double] = [
            schedDay("2030-04-01"): 74.6, schedDay("2030-04-02"): 74.2, schedDay("2030-04-03"): 74.0, schedDay("2030-04-04"): 73.9,
        ]
        #expect(BodySchedule.checkpointCrossed(avg7History: loss, threshold: 74, goal: .lose) == schedDay("2030-04-03"))
        #expect(BodySchedule.checkpointCrossed(avg7History: loss, threshold: 74, goal: .maintain) == nil)
        #expect(BodySchedule.checkpointCrossed(avg7History: [:], threshold: 74, goal: .lose) == nil)

        var cut = CoachPlan.Phase(id: "2", goal: .lose, start: schedDay("2030-04-01"), reviewMin: 73, reviewMax: 74)
        #expect(BodySchedule.reviewThreshold(of: cut) == 74)
        #expect(BodySchedule.checkpointCrossed(avg7History: loss, phase: cut) == schedDay("2030-04-03"))
        cut.reviewMax = 0
        #expect(BodySchedule.reviewThreshold(of: cut) == 73)
        #expect(BodySchedule.checkpointCrossed(avg7History: loss, phase: cut) == nil)
        #expect(BodySchedule.reviewThreshold(of: CoachPlan.Phase(id: "3", goal: .maintain, reviewMin: 80)) == nil)
        #expect(BodySchedule.reviewThreshold(of: CoachPlan.Phase(id: "4", goal: .gain)) == nil)
        #expect(BodySchedule.reviewThreshold(of: CoachPlan.Phase(id: "5", goal: .gain, reviewMax: 83)) == 83)
    }

    @Test func weighInPausesAndOptions() {
        let cal = scheduleUTC
        let plan = schedPlan()
        let start = schedDay("2030-01-03")
        let tape = [schedTape("2030-01-03", schedFullSites), schedTape("2030-01-07", [.waist])]
        let schedule = BodySchedule(plan: plan, start: start, tape: tape, assessmentDays: [start])
        let day = schedDay("2030-01-08")
        let morning = day.date(minutes: 7 * 60, calendar: cal)
        let noon = day.date(minutes: 12 * 60, calendar: cal)
        #expect(schedule.dueItems(on: day, now: morning, calendar: cal).map(\.title) == ["Weigh in"])
        #expect(schedule.dueItems(on: day, now: morning, hasMorningWeighIn: true, calendar: cal).isEmpty)
        #expect(schedule.dueItems(on: day, now: noon, calendar: cal).isEmpty)
        #expect(schedule.dueItems(on: day, calendar: cal).isEmpty)

        // Paused days show nothing.
        var paused = plan
        paused.pauses = [CoachPlan.Pause(start: day, end: schedDay("2030-01-12"), reason: .holiday)]
        let pausedSchedule = BodySchedule(plan: paused, start: start, tape: tape, assessmentDays: [start])
        #expect(pausedSchedule.dueItems(on: day, now: morning, calendar: cal).isEmpty)
        let after = schedDay("2030-01-13")
        #expect(pausedSchedule.dueItems(on: after, now: after.date(minutes: 420, calendar: cal), calendar: cal).map(\.kind) == [.weighIn])

        // Without a plan nothing is due.
        let none = BodySchedule(plan: CoachPlan(), start: nil, tape: [], assessmentDays: [])
        #expect(!none.isSetUp && none.dueItems(on: day, now: morning, calendar: cal).isEmpty)

        // Tracking with the tape estimate: no separate assessments.
        var navy = plan
        navy.routine.bodyFatMethod = .navy
        let navySchedule = BodySchedule(plan: navy, start: start, tape: [], assessmentDays: [])
        #expect(!navySchedule.needsAssessments && navySchedule.nextAssessment(today: start, calendar: cal) == nil)
        #expect(navySchedule.dueItems(on: start, calendar: cal).first?.includesAssessment == false)

        // Two weekly sites, both sides.
        var two = plan
        two.routine.weeklySites = [.waist, .arm]
        two.routine.side = .both
        let twoSchedule = BodySchedule(plan: two, start: start, tape: [tape[0]], assessmentDays: [start])
        let item = twoSchedule.dueItems(on: schedDay("2030-01-07"), calendar: cal).first
        #expect(item?.sites == [.waist, .arm, .armLeft] && item?.title == "Measurements")

        // Plain values the strip and the widget snapshot can carry.
        let pill = BodyDueItem(kind: .full, dueDay: start, overdueDays: 1, reason: .baseline, sites: [.waist], includesAssessment: true)
        let data = try? JSONEncoder().encode(pill)
        #expect(data.flatMap { try? JSONDecoder().decode(BodyDueItem.self, from: $0) } == pill)
        #expect(pill.overdueText == "overdue 1 day" && pill.id == "full")
        #expect(BodyDueItem(kind: .weighIn, dueDay: start).overdueText == nil)
    }
}
