import Foundation
import Testing
@testable import NinaCore

private var vienna: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
    return calendar
}

private func at(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date {
    day.date(minutes: hour * 60 + minute, calendar: vienna)
}

/// Two devices planned the same routine day before they synced (made-up times in 2030).
@Suite("Plan clean-up")
struct PlanCleanupTests {
    let rule = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    let day = DayKey(year: 2030, month: 3, day: 12)
    var key: String { PlanSchedule.key(rule: rule, day: day) }
    var early: Date { at(day, 5) }
    var late: Date { at(day, 6) }

    /// A saved meal of two foods planned by one device.
    func meal(_ prefix: String, created: Date, status: String = "planned", modified: Date? = nil,
              trashed: Bool = false, source: String = "plan") -> [PlanSchedule.Item] {
        (1...2).map { index in
            PlanSchedule.Item(id: "\(prefix)-\(index)", key: key, groupID: "group-\(prefix)", status: status, source: source,
                              createdAt: created, modifiedAt: modified ?? created, isTrashed: trashed)
        }
    }

    /// What the store does with the answer: the losers go to the trash, marked as the clean-up's.
    func applied(_ items: [PlanSchedule.Item], now: Date) -> [PlanSchedule.Item] {
        let losers = Set(PlanSchedule.duplicates(items))
        return items.map { item in
            guard losers.contains(item.id) else { return item }
            var moved = item
            moved.isTrashed = true
            moved.source = PlanSchedule.duplicateSource
            moved.modifiedAt = now
            return moved
        }
    }

    @Test func untouchedCopiesKeepTheOldest() {
        let items = meal("phone", created: late) + meal("mac", created: early)
        #expect(PlanSchedule.duplicates(items) == ["phone-1", "phone-2"])
    }

    @Test func aCopyEatenOnTheWatchBeatsTheOlderPlannedOne() {
        let eaten = meal("watch", created: late, status: "eaten", modified: at(day, 8))
        let items = meal("phone", created: early) + eaten
        #expect(PlanSchedule.duplicates(items) == ["phone-1", "phone-2"])
    }

    @Test func anEditedCopyCountsAsActedOn() {
        let edited = meal("mac", created: late, modified: late.addingTimeInterval(30))
        #expect(PlanSchedule.duplicates(meal("phone", created: early) + edited) == ["phone-1", "phone-2"])
        // A second of slack: the save right after logging is not an edit.
        let saved = meal("mac", created: late, modified: late.addingTimeInterval(0.5))
        #expect(PlanSchedule.duplicates(meal("phone", created: early) + saved) == ["mac-1", "mac-2"])
    }

    @Test func aPlanDeletedOnOneDeviceStaysDeleted() {
        let deleted = meal("phone", created: early, modified: at(day, 7), trashed: true)
        let items = deleted + meal("watch", created: late)
        #expect(PlanSchedule.duplicates(items) == ["watch-1", "watch-2"])
    }

    @Test func eatenBeatsADeletedCopy() {
        let deleted = meal("phone", created: early, modified: at(day, 7), trashed: true)
        let eaten = meal("watch", created: late, status: "eaten", modified: at(day, 8))
        #expect(PlanSchedule.duplicates(deleted + eaten).isEmpty)
    }

    @Test func recipePortionsWithoutAGroupAreToldApart() {
        let phone = PlanSchedule.Item(id: "b-phone", key: key, createdAt: early)
        let mac = PlanSchedule.Item(id: "a-mac", key: key, createdAt: late)
        #expect(PlanSchedule.duplicates([phone, mac]) == ["a-mac"])
    }

    @Test func aTieGoesToTheSmallestID() {
        let items = meal("b", created: early) + meal("a", created: early)
        #expect(PlanSchedule.duplicates(items) == ["b-1", "b-2"])
    }

    @Test func twoPassesGiveTheSameResult() {
        let cases: [[PlanSchedule.Item]] = [
            meal("phone", created: late) + meal("mac", created: early),
            meal("phone", created: early) + meal("watch", created: late, status: "eaten", modified: at(day, 8)),
            meal("phone", created: early, modified: at(day, 7), trashed: true) + meal("watch", created: late),
            meal("a", created: early) + meal("b", created: late) + meal("c", created: late, status: "skipped", modified: at(day, 9)),
        ]
        for items in cases {
            let once = applied(items, now: at(day, 10))
            #expect(PlanSchedule.duplicates(once).isEmpty)
            let live = once.filter { !$0.isTrashed }
            // Something of the plan is still there, unless the person deleted it.
            if items.contains(where: { $0.isTrashed }) {
                #expect(live.isEmpty)
            } else {
                #expect(!live.isEmpty)
                #expect(Set(live.map(\.groupID)).count == 1)
            }
        }
    }

    @Test func theCleanUpsOwnTombstonesNeverWin() {
        let loser = meal("phone", created: early, modified: at(day, 7), trashed: true, source: PlanSchedule.duplicateSource)
        let items = loser + meal("watch", created: late)
        #expect(PlanSchedule.duplicates(items).isEmpty)
        // A routine change's leftovers don't count as the person's delete either.
        let retired = meal("old", created: early, modified: at(day, 7), trashed: true, source: PlanSchedule.retiredSource)
        #expect(PlanSchedule.duplicates(retired + meal("new", created: late)).isEmpty)
    }

    @Test func otherKeysAreLeftAlone() {
        let other = PlanSchedule.Item(id: "x", key: PlanSchedule.key(rule: rule, day: day.adding(days: 1, calendar: vienna)),
                                      createdAt: late)
        let plain = PlanSchedule.Item(id: "y", key: "", createdAt: late)
        #expect(PlanSchedule.duplicates(meal("phone", created: early) + [other, plain]).isEmpty)
    }

    @Test func keysTellTheirRuleAndDay() {
        #expect(PlanSchedule.ruleID(of: key) == rule)
        #expect(PlanSchedule.day(of: key) == day)
        #expect(key.hasPrefix(PlanSchedule.keyPrefix(rule: rule)))
        #expect(PlanSchedule.ruleID(of: "rule:nope:2030-03-12") == nil)
        #expect(PlanSchedule.ruleID(of: "") == nil)
        #expect(PlanSchedule.day(of: "rule:\(rule.uuidString):soon") == nil)
    }

    @Test func untouchedMeansPlannedAndUnchanged() {
        #expect(PlanSchedule.isUntouched(status: "planned", createdAt: early, modifiedAt: early))
        #expect(PlanSchedule.isUntouched(status: "planned", createdAt: early, modifiedAt: early.addingTimeInterval(1)))
        #expect(!PlanSchedule.isUntouched(status: "planned", createdAt: early, modifiedAt: early.addingTimeInterval(2)))
        #expect(!PlanSchedule.isUntouched(status: "eaten", createdAt: early, modifiedAt: early))
        #expect(!PlanSchedule.isUntouched(status: "skipped", createdAt: early, modifiedAt: early))
        #expect(PlanSchedule.isMarked(source: PlanSchedule.duplicateSource))
        #expect(PlanSchedule.isMarked(source: PlanSchedule.retiredSource))
        #expect(!PlanSchedule.isMarked(source: "plan") && !PlanSchedule.isMarked(source: "copy"))
    }

    @Test func takenKeysLeaveRetiredPlansOut() {
        let retired = PlanSchedule.Item(id: "r", key: key, source: PlanSchedule.retiredSource, createdAt: early,
                                        modifiedAt: late, isTrashed: true)
        #expect(PlanSchedule.takenKeys([retired]).isEmpty)
        let deleted = PlanSchedule.Item(id: "d", key: key, createdAt: early, modifiedAt: late, isTrashed: true)
        #expect(PlanSchedule.takenKeys([deleted]) == [key])
        let live = PlanSchedule.Item(id: "l", key: key, createdAt: early)
        #expect(PlanSchedule.takenKeys([live, PlanSchedule.Item(id: "p", key: "", createdAt: early)]) == [key])
    }
}

@Suite("Copies of routine meals")
struct PlanCopyTests {
    let rule = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    let today = DayKey(year: 2030, month: 3, day: 11)
    var tomorrow: DayKey { today.adding(days: 1, calendar: vienna) }
    var sourceKey: String { PlanSchedule.key(rule: rule, day: today) }
    var targetKey: String { PlanSchedule.key(rule: rule, day: tomorrow) }

    func rule(_ covers: Bool) -> (UUID) -> Bool { { id in covers && id == rule } }

    @Test func aPlannedCopyLeavesOutWhatTheRoutineAlreadyPlans() {
        let planned = PlanSchedule.Item(id: "p", key: targetKey, createdAt: at(today, 6))
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: tomorrow, planned: true, existing: [planned],
                                      ruleCovers: rule(true)) == .skip)
        // Eaten copies are logged anyway, without the key.
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: tomorrow, planned: false, existing: [planned],
                                      ruleCovers: rule(true)) == .plain)
    }

    @Test func aDayTheRoutineHasNotReachedTakesItsKey() {
        let later = today.adding(days: 5, calendar: vienna)
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: later, planned: true, existing: [], ruleCovers: rule(true))
                == .key(PlanSchedule.key(rule: rule, day: later)))
    }

    @Test func aDeletedPlanGetsAnOrdinaryCopy() {
        let deleted = PlanSchedule.Item(id: "d", key: targetKey, createdAt: at(today, 6), modifiedAt: at(today, 9), isTrashed: true)
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: tomorrow, planned: true, existing: [deleted],
                                      ruleCovers: rule(true)) == .plain)
        let retired = PlanSchedule.Item(id: "r", key: targetKey, source: PlanSchedule.retiredSource, createdAt: at(today, 6),
                                        modifiedAt: at(today, 9), isTrashed: true)
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: tomorrow, planned: true, existing: [retired],
                                      ruleCovers: rule(true)) == .key(targetKey))
    }

    @Test func otherEntriesAreOrdinaryCopies() {
        #expect(PlanSchedule.copyRule(sourceKey: "", to: tomorrow, planned: true, existing: [], ruleCovers: rule(true)) == .plain)
        #expect(PlanSchedule.copyRule(sourceKey: sourceKey, to: tomorrow, planned: true, existing: [], ruleCovers: rule(false)) == .plain)
    }
}

