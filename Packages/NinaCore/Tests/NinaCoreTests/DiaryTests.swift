import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
    return calendar
}

@Suite("Days")
struct DayTests {
    @Test func keysAndArithmetic() throws {
        let day = try #require(DayKey("2026-11-13"))
        #expect(day.weekday(calendar: utc) == 5) // Friday
        #expect(day.adding(days: 1, calendar: utc).rawValue == "2026-11-14")
        #expect(day.adding(days: -13, calendar: utc).rawValue == "2026-10-31")
        #expect(day.startOfWeek(calendar: utc).rawValue == "2026-11-09")
        #expect(day.days(to: DayKey(year: 2026, month: 12, day: 1), calendar: utc) == 18)
        #expect(DayKey.range(day, through: day.adding(days: 2, calendar: utc), calendar: utc).count == 3)
        #expect(DayKey("2026-13-01") == nil)
    }

    @Test func daylightSavingDoesNotSkipDays() throws {
        let day = try #require(DayKey("2026-03-28"))
        #expect(day.adding(days: 1, calendar: utc).rawValue == "2026-03-29")
        #expect(day.adding(days: 2, calendar: utc).rawValue == "2026-03-30")
    }

    @Test func lateSnacksCanCountForYesterday() throws {
        let day = try #require(DayKey("2026-11-13"))
        let lateNight = day.date(minutes: 25 * 60 + 30, calendar: utc) // 01:30 next day
        #expect(DayKey(date: lateNight, calendar: utc).rawValue == "2026-11-14")
        #expect(DayKey(date: lateNight, calendar: utc, dayStartHour: 3).rawValue == "2026-11-13")
    }

    @Test func clockTimes() {
        #expect(ClockTime.parse("7:30") == 450)
        #expect(ClockTime.parse("19h") == 1140)
        #expect(ClockTime.parse("1230") == 750)
        #expect(ClockTime.parse("25:00") == nil)
        #expect(ClockTime.text(450) == "07:30")
    }

    @Test func timesOnADayStayOnTheWallClock() throws {
        var vienna = Calendar(identifier: .gregorian)
        vienna.timeZone = try #require(TimeZone(identifier: "Europe/Vienna"))
        // The clocks go forward on 31 Mar 2030 and back on 27 Oct 2030: 06:00, 07:00 and 21:00 stay.
        for raw in ["2030-03-31", "2030-10-27", "2030-06-12"] {
            let day = try #require(DayKey(raw))
            for minutes in [6 * 60, 7 * 60, 21 * 60] {
                let date = day.date(minutes: minutes, calendar: vienna)
                #expect(ClockTime.minutes(of: date, calendar: vienna) == minutes, "\(raw) \(ClockTime.text(minutes))")
                #expect(DayKey(date: date, calendar: vienna) == day)
            }
        }
        // Past midnight: the next day (a slot time plus a delay).
        let day = try #require(DayKey("2030-03-30"))
        let late = day.date(minutes: 25 * 60 + 10, calendar: vienna)
        #expect(DayKey(date: late, calendar: vienna).rawValue == "2030-03-31")
        #expect(ClockTime.minutes(of: late, calendar: vienna) == 70)
        let before = day.date(minutes: -30, calendar: vienna)
        #expect(DayKey(date: before, calendar: vienna).rawValue == "2030-03-29")
        #expect(ClockTime.minutes(of: before, calendar: vienna) == 23 * 60 + 30)
        // A time the clock skips moves forward with it.
        let skipped = try #require(DayKey("2030-03-31")).date(minutes: 2 * 60 + 30, calendar: vienna)
        #expect(ClockTime.minutes(of: skipped, calendar: vienna) == 3 * 60 + 30)
    }
}

@Suite("Goals")
struct GoalTests {
    @Test func mifflinStJeor() {
        let profile = BodyProfile(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .maintain)
        // 10·80 + 6.25·180 − 5·30 + 5 = 1780
        #expect(GoalCalculator.bmr(profile) == 1780)
        let plan = GoalCalculator.plan(profile)
        #expect(plan.maintenance == 1780 * 1.55)
        #expect(plan.targets.energy == 2760)
        #expect(plan.targets.protein == (2760 * 0.25 / 4).rounded())
        #expect(plan.targets.water == 2500)
    }

    @Test func losingRespectsTheFloor() {
        let small = BodyProfile(sex: .female, age: 60, heightCm: 155, weightKg: 50, activity: .sedentary, goal: .lose, ratePerWeek: 1)
        let plan = GoalCalculator.plan(small)
        #expect(plan.hitFloor)
        #expect(plan.targets.energy >= 1200)
        #expect(plan.steps.contains { $0.title == "Deficit" })
    }

    @Test func deficitIsSevenSevenHundredPerKilo() {
        let profile = BodyProfile(sex: .male, age: 35, heightCm: 182, weightKg: 92, activity: .light, goal: .lose, ratePerWeek: 0.5)
        let plan = GoalCalculator.plan(profile)
        #expect(plan.adjustment == -550)
    }

