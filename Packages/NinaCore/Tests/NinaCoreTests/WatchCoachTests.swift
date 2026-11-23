import Foundation
import Testing
@testable import NinaCore

// Made-up numbers: a lean gain from Tue 1 Jan 2030 at 0.15–0.25 kg a week, weigh-ins around
// 74 kg, a waist around 82 cm.

private var watchUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func watchDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func watchPhase(id: String = "1", goal: WeightGoal = .gain) -> CoachPlan.Phase {
    let start = watchDay("2030-01-01")
    return CoachPlan.Phase(id: id, name: "Lean gain", goal: goal, start: start, end: watchDay("2030-03-31"), rateMin: 0.15,
                           rateMax: 0.25, startedAt: start.date(minutes: 8 * 60, calendar: watchUTC), status: .active)
}

private func watchPlan(checks: [CoachPlan.Check] = []) -> CoachPlan {
    let types = [
        CoachPlan.DayType(id: "gym", name: "Gym", emoji: "🏋️", schedule: .fixed, weekdays: Weekdays([1, 3, 5])),
        CoachPlan.DayType(id: "tennis", name: "Tennis", emoji: "🎾", schedule: .flexible, perWeek: 2),
        CoachPlan.DayType(id: "rest", name: "Rest", schedule: .default),
    ]
    return CoachPlan(dayTypes: types, phases: [watchPhase()], checks: checks)
}

/// "1,240": what the watch's locale formatting does to kcal.
private func grouped(_ value: Double) -> String {
    let digits = String(Int(value.rounded()))
    var result = ""
    for (index, character) in digits.enumerated() {
        if index > 0, (digits.count - index) % 3 == 0 { result += "," }
        result.append(character)
    }
    return result
}

struct WatchCoachCrownTests {
    @Test func valuesStayOnTheGrid() {
        let range = WeightSignal.plausibleRange
        #expect(WatchCoach.snapped(74.30000000001, in: range) == 74.3)
        #expect(WatchCoach.snapped(74.26, in: range) == 74.3)
        #expect(WatchCoach.snapped(10, in: range) == 25)
        #expect(WatchCoach.snapped(412, in: range) == 300)
        #expect(WatchCoach.snapped(.nan, in: range) == 25)
        #expect(WatchCoach.stepped(74.2, by: 1, in: range) == 74.3)
        #expect(WatchCoach.stepped(74.2, by: -3, in: range) == 73.9)
        #expect(WatchCoach.stepped(299.95, by: 1, in: range) == 300)
        #expect(WatchCoach.stepped(25, by: -1, in: range) == 25)
        var value = 74.0
        for _ in 0..<10 { value = WatchCoach.stepped(value, by: 1, in: range) }
        #expect(value == 75.0)
    }

    @Test func weighInStartsFromTheLastTypedWeight() {
        #expect(WatchCoach.startWeight(latest: 74.24, bodyWeight: 75) == 74.2)
        #expect(WatchCoach.startWeight(latest: nil, bodyWeight: 75.36) == 75.4)
        #expect(WatchCoach.startWeight(latest: nil, bodyWeight: nil) == WatchCoach.defaultWeight)
        #expect(WatchCoach.startWeight(latest: 0, bodyWeight: nil) == WatchCoach.defaultWeight)
        #expect(WatchCoach.startWeight(latest: 412, bodyWeight: nil) == 300)
    }

    @Test func tapeStartsFromTheSitesLastReading() {
        #expect(WatchCoach.startGirth(.waist, previous: 82.46) == 82.5)
        #expect(WatchCoach.startGirth(.waistNarrow, previous: nil) == 75)
        #expect(WatchCoach.startGirth(.armLeft, previous: nil) == 30)
        #expect(WatchCoach.startGirth(.waist, previous: 10) == 50)
        for site in BodySite.allCases {
            #expect(site.isPlausible(WatchCoach.typicalGirth(site)))
        }
    }

    @Test func previousReadingOfASite() {
        let records = [
            BodyTapeRecord(day: watchDay("2030-01-07"), values: BodyValues([.waist: 82, .hip: 97]), conditions: "morning,fasted"),
            BodyTapeRecord(day: watchDay("2030-01-14"), values: BodyValues([.waist: 82.5]), conditions: "later"),
            BodyTapeRecord(day: watchDay("2030-01-21"), values: BodyValues([.waist: 83]), conditions: "morning,fasted"),
        ]
        let waist = WatchCoach.previousGirth(.waist, in: records, onOrBefore: watchDay("2030-01-20"))
        #expect(waist?.value == 82.5)
        #expect(waist?.day == watchDay("2030-01-14"))
        #expect(WatchCoach.previousGirth(.waist, in: records, onOrBefore: watchDay("2030-01-10"))?.value == 82)
        #expect(WatchCoach.previousGirth(.hip, in: records, onOrBefore: watchDay("2030-01-21"))?.value == 97)
        #expect(WatchCoach.previousGirth(.chest, in: records, onOrBefore: watchDay("2030-01-21")) == nil)
    }