@Suite("Day start")
struct DayStartTests {
    let day = DayKey(year: 2030, month: 1, day: 15)

    @Test func timesBeforeTheStartBelongToTheNight() {
        let late = day.date(minutes: 30, dayStartHour: 3, calendar: vienna)
        #expect(DayKey(date: late, calendar: vienna) == day.adding(days: 1, calendar: vienna))
        #expect(DayKey(date: late, calendar: vienna, dayStartHour: 3) == day)
        #expect(day.date(minutes: 7 * 60, dayStartHour: 3, calendar: vienna) == day.date(minutes: 7 * 60, calendar: vienna))
        #expect(day.date(minutes: 30, dayStartHour: 0, calendar: vienna) == day.date(minutes: 30, calendar: vienna))
    }

    @Test func slotsSortFromTheDayStart() {
        #expect(ClockTime.diaryMinutes(30, dayStartHour: 3) == 1470)
        #expect(ClockTime.diaryMinutes(180, dayStartHour: 3) == 180)
        #expect(ClockTime.diaryMinutes(30, dayStartHour: 0) == 30)
        let slots = [30, 7 * 60, 19 * 60].sorted { ClockTime.diaryMinutes($0, dayStartHour: 3) < ClockTime.diaryMinutes($1, dayStartHour: 3) }
        #expect(slots == [7 * 60, 19 * 60, 30])
    }

