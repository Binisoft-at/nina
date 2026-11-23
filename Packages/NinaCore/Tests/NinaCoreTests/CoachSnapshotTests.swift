import Foundation
import Testing
@testable import NinaCore

// A made-up plan set up on Thu 3 Jan 2030: a lean gain, Gym on Mon/Wed/Fri, Tennis twice a
// week, Rest otherwise; the baseline full set on 3 Jan and a weekly waist on Mon 7 Jan.

private var snapUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func snapDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func snapTime(_ raw: String, _ minutes: Int) -> Date { snapDay(raw).date(minutes: minutes, calendar: snapUTC) }

private func snapPlan(pauses: [CoachPlan.Pause] = []) -> CoachPlan {
    let revision = CoachPlan.Revision(from: snapDay("2030-01-03"), baseline: DailyTargets(energy: 2450, protein: 150, carbs: 300, fat: 70),
                                      byType: [:], reason: "import")
    let gain = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: snapDay("2030-01-03"), end: snapDay("2030-03-28"),
                               endApprox: true, rateMin: 0.1, rateMax: 0.2, startedAt: snapTime("2030-01-03", 8 * 60),
                               status: .active, revisions: [revision])
    let types = [
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
    return CoachPlan(dayTypes: types, phases: [gain], checks: checks, pauses: pauses)
}

/// The baseline (full set and assessment on 3 Jan), a weekly waist on 7 Jan and optionally on 14 Jan.
private func snapSchedule(_ plan: CoachPlan, waistOn14: Bool = false) -> BodySchedule {
    let full: [BodySite: Double] = [.neck: 38, .chest: 100, .arm: 34, .waist: 82, .hip: 96, .thigh: 56]
    var tape = [BodyTapeRecord(day: snapDay("2030-01-03"), values: BodyValues(full), conditions: "morning,fasted"),
                BodyTapeRecord(day: snapDay("2030-01-07"), values: BodyValues([.waist: 82.5]), conditions: "morning,fasted")]
    if waistOn14 {
        tape.append(BodyTapeRecord(day: snapDay("2030-01-14"), values: BodyValues([.waist: 82.6]), conditions: "morning,fasted"))
    }
    return BodySchedule(plan: plan, start: BodySchedule.setUpDay(of: plan, calendar: snapUTC), tape: tape,
                        assessmentDays: [snapDay("2030-01-03")])
}

private func snapInput(_ plan: CoachPlan = snapPlan(), today: String = "2030-01-14", minutes: Int = 7 * 60,
                       configure: (inout CoachSnapshot.Input) -> Void = { _ in }) -> CoachSnapshot.Input {
    var input = CoachSnapshot.Input(plan: plan, today: snapDay(today), now: snapTime(today, minutes), energyToday: 2500,
                                    energyTomorrow: 2300, schedule: snapSchedule(plan), calendar: snapUTC)
    configure(&input)
    return input
}

/// Daily morning weigh-ins from 1 Jan 2030 rising 0.2 kg a week, and a phase that matches them.
private func snapWeightPlan(pause: CoachPlan.Pause? = nil) -> CoachPlan {
    let start = snapDay("2030-01-01")
    let phase = CoachPlan.Phase(id: "1", name: "Lean gain", goal: .gain, start: start, end: snapDay("2030-03-31"), rateMin: 0.15,
                                rateMax: 0.25, startedAt: start.date(minutes: 8 * 60, calendar: snapUTC), status: .active)
    return CoachPlan(dayTypes: [CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default)], phases: [phase],
                     pauses: pause.map { [$0] } ?? [])
}

private func snapSummary(_ plan: CoachPlan, today: String = "2030-01-21") -> WeightSignal.Summary {
    let start = snapDay("2030-01-01")
    let readings = (0...20).map { offset -> WeightSignal.Reading in
        let day = start.adding(days: offset, calendar: snapUTC)
        return WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: snapUTC), kilograms: 74 + 0.2 / 7 * Double(offset))
    }
    return WeightSignal(readings, calendar: snapUTC).summary(on: snapDay(today), plan: plan)
}

