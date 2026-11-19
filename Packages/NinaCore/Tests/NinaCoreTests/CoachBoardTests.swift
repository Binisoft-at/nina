import Foundation
import Testing
@testable import NinaCore

// A made-up plan set up on Thu 3 Jan 2030: a lean gain until ~28 Mar (review at 79–80 kg), a
// planned cut from ~1 Apr, Gym on Mon/Wed/Fri, Tennis twice a week, Rest otherwise.

private var boardUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func boardDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func boardTime(_ raw: String, _ minutes: Int) -> Date { boardDay(raw).date(minutes: minutes, calendar: boardUTC) }

private let boardFallback = DailyTargets(energy: 2200, protein: 120, carbs: 250, fat: 70)
private let boardGym = DailyTargets(energy: 2500, protein: 150, carbs: 300, fat: 70)
private let boardTennis = DailyTargets(energy: 2600, protein: 150, carbs: 325, fat: 70)
private let boardRest = DailyTargets(energy: 2300, protein: 150, carbs: 250, fat: 70)

private func boardPlan(cut: Bool = true, pauses: [CoachPlan.Pause] = [], types: Bool = true) -> CoachPlan {
    let revision = CoachPlan.Revision(from: boardDay("2030-01-03"), baseline: DailyTargets(energy: 2450, protein: 150, carbs: 300, fat: 70),
                                      byType: ["gym": boardGym, "tennis": boardTennis, "rest": boardRest], reason: "import")
    let gain = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: boardDay("2030-01-03"), end: boardDay("2030-03-28"),
                               endApprox: true, rateMin: 0.1, rateMax: 0.2, reviewMin: 79, reviewMax: 80, targetWeight: 80,
                               startedAt: boardTime("2030-01-03", 8 * 60), status: .active, revisions: [revision])
    let cutPhase = CoachPlan.Phase(id: "2", name: "Cut", goal: .lose, start: boardDay("2030-04-01"), startApprox: true)
    let dayTypes = [
        CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
        CoachPlan.DayType(id: "tennis", name: "Tennis", schedule: .flexible, perWeek: 2),
        CoachPlan.DayType(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
    ]
    let checks = [
        CoachPlan.Check(id: "omega", name: "Omega-3", emoji: "🐟", timing: .anytime),
        CoachPlan.Check(id: "vitd", name: "Vitamin D", dose: "1000 IU", timing: .time(6 * 60)),
        CoachPlan.Check(id: "creatine", name: "Creatine", emoji: "💊", dose: "3–5 g", timing: .meal("breakfast"), isOptional: true),
        CoachPlan.Check(id: "magnesium", name: "Magnesium", emoji: "🌙", timing: .meal("dinner")),
        CoachPlan.Check(id: "electrolytes", name: "Electrolytes", emoji: "🧂", days: .dayTypes(["tennis"])),
    ]
    return CoachPlan(dayTypes: types ? dayTypes : [], phases: cut ? [gain, cutPhase] : [gain], checks: checks, pauses: pauses)
}

private func boardInput(_ plan: CoachPlan = boardPlan(), day: String, today: String? = nil, minutes: Int = 12 * 60,
                        configure: (inout CoachBoard.Input) -> Void = { _ in }) -> CoachBoard.Input {
    let todayKey = boardDay(today ?? day)
    var input = CoachBoard.Input(plan: plan, day: boardDay(day), today: todayKey, now: todayKey.date(minutes: minutes, calendar: boardUTC),
                                 fallback: boardFallback, calendar: boardUTC)
    configure(&input)
    return input
}

/// The schedule after the baseline (full set and assessment on 3 Jan) and a weekly waist on 7 Jan.
private func boardSchedule(_ plan: CoachPlan, measured: Bool = true) -> BodySchedule {
    let full: [BodySite: Double] = [.neck: 38, .chest: 100, .arm: 34, .waist: 82, .hip: 96, .thigh: 56]
    let waist: [BodySite: Double] = [.waist: 82.5]
    let tape = measured ? [BodyTapeRecord(day: boardDay("2030-01-03"), values: BodyValues(full), conditions: "morning,fasted"),
                           BodyTapeRecord(day: boardDay("2030-01-07"), values: BodyValues(waist), conditions: "morning,fasted")] : []
    return BodySchedule(plan: plan, start: BodySchedule.setUpDay(of: plan, calendar: boardUTC), tape: tape,
                        assessmentDays: measured ? [boardDay("2030-01-03")] : [])
}