    @Test func theDayStartsAtItsHour() {
        #expect(day.start(dayStartHour: 3, calendar: vienna) == day.date(minutes: 180, calendar: vienna))
        #expect(day.start(dayStartHour: 0, calendar: vienna) == day.date(calendar: vienna))
    }
}

@Suite("Widget timeline")
struct WidgetTimelineTests {
    /// The app's day (15 Jan 2030) with the day starting at 3:00: 1,800 kcal eaten.
    let day = DayKey(year: 2030, month: 1, day: 15)
    var next: DayKey { day.adding(days: 1, calendar: vienna) }

    func snapshot(startHour: Int? = 3, planned: [TodaySnapshot.PlannedItem]? = nil) -> TodaySnapshot {
        var snapshot = TodaySnapshot(day: day.rawValue, energy: 1800, energyGoal: 2300, protein: 120, proteinGoal: 150,
                                     carbs: 200, carbsGoal: 260, fat: 60, fatGoal: 75, water: 1500, waterGoal: 2250)
        snapshot.dayStartHour = startHour
        snapshot.planned = planned
        snapshot.tomorrow = TodaySnapshot.Goals(day: next, targets: DailyTargets(energy: 2500, protein: 150, carbs: 300,
                                                                                    fat: 75, water: 2250))
        return snapshot
    }