@Suite("Coach widget snapshot")
struct CoachWidgetSnapshotTests {
    @Test func todayAndTomorrow() throws {
        let snapshot = CoachSnapshot(snapInput { input in
            input.checkStates = ["creatine": .done]
            input.dayTypeMarks = ["2030-01-15": "tennis"]
        })
        #expect(snapshot.day == "2030-01-14")
        #expect(snapshot.isSetUp)
        #expect(snapshot.days.map(\.day) == ["2030-01-14", "2030-01-15"])

        // Monday: Gym from the schedule; checks timed to meals first, then clock times, then anytime.
        let monday = snapshot.days[0]
        let gym = try #require(monday.dayType)
        #expect(gym.id == "gym" && gym.label == "🏋️ Gym" && gym.title == "Gym day" && !gym.isManual && gym.energy == 2500)
        #expect(monday.checks.map(\.id) == ["creatine", "magnesium", "vitd", "omega"])
        #expect(monday.checks.map(\.state) == [.done, .open, .open, .open])
        #expect(monday.checks[0].dose == "3–5 g" && monday.checks[0].isOptional)
        #expect(monday.checks[0].label == "💊 Creatine" && monday.checks[2].label == "Vitamin D")
        #expect(monday.weighInUntil == snapTime("2030-01-14", 11 * 60))
        #expect(!monday.isPaused)

        // Tuesday picked as Tennis by hand: its own check is due, everything open, the weigh-in asked for.
        let tuesday = snapshot.days[1]
        #expect(tuesday.dayType?.id == "tennis")
        #expect(tuesday.dayType?.isManual == true)
        #expect(tuesday.dayType?.emoji == CoachPlan.DayType.suggestedEmoji(for: "Tennis"))
        #expect(tuesday.dayType?.energy == 2300)
        #expect(tuesday.checks.map(\.id) == ["creatine", "magnesium", "vitd", "omega", "electrolytes"])
        let allOpen = tuesday.checks.allSatisfy { $0.isOpen }
        #expect(allOpen)
        #expect(tuesday.weighInUntil == snapTime("2030-01-15", 11 * 60))
    }

    @Test func weighInFollowsTheMorning() {
        // Weighed in already: nothing to ask today, but tomorrow still asks.
        let weighed = CoachSnapshot(snapInput { $0.hasMorningWeighIn = true })
        #expect(weighed.days[0].weighInUntil == nil)
        #expect(weighed.days[1].weighInUntil != nil)
        // Made after the cutoff: not asked for any more.
        let late = CoachSnapshot(snapInput(minutes: 12 * 60))
        #expect(late.days[0].weighInUntil == nil)
    }

    @Test func shownThroughTheDay() {
        let snapshot = CoachSnapshot(snapInput { $0.checkStates = ["creatine": .done, "omega": .skipped] })

        let morning = snapshot.shown(at: snapTime("2030-01-14", 7 * 60 + 5), calendar: snapUTC)
        #expect(morning.day == snapDay("2030-01-14"))
        #expect(!morning.isOutdated)
        #expect(morning.needsWeighIn)
        #expect(morning.primary == .weighIn)
        #expect(morning.openChecks.map(\.id) == ["magnesium", "vitd"])
        #expect(morning.checksText == "2 of 4 done")

        // After the cutoff the weekly waist (due today) is what a tap opens.
        let noon = snapshot.shown(at: snapTime("2030-01-14", 12 * 60), calendar: snapUTC)
        #expect(!noon.needsWeighIn)
        #expect(noon.measurement?.kind == .weekly)
        #expect(noon.measurementLine(calendar: snapUTC) == "Waist · today")
        #expect(noon.primary == .measure(.weekly))

        // The day changes at midnight: tomorrow's Rest day, everything open, the waist overdue.
        let next = snapshot.shown(at: snapTime("2030-01-15", 0), calendar: snapUTC)
        #expect(next.day == snapDay("2030-01-15"))
        #expect(next.dayType?.id == "rest")
        #expect(next.checks.count == 4 && next.openChecks.count == 4)
        #expect(next.needsWeighIn)
        #expect(next.measurementWhen(calendar: snapUTC) == "overdue 1 day")

        // Two days on, the snapshot doesn't know the day.
        let later = snapshot.shown(at: snapTime("2030-01-16", 8 * 60), calendar: snapUTC)
        #expect(later.isOutdated)
        #expect(later.dayType == nil && later.checks.isEmpty && !later.needsWeighIn)
        #expect(later.weight == snapshot.weight)
        #expect(later.measurementWhen(calendar: snapUTC) == "overdue 2 days")
    }