@Suite("Coach board")
struct CoachBoardTests {
    @Test func nothingWithoutAPlan() {
        let board = CoachBoard(boardInput(CoachPlan(), day: "2030-01-14") { input in
            input.checkpoint = boardDay("2030-01-10")
            input.bodyItems = [BodyDueItem(kind: .weighIn, dueDay: boardDay("2030-01-14"))]
        })
        #expect(board == CoachBoard.empty)
        #expect(board.weekAverageLine == nil)
    }

    @Test func dayTypeChip() throws {
        // Monday: Gym from the schedule.
        let monday = try #require(CoachBoard(boardInput(day: "2030-01-07")).chip)
        #expect(monday.id == "gym")
        #expect(monday.title == "Gym day")
        #expect(monday.emoji == "🏋️")
        #expect(!monday.isManual)
        #expect(monday.quotaText == nil)
        #expect(monday.energy == 2500)
        #expect(monday.options.map(\.id) == ["gym", "tennis", "rest"])
        #expect(monday.options.map(\.energy) == [2500, 2600, 2300])
        #expect(monday.options.first { $0.isSelected }?.id == "gym")
        #expect(monday.options[1].quotaText == "0 of 2 this week")
        #expect(monday.options[1].emoji == CoachPlan.DayType.suggestedEmoji(for: "Tennis"))

        // Tuesday picked as Tennis by hand: filled chip, quota, Tennis targets.
        let marks = ["2030-01-08": "tennis", "2030-01-11": "tennis"]
        let tuesday = try #require(CoachBoard(boardInput(day: "2030-01-08") { $0.dayTypeMarks = marks }).chip)
        #expect(tuesday.id == "tennis")
        #expect(tuesday.isManual)
        #expect(tuesday.quotaText == "Tennis · 2 of 2 this week")
        #expect(tuesday.energy == 2600)
        // Looking back from the next week.
        let later = try #require(CoachBoard(boardInput(day: "2030-01-08", today: "2030-01-14") { $0.dayTypeMarks = marks }).chip)
        #expect(later.quotaText == "Tennis · 2 of 2 that week")

        // Thursday: the default type.
        let thursday = try #require(CoachBoard(boardInput(day: "2030-01-10")).chip)
        #expect(thursday.title == "Rest day")
        #expect(thursday.energy == 2300)

        // A plan without day types has no chip.
        #expect(CoachBoard(boardInput(boardPlan(types: false), day: "2030-01-07")).chip == nil)
    }

