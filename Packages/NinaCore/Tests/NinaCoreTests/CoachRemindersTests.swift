import Foundation
import Testing
@testable import NinaCore

// A made-up plan: a lean gain started Mon 7 Jan 2030 (review at 79–80 kg), Gym Mon/Wed/Fri,
// Tennis twice a week, Rest otherwise; check-in on Mondays. All numbers are invented.

private var reminderUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func reminderDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func reminderTime(_ raw: String, _ minutes: Int) -> Date { reminderDay(raw).date(minutes: minutes, calendar: reminderUTC) }

private let reminderGym = DailyTargets(energy: 2500, protein: 150, carbs: 300, fat: 70)
private let reminderRest = DailyTargets(energy: 2300, protein: 150, carbs: 250, fat: 70)

private func reminderPlan(checks: [CoachPlan.Check]? = nil, pauses: [CoachPlan.Pause] = [], phases extra: [CoachPlan.Phase] = []) -> CoachPlan {
    let revision = CoachPlan.Revision(from: reminderDay("2030-01-07"), baseline: reminderRest,
                                      byType: ["gym": reminderGym, "rest": reminderRest], reason: "import")
    let gain = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: reminderDay("2030-01-07"), end: reminderDay("2030-03-29"),
                               rateMin: 0.1, rateMax: 0.2, reviewMin: 79, reviewMax: 80, targetWeight: 80,
                               startedAt: reminderTime("2030-01-07", 8 * 60), status: .active, revisions: [revision])
    let dayTypes = [
        CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
        CoachPlan.DayType(id: "tennis", name: "Tennis", emoji: "🎾", schedule: .flexible, perWeek: 2),
        CoachPlan.DayType(id: "rest", name: "Rest", emoji: "🛋️", schedule: .default),
    ]
    let defaultChecks = [
        CoachPlan.Check(id: "creatine", name: "Creatine", dose: "3–5 g", timing: .meal("breakfast"), isOptional: true, remind: true),
        CoachPlan.Check(id: "magnesium", name: "Magnesium", emoji: "🌙", timing: .time(22 * 60), remind: true),
        CoachPlan.Check(id: "omega", name: "Omega-3", timing: .meal("lunch")),
    ]
    var routine = CoachPlan.Routine()
    routine.checkInWeekday = 1
    return CoachPlan(dayTypes: dayTypes, phases: [gain] + extra, checks: checks ?? defaultChecks, routine: routine, pauses: pauses)
}

/// Monday 14 Jan 2030 at 06:00: a gym day and the check-in day.
private func reminderInput(_ plan: CoachPlan = reminderPlan(), now: Date = reminderTime("2030-01-14", 6 * 60),
                           kinds: Set<CoachReminders.Kind> = Set(CoachReminders.Kind.allCases)) -> CoachReminders.Input {
    let today = DayKey(date: now, calendar: reminderUTC)
    var input = CoachReminders.Input(plan: plan, now: now, today: today, kinds: kinds, calendar: reminderUTC)
    for offset in 0..<3 {
        let day = today.adding(days: offset, calendar: reminderUTC)
        input.targets[day] = plan.targets(on: day, marks: [:], fallback: .standard, calendar: reminderUTC)
    }
    input.lastWeight = 76.4
    return input
}

@Suite("Coach reminders")
struct CoachRemindersTests {
    @Test func nothingWithoutAPlan() {
        let input = reminderInput(CoachPlan())
        #expect(CoachReminders.plan(input).requests.isEmpty)
        var off = reminderInput()
        off.kinds = []
        #expect(CoachReminders.plan(off).requests.isEmpty)
    }