    @Test func aLateSnackStillCountsForTheAppsDay() {
        let stored = snapshot()
        for (hour, minute) in [(0, 30), (2, 59)] {
            let now = at(next, hour, minute)
            let shown = stored.current(now: now, calendar: vienna)
            #expect(shown.day == day.rawValue)
            #expect(shown.energy == 1800)
            #expect(stored.nextDayStart(after: now, calendar: vienna) == at(next, 3))
        }
        let three = stored.current(now: at(next, 3), calendar: vienna)
        #expect(three.day == next.rawValue)
        #expect(three.energy == 0 && three.energyGoal == 2500)
        #expect(stored.nextDayStart(after: at(next, 3), calendar: vienna) == at(next.adding(days: 1, calendar: vienna), 3))
    }

    @Test func theTimelineChangesDayAtTheDayStart() {
        let points = snapshot().timeline(now: at(next, 0, 30), calendar: vienna)
        #expect(points.map(\.date) == [at(next, 0, 30), at(next, 3)])
        #expect(points[0].snapshot.energy == 1800)
        #expect(points[1].snapshot.day == next.rawValue && points[1].snapshot.energy == 0)
    }

    @Test func olderFilesMeanMidnight() throws {
        var old = snapshot(startHour: nil)
        old.nextPlanned = "Dinner · 18:30"
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(TodaySnapshot.self, from: data)
        #expect(decoded.dayStartHour == nil && decoded.planned == nil)
        #expect(decoded.current(now: at(next, 0, 30), calendar: vienna).day == next.rawValue)
        #expect(decoded.current(now: at(day, 17), calendar: vienna).nextPlanned == "Dinner · 18:30")
        #expect(decoded.timeline(now: at(day, 17), calendar: vienna).map(\.date) == [at(day, 17), at(next, 0)])
    }

    @Test func thePlannedLineMovesOn() {
        let planned = [
            TodaySnapshot.PlannedItem(day: day, time: at(day, 12, 30), text: "Lunch · 12:30"),
            TodaySnapshot.PlannedItem(day: day, time: at(day, 19), text: "Dinner · 19:00"),
            TodaySnapshot.PlannedItem(day: next, time: at(next, 7, 30), text: "Breakfast · 7:30"),
        ]
        let points = snapshot(planned: planned).timeline(now: at(day, 10), calendar: vienna)
        #expect(points.map(\.date) == [at(day, 10), at(day, 12, 30), at(day, 19), at(next, 3), at(next, 7, 30)])
        #expect(points.map(\.snapshot.nextPlanned) == ["Lunch · 12:30", "Dinner · 19:00", nil, "Breakfast · 7:30", nil])
        #expect(points[3].snapshot.energy == 0 && points[3].snapshot.energyGoal == 2500)
    }
}