    @Test func stripOrder() {
        let plan = boardPlan()
        let today = boardDay("2030-01-14")
        let now = boardTime("2030-01-14", 7 * 60)
        let items = CoachBoard.bodyItems(boardSchedule(plan), on: today, today: today, now: now, hasMorningWeighIn: false,
                                         calendar: boardUTC)
        let board = CoachBoard(boardInput(plan, day: "2030-01-14", minutes: 7 * 60) { input in
            input.bodyItems = items
            input.checkStates = ["creatine": .done]
        })
        // Weigh in → the weekly waist → checks by meal time, then clock time, then anytime.
        #expect(board.strip.map(\.id) == ["weighIn", "body.weekly", "check.creatine", "check.magnesium", "check.vitd", "check.omega"])
        #expect(board.strip.map(\.title) == ["Weigh in", "Waist", "Creatine · 3–5 g", "Magnesium", "Vitamin D · 1000 IU", "Omega-3"])
        #expect(board.strip.map(\.state) == [.open, .open, .done, .open, .open, .open])
        #expect(board.strip[0].action == .weighIn)
        #expect(board.strip[0].symbol == "scalemass")
        #expect(board.strip[1].action == .measure(items[1]))
        #expect(board.strip[2].emoji == "💊")
        #expect(board.strip[4].symbol == "pills")
        #expect(board.strip[4].action == .check("vitd"))

        // After the weigh-in the pill is gone; a Tennis day adds its check.
        let tennis = CoachBoard(boardInput(plan, day: "2030-01-14", minutes: 9 * 60) { input in
            input.dayTypeMarks = ["2030-01-14": "tennis"]
            input.bodyItems = CoachBoard.bodyItems(boardSchedule(plan), on: today, today: today, now: input.now,
                                                   hasMorningWeighIn: true, calendar: boardUTC)
        })
        #expect(tennis.strip.map(\.id) == ["body.weekly", "check.creatine", "check.magnesium", "check.vitd", "check.omega",
                                           "check.electrolytes"])
    }

    @Test func overdueBodyItemSaysSo() {
        let late = BodyDueItem(kind: .weekly, dueDay: boardDay("2030-01-14"), overdueDays: 3, sites: [.waist])
        let board = CoachBoard(boardInput(day: "2030-01-17") { $0.bodyItems = [late] })
        #expect(board.strip.first?.detail == "overdue 3 days")
        let early = BodyDueItem(kind: .weekly, dueDay: boardDay("2030-01-14"), overdueDays: 1, sites: [.waist])
        #expect(CoachBoard(boardInput(day: "2030-01-15") { $0.bodyItems = [early] }).strip.first?.detail == nil)
    }

    @Test func overdueNoticeShowsOnceThenWaitsForTheCheckIn() {
        // A full set due on Thu 10 Jan; the check-in day is Monday.
        func pill(_ day: String) -> CoachBoard.StripItem? {
            let overdue = boardDay("2030-01-10").days(to: boardDay(day), calendar: boardUTC)
            let full = BodyDueItem(kind: .full, dueDay: boardDay("2030-01-10"), overdueDays: overdue, reason: .phaseStart)
            return CoachBoard(boardInput(day: day) { $0.bodyItems = [full] }).strip.first { $0.id == "body.full" }
        }
        #expect(pill("2030-01-10")?.detail == nil)
        #expect(pill("2030-01-12") != nil)
        #expect(pill("2030-01-12")?.detail == nil)
        // Sunday: overdue 3 days, said once.
        #expect(pill("2030-01-13")?.detail == "overdue 3 days")
        // Monday is the check-in day: it shows again.
        #expect(pill("2030-01-14")?.detail == "overdue 4 days")
        // Then it waits for the next check-in day.
        #expect(pill("2030-01-15") == nil)
        #expect(pill("2030-01-17") == nil)
        #expect(pill("2030-01-20") == nil)
        #expect(pill("2030-01-21")?.detail == "overdue 11 days")
        // The checks still show on the quiet days.
        let quiet = CoachBoard(boardInput(day: "2030-01-15") { input in
            input.bodyItems = [BodyDueItem(kind: .full, dueDay: boardDay("2030-01-10"), overdueDays: 5)]
        })
        #expect(!quiet.strip.isEmpty)
        #expect(!quiet.strip.contains { $0.kind == .body })
        // A plan with Thursday check-ins brings it back on Thursday.
        var thursday = boardPlan()
        thursday.routine.checkInWeekday = 4
        let back = CoachBoard(boardInput(thursday, day: "2030-01-17") { input in
            input.bodyItems = [BodyDueItem(kind: .full, dueDay: boardDay("2030-01-10"), overdueDays: 7)]
        })
        #expect(back.strip.first { $0.id == "body.full" }?.detail == "overdue 7 days")
        // Overdue 1–2 days on the check-in day: shown, nothing said yet.
        let soon = CoachBoard(boardInput(day: "2030-01-14") { input in
            input.bodyItems = [BodyDueItem(kind: .assessment, dueDay: boardDay("2030-01-12"), overdueDays: 2)]
        })
        #expect(soon.strip.first { $0.id == "body.assessment" }?.detail == nil)
        #expect(soon.strip.contains { $0.id == "body.assessment" })
    }

    @Test func stripHidesWhenEverythingIsDone() {
        let done: [String: CheckState] = ["omega": .done, "vitd": .skipped, "creatine": .done, "magnesium": .done]
        let board = CoachBoard(boardInput(day: "2030-01-14") { $0.checkStates = done })
        #expect(board.strip.isEmpty)
    }

    @Test func pastDaysShowOnlyWhatIsMissing() {
        let late = BodyDueItem(kind: .weekly, dueDay: boardDay("2030-01-07"), overdueDays: 2, sites: [.waist])
        let weighIn = BodyDueItem(kind: .weighIn, dueDay: boardDay("2030-01-09"))
        let board = CoachBoard(boardInput(day: "2030-01-09", today: "2030-01-14") { input in
            input.checkStates = ["creatine": .done, "magnesium": .skipped]
            input.bodyItems = [weighIn, late]
        })
        #expect(board.strip.map(\.id) == ["check.vitd", "check.omega"])
        let complete = CoachBoard(boardInput(day: "2030-01-09", today: "2030-01-14") { input in
            input.checkStates = ["creatine": .done, "magnesium": .skipped, "vitd": .done, "omega": .done]
        })
        #expect(complete.strip.isEmpty)
        // Nothing before the plan was set up.
        #expect(CoachBoard(boardInput(day: "2030-01-02", today: "2030-01-14")).strip.isEmpty)
        // A future day: its checks, no weigh-in.
        let future = CoachBoard(boardInput(day: "2030-01-16", today: "2030-01-14") { $0.bodyItems = [weighIn] })
        #expect(future.strip.map(\.id) == ["check.creatine", "check.magnesium", "check.vitd", "check.omega"])
    }

    @Test func nothingWhilePaused() {
        let plan = boardPlan(pauses: [CoachPlan.Pause(start: boardDay("2030-02-14"), end: boardDay("2030-02-20"), reason: .holiday)])
        let board = CoachBoard(boardInput(plan, day: "2030-02-18", minutes: 7 * 60) { input in
            input.bodyItems = [BodyDueItem(kind: .weighIn, dueDay: boardDay("2030-02-18"))]
            input.checkpoint = boardDay("2030-02-10")
        })
        #expect(board.strip.isEmpty)
        #expect(board.card == nil)
        #expect(board.chip?.id == "gym")
    }

    @Test func phaseStartCardComesFirst() throws {
        let input = boardInput(day: "2030-04-01") { input in
            input.checkpoint = boardDay("2030-03-20")
            input.hasMorningWeighIn = true
        }
        let card = try #require(CoachBoard(input).card)
        #expect(card.kind == .phaseStart)
        #expect(card.key == "phaseStart.2")
        #expect(card.title == "Cut starts today")
        #expect(card.message.contains("Lean gain keeps running"))
        #expect(card.primary == CoachBoard.Card.Choice(title: "Start", action: .startPhase("2")))
        #expect(card.secondary?.action == .postponePhase("2"))
        #expect(card.more.map(\.action) == [.editPhase("2")])
        #expect(card.phaseID == "2")
        // Only on today.
        #expect(CoachBoard(boardInput(day: "2030-04-02", today: "2030-04-01")).card == nil)
        // A start that has passed without a tap.
        let late = try #require(CoachBoard(boardInput(day: "2030-04-03")).card)
        #expect(late.title == "Cut is ready to start")
    }

    @Test func laterSkipsToTheNextCard() throws {
        let today = boardDay("2030-04-01")
        func card(_ dismissed: [String: DayKey], reviewed: Set<String> = []) -> CoachBoard.Card? {
            CoachBoard(boardInput(day: "2030-04-01") { input in
                input.checkpoint = boardDay("2030-03-20")
                input.hasMorningWeighIn = true
                input.dismissed = dismissed
                input.reviewedPhases = reviewed
            }).card
        }
        // Start put off today → the review checkpoint.
        let review = try #require(card(["phaseStart.2": today]))
        #expect(review.kind == .review)
        #expect(review.key == "review.1")
        #expect(review.title == "Review weight reached")
        #expect(review.message.contains("reached 79 kg"))
        #expect(review.primary.action == .review("1"))
        // "Later" on the review holds for 7 days, then it asks again.
        let held = try #require(card(["phaseStart.2": today, "review.1": boardDay("2030-03-26")]))
        #expect(held.kind == .checkIn)
        #expect(held.key == "checkIn.week-2030-04-01")
        #expect(held.primary.action == .checkIn(today))
        #expect(card(["phaseStart.2": today, "review.1": boardDay("2030-03-25")])?.kind == .review)
        // A review decision ends it; yesterday's "Later" on the start no longer counts.
        #expect(card(["phaseStart.2": boardDay("2030-03-31")], reviewed: ["1"])?.kind == .phaseStart)
        #expect(card(["phaseStart.2": today], reviewed: ["1"])?.kind == .checkIn)
    }

    @Test func ceilingsOpenTheReview() throws {
        let card = try #require(CoachBoard(boardInput(day: "2030-02-21") { $0.ceilings = [.waistGain] }).card)
        #expect(card.kind == .review)
        #expect(card.title == "Time for a phase review")
        #expect(card.message == BodyCeiling.waistGain.message + ".")
    }

    @Test func checkInCardTiming() {
        func card(_ day: String, minutes: Int, weighed: Bool = false, saved: Set<String> = []) -> CoachBoard.Card? {
            CoachBoard(boardInput(day: day, minutes: minutes) { input in
                input.hasMorningWeighIn = weighed
                input.checkInKeys = saved
            }).card
        }
        // Monday morning: after the weigh-in, or from the morning cutoff.
        #expect(card("2030-01-14", minutes: 8 * 60) == nil)
        #expect(card("2030-01-14", minutes: 8 * 60, weighed: true)?.key == "checkIn.week-2030-01-14")
        #expect(card("2030-01-14", minutes: 11 * 60)?.kind == .checkIn)
        // Up to 3 days, any time.
        #expect(card("2030-01-16", minutes: 7 * 60)?.primary.action == .checkIn(boardDay("2030-01-14")))
        #expect(card("2030-01-17", minutes: 12 * 60) == nil)
        // Saved this week.
        #expect(card("2030-01-14", minutes: 12 * 60, saved: ["week-2030-01-14"]) == nil)
        // Not before the phase has run a day.
        #expect(card("2029-12-31", minutes: 12 * 60) == nil)
    }

    @Test func baselineCard() throws {
        let plan = boardPlan()
        let today = boardDay("2030-01-03")
        let items = CoachBoard.bodyItems(boardSchedule(plan, measured: false), on: today, today: today,
                                         now: boardTime("2030-01-03", 8 * 60), hasMorningWeighIn: false, calendar: boardUTC)
        let board = CoachBoard(boardInput(plan, day: "2030-01-03", minutes: 8 * 60) { $0.bodyItems = items })
        let card = try #require(board.card)
        let full = try #require(items.first { $0.kind == .full })
        #expect(full.reason == .baseline)
        #expect(full.includesAssessment)
        #expect(card.kind == .baseline)
        #expect(card.key == "baseline.2030-01-03")
        #expect(card.primary.action == .measure(full))
        #expect(card.message.contains("body fat"))
        #expect(board.strip.prefix(2).map(\.id) == ["weighIn", "body.full"])

        let assessment = BodyDueItem(kind: .assessment, dueDay: today, reason: .baseline)
        let only = try #require(CoachBoard(boardInput(plan, day: "2030-01-03") { $0.bodyItems = [assessment] }).card)
        #expect(only.primary.action == .assessment(assessment))
    }

    @Test func welcomeBackAfterAPause() throws {
        let plan = boardPlan(pauses: [CoachPlan.Pause(start: boardDay("2030-02-14"), end: boardDay("2030-02-20"), reason: .holiday)])
        func card(_ day: String, minutes: Int = 12 * 60, weighed: Bool = false, dismissed: [String: DayKey] = [:]) -> CoachBoard.Card? {
            CoachBoard(boardInput(plan, day: day, minutes: minutes) { input in
                input.hasMorningWeighIn = weighed
                input.dismissed = dismissed
            }).card
        }
        let noon = try #require(card("2030-02-22"))
        #expect(noon.kind == .welcomeBack)
        #expect(noon.key == "welcomeBack.2030-02-20")
        #expect(noon.message == "Weigh in tomorrow morning to restart your 7-day average.")
        #expect(noon.primary.action == .dismiss)
        #expect(card("2030-02-22", minutes: 8 * 60)?.primary.action == .weighIn)
        #expect(card("2030-02-22", weighed: true)?.message == "Your 7-day average fills up again over the next mornings.")
        // Once put off, it stays away; and only for 3 days.
        #expect(card("2030-02-23", dismissed: ["welcomeBack.2030-02-20": boardDay("2030-02-22")]) == nil)
        #expect(card("2030-02-24") == nil)
        // The day the pause ends is still paused.
        #expect(card("2030-02-20") == nil)
    }

    @Test func phaseEndCard() throws {
        let card = try #require(CoachBoard(boardInput(day: "2030-03-28")).card)
        #expect(card.kind == .phaseEnd)
        #expect(card.key == "phaseEnd.1")
        #expect(card.title == "Lean gain ends today")
        #expect(card.primary.action == .startPhase("2"))
        #expect(card.secondary?.action == .editPhase("1"))
        let after = try #require(CoachBoard(boardInput(day: "2030-03-29")).card)
        #expect(after.title == "Lean gain has reached its end date")
        let alone = try #require(CoachBoard(boardInput(boardPlan(cut: false), day: "2030-03-28")).card)
        #expect(alone.primary.action == .editPlan)
    }

    @Test func weekAverage() throws {
        // Planned: (3 × 2500 + 2 × 2600 + 2 × 2300) ÷ 7.
        let planned = try #require(CoachBoard(boardInput(day: "2030-01-09")).weekAverage)
        #expect(planned.text == "Week avg 2,471 kcal")
        #expect(abs(planned.planned - 17_300.0 / 7) < 1e-9)
        #expect(planned.eaten == nil)
        // Two logged days: eaten against those days' targets (Gym 2500, Rest 2300).
        let eaten: [DayKey: Double] = [boardDay("2030-01-07"): 2450, boardDay("2030-01-08"): 2550, boardDay("2030-01-10"): 9000]
        let logged = try #require(CoachBoard(boardInput(day: "2030-01-09") { $0.eaten = eaten }).weekAverage)
        #expect(logged.loggedDays == 2)
        #expect(logged.eaten == 2500)
        #expect(logged.target == 2400)
        #expect(CoachBoard(boardInput(day: "2030-01-09") { $0.eaten = eaten }).weekAverageLine == "Week avg 2,500 of 2,400 kcal")
        // Not without day types, nor before the phase.
        #expect(CoachBoard(boardInput(boardPlan(types: false), day: "2030-01-09")).weekAverage == nil)
        #expect(CoachBoard(boardInput(day: "2030-01-01")).weekAverageLine == nil)
    }

    @Test func phaseStartTargetChanges() {
        let plan = boardPlan()
        let before = plan.revision(on: boardDay("2030-04-01"))
        // The cut's targets: every type 300 kcal lower, Rest only from the baseline.
        let after = CoachPlan.Revision(from: boardDay("2030-04-01"), baseline: DailyTargets(energy: 2000, protein: 160, carbs: 200, fat: 60),
                                       byType: ["gym": DailyTargets(energy: 2200, protein: 160, carbs: 230, fat: 60),
                                                "tennis": DailyTargets(energy: 2300, protein: 160, carbs: 250, fat: 60)])
        let changes = CoachBoard.targetChanges(plan: plan, before: before, after: after, fallback: boardFallback)
        #expect(changes.map(\.id) == ["gym", "tennis", "rest"])
        #expect(changes.map(\.before) == [2500, 2600, 2300])
        #expect(changes.map(\.after) == [2200, 2300, 2000])
        #expect(changes[0].title == "🏋️ Gym")
        #expect(changes[1].emoji == CoachPlan.DayType.suggestedEmoji(for: "Tennis"))
        let allChange = changes.allSatisfy { $0.changes }
        #expect(allChange)
        // Nothing running yet: the profile's targets before.
        let fresh = CoachBoard.targetChanges(plan: plan, before: nil, after: after, fallback: boardFallback)
        #expect(fresh.map(\.before) == [2200, 2200, 2200])
        // Without day types one line for the whole day; the same kcal is no change.
        let plain = CoachBoard.targetChanges(plan: boardPlan(types: false), before: nil,
                                             after: CoachPlan.Revision(from: boardDay("2030-04-01"), baseline: boardFallback),
                                             fallback: boardFallback)
        #expect(plain.map(\.id) == ["day"])
        #expect(plain.first?.title == "Every day")
        #expect(plain.first?.changes == false)
    }

    @Test func postponingAPhase() {
        let plan = boardPlan()
        #expect(plan.postponing(phase: "2", from: boardDay("2030-04-01"), calendar: boardUTC).phase(id: "2")?.start
                == boardDay("2030-04-08"))
        // A start that has already passed moves to a week from today.
        #expect(plan.postponing(phase: "2", from: boardDay("2030-04-03"), calendar: boardUTC).phase(id: "2")?.start
                == boardDay("2030-04-10"))
        #expect(plan.postponing(phase: "1", from: boardDay("2030-01-05"), calendar: boardUTC) == plan)
        #expect(plan.postponing(phase: "9", from: boardDay("2030-01-05"), calendar: boardUTC) == plan)
        // Moved on, it is no longer due.
        let moved = plan.postponing(phase: "2", from: boardDay("2030-04-01"), calendar: boardUTC)
        #expect(moved.duePhase(on: boardDay("2030-04-01")) == nil)
    }
}