    @Test func notesUnderATapeValue() {
        let previous = GirthReading(day: watchDay("2030-01-14"), value: 82)
        let calendar = watchUTC
        #expect(WatchCoach.girthNote(82.5, previous: previous, on: watchDay("2030-01-21"), calendar: calendar) == .ok)
        #expect(WatchCoach.girthNote(83.2, previous: previous, on: watchDay("2030-01-21"), calendar: calendar) == .recheck)
        #expect(WatchCoach.girthNote(85.5, previous: previous, on: watchDay("2030-01-17"), calendar: calendar) == .jump)
        #expect(WatchCoach.girthNote(85.5, previous: previous, on: watchDay("2030-01-28"), calendar: calendar) == .recheck)
        #expect(WatchCoach.girthNote(90, previous: nil, on: watchDay("2030-01-28"), calendar: calendar) == .ok)
    }
}

struct WatchCoachChipTests {
    private func chip(emoji: String = "🎾") -> CoachBoard.Chip {
        CoachBoard.Chip(id: "tennis", name: "Tennis", emoji: emoji, title: "Tennis day", isManual: true,
                        quotaText: "Tennis · 1 of 2 this week", energy: 2400, options: [])
    }

    /// The ring above already says what is left: the chip names the day's target instead.
    @Test func chipSaysTheDaysTarget() {
        #expect(WatchCoach.chipText(chip()) == "🎾 Tennis · 2400 kcal")
        #expect(WatchCoach.chipText(chip(), energy: { grouped($0) + " kcal" }) == "🎾 Tennis · 2,400 kcal")
        #expect(WatchCoach.chipText(chip(emoji: "")) == "Tennis · 2400 kcal")
        // The older call with what is left (and a number without its unit) shows the target too.
        #expect(WatchCoach.chipText(chip(), remaining: 1240, energy: grouped) == "🎾 Tennis · 2,400")
        #expect(WatchCoach.chipText(chip(), remaining: -120.4) == "🎾 Tennis · 2400")
    }

    @Test func dayTypeChoicesShowKcalAndTheFlexibleCount() {
        let tennis = CoachBoard.ChipOption(id: "tennis", name: "Tennis", emoji: "🎾", energy: 2400, quotaText: "1 of 2 this week",
                                           isSelected: false)
        let rest = CoachBoard.ChipOption(id: "rest", name: "Rest", emoji: "", energy: 2150, quotaText: nil, isSelected: true)
        #expect(WatchCoach.optionDetail(tennis) == "2400 kcal · 1 of 2 this week")
        #expect(WatchCoach.optionDetail(rest, energy: { grouped($0) + " kcal" }) == "2,150 kcal")
    }

    @Test func chipFromTheBoardCountsTheWeek() throws {
        // Fri 4 Jan 2030 is a gym day by schedule; tennis was picked on Tue 1 Jan.
        let plan = watchPlan()
        let today = watchDay("2030-01-04")
        let input = CoachBoard.Input(plan: plan, day: today, today: today, now: today.date(minutes: 9 * 60, calendar: watchUTC),
                                     dayTypeMarks: ["2030-01-01": "tennis"], calendar: watchUTC)
        let chip = try #require(CoachBoard(input).chip)
        #expect(chip.id == "gym")
        #expect(chip.isManual == false)
        #expect(chip.options.first { $0.id == "tennis" }?.quotaText == "1 of 2 this week")
        // Without targets in the plan the day falls back to the profile's 2,000 kcal.
        #expect(WatchCoach.chipText(chip) == "🏋️ Gym · 2000 kcal")
    }
}

struct WatchCoachPillTests {
    private let creatine = CoachPlan.Check(id: "creatine", name: "Creatine", emoji: "💊", dose: "3–5 g", timing: .meal("breakfast"))
    private let day = watchDay("2030-01-07")

    private func weighIn() -> CoachBoard.StripItem {
        CoachBoard.StripItem(id: "weighIn", kind: .weighIn, title: "Weigh in", symbol: "scalemass", action: .weighIn)
    }

    private func body(_ kind: BodyDueItem.Kind, sites: [BodySite] = []) -> CoachBoard.StripItem {
        let due = BodyDueItem(kind: kind, dueDay: day, sites: sites)
        let action: CoachBoard.Action = kind == .assessment ? .assessment(due) : .measure(due)
        return CoachBoard.StripItem(id: "body.\(kind.rawValue)", kind: .body, title: due.title, action: action)
    }

    private func check(_ state: CoachBoard.StripItem.State) -> CoachBoard.StripItem {
        CoachBoard.StripItem(id: "check.creatine", kind: .check, title: "Creatine · 3–5 g", emoji: "💊", state: state,
                             action: .check("creatine"))
    }

