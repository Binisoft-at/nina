import Foundation
import Testing
@testable import NinaCore

/// A routine's planned meal moved to another day keeps the key of the day it was planned for.
/// The routine must not plan that day again – also when the meal now sits outside the 3-day
/// window the store reads by day (made-up rule and days in 2030).
@Suite("Plan: moved entries")
struct PlanMovedEntryTests {
    let rule = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
    /// Monday, 11 March 2030.
    let monday = DayKey(year: 2030, month: 3, day: 11)
    let created = Date(timeIntervalSince1970: 1_900_000_000)

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }

    func item(_ id: String, day: DayKey, trashed: Bool = false, source: String = "plan") -> PlanSchedule.Item {
        PlanSchedule.Item(id: id, key: PlanSchedule.key(rule: rule, day: day), source: source, createdAt: created,
                          modifiedAt: created.addingTimeInterval(60), isTrashed: trashed)
    }

    @Test("The keys of a rule follow its weekdays and its first and last day")
    func keysOfTheWindow() {
        let wednesday = monday.adding(days: 2, calendar: calendar)
        let all = PlanSchedule.keys(rule: rule, weekdays: .everyDay, from: monday, horizon: 3, calendar: calendar)
        #expect(all == (0..<3).map { PlanSchedule.key(rule: rule, day: monday.adding(days: $0, calendar: calendar)) })

        let weekdays = Weekdays([1, 3])
        let some = PlanSchedule.keys(rule: rule, weekdays: weekdays, from: monday, horizon: 3, calendar: calendar)
        #expect(some == [PlanSchedule.key(rule: rule, day: monday), PlanSchedule.key(rule: rule, day: wednesday)])

        let late = PlanSchedule.keys(rule: rule, weekdays: .everyDay, from: monday, horizon: 3, startDay: wednesday,
                                     calendar: calendar)
        #expect(late == [PlanSchedule.key(rule: rule, day: wednesday)])
        #expect(PlanSchedule.keys(rule: rule, weekdays: .everyDay, from: monday, horizon: 3, endDay: monday.adding(days: -1),
                                  calendar: calendar).isEmpty)
    }

    @Test("Wednesday's lunch moved to Saturday keeps Wednesday from being planned again")
    func movedOutOfTheWindow() {
        let wednesday = monday.adding(days: 2, calendar: calendar)
        let saturday = monday.adding(days: 5, calendar: calendar)
        // The window (Mon–Wed) holds Monday's and Tuesday's plans; Wednesday's sits on Saturday now.
        let window = [item("mon", day: monday), item("tue", day: monday.adding(days: 1, calendar: calendar))]
        let wanted = PlanSchedule.keys(rule: rule, weekdays: .everyDay, from: monday, horizon: 3, calendar: calendar)
        let missing = wanted.filter { !PlanSchedule.takenKeys(window).contains($0) }
        #expect(missing == [PlanSchedule.key(rule: rule, day: wednesday)])

        // What the store finds for the missing keys on any other day: the moved entry.
        let moved = item("moved", day: wednesday)
        #expect(moved.key.hasSuffix(wednesday.rawValue) && !moved.key.hasSuffix(saturday.rawValue))
        let taken = PlanSchedule.takenKeys(window + [moved])
        #expect(wanted.allSatisfy { taken.contains($0) })

        // Once Saturday is in the window, the moved entry is the only one with its key: nothing
        // to clean up, so it is never taken for a duplicate.
        #expect(PlanSchedule.duplicates([moved]).isEmpty)
    }

    @Test("A planned meal a routine change took out doesn't keep its day, wherever it is")
    func retiredStaysFree() {
        let wednesday = monday.adding(days: 2, calendar: calendar)
        let retired = item("retired", day: wednesday, trashed: true, source: PlanSchedule.retiredSource)
        #expect(!PlanSchedule.takenKeys([retired]).contains(PlanSchedule.key(rule: rule, day: wednesday)))
        // One the person deleted keeps it (the day's plan stays deleted).
        let deleted = item("deleted", day: wednesday, trashed: true)
        #expect(PlanSchedule.takenKeys([deleted]).contains(PlanSchedule.key(rule: rule, day: wednesday)))
    }
}