    @Test func morningWeighInWithFoldedChecks() throws {
        let schedule = CoachReminders.plan(reminderInput())
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-14"))
        #expect(morning.minutes == 7 * 60)
        #expect(morning.date == reminderTime("2030-01-14", 7 * 60))
        #expect(morning.title == "Good morning · 🏋️ Gym day")
        #expect(morning.body == "Weigh in before breakfast. Creatine · 3–5 g with breakfast. Today 2,500 kcal · 150 g protein.")
        #expect(morning.url == "nina://weigh")
        let actions = morning.category.actions
        #expect(actions.map(\.title) == ["Weight…", "Creatine done"])
        #expect(actions.first?.style == .textInput(button: "Save", placeholder: "76.4 kg"))
        // The breakfast check has no notification of its own; the evening one does (clamped to 21:00).
        #expect(schedule.request("nina.coach.check.creatine.2030-01-14") == nil)
        let magnesium = try #require(schedule.request("nina.coach.check.magnesium.2030-01-14"))
        #expect(magnesium.minutes == 21 * 60)
        #expect(magnesium.title == "🌙 Magnesium")
        #expect(magnesium.category.actions.map(\.title) == ["Taken", "Not today"])
        #expect(magnesium.checkID == "magnesium")
        // Checks without a reminder in the plan stay quiet.
        #expect(!schedule.ids.contains { $0.contains("omega") })
        // Three days, earliest first.
        #expect(schedule.requests.map(\.date) == schedule.requests.map(\.date).sorted())
        #expect(schedule.requests.contains { $0.id == "nina.coach.morning.2030-01-16" })
        #expect(!schedule.requests.contains { $0.day == reminderDay("2030-01-17") })
    }

    @Test func doneTasksTakeTheirNotificationAway() throws {
        var input = reminderInput()
        input.weighedIn = [reminderDay("2030-01-14")]
        var schedule = CoachReminders.plan(input)
        // Weighed in: the morning one stays for the creatine, and a tap opens Today.
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-14"))
        #expect(morning.body == "Creatine · 3–5 g with breakfast. Today 2,500 kcal · 150 g protein.")
        #expect(morning.url == "nina://today")
        #expect(morning.category.actions.map(\.title) == ["Creatine done"])

        input.checkStates[reminderDay("2030-01-14")] = ["creatine": .done, "magnesium": .skipped]
        schedule = CoachReminders.plan(input)
        #expect(schedule.request("nina.coach.morning.2030-01-14") == nil)
        #expect(schedule.request("nina.coach.check.magnesium.2030-01-14") == nil)
        #expect(schedule.request("nina.coach.check.magnesium.2030-01-15") != nil)
    }

    @Test func weeklyCheckInUntilSaved() throws {
        var input = reminderInput()
        let checkIn = try #require(CoachReminders.plan(input).request("nina.coach.checkin.2030-01-14"))
        #expect(checkIn.minutes == 18 * 60)
        #expect(checkIn.title == "Weekly check-in · 2 minutes")
        #expect(checkIn.url == "nina://checkin")
        #expect(checkIn.category.actions == [CoachReminders.Action(id: "open:nina://checkin", title: "Open", style: .foreground)])
        input.checkInKeys = [DayMarks.checkInKey(week: reminderDay("2030-01-14"), calendar: reminderUTC)]
        #expect(CoachReminders.plan(input).request("nina.coach.checkin.2030-01-14") == nil)
        // Not on the phase's first day: nothing to look back on yet.
        let first = reminderInput(now: reminderTime("2030-01-07", 6 * 60))
        #expect(CoachReminders.plan(first).request("nina.coach.checkin.2030-01-07") == nil)
    }

    @Test func atMostOneBeforeTen() throws {
        let early = CoachPlan.Check(id: "vitd", name: "Vitamin D", timing: .time(9 * 60 + 30), remind: true)
        let cut = CoachPlan.Phase(id: "2", name: "Cut", goal: .lose, start: reminderDay("2030-01-15"))
        let schedule = CoachReminders.plan(reminderInput(reminderPlan(checks: [early], phases: [cut])))
        let vitamin = try #require(schedule.request("nina.coach.check.vitd.2030-01-15"))
        let start = try #require(schedule.request("nina.coach.phase.start.2.2030-01-15"))
        #expect(vitamin.minutes == 10 * 60)
        #expect(start.minutes == 10 * 60)
        #expect(start.title == "Cut starts today")
        #expect(start.url == "nina://today")
        #expect(start.category.actions.map(\.id) == ["open:nina://plan"])
        let beforeTen = schedule.requests.filter { $0.day == reminderDay("2030-01-15") && $0.minutes < 10 * 60 }
        #expect(beforeTen.map(\.kind) == [.morning])

        // Without the weigh-in reminder the first early one keeps its time.
        let noMorning = CoachReminders.plan(reminderInput(reminderPlan(checks: [early], phases: [cut]), kinds: [.check, .phase]))
        #expect(noMorning.request("nina.coach.phase.start.2.2030-01-15")?.minutes == 9 * 60)
        #expect(noMorning.request("nina.coach.check.vitd.2030-01-15")?.minutes == 10 * 60)
    }