    @Test func targetsEncodeAndScale() {
        let targets = DailyTargets.standard
        #expect(DailyTargets(encoded: targets.encoded) == targets)
        let scaled = targets.scaled(toEnergy: 2200)
        #expect(scaled.energy == 2200)
        #expect(scaled.protein == (125 * 1.1).rounded())
        let allValid = MacroSplit.presets.allSatisfy { $0.isValid }
        #expect(allValid)
    }
}

@Suite("Diary")
struct DiaryMathTests {
    let day = DayKey(year: 2026, month: 11, day: 13)

    func entry(_ meal: String, _ kcal: Double, _ status: EntryStatus = .eaten, protein: Double = 10) -> EntryFacts {
        EntryFacts(day: day, meal: meal, status: status, nutrients: NutrientValues([.energy: kcal, .protein: protein, .carbs: 0, .fat: 0]),
                   name: meal, time: day.date(calendar: utc))
    }

    @Test func totalsAndProgress() {
        let entries = [entry("breakfast", 400), entry("lunch", 700), entry("dinner", 600, .planned), entry("snack", 200, .skipped)]
        let totals = DayTotals(day: day, entries: entries, water: 1500)
        #expect(totals.eaten.energy == 1100)
        #expect(totals.planned.energy == 600)
        #expect(totals.projected.energy == 1700)
        #expect(totals.byMeal["lunch"]?.energy == 700)
        #expect(totals.eatenCount == 2)
        let progress = DayProgress(totals: totals, targets: .standard, activityBonus: 300)
        #expect(progress.energyBudget == 2300)
        #expect(progress.energyRemaining == 1200)
        #expect(progress.verdict == .under)
        #expect(progress.fraction(.water) == 0.75)
    }

    @Test func mealSlots() {
        let slots = MealSlot.decode("")
        #expect(slots.map(\.id) == ["breakfast", "lunch", "snack", "dinner"])
        #expect(MealSlot.suggested(atMinutes: 8 * 60, in: slots).id == "breakfast")
        #expect(MealSlot.suggested(atMinutes: 12 * 60 + 50, in: slots).id == "lunch")
        #expect(MealSlot.suggested(atMinutes: 16 * 60, in: slots).id == "snack")
        #expect(MealSlot.suggested(atMinutes: 22 * 60 + 30, in: slots).id == "snack")
        let custom = slots + [MealSlot(id: "jause", name: "Jause", emoji: "🥪", minutes: 10 * 60)]
        let decoded = MealSlot.decode(MealSlot.encode(custom))
        #expect(decoded.first { $0.id == "jause" }?.name == "Jause")
        #expect(MealSlot.matching("Frühstück", in: decoded)?.id == "breakfast")
        #expect(MealSlot.matching("jause", in: decoded)?.id == "jause")
    }

    @Test func statuses() {
        #expect(EntryStatus(text: "geplant") == .planned)
        #expect(EntryStatus(text: "") == .eaten)
    }
}

@Suite("Insights")
struct InsightTests {
    let today = DayKey(year: 2026, month: 11, day: 13)

    @Test func streaks() {
        let logged: Set<DayKey> = Set((0..<5).map { today.adding(days: -$0, calendar: utc) } + (8..<15).map { today.adding(days: -$0, calendar: utc) })
        let result = Insights.streaks(logged: logged, today: today, calendar: utc)
        #expect(result.current == 5)
        #expect(result.best == 7)
        let yesterdayOnly: Set<DayKey> = [today.adding(days: -1, calendar: utc)]
        #expect(Insights.streaks(logged: yesterdayOnly, today: today, calendar: utc).current == 1)
    }

    @Test func periodStats() {
        let days = (0..<7).map { today.adding(days: -$0, calendar: utc) }
        let totals = days.enumerated().map { index, day in
            DayTotals(day: day, entries: index == 6 ? [] : [
                EntryFacts(day: day, meal: "lunch", nutrients: NutrientValues([.energy: index == 0 ? 2500 : 2000, .protein: 100, .carbs: 250, .fat: 66]),
                           name: "x", time: day.date(calendar: utc)),
            ], water: 2000)
        }
        let stats = Insights.stats(totals: totals, targets: { _ in .standard }, calendar: utc)
        #expect(stats.loggedDays == 6)
        #expect(abs(stats.average.energy - 2083.33) < 0.1)
        #expect(stats.overDays == 1)
        #expect(abs(stats.onTrackShare - 5.0 / 6) < 0.001)
    }

    @Test func topFoods() {
        let day = today
        let entries = [
            EntryFacts(day: day, meal: "b", nutrients: NutrientValues([.energy: 100, .protein: 20]), foodRef: FoodRef("a"), name: "Skyr", time: Date()),
            EntryFacts(day: day, meal: "b", nutrients: NutrientValues([.energy: 100, .protein: 20]), foodRef: FoodRef("a"), name: "Skyr", time: Date()),
            EntryFacts(day: day, meal: "b", nutrients: NutrientValues([.energy: 500, .protein: 5]), foodRef: FoodRef("b"), name: "Cake", time: Date()),
        ]
        #expect(Insights.topFoods(entries).first?.name == "Skyr")
        #expect(Insights.topFoods(entries, by: .energy).first?.name == "Cake")
        #expect(Insights.topFoods(entries, by: .protein).first?.count == 2)
    }