    @Test func dayStartHourMovesTheDay() {
        // The diary day starts at 3:00: 01:30 on the 15th still counts for the 14th.
        let snapshot = CoachSnapshot(snapInput { $0.dayStartHour = 3 })
        #expect(snapshot.today(now: snapTime("2030-01-15", 90), calendar: snapUTC) == snapDay("2030-01-14"))
        #expect(snapshot.shown(at: snapTime("2030-01-15", 90), calendar: snapUTC).dayType?.id == "gym")
        #expect(snapshot.shown(at: snapTime("2030-01-15", 4 * 60), calendar: snapUTC).dayType?.id == "rest")
        #expect(snapshot.nextReload(after: snapTime("2030-01-14", 7 * 60), calendar: snapUTC)
                == snapTime("2030-01-15", 3 * 60).addingTimeInterval(60))
    }

    @Test func timelinePoints() {
        let now = snapTime("2030-01-14", 7 * 60)
        let points = CoachSnapshot(snapInput()).timeline(now: now, calendar: snapUTC)
        #expect(points.map(\.date) == [now, snapTime("2030-01-14", 11 * 60), snapTime("2030-01-15", 0),
                                       snapTime("2030-01-15", 11 * 60), snapTime("2030-01-16", 0)])
        #expect(points.map(\.shown.needsWeighIn) == [true, false, true, false, false])
        #expect(points.last?.shown.isOutdated == true)
    }

    @Test func nextMeasurement() {
        let plan = snapPlan()
        // The waist of 14 Jan was measured: the next one is Monday 21 Jan.
        let measured = CoachSnapshot(snapInput { $0.schedule = snapSchedule(plan, waistOn14: true) })
        let next = measured.measurement
        #expect(next?.kind == .weekly)
        #expect(next?.title == "Waist")
        #expect(next?.dueDay == "2030-01-21")
        #expect(next?.symbol == "ruler")
        #expect(next?.whenText(on: snapDay("2030-01-14"), calendar: snapUTC) == "21 Jan")
        #expect(next?.whenText(on: snapDay("2030-01-16"), calendar: snapUTC) == "Mon")
        #expect(next?.whenText(on: snapDay("2030-01-20"), calendar: snapUTC) == "tomorrow")
        #expect(next?.isDue(on: snapDay("2030-01-20")) == false)
        #expect(next?.isDue(on: snapDay("2030-01-21")) == true)

        // Weeks later the full set (with the assessment) comes first.
        let full = CoachSnapshot(snapInput(today: "2030-02-25") { $0.schedule = snapSchedule(plan, waistOn14: true) })
        #expect(full.measurement?.kind == .full)
        #expect(full.measurement?.title == "Full measurement")
        #expect(full.measurement?.symbol == "figure.arms.open")
    }

    @Test func weightStatus() throws {
        let plan = snapWeightPlan()
        let snapshot = CoachSnapshot(snapInput(plan, today: "2030-01-21") { $0.summary = snapSummary(plan) })
        let weight = try #require(snapshot.weight)
        #expect(weight.word == "In range")
        #expect(weight.line == "In range")
        #expect(weight.tone == .good)
        #expect(weight.phaseName == "Lean gain")
        #expect(weight.averageText() == "74.5 kg")
        #expect(weight.rateText() == "+0.20 kg/wk")
        #expect(weight.statusText() == "+0.20 kg/wk · In range")
        let comma: (Double, Int) -> String = { value, decimals in CoachSnapshot.fixed(value, decimals).replacingOccurrences(of: ".", with: ",") }
        #expect(weight.statusText(number: comma) == "+0,20 kg/wk · In range")
    }

    @Test func pausedDay() throws {
        let pause = CoachPlan.Pause(start: snapDay("2030-01-20"), end: snapDay("2030-01-31"))
        let plan = snapWeightPlan(pause: pause)
        let snapshot = CoachSnapshot(snapInput(plan, today: "2030-01-21") { $0.summary = snapSummary(plan) })
        let weight = try #require(snapshot.weight)
        #expect(weight.word == "Paused")
        #expect(weight.line == "Paused · until 31 Jan")
        #expect(weight.rate == nil)
        #expect(weight.tone == .neutral)
        #expect(snapshot.days[0].isPaused)
        #expect(snapshot.days[0].checks.isEmpty && snapshot.days[0].weighInUntil == nil)
        #expect(snapshot.measurement == nil)
        let shown = snapshot.shown(at: snapTime("2030-01-21", 8 * 60), calendar: snapUTC)
        #expect(shown.isPaused && shown.primary == .progress)
    }

    @Test func withoutAPlan() {
        let plan = CoachPlan()
        let snapshot = CoachSnapshot(snapInput(plan, today: "2030-01-21") { input in
            input.summary = snapSummary(plan)
            input.schedule = BodySchedule(isSetUp: false)
        })
        #expect(!snapshot.isSetUp)
        let bare = snapshot.days.allSatisfy { $0.dayType == nil && $0.checks.isEmpty && $0.weighInUntil == nil }
        #expect(bare)
        #expect(snapshot.measurement == nil)
        // The average still shows, without status words.
        #expect(snapshot.weight?.average != nil)
        #expect(snapshot.weight?.word == nil && snapshot.weight?.tone == .neutral)
        #expect(snapshot.shown(at: snapTime("2030-01-21", 8 * 60), calendar: snapUTC).primary == .plan)
        // No weigh-ins either: nothing to show.
        #expect(CoachSnapshot(snapInput(plan) { $0.schedule = BodySchedule(isSetUp: false) }).weight == nil)
    }

    @Test func beforeThePlanWasSetUp() {
        // On 2 Jan the plan (set up on 3 Jan) shows its day type but no checks and no weigh-in yet.
        let snapshot = CoachSnapshot(snapInput(today: "2030-01-02"))
        #expect(snapshot.days[0].dayType != nil)
        #expect(snapshot.days[0].checks.isEmpty && snapshot.days[0].weighInUntil == nil)
        #expect(!snapshot.days[1].checks.isEmpty)
    }

    @Test func checksText() {
        func shown(_ states: [CoachBoard.StripItem.State]) -> CoachSnapshot.Shown {
            var value = CoachSnapshot.placeholderShown
            value.checks = states.enumerated().map { index, state in
                CoachSnapshot.Check(id: "c\(index)", name: "Check \(index)", emoji: "", dose: "", state: state, isOptional: false)
            }
            return value
        }
        #expect(shown([]).checksText == nil)
        #expect(shown([.open]).checksText == "0 of 1 done")
        #expect(shown([.done]).checksText == "Done")
        #expect(shown([.done, .skipped, .done]).checksText == "All 3 done")
        #expect(shown([.done, .open, .open]).checksText == "1 of 3 done")
    }

    @Test func links() {
        #expect(CoachSnapshot.Link.weighIn.url(scheme: "nina") == "nina://weigh")
        #expect(CoachSnapshot.Link.measure(.weekly).url(scheme: "nina") == "nina://measure?mode=weekly")
        #expect(CoachSnapshot.Link.measure(.full).url(scheme: "nina") == "nina://measure?mode=full")
        #expect(CoachSnapshot.Link.measure(.assessment).url(scheme: "nina") == "nina://measure?mode=assessment")
        #expect(CoachSnapshot.Link.check("creatine").url(scheme: "nina") == "nina://check/creatine")
        #expect(CoachSnapshot.Link.check("a b/c").url(scheme: "nina") == "nina://check/a%20b%2Fc")
        #expect(CoachSnapshot.Link.progress.url(scheme: "nina") == "nina://progress")
        #expect(CoachSnapshot.Link.plan.url(scheme: "nina") == "nina://plan")
        #expect(CoachSnapshot.Link.today.url(scheme: "nina") == "nina://today")
    }

    @Test func numbers() {
        #expect(CoachSnapshot.signed(0.153, decimals: 2) == "+0.15")
        #expect(CoachSnapshot.signed(-0.2, decimals: 2) == "\u{2212}0.20")
        #expect(CoachSnapshot.signed(0.001, decimals: 2) == "0.00")
        #expect(CoachSnapshot.fixed(-0.04, 1) == "0.0")
    }

    @Test func fileRoundTrip() throws {
        let snapshot = CoachSnapshot(snapInput { $0.checkStates = ["creatine": .done] })
        // The App Group file is written and read with ISO 8601 dates (BinisoftKit's SnapshotFile).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CoachSnapshot.self, from: try encoder.encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.v == CoachSnapshot.currentVersion)

        var later = snapshot
        later.updatedAt = snapTime("2030-01-14", 9 * 60)
        #expect(later.hasSameContent(as: snapshot))
        later.days[0].checks[1].state = .done
        #expect(!later.hasSameContent(as: snapshot))
        #expect(!snapshot.hasSameContent(as: nil))
    }

    @Test func todayWidgetIsAlwaysKcal() throws {
        // A snapshot written by an older build that showed kJ still reads, and shows kcal.
        let json = """
        {"day":"2030-01-14","energy":1200,"energyGoal":2400,"protein":80,"proteinGoal":150,"carbs":100,"carbsGoal":300,
         "fat":40,"fatGoal":70,"water":1000,"waterGoal":2500,"energyUnit":"kJ","updatedAt":0}
        """
        let snapshot = try JSONDecoder().decode(TodaySnapshot.self, from: Data(json.utf8))
        #expect(snapshot.unit == .kcal)
        #expect(snapshot.energyUnit == "kJ")
    }

    @Test func siriNames() {
        #expect(CoachSiriNames.dayTypeSynonyms("Tennis") == ["Tennis day", "Tennistag", "Tennis Tag"])
        #expect(CoachSiriNames.dayTypeSynonyms("Ruhetag").isEmpty)
        #expect(CoachSiriNames.dayTypeSynonyms("Rest day").isEmpty)
        #expect(CoachSiriNames.dayTypeSynonyms("  ").isEmpty)

        #expect(CoachSiriNames.key("Tennistag") == "tennis")
        #expect(CoachSiriNames.key(" Rest Day ") == "rest")
        #expect(CoachSiriNames.key("Kraft-Tag") == "kraft")
        #expect(CoachSiriNames.key("Day") == "day")

        #expect(CoachSiriNames.matches("tennistag", name: "Tennis"))
        #expect(CoachSiriNames.matches("Tennis day", name: "Tennis"))
        #expect(CoachSiriNames.matches("ten", name: "Tennis"))
        #expect(CoachSiriNames.matches("Kreatin", name: "Kreatin"))
        #expect(CoachSiriNames.key("Omega-3") == "omega3")
        #expect(CoachSiriNames.matches("Omega 3", name: "Omega-3"))
        #expect(CoachSiriNames.matches("omega", name: "Omega-3"))
        #expect(CoachSiriNames.matches("Vitamin-D", name: "Vitamin D"))
        #expect(CoachSiriNames.matches("Ruhetag", name: "Ruhetag"))
        #expect(CoachSiriNames.matches("Gym", name: "Tennis") == false)
        #expect(CoachSiriNames.matches("", name: "Tennis") == false)
    }
}