    @Test func quietHours() throws {
        var plan = reminderPlan(checks: [CoachPlan.Check(id: "early", name: "Iron", timing: .time(5 * 60), remind: true)])
        plan.routine.weighInMinutes = 5 * 60 + 30
        let schedule = CoachReminders.plan(reminderInput(plan))
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-14"))
        #expect(morning.minutes == 6 * 60)
        #expect(morning.body.hasPrefix("Weigh in before breakfast. Iron at 05:00."))
        #expect(schedule.requests.allSatisfy { $0.minutes >= 6 * 60 && $0.minutes <= 21 * 60 })
        #expect(CoachReminders.quiet(23 * 60) == 21 * 60)
    }

    @Test func checksFollowTheirTimeWhenTheMorningIsOff() throws {
        let schedule = CoachReminders.plan(reminderInput(kinds: [.check]))
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-14"))
        #expect(morning.minutes == MealSlot.breakfast.minutes)
        #expect(morning.body.hasPrefix("Creatine · 3–5 g with breakfast."))
        #expect(!morning.body.contains("Weigh in"))
        #expect(schedule.request("nina.coach.checkin.2030-01-14") == nil)
    }

    @Test func aPauseSilencesEverything() {
        let pause = CoachPlan.Pause(start: reminderDay("2030-01-14"), end: reminderDay("2030-01-15"), reason: .holiday)
        let schedule = CoachReminders.plan(reminderInput(reminderPlan(pauses: [pause])))
        #expect(schedule.requests.allSatisfy { $0.day == reminderDay("2030-01-16") })
        #expect(!schedule.requests.isEmpty)
    }

    @Test func eveningBeforeAFullSet() throws {
        var input = reminderInput(now: reminderTime("2030-01-13", 12 * 60))
        let monday = reminderDay("2030-01-14")
        input.bodyDue[monday] = [BodyDueItem(kind: .full, dueDay: monday, sites: [.waist, .chest], includesAssessment: true)]
        input.lastFullSet = reminderDay("2030-01-07")
        let schedule = CoachReminders.plan(input)
        let evening = try #require(schedule.request("nina.coach.measure.2030-01-13"))
        #expect(evening.minutes == 20 * 60)
        #expect(evening.title == "Tomorrow: full measurement")
        #expect(evening.body == "Before breakfast, after the bathroom – like on 7 Jan.")
        #expect(evening.category.actions.isEmpty)
        // The morning of the day says so and offers Measure.
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-14"))
        #expect(morning.body.contains("Full measurement today."))
        #expect(morning.category.actions.map(\.id).contains("open:nina://measure"))
        // An overdue set gets no evening reminder.
        input.bodyDue[monday] = [BodyDueItem(kind: .full, dueDay: reminderDay("2030-01-10"), overdueDays: 4)]
        #expect(CoachReminders.plan(input).request("nina.coach.measure.2030-01-13") == nil)
    }