    @Test func theWatchDoesWeighInsWeeklyTapeAndChecks() {
        #expect(WatchCoach.act(for: weighIn()) == .weighIn)
        #expect(WatchCoach.act(for: body(.weekly, sites: [.waist, .arm])) == .measure([.waist, .arm]))
        #expect(WatchCoach.act(for: body(.weekly)) == nil)
        #expect(WatchCoach.act(for: body(.full, sites: [.waist, .hip])) == nil)
        #expect(WatchCoach.act(for: body(.assessment)) == nil)
        #expect(WatchCoach.act(for: check(.open)) == .check("creatine"))
    }

    @Test func fullSetsAndAssessmentsStayOnThePhone() {
        let strip = [weighIn(), body(.full, sites: [.waist, .hip]), check(.done)]
        #expect(WatchCoach.pills(strip).map(\.id) == ["weighIn", "check.creatine"])
        // Nothing open the watch can do: the row is hidden.
        #expect(WatchCoach.pills([body(.full, sites: [.waist]), body(.assessment), check(.done)]).isEmpty)
        #expect(WatchCoach.pills([check(.skipped)]).isEmpty)
        #expect(WatchCoach.pills([]).isEmpty)
    }

    @Test func pillTitlesLeaveTheDoseOut() {
        let plan = watchPlan(checks: [creatine])
        #expect(WatchCoach.pillTitle(check(.open), plan: plan) == "Creatine")
        #expect(WatchCoach.pillTitle(weighIn(), plan: plan) == "Weigh in")
        #expect(WatchCoach.pillTitle(body(.weekly, sites: [.waist]), plan: plan) == "Waist")
        #expect(WatchCoach.pillTitle(body(.weekly, sites: [.waist, .arm]), plan: plan) == "Measurements")
        // A check the plan no longer has keeps the strip's title.
        #expect(WatchCoach.pillTitle(check(.open), plan: watchPlan()) == "Creatine · 3–5 g")
    }

    @Test func pillsFromTheSameBoardThePhoneUses() {
        // Mon 7 Jan 2030 at 07:30: no weigh-in yet, the weekly waist is due, creatine open.
        let plan = watchPlan(checks: [creatine])
        let input = CoachBoard.Input(plan: plan, day: day, today: day, now: day.date(minutes: 7 * 60 + 30, calendar: watchUTC),
                                     bodyItems: [BodyDueItem(kind: .weighIn, dueDay: day),
                                                 BodyDueItem(kind: .weekly, dueDay: day, sites: [.waist])],
                                     calendar: watchUTC)
        let pills = WatchCoach.pills(CoachBoard(input).strip)
        #expect(pills.map(\.id) == ["weighIn", "body.weekly", "check.creatine"])
        #expect(pills.compactMap(WatchCoach.act(for:)) == [.weighIn, .measure([.waist]), .check("creatine")])
    }
}

struct WatchCoachTapeFlowTests {
    @Test func oneSiteAtATime() {
        var flow = WatchCoach.TapeFlow(sites: [.waist, .hip, .waist])
        #expect(flow.sites == [.waist, .hip])
        #expect(flow.current == .waist)
        #expect(flow.next == .hip)
        #expect(flow.progress == "1 of 2")
        #expect(flow.savedText == nil)
        flow.save(82.46)
        #expect(flow.values[.waist] == 82.5)
        #expect(flow.current == .hip)
        #expect(flow.next == nil)
        #expect(flow.progress == "2 of 2")
        flow.skip()
        #expect(flow.isFinished)
        #expect(flow.progress == nil)
        #expect(flow.savedSites == [.waist])
        #expect(flow.savedText == "Waist saved")
        flow.save(90)
        #expect(flow.values[.hip] == nil)
    }

    @Test func savedSitesReadAsAList() {
        var two = WatchCoach.TapeFlow(sites: [.waistNarrow, .hip])
        two.save(74)
        two.save(97)
        #expect(two.savedText == "Narrow waist and hip saved")
        var three = WatchCoach.TapeFlow(sites: [.waistNarrow, .hip, .armLeft])
        three.save(74)
        three.save(97)
        three.save(29.5)
        #expect(three.savedText == "Narrow waist, hip and arm (left) saved")
        let single = WatchCoach.TapeFlow(sites: [.waist])
        #expect(single.progress == nil)
    }

    @Test func savedValuesStayPlausible() {
        var flow = WatchCoach.TapeFlow(sites: [.arm])
        flow.save(12)
        #expect(flow.values[.arm] == 18)
    }
}

struct WatchCoachStatusTests {
    private let plan = watchPlan()