    @Test func weightTrendSmoothsNoise() {
        var weights: [DayKey: Double] = [:]
        for offset in 0..<20 {
            weights[today.adding(days: -offset, calendar: utc)] = 80 - Double(20 - offset) * 0.05 + (offset % 2 == 0 ? 0.6 : -0.6)
        }
        let trend = Insights.weightTrend(weights, through: today, calendar: utc)
        #expect(trend.count == 20)
        let raw = weights.values
        let rawSpread = (raw.max() ?? 0) - (raw.min() ?? 0)
        let trendValues = trend.compactMap(\.trend)
        let trendSpread = (trendValues.max() ?? 0) - (trendValues.min() ?? 0)
        #expect(trendSpread < rawSpread)
    }

    @Test func maintenanceFromIntakeAndWeight() throws {
        // 28 days at 2,200 kcal while losing 1 kg → ≈ 2,200 + 7,700/27 ≈ 2,485 kcal.
        var totals: [DayTotals] = []
        var weights: [DayKey: Double] = [:]
        for offset in 0..<28 {
            let day = today.adding(days: -offset, calendar: utc)
            totals.append(DayTotals(day: day, entries: [
                EntryFacts(day: day, meal: "lunch", nutrients: NutrientValues([.energy: 2200]), name: "x", time: Date()),
            ]))
            if offset % 2 == 0 { weights[day] = 80 - Double(27 - offset) / 27 }
        }
        for offset in 28..<42 { weights[today.adding(days: -offset, calendar: utc)] = 80 }
        let estimate = try #require(Insights.maintenance(totals: totals, weights: weights, today: today, calendar: utc))
        #expect(estimate.kilocalories > 2350 && estimate.kilocalories < 2600)
        #expect(estimate.weightChange < 0)
        #expect(Insights.maintenance(totals: Array(totals.prefix(5)), weights: weights, today: today, calendar: utc) == nil)
    }
}

@Suite("Plans")
struct PlanTests {
    let monday = DayKey(year: 2026, month: 11, day: 9)

    @Test func weekdays() {
        #expect(Weekdays(encoded: "1, 3,5,9").encoded == "1,3,5")
        #expect(Weekdays.workdays.summary == "Mon–Fri")
        #expect(Weekdays([6, 7]).summary == "Sat, Sun")
        #expect(Weekdays.workdays.contains(monday, calendar: utc))
        #expect(!Weekdays.workdays.contains(monday.adding(days: 5, calendar: utc), calendar: utc))
    }

    @Test func scheduleDays() {
        let days = PlanSchedule.days(for: .workdays, from: monday, horizon: 7, calendar: utc)
        #expect(days.count == 5)
        let limited = PlanSchedule.days(for: .everyDay, from: monday, horizon: 7, startDay: monday.adding(days: 2, calendar: utc),
                                        endDay: monday.adding(days: 3, calendar: utc), calendar: utc)
        #expect(limited.count == 2)
    }

    @Test func duplicateGroupsConverge() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let items = [
            PlanSchedule.Item(id: "phone", key: "k1", groupID: "g1", createdAt: late),
            PlanSchedule.Item(id: "mac", key: "k1", groupID: "g2", createdAt: early),
            PlanSchedule.Item(id: "only", key: "k2", groupID: "g3", createdAt: early),
        ]
        #expect(PlanSchedule.duplicates(items) == ["phone"])
    }
}

@Suite("Snapshot")
struct SnapshotTests {
    @Test func emptiesOnANewDay() {
        let snapshot = TodaySnapshot.placeholder
        let next = DayKey(year: 2026, month: 1, day: 2)
        #expect(snapshot.current(today: next).energy == 0)
        #expect(snapshot.current(today: next).energyGoal == snapshot.energyGoal)
        #expect(snapshot.current(today: DayKey(year: 2026, month: 1, day: 1)) == snapshot)
        var later = snapshot
        later.updatedAt = Date()
        #expect(later.hasSameContent(as: snapshot))
    }

    @Test func healthMappingIsUnique() {
        #expect(Set(HealthMapping.items.map(\.identifier)).count == HealthMapping.items.count)
        #expect(HealthMapping.items.first?.nutrient == .energy)
    }
}

@Suite("Tour")
struct TourTests {
    @Test func catalogHasNoProblems() {
        #expect(NinaTour.catalog.problems().isEmpty)
    }

    @Test func stepsTickOff() {
        var page = NinaTourSnapshot()
        page.eatenCount = 3
        page.plannedCount = 1
        var log = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "log")
        page.eatenCount = 4
        let logged = log.observe(page)
        #expect(logged)

        var plan = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "plan")
        page.plannedCount = 0
        let confirmed = plan.observe(page)
        #expect(confirmed)

        var undo = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "undo")
        page.trashedCount = 1
        let deleted = undo.observe(page)
        page.trashedCount = 0
        let restored = undo.observe(page)
        #expect(!deleted)
        #expect(restored)
    }
}