    @Test func waistRightInTheMorningBanner() throws {
        var input = reminderInput()
        let monday = reminderDay("2030-01-14")
        input.bodyDue[monday] = [BodyDueItem(kind: .weekly, dueDay: monday, sites: [.waist])]
        input.lastTape = [.waist: 84.5]
        let morning = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-14"))
        #expect(morning.body.contains("Waist today."))
        let waist = try #require(morning.category.actions.first { $0.id == "tape:waist" })
        #expect(waist.title == "Waist…")
        #expect(waist.style == .textInput(button: "Save", placeholder: "84.5 cm"))
        #expect(morning.category.actions.first?.id == "weight")
        #expect(!morning.category.actions.contains { $0.id == "open:nina://measure" })

        // Several weekly sites (and a full set) open the measure sheet instead.
        input.bodyDue[monday] = [BodyDueItem(kind: .weekly, dueDay: monday, sites: [.waist, .hip])]
        let several = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-14"))
        #expect(several.category.actions.contains { $0.id == "open:nina://measure" })
        #expect(!several.category.actions.contains { $0.id.hasPrefix("tape:") })
    }

    /// No weekly sites and body fat more often than the full set: some mornings only body fat is
    /// due. The banner's button opens the body-fat sheet, not the (empty) tape pager.
    @Test func onlyBodyFatDueOpensTheBodyFatSheet() throws {
        let monday = reminderDay("2030-01-14")
        let routine = CoachPlan.Routine(weeklySites: [], fullEveryWeeks: 8, bodyFatEveryWeeks: 4)
        let start = reminderDay("2029-12-17")
        let body = BodySchedule(routine: routine, start: start, fullDays: [start], assessmentDays: [start])
        let due = body.dueItems(on: monday, calendar: reminderUTC)
        #expect(due.map(\.kind) == [.assessment])

        var input = reminderInput()
        input.bodyDue[monday] = due
        let morning = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-14"))
        #expect(morning.body.contains("Body fat today."))
        let open = try #require(morning.category.actions.first { $0.id.hasPrefix("open:") })
        #expect(open.id == "open:nina://measure?mode=assessment")
        #expect(open.title == "Body Fat")
        #expect(open.style == .foreground)
        #expect(!morning.category.actions.contains { $0.id == "open:nina://measure" })
        #expect(CoachReminders.command(action: open.id) == .open("nina://measure?mode=assessment"))

        // A full set that includes body fat still opens the tape pager.
        input.bodyDue[monday] = [BodyDueItem(kind: .full, dueDay: monday, sites: [.waist, .chest], includesAssessment: true)]
        let full = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-14"))
        #expect(full.category.actions.contains { $0.id == "open:nina://measure" })
        #expect(!full.category.actions.contains { $0.id.hasSuffix("mode=assessment") })
    }

    @Test func typedTapeValues() {
        #expect(CoachReminders.command(action: "tape:waist", text: "84,5") == .tape(.waist, 84.5))
        #expect(CoachReminders.command(action: "tape:waist", text: " 84.5 cm ") == .tape(.waist, 84.5))
        #expect(CoachReminders.command(action: "tape:waist", text: "8.45") == .tape(.waist, nil))
        #expect(CoachReminders.command(action: "tape:waist", text: "84 kg") == .tape(.waist, nil))
        #expect(CoachReminders.command(action: "tape:waist_narrow", text: "71") == .tape(.waistNarrow, 71))
        #expect(CoachReminders.command(action: "tape:nose", text: "84") == nil)

        let records = [
            BodyTapeRecord(day: reminderDay("2030-01-07"), values: BodyValues([BodySite.waist: 84.0])),
            BodyTapeRecord(day: reminderDay("2029-12-01"), values: BodyValues([BodySite.waist: 90.0, BodySite.hip: 100.0])),
        ]
        #expect(CoachReminders.lastTape(records) == [.waist: 84.0, .hip: 100.0])
        // A change of more than 3 cm within a week needs a look; later it's fine.
        let monday = reminderDay("2030-01-14")
        #expect(!CoachReminders.tapeNeedsALook(84.6, site: .waist, on: monday, records: records, calendar: reminderUTC))
        #expect(CoachReminders.tapeNeedsALook(87.6, site: .waist, on: monday, records: records, calendar: reminderUTC))
        #expect(!CoachReminders.tapeNeedsALook(87.6, site: .waist, on: reminderDay("2030-01-21"), records: records, calendar: reminderUTC))
        #expect(!CoachReminders.tapeNeedsALook(120.0, site: .chest, on: monday, records: records, calendar: reminderUTC))
    }