    @Test func inRangeLine() {
        let status = WatchCoach.status(average: 74.62, rate: 0.153, status: .inRange, phaseID: "1", plan: plan, checkIns: [])
        #expect(status?.text() == "avg 74.6 · +0.15/wk · In range")
        #expect(status?.tone == .good)
        #expect(status?.numbersText() == "avg 74.6 · +0.15/wk")
    }

    @Test func gatheringDataWithoutAValidRate() {
        let status = WatchCoach.status(average: 74.62, rate: nil, status: .gathering, phaseID: "1", plan: plan, checkIns: [])
        #expect(status?.text() == "avg 74.6 · Gathering data")
        #expect(status?.tone == .neutral)
        let early = WatchCoach.status(average: nil, rate: nil, status: .gathering, phaseID: "1", plan: plan, checkIns: [])
        #expect(early?.text() == "Gathering data")
    }

    @Test func withoutAPhaseOnlyTheNumbers() {
        let status = WatchCoach.status(average: 74.62, rate: -0.2, status: nil, phaseID: nil, plan: plan, checkIns: [])
        #expect(status?.text() == "avg 74.6 · −0.20/wk")
        #expect(status?.word == nil)
        #expect(WatchCoach.status(average: nil, rate: nil, status: nil, phaseID: nil, plan: plan, checkIns: []) == nil)
        #expect(WatchCoach.status(average: nil, rate: 0.2, status: nil, phaseID: nil, plan: plan, checkIns: []) == nil)
    }

    @Test func offTrackOnlyAfterTwoCheckInsOnTheSameSide() {
        let below = CheckInSnapshot(day: watchDay("2030-01-14"), deviation: .below, phaseID: "1")
        let alsoBelow = CheckInSnapshot(day: watchDay("2030-01-21"), deviation: .below, phaseID: "1")
        let otherPhase = CheckInSnapshot(day: watchDay("2029-12-24"), deviation: .below, phaseID: "0")
        let once = WatchCoach.status(average: 74.6, rate: 0.05, status: .slower, phaseID: "1", plan: plan, checkIns: [alsoBelow])
        #expect(once?.word == "Slower than planned")
        #expect(once?.tone == .watch)
        let twice = WatchCoach.status(average: 74.6, rate: 0.05, status: .slower, phaseID: "1", plan: plan,
                                      checkIns: [below, alsoBelow])
        #expect(twice?.word == "Off track")
        #expect(twice?.tone == .alert)
        let mixed = WatchCoach.status(average: 74.6, rate: 0.05, status: .slower, phaseID: "1", plan: plan,
                                      checkIns: [otherPhase, alsoBelow])
        #expect(mixed?.word == "Slower than planned")
        // In range never reads off track.
        let fine = WatchCoach.status(average: 74.6, rate: 0.2, status: .inRange, phaseID: "1", plan: plan,
                                     checkIns: [below, alsoBelow])
        #expect(fine?.word == "In range")
    }

    @Test func fromTheWeightSignal() {
        // Daily morning weigh-ins rising 0.2 kg a week for three weeks.
        let start = watchDay("2030-01-01")
        let readings = (0...20).map { offset -> WeightSignal.Reading in
            let day = start.adding(days: offset, calendar: watchUTC)
            return WeightSignal.Reading(day: day, time: day.date(minutes: 7 * 60, calendar: watchUTC),
                                        kilograms: 74 + 0.2 / 7 * Double(offset))
        }
        let signal = WeightSignal(readings, calendar: watchUTC)
        let today = watchDay("2030-01-21")
        let status = WatchCoach.status(summary: signal.summary(on: today, plan: plan), plan: plan, checkIns: [])
        #expect(status?.text() == "avg 74.5 · +0.20/wk · In range")

        // A week of weigh-ins: an average, no rate yet.
        let firstWeek = WeightSignal(Array(readings.prefix(7)), calendar: watchUTC)
        let early = WatchCoach.status(summary: firstWeek.summary(on: watchDay("2030-01-07"), plan: plan), plan: plan, checkIns: [])
        #expect(early?.word == "Gathering data")
        #expect(early?.rate == nil)
        #expect(early?.average != nil)
    }

    @Test func numbersInThePersonsFormat() {
        let status = WatchCoach.Status(average: 74.62, rate: -0.153, word: "Faster than planned", tone: .watch)
        let comma: (Double, Int) -> String = { WatchCoach.fixed($0, $1).replacingOccurrences(of: ".", with: ",") }
        #expect(status.text(number: comma) == "avg 74,6 · −0,15/wk · Faster than planned")
        #expect(WatchCoach.signed(0.153, 2) == "+0.15")
        #expect(WatchCoach.signed(-0.2, 2) == "−0.20")
        #expect(WatchCoach.signed(0.001, 2) == "0.00")
        #expect(WatchCoach.signed(-0.004, 2) == "0.00")
        #expect(WatchCoach.fixed(-0.04, 1) == "0.0")
    }
}