    @Test func flexibleTypeOfferedOnARestDay() throws {
        // Tue 15 Jan is a rest day; no tennis yet this week.
        var input = reminderInput()
        var morning = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-15"))
        #expect(morning.title == "Good morning · 🛋️ Rest day")
        #expect(morning.category.actions.map(\.id) == ["weight", "daytype:tennis", "check.done:creatine"])
        #expect(morning.category.actions.map(\.title).contains("🎾 Tennis today"))
        // Two tennis days already this week: no offer.
        input.dayTypeMarks = ["2030-01-14": "tennis", "2030-01-16": "tennis"]
        morning = try #require(CoachReminders.plan(input).request("nina.coach.morning.2030-01-15"))
        #expect(!morning.category.actions.map(\.id).contains("daytype:tennis"))
    }

    @Test func atMostFourActions() throws {
        let checks = (1...5).map { CoachPlan.Check(id: "c\($0)", name: "Check \($0)", timing: .anytime, remind: true) }
        let schedule = CoachReminders.plan(reminderInput(reminderPlan(checks: checks)))
        let morning = try #require(schedule.request("nina.coach.morning.2030-01-15"))
        #expect(morning.category.actions.count == CoachReminders.maxActions)
        #expect(morning.category.actions.first?.id == "weight")
    }

    @Test func reviewComesOnce() throws {
        var input = reminderInput(now: reminderTime("2030-01-14", 12 * 60))
        input.checkpoint = reminderDay("2030-01-13")
        let review = try #require(CoachReminders.plan(input).request("nina.coach.phase.review.1"))
        #expect(review.date == reminderTime("2030-01-14", 12 * 60 + 1))
        #expect(review.title == "Time for a phase review")
        #expect(review.body == "Lean gain: 79 kg reached – time to review.")
        #expect(review.url == "nina://review/1")
        // Planned once: the stored time wins; once it passed it's no longer pending.
        input.reviewPlannedAt = ["1": reminderTime("2030-01-14", 12 * 60 + 1)]
        input.now = reminderTime("2030-01-14", 15 * 60)
        let schedule = CoachReminders.plan(input)
        #expect(schedule.request("nina.coach.phase.review.1")?.date == reminderTime("2030-01-14", 12 * 60 + 1))
        #expect(!schedule.pending(after: input.now).contains { $0.id == "nina.coach.phase.review.1" })
        // After 21:00 it waits for the morning.
        var late = reminderInput(now: reminderTime("2030-01-14", 21 * 60 + 30))
        late.checkpoint = reminderDay("2030-01-13")
        #expect(CoachReminders.plan(late).request("nina.coach.phase.review.1")?.date == reminderTime("2030-01-15", 10 * 60))
        // A review decision ends it.
        input.reviewedPhases = ["1"]
        #expect(CoachReminders.plan(input).request("nina.coach.phase.review.1") == nil)
    }

    @Test func phaseEndOnItsDate() throws {
        let input = reminderInput(now: reminderTime("2030-03-28", 6 * 60))
        let end = try #require(CoachReminders.plan(input).request("nina.coach.phase.end.1.2030-03-29"))
        #expect(end.title == "Lean gain ends today")
        #expect(end.minutes == 10 * 60)
    }

    @Test func pendingLeavesPastOnesOut() {
        let input = reminderInput(now: reminderTime("2030-01-14", 12 * 60))
        let schedule = CoachReminders.plan(input)
        #expect(schedule.ids.contains("nina.coach.morning.2030-01-14"))
        #expect(!schedule.pending(after: input.now).contains { $0.id == "nina.coach.morning.2030-01-14" })
        #expect(schedule.pending(after: input.now).contains { $0.id == "nina.coach.checkin.2030-01-14" })
        #expect(Set(schedule.categories.map(\.id)).count == schedule.categories.count)
    }

    @Test func actionCommands() {
        #expect(CoachReminders.command(action: "weight", text: "76,4") == .weight(76.4))
        #expect(CoachReminders.command(action: "weight", text: "hello") == .weight(nil))
        #expect(CoachReminders.command(action: "open:nina://checkin") == .open("nina://checkin"))
        #expect(CoachReminders.command(action: "check.done:creatine") == .check("creatine", .done))
        #expect(CoachReminders.command(action: "check.skip:creatine") == .check("creatine", .skipped))
        #expect(CoachReminders.command(action: "daytype:tennis") == .dayType("tennis"))
        #expect(CoachReminders.command(action: "eaten") == nil)
    }

    @Test func typedWeights() {
        #expect(CoachReminders.weight(from: "76,4") == 76.4)
        #expect(CoachReminders.weight(from: "76.4 kg") == 76.4)
        #expect(CoachReminders.weight(from: " 76.4kg ") == 76.4)
        #expect(CoachReminders.weight(from: "76 KG") == 76)
        #expect(CoachReminders.weight(from: "7.64") == nil)
        #expect(CoachReminders.weight(from: "764") == nil)
        #expect(CoachReminders.weight(from: "76 4") == nil)
        #expect(CoachReminders.weight(from: "1.076,4") == nil)
        #expect(CoachReminders.weight(from: "") == nil)
        // The sheet is prefilled with what was typed when it needs a look.
        #expect(CoachReminders.number(from: "7,64 kg") == 7.64)
        #expect(CoachReminders.number(from: "764") == 764)
        #expect(CoachReminders.number(from: "1/2") == nil)
        #expect(CoachReminders.number(from: "-70") == nil)
    }
}

@Suite("Today snapshot: day types")
struct CoachSnapshotTests {
    @Test func olderFilesStillRead() throws {
        // A file written before day types existed.
        let old = """
        {"day":"2030-01-14","energy":1200,"energyGoal":2500,"protein":80,"proteinGoal":150,"carbs":120,"carbsGoal":300,
         "fat":40,"fatGoal":70,"water":1000,"waterGoal":2500,"energyUnit":"kcal","updatedAt":0}
        """
        let snapshot = try JSONDecoder().decode(TodaySnapshot.self, from: Data(old.utf8))
        #expect(snapshot.energyGoal == 2500)
        #expect(snapshot.dayTypeEmoji == nil)
        #expect(snapshot.dayTypePrefix == "")
        #expect(snapshot.tomorrow == nil)
    }

    @Test func dayTypeAndTomorrowRoundTrip() throws {
        let gym = CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1]))
        let tennis = CoachPlan.DayType(id: "tennis", name: "Tennis", schedule: .flexible, perWeek: 2)
        var snapshot = TodaySnapshot(day: "2030-01-14", energy: 1200, energyGoal: 2500, protein: 80, proteinGoal: 150, carbs: 120,
                                     carbsGoal: 300, fat: 40, fatGoal: 70, water: 1000, waterGoal: 2500)
        snapshot.use(dayType: gym, isManual: true)
        snapshot.tomorrow = TodaySnapshot.Goals(day: reminderDay("2030-01-15"), targets: reminderRest, dayType: tennis)
        #expect(snapshot.dayTypePrefix == "🏋️ ")
        #expect(snapshot.dayTypeIsManual == true)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(TodaySnapshot.self, from: data) == snapshot)

        // After midnight: the next day's goals and its emoji (a fitting one when the type has none).
        let next = snapshot.current(today: reminderDay("2030-01-15"))
        #expect(next.energy == 0)
        #expect(next.energyGoal == 2300)
        #expect(next.dayTypeID == "tennis")
        #expect(next.dayTypeEmoji == CoachPlan.DayType.suggestedEmoji(for: "Tennis"))
        // A day further on keeps the goals but not the day type.
        let later = snapshot.current(today: reminderDay("2030-01-16"))
        #expect(later.energyGoal == 2500)
        #expect(later.dayTypeEmoji == nil)
        snapshot.use(dayType: nil)
        #expect(snapshot.dayTypeID == nil && snapshot.dayTypeIsManual == nil)
    }
}
